import { ref, shallowRef } from 'vue'
import { getPinyinCandidates, split } from 'pinyin-match-hanzi'
import { cancelPendingSystemKeyboardInvoke } from './keyboardInvoke'

export type OnScreenKeyboardType = 'chinese' | 'english' | 'number'

export type ApplyKeyboardChangeResult = {
  shouldResetBuffer: boolean
  remainingPinyin: string
}

export const KEYBOARD_TARGET_CLASS = 'qms-keyboard-target'
/** 触屏滑动/点击时不关闭键盘、不 blur 输入框的区域（如业务类型下拉） */
export const KEEP_KEYBOARD_FOCUS_CLASS = 'qms-keep-keyboard-focus'
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
let lastPointerTarget: EventTarget | null = null
let outsideDismissInstalled = false
let lockedScrollY = 0

function resolveKeyboardType(
  _input: HTMLInputElement | HTMLTextAreaElement
): OnScreenKeyboardType {
  return 'chinese'
}

function isPinyinComposing(value: string) {
  return /^[a-zA-Z']+$/.test(value)
}

function containsChinese(value: string) {
  return /[\u4e00-\u9fff]/.test(value)
}

function splitPinyinSyllables(pinyin: string) {
  if (!isPinyinComposing(pinyin)) {
    return []
  }

  const { result } = split(pinyin.toLowerCase())
  return result ?? []
}

function findConsumedPinyinLength(pendingPinyin: string, hanzi: string) {
  if (!pendingPinyin || !hanzi) {
    return pendingPinyin.length
  }

  const matchesPrefix = (prefix: string) => {
    const words = getPinyinCandidates(prefix).map((item) => item.w)
    return words.includes(hanzi)
  }

  // 词组选词（如 woqu 选「我去」）优先消耗最长匹配音节
  if (hanzi.length > 1) {
    for (let len = pendingPinyin.length; len >= 1; len -= 1) {
      if (matchesPrefix(pendingPinyin.slice(0, len))) {
        return len
      }
    }

    return pendingPinyin.length
  }

  // 单字选词：只消耗第一个拼音音节（woqu 选「我」→ wo + qu）
  const syllables = splitPinyinSyllables(pendingPinyin)
  if (syllables.length > 0 && matchesPrefix(syllables[0])) {
    return syllables[0].length
  }

  for (let len = pendingPinyin.length; len >= 1; len -= 1) {
    if (matchesPrefix(pendingPinyin.slice(0, len))) {
      return len
    }
  }

  return pendingPinyin.length
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
  const root = document.documentElement
  const body = document.body

  root.classList.toggle(KEYBOARD_OPEN_CLASS, locked)

  if (locked) {
    lockedScrollY = window.scrollY
    body.style.position = 'fixed'
    body.style.top = `-${lockedScrollY}px`
    body.style.left = '0'
    body.style.right = '0'
    body.style.width = '100%'
    body.style.overflow = 'hidden'
    return
  }

  body.style.position = ''
  body.style.top = ''
  body.style.left = ''
  body.style.right = ''
  body.style.width = ''
  body.style.overflow = ''

  if (lockedScrollY > 0) {
    window.scrollTo(0, lockedScrollY)
  }
  lockedScrollY = 0
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

function isKeepKeyboardFocusTarget(target: EventTarget | null) {
  if (!(target instanceof Element)) {
    return false
  }

  return Boolean(target.closest(`.${KEEP_KEYBOARD_FOCUS_CLASS}`))
}

function isKeyboardInteractionTarget(target: EventTarget | null) {
  if (!(target instanceof Element)) {
    return false
  }

  return Boolean(
    target.closest('.keyboard-panel') ||
      target.closest('.qms-on-screen-keyboard')
  )
}

function isActiveInputTarget(target: EventTarget | null) {
  const input = activeInputElement.value
  if (!input || !(target instanceof Element)) {
    return false
  }

  return target === input || input.contains(target)
}

function resolveEditableInputTarget(target: EventTarget | null) {
  if (!(target instanceof Element)) {
    return null
  }

  const element = target.closest(
    'input:not([disabled]):not([readonly]), textarea:not([disabled]):not([readonly])'
  )

  if (
    element instanceof HTMLInputElement ||
    element instanceof HTMLTextAreaElement
  ) {
    return element
  }

  return null
}

function handleOutsideDismiss(event: PointerEvent) {
  lastPointerTarget = event.target

  if (!onScreenKeyboardVisible.value) {
    return
  }

  if (isKeyboardInteractionTarget(event.target)) {
    return
  }

  if (isKeepKeyboardFocusTarget(event.target)) {
    return
  }

  if (isActiveInputTarget(event.target)) {
    return
  }

  const nextInput = resolveEditableInputTarget(event.target)
  if (nextInput) {
    if (nextInput !== activeInputElement.value) {
      openOnScreenKeyboard(nextInput)
    }
    return
  }

  const input = activeInputElement.value
  closeOnScreenKeyboard()
  input?.blur()
}

export function setupKeyboardOutsideDismiss() {
  if (outsideDismissInstalled) {
    return
  }

  outsideDismissInstalled = true
  document.addEventListener('pointerdown', handleOutsideDismiss, true)
}

export function teardownKeyboardOutsideDismiss() {
  if (!outsideDismissInstalled) {
    return
  }

  outsideDismissInstalled = false
  document.removeEventListener('pointerdown', handleOutsideDismiss, true)
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

    if (
      !(
        lastPointerTarget instanceof Element &&
        (lastPointerTarget.closest('.keyboard-panel, .qms-on-screen-keyboard') ||
          isKeepKeyboardFocusTarget(lastPointerTarget))
      )
    ) {
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
  cancelPendingSystemKeyboardInvoke()

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
  cancelPendingSystemKeyboardInvoke()
  detachBlurGuard()
  clearKeyboardTargetMark()
  setKeyboardOpenScrollLock(false)
  onScreenKeyboardVisible.value = false
  activeInputElement.value = null
  committedText.value = ''
}

/**
 * 处理键盘输出。
 * @param pendingPinyinBeforeUpdate 选字/退格前的键盘拼音缓冲
 */
export function applyKeyboardChange(
  value: string,
  pendingPinyinBeforeUpdate = ''
): ApplyKeyboardChangeResult {
  const input = activeInputElement.value
  if (!input) {
    return { shouldResetBuffer: false, remainingPinyin: '' }
  }

  if (onScreenKeyboardType.value === 'chinese') {
    if (!value) {
      setInputValue(input, committedText.value)
      return { shouldResetBuffer: false, remainingPinyin: '' }
    }

    if (/^[0-9]+$/.test(value)) {
      return { shouldResetBuffer: false, remainingPinyin: '' }
    }

    if (isPinyinComposing(value)) {
      setInputValue(input, committedText.value + value)
      return { shouldResetBuffer: false, remainingPinyin: '' }
    }

    if (containsChinese(value)) {
      let remainingPinyin = ''

      if (isPinyinComposing(pendingPinyinBeforeUpdate)) {
        const consumedLength = findConsumedPinyinLength(
          pendingPinyinBeforeUpdate,
          value
        )
        remainingPinyin = pendingPinyinBeforeUpdate.slice(consumedLength)
      }

      committedText.value += value
      setInputValue(input, committedText.value + remainingPinyin)
      return { shouldResetBuffer: true, remainingPinyin }
    }
  }

  setInputValue(input, committedText.value + value)
  return { shouldResetBuffer: false, remainingPinyin: '' }
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

export function applyDigit(digit: string) {
  const input = activeInputElement.value
  if (!input || !/^[0-9]$/.test(digit)) {
    return
  }

  committedText.value += digit
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

/** 与物理键盘回车一致：提交当前输入框所在表单 */
export function submitActiveInputForm() {
  const input = activeInputElement.value
  if (!input) {
    return
  }

  committedText.value = input.value

  const form = input.closest('form')
  if (form instanceof HTMLFormElement) {
    form.requestSubmit()
    return
  }

  input.dispatchEvent(
    new KeyboardEvent('keydown', {
      key: 'Enter',
      code: 'Enter',
      bubbles: true,
      cancelable: true,
    })
  )
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

export function isRecentKeepKeyboardFocusInteraction() {
  return isKeepKeyboardFocusTarget(lastPointerTarget)
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
