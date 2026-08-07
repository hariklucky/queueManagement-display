const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('qms', {
  isElectron: true,
  platform: process.platform,

  loadRuntimeConfig() {
    return ipcRenderer.invoke('qms:load-runtime-config')
  },

  saveRuntimeConfig(partial) {
    return ipcRenderer.invoke('qms:save-runtime-config', partial)
  },

  httpFetch(payload) {
    return ipcRenderer.invoke('qms:http-fetch', payload)
  },

  showTouchKeyboard() {
    return ipcRenderer.invoke('qms:show-touch-keyboard')
  },

  warmUpTouchKeyboard() {
    return ipcRenderer.invoke('qms:warm-up-touch-keyboard')
  },

  toggleDevtools() {
    return ipcRenderer.invoke('qms:toggle-devtools')
  },

  openExternal(url) {
    return ipcRenderer.invoke('qms:open-external', url)
  },

  quitApp() {
    // 退出后进程会结束，无需等待；send 比 invoke 更不容易因通道销毁报错
    ipcRenderer.send('qms:quit-app')
    return Promise.resolve(true)
  },

  getAutoLaunch() {
    return ipcRenderer.invoke('qms:get-auto-launch')
  },

  setAutoLaunch(enabled) {
    return ipcRenderer.invoke('qms:set-auto-launch', enabled)
  },
})
