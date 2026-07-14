import { invoke, isTauri } from '@tauri-apps/api/core'
import {
  cancelPendingSystemKeyboardInvoke,
  scheduleSystemKeyboardInvoke,
} from './keyboardInvoke'
import {
  activeInputElement as keyboardActiveInput,
  onScreenKeyboardVisible,
  openOnScreenKeyboard,
} from './onScreenKeyboard'
import { shouldForceOnScreenKeyboardFromConfig } from './runtimeConfig'

const INPUT_SELECTOR =
  'input:not([disabled]):not([readonly]), textarea:not([disabled]):not([readonly]), select:not([disabled])'

const KEYBOARD_RETRY_COUNT = 2
const KEYBOARD_RETRY_DELAY_MS = 300
const KEYBOARD_INVOKE_DELAY_MS = 120
const ACTIVATE_DEBOUNCE_MS = 400

interface TouchKeyboardResult {
  method: string
  visible: boolean
}

let opening = false
let installed = false
let activeInput: HTMLInputElement | HTMLTextAreaElement | null = null
let lastActivatedInput: HTMLElement | null = null
let lastActivatedAt = 0

function isTauriRuntime() {
  return (
    isTauri() ||
    '__TAURI_INTERNALS__' in window ||
    '__TAURI__' in window ||
    Boolean(import.meta.env.TAURI_ENV_PLATFORM)
  )
}

function logTouchKeyboard(message: string, detail?: unknown) {
  if (detail === undefined) {
    console.info(`[QMS][TouchKeyboard] ${message}`)
    return
  }

  console.info(`[QMS][TouchKeyboard] ${message}`, detail)
}

function sleep(ms: number) {
  return new Promise<void>((resolve) => {
    window.setTimeout(resolve, ms)
  })
}

function resolveInputTarget(target: EventTarget | null): HTMLElement | null {
  if (!(target instanceof HTMLElement)) {
    return null
  }

  if (target.matches(INPUT_SELECTOR)) {
    return target
  }

  return target.closest<HTMLElement>(INPUT_SELECTOR)
}

function isTextInput(
  element: HTMLElement
): element is HTMLInputElement | HTMLTextAreaElement {
  return (
    element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement
  )
}

function isEditableField(element: HTMLElement) {
  if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
    return !element.readOnly
  }

  return true
}

/** 部分触屏设备上，先 readonly 再 focus 更容易触发系统键盘 */
function prepareInputForTouchKeyboard(input: HTMLElement) {
  if (!isTextInput(input)) {
    input.focus({ preventScroll: true })
    return
  }

  if (
    onScreenKeyboardVisible.value ||
    shouldForceOnScreenKeyboard() ||
    !isTauriRuntime()
  ) {
    focusInputAtEnd(input)
    return
  }

  const hadReadonly = input.readOnly
  if (!hadReadonly) {
    input.readOnly = true
  }

  input.focus({ preventScroll: true })

  window.setTimeout(() => {
    if (!hadReadonly) {
      input.readOnly = false
    }
    input.focus({ preventScroll: true })
  }, 0)
}

function focusInputAtEnd(input: HTMLInputElement | HTMLTextAreaElement) {
  input.focus({ preventScroll: true })

  const length = input.value.length
  try {
    input.setSelectionRange(length, length)
  } catch {
    // ignore
  }
}

function isNonWindowsTauriRuntime() {
  const platform = import.meta.env.TAURI_ENV_PLATFORM
  if (platform) {
    return isTauriRuntime() && platform !== 'windows'
  }

  return (
    isTauriRuntime() &&
    typeof navigator !== 'undefined' &&
    !/Win/i.test(navigator.userAgent)
  )
}

function shouldUseInAppKeyboardOnly() {
  return (
    shouldForceOnScreenKeyboard() ||
    !isTauriRuntime() ||
    isNonWindowsTauriRuntime()
  )
}

function shouldSkipDuplicateActivate(input: HTMLElement) {
  const now = Date.now()
  if (
    lastActivatedInput === input &&
    now - lastActivatedAt < ACTIVATE_DEBOUNCE_MS
  ) {
    return true
  }

  lastActivatedInput = input
  lastActivatedAt = now
  return false
}

function isNonRetryableKeyboardResult(result: TouchKeyboardResult | null) {
  if (!result) {
    return false
  }

  return (
    result.method === 'skipped-non-windows' ||
    result.method === 'none'
  )
}

function shouldOpenOnScreenKeyboardImmediately(
  input: HTMLElement
): input is HTMLInputElement | HTMLTextAreaElement {
  if (!isTextInput(input)) {
    return false
  }

  if (shouldUseInAppKeyboardOnly()) {
    return true
  }

  // 应用内键盘已展示时，只切换绑定输入框，不再唤起系统键盘
  if (onScreenKeyboardVisible.value) {
    return true
  }

  return false
}

function shouldSkipRedundantClickActivate(
  input: HTMLElement,
  eventType: string
) {
  if (eventType !== 'click') {
    return false
  }

  return (
    onScreenKeyboardVisible.value &&
    isTextInput(input) &&
    keyboardActiveInput.value === input
  )
}

async function invokeTouchKeyboard(source: string) {
  let lastResult: TouchKeyboardResult | null = null

  for (let attempt = 1; attempt <= KEYBOARD_RETRY_COUNT; attempt += 1) {
    try {
      const result = await invoke<TouchKeyboardResult>('show_touch_keyboard')
      lastResult = result

      logTouchKeyboard('触摸键盘命令已执行', { source, attempt, ...result })

      if (result.visible) {
        return result
      }

      if (isNonRetryableKeyboardResult(result)) {
        return result
      }

      logTouchKeyboard('系统键盘窗口未检测到，准备重试', {
        source,
        attempt,
        method: result.method,
      })
    } catch (error) {
      logTouchKeyboard('触摸键盘唤起失败，准备重试', { source, attempt, error })
    }

    if (attempt < KEYBOARD_RETRY_COUNT) {
      await sleep(KEYBOARD_RETRY_DELAY_MS)
    }
  }

  return lastResult
}

function shouldForceOnScreenKeyboard() {
  return shouldForceOnScreenKeyboardFromConfig()
}

function openFallbackKeyboard() {
  if (!activeInput) {
    logTouchKeyboard('系统键盘不可用，但未找到当前输入框')
    return
  }

  logTouchKeyboard('改用应用内虚拟键盘', {
    inputType: activeInput.getAttribute('type') || activeInput.tagName,
  })
  openOnScreenKeyboard(activeInput)
}

async function showTouchKeyboard(source: string) {
  if (opening) {
    logTouchKeyboard('已在唤起中，跳过重复调用', { source })
    return
  }

  if (onScreenKeyboardVisible.value) {
    logTouchKeyboard('应用内键盘已展示，跳过重复唤起', { source })
    return
  }

  if (!isTauriRuntime()) {
    if (activeInput) {
      openOnScreenKeyboard(activeInput)
    }
    return
  }

  if (shouldForceOnScreenKeyboard() || isNonWindowsTauriRuntime()) {
    logTouchKeyboard('直接使用应用内虚拟键盘', { source })
    openFallbackKeyboard()
    return
  }

  opening = true
  logTouchKeyboard('正在唤起 Windows 触摸键盘', { source })

  try {
    const result = await invokeTouchKeyboard(source)

    if (!result?.visible) {
      openFallbackKeyboard()
    }
  } finally {
    window.setTimeout(() => {
      opening = false
    }, 400)
  }
}

function shouldSkipRepeatKeyboardActivate(
  input: HTMLElement,
  eventType: string
) {
  if (eventType !== 'focusin') {
    return false
  }

  if (!onScreenKeyboardVisible.value || !keyboardActiveInput.value) {
    return false
  }

  return keyboardActiveInput.value === input
}

function handleInputActivate(event: Event) {
  const input = resolveInputTarget(event.target)
  if (!input || !isEditableField(input)) {
    return
  }

  if (shouldSkipRepeatKeyboardActivate(input, event.type)) {
    return
  }

  if (shouldSkipDuplicateActivate(input)) {
    return
  }

  if (shouldSkipRedundantClickActivate(input, event.type)) {
    return
  }

  if (isTextInput(input)) {
    activeInput = input
  }

  logTouchKeyboard('检测到输入框激活', {
    eventType: event.type,
    inputType: input.getAttribute('type') || input.tagName,
    placeholder: input.getAttribute('placeholder'),
  })

  if (shouldOpenOnScreenKeyboardImmediately(input)) {
    cancelPendingSystemKeyboardInvoke()
    openOnScreenKeyboard(input)
    return
  }

  if (
    event.type === 'pointerdown' ||
    event.type === 'touchstart' ||
    event.type === 'click'
  ) {
    prepareInputForTouchKeyboard(input)
  }

  cancelPendingSystemKeyboardInvoke()
  scheduleSystemKeyboardInvoke(() => {
    void showTouchKeyboard(event.type)
  }, KEYBOARD_INVOKE_DELAY_MS)
}

async function warmUpTouchKeyboard() {
  if (!isTauriRuntime() || shouldForceOnScreenKeyboard()) {
    return
  }

  try {
    await invoke('warm_up_touch_keyboard')
    logTouchKeyboard('触摸键盘预热完成')
  } catch (error) {
    logTouchKeyboard('触摸键盘预热失败', error)
  }
}

/** 输入框聚焦/点击时唤起 Windows 触摸键盘（TabTip），失败则显示应用内键盘 */
export function setupTouchKeyboard() {
  if (installed) {
    return
  }

  installed = true

  logTouchKeyboard('开始注册监听', {
    isTauri: isTauri(),
    isTauriRuntime: isTauriRuntime(),
    forceOnScreenKeyboard: shouldForceOnScreenKeyboard(),
    platform: import.meta.env.TAURI_ENV_PLATFORM,
    mode: import.meta.env.MODE,
  })

  document.addEventListener('focusin', handleInputActivate, true)
  document.addEventListener('pointerdown', handleInputActivate, true)

  logTouchKeyboard('监听已注册（focusin / pointerdown）')

  void warmUpTouchKeyboard()
}
