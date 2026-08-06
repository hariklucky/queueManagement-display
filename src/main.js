import { createApp } from 'vue'
import './style.css'
import App from './App.vue'
import { setupDevtoolsShortcut } from './utils/debugDevtools'
import { setupTouchKeyboard } from './utils/touchKeyboard'
import { initRuntimeConfig, getApiBaseURL } from './utils/runtimeConfig'
import { isHttpLogEnabled } from './utils/httpLogger'
import { isElectron } from './utils/electron'

function clearBootStatus() {
  document.getElementById('boot-status')?.remove()
}

function showBootError(message) {
  const status = document.getElementById('boot-status')
  if (!status) {
    return
  }

  status.textContent = message
  status.style.color = '#b91c1c'
}

async function bootstrap() {
  const app = createApp(App)

  app.config.errorHandler = (error, instance, info) => {
    console.error('[QMS] Vue 渲染错误', error, info, instance)
    showBootError('界面渲染失败，请按 F12 查看控制台错误信息')
  }

  setupDevtoolsShortcut()

  // 必须先读完安装目录 config.json，再挂载页面，避免首个请求仍走打包时的 VITE_API_BASE_URL
  try {
    await initRuntimeConfig()
  } catch (error) {
    console.error('[QMS] 初始化运行配置失败', error)
  }

  app.mount('#app')
  clearBootStatus()
  setupTouchKeyboard()

  if (isHttpLogEnabled()) {
    console.info('[QMS] 运行环境', {
      mode: import.meta.env.MODE,
      isElectron: isElectron(),
      apiBaseURL: getApiBaseURL(),
      hint:
        isElectron() && import.meta.env.PROD
          ? '生产包 HTTP 走 Electron 主进程请求，请在 Console 查看 [QMS] 日志（Network 不显示真实地址）'
          : '开发模式可在 Network 面板查看 /api 请求',
    })
  }
}

bootstrap().catch((error) => {
  console.error('[QMS] 应用启动失败', error)
  showBootError('应用启动失败，请按 F12 查看控制台错误信息')
})
