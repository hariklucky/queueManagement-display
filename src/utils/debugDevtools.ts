import { invoke, isTauri } from '@tauri-apps/api/core'

/** 生产包中按 F12 打开/关闭 DevTools（需 Cargo devtools feature） */
export function setupDevtoolsShortcut() {
  if (!isTauri()) {
    return
  }

  window.addEventListener('keydown', (event) => {
    if (event.key !== 'F12') {
      return
    }

    event.preventDefault()

    invoke('plugin:webview|internal_toggle_devtools').catch((error) => {
      console.error('打开 DevTools 失败', error)
    })
  })
}
