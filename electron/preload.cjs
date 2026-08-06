const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('qms', {
  isElectron: true,
  platform: process.platform,

  loadRuntimeConfig() {
    return ipcRenderer.invoke('qms:load-runtime-config')
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
})
