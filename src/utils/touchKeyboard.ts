import { invoke, isTauri } from '@tauri-apps/api/core'

const INPUT_SELECTOR =
  'input:not([disabled]):not([readonly]), textarea:not([disabled]):not([readonly]), select:not([disabled])'

/** 输入框聚焦时唤起 Windows 触摸键盘（TabTip） */
export function setupTouchKeyboard() {
  if (!isTauri()) {
    return
  }

  document.addEventListener(
    'focusin',
    (event) => {
      const target = event.target
      if (!(target instanceof HTMLElement) || !target.matches(INPUT_SELECTOR)) {
        return
      }

      invoke('show_touch_keyboard').catch((error) => {
        console.warn('打开触摸键盘失败', error)
      })
    },
    true,
  )
}
