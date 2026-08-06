/** 是否运行在 Electron 桌面壳中 */
export function isElectron(): boolean {
  return Boolean(window.qms?.isElectron)
}

export function getElectronPlatform(): string {
  return window.qms?.platform || ''
}
