import { ref, shallowRef } from 'vue'

export type OnScreenKeyboardType = 'chinese' | 'english' | 'number'

export const KEYBOARD_TARGET_CLASS = 'qms-keyboard-target'
const KEYBOARD_OPEN_CLASS = 'qms-keyboard-open'

export const onScreenKeyboardVisible = ref(false)
export const activeInputElement = shallowRef<
  HTMLInputElement | HTMLTextAreaElement | null
>(null)
export const onScreenKeyboardType = ref<OnScreenKeyboardType>('chinese')

/** 已确认写入输入框的文字（不含当前正在拼写的拼音） */
export const committedText = ref('')

let blurGuardInput: HTMLInputElement | HTMLTextAreaElement | null = null
let blurGuardToken = 0

function resolveKeyboardType(
  _input: HTMLInputElement | HTMLTextAreaElement
): OnScreenKeyboardType {
  return 'chinese'
}

function isPinyinComposing(value: string) {
  return /^[a-zA-Z']+$/.test(value)
}

function isLatinOrDigitComposing(value: string) {
  return /^[a-zA-Z0-9']+$/.test(value)
}

function containsChinese(value: string) {
  return /[\u4e00-\u9fff]/.test(value)
}

function clearKeyboardTargetMark() {
  document.querySelectorAll(`.${KEYBOARD_TARGET_CLASS}`).forEach((element) => {
    element.classList.remove(KEYBOARD_TARGET_CLASS)
  })
}

function markKeyboardTarget(input: HTMLInputElement | HTMLTextAreaElement) {
  clearKeyboardTargetMark()
  input.classList.add(KEYBOARD_TARGET_CLASS)
}

function setKeyboardOpenScrollLock(locked: boolean) {
  document.documentElement.classList.toggle(KEYBOARD_OPEN_CLASS, locked)
}

function focusInputAtEnd(input: HTMLInputElement | HTMLTextAreaElement) {
  const scrollX = window.scrollX
  const scrollY = window.scrollY

  input.focus({ preventScroll: true })

  window.scrollTo(scrollX, scrollY)

  const length = input.value.length
  try {
    input.setSelectionRange(length, length)
  } catch {
    // 部分浏览器/输入类型不支持 setSelectionRange
  }
}

function handleActiveInputBlur() {
  if (!onScreenKeyboardVisible.value || !blurGuardInput) {
    return
  }

  const inputThatBlurred = blurGuardInput
  const token = blurGuardToken

  window.setTimeout(() => {
    if (token !== blurGuardToken) {
      return
    }

    if (!onScreenKeyboardVisible.value || blurGuardInput !== inputThatBlurred) {
      return
    }

    const activeElement = document.activeElement
    if (
      activeElement instanceof HTMLInputElement ||
      activeElement instanceof HTMLTextAreaElement
    ) {
      // 用户已切换到其他输入框，不要把焦点抢回来
      if (activeElement !== inputThatBlurred) {
        return
      }
    }

    if (activeInputElement.value !== inputThatBlurred) {
      return
    }

    if (document.activeElement !== inputThatBlurred) {
      focusInputAtEnd(inputThatBlurred)
      markKeyboardTarget(inputThatBlurred)
    }
  }, 30)
}

function attachBlurGuard(input: HTMLInputElement | HTMLTextAreaElement) {
  detachBlurGuard()
  blurGuardInput = input
  input.addEventListener('blur', handleActiveInputBlur)
}

function detachBlurGuard() {
  blurGuardToken += 1

  if (!blurGuardInput) {
    return
  }

  blurGuardInput.removeEventListener('blur', handleActiveInputBlur)
  blurGuardInput = null
}

export function maintainActiveInputFocus() {
  const input = activeInputElement.value
  if (!input || !onScreenKeyboardVisible.value) {
    return
  }

  markKeyboardTarget(input)

  if (document.activeElement !== input) {
    focusInputAtEnd(input)
  }
}

export function setInputValue(
  input: HTMLInputElement | HTMLTextAreaElement,
  value: string
) {
  const prototype =
    input instanceof HTMLTextAreaElement
      ? window.HTMLTextAreaElement.prototype
      : window.HTMLInputElement.prototype
  const descriptor = Object.getOwnPropertyDescriptor(prototype, 'value')

  descriptor?.set?.call(input, value)
  input.dispatchEvent(new Event('input', { bubbles: true }))
  maintainActiveInputFocus()
}

export function openOnScreenKeyboard(
  input: HTMLInputElement | HTMLTextAreaElement
) {
  const isSameActiveInput =
    onScreenKeyboardVisible.value && activeInputElement.value === input

  if (isSameActiveInput) {
    markKeyboardTarget(input)
    attachBlurGuard(input)
    if (document.activeElement !== input) {
      focusInputAtEnd(input)
    }
    return
  }

  if (onScreenKeyboardVisible.value && activeInputElement.value) {
    detachBlurGuard()
  }

  activeInputElement.value = input
  committedText.value = input.value
  onScreenKeyboardType.value = resolveKeyboardType(input)
  onScreenKeyboardVisible.value = true
  setKeyboardOpenScrollLock(true)
  markKeyboardTarget(input)
  attachBlurGuard(input)
  focusInputAtEnd(input)
}

export function closeOnScreenKeyboard() {
  detachBlurGuard()
  clearKeyboardTargetMark()
  setKeyboardOpenScrollLock(false)
  onScreenKeyboardVisible.value = false
  activeInputElement.value = null
  committedText.value = ''
}

/**
 * 处理键盘输出。
 * @returns 是否需要在选字后清空键盘内部缓冲（以便继续输入下一个字）
 */
export function applyKeyboardChange(value: string): boolean {
  const input = activeInputElement.value
  if (!input) {
    return false
  }

  if (onScreenKeyboardType.value === 'chinese') {
    if (!value) {
      setInputValue(input, committedText.value)
      return false
    }

    if (isPinyinComposing(value) || isLatinOrDigitComposing(value)) {
      setInputValue(input, committedText.value + value)
      return false
    }

    if (containsChinese(value)) {
      committedText.value += value
      setInputValue(input, committedText.value)
      return true
    }
  }

  setInputValue(input, committedText.value + value)
  return false
}

export function applyBackspace() {
  const input = activeInputElement.value
  if (!input || committedText.value.length === 0) {
    return
  }

  committedText.value = committedText.value.slice(0, -1)
  setInputValue(input, committedText.value)
}

export function applySpace() {
  const input = activeInputElement.value
  if (!input) {
    return
  }

  committedText.value += ' '
  setInputValue(input, committedText.value)
}

export function clearKeyboardInput() {
  committedText.value = ''
  const input = activeInputElement.value
  if (input) {
    setInputValue(input, '')
  }
}

export function finalizeBufferToCommitted() {
  const input = activeInputElement.value
  if (input) {
    committedText.value = input.value
  }
}

/** 外部修改输入框内容时（如清空按钮），通知键盘组件重置内部缓冲 */
export const keyboardSessionResetSignal = ref(0)

/** 外部修改输入框内容时，同步键盘已确认文字与输入框 DOM */
export function syncKeyboardSessionValue(value: string) {
  committedText.value = value
  const input = activeInputElement.value
  if (input) {
    setInputValue(input, value)
  }
  keyboardSessionResetSignal.value += 1
}

export function syncKeyboardSession(input: HTMLInputElement | HTMLTextAreaElement) {
  markKeyboardTarget(input)
  attachBlurGuard(input)
}

export function isActiveKeyboardInput(
  input: HTMLInputElement | HTMLTextAreaElement | null | undefined
) {
  return (
    Boolean(input) &&
    onScreenKeyboardVisible.value &&
    activeInputElement.value === input
  )
}

type SubmitPassthroughTarget = {
  element: HTMLElement
  handler: () => void
}

let submitPassthroughTarget: SubmitPassthroughTarget | null = null

export function registerSubmitPassthrough(
  element: HTMLElement | null | undefined,
  handler: (() => void) | null | undefined
) {
  if (!element || !handler) {
    submitPassthroughTarget = null
    return
  }

  submitPassthroughTarget = { element, handler }
}

function getPointerClientPoint(event: MouseEvent | TouchEvent) {
  if ('touches' in event) {
    const touch = event.touches[0] ?? event.changedTouches[0]
    if (!touch) {
      return null
    }

    return { x: touch.clientX, y: touch.clientY }
  }

  return { x: event.clientX, y: event.clientY }
}

/** 键盘打开时，若点击落在注册按钮区域，则转发点击（用于底部提交按钮） */
export function trySubmitPassthrough(event: MouseEvent | TouchEvent) {
  if (!submitPassthroughTarget) {
    return false
  }

  if (event.target instanceof Element) {
    const keyboardRoot = event.target.closest('.keyboard-panel, .qms-on-screen-keyboard')
    if (keyboardRoot) {
      return false
    }
  }

  const point = getPointerClientPoint(event)
  if (!point) {
    return false
  }

  const rect = submitPassthroughTarget.element.getBoundingClientRect()
  const { x, y } = point

  if (
    x >= rect.left &&
    x <= rect.right &&
    y >= rect.top &&
    y <= rect.bottom
  ) {
    submitPassthroughTarget.handler()
    return true
  }

  return false
}
