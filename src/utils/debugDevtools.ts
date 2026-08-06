/** 生产包中按 F12 打开/关闭 DevTools */
import { isElectron } from './electron'

export function setupDevtoolsShortcut() {
  if (!isElectron() || !window.qms?.toggleDevtools) {
    return
  }

  window.addEventListener('keydown', (event) => {
    if (event.key !== 'F12') {
      return
    }

    event.preventDefault()

    window.qms.toggleDevtools().catch((error) => {
      console.error('打开 DevTools 失败', error)
    })
  })
}
