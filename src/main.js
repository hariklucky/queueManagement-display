import { createApp } from 'vue'
import './style.css'
import App from './App.vue'
import { setupDevtoolsShortcut } from './utils/debugDevtools'
import { setupTouchKeyboard } from './utils/touchKeyboard'
import { initRuntimeConfig, getApiBaseURL } from './utils/runtimeConfig'
import { isHttpLogEnabled } from './utils/httpLogger'
import { isTauri } from '@tauri-apps/api/core'

async function bootstrap() {
  try {
    await initRuntimeConfig()
  } catch (error) {
    console.error('[QMS] 初始化运行配置失败', error)
  }

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

  setupTouchKeyboard()
}

bootstrap()
