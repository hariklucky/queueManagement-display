import { createApp } from 'vue'
import './style.css'
import App from './App.vue'
import { setupDevtoolsShortcut } from './utils/debugDevtools'
import { setupTouchKeyboard } from './utils/touchKeyboard'
import { getApiBaseURL } from './utils/request'
import { isHttpLogEnabled } from './utils/httpLogger'
import { isTauri } from '@tauri-apps/api/core'

if (isHttpLogEnabled()) {
  console.info('[QMS] 运行环境', {
    mode: import.meta.env.MODE,
    isTauri: isTauri(),
    apiBaseURL: getApiBaseURL(),
    hint: isTauri() && import.meta.env.PROD
      ? '生产包 HTTP 走 Rust 原生请求，请在 Console 查看 [QMS] 日志（Network 不显示真实地址）'
      : '开发模式可在 Network 面板查看 /api 请求',
  })
}

setupDevtoolsShortcut()

const app = createApp(App)
app.mount('#app')

// 等 Vue 挂载完成后再注册，避免 isTauri / DOM 未就绪
setupTouchKeyboard()
