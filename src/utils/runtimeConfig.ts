import { invoke, isTauri } from '@tauri-apps/api/core'

export interface RuntimeConfig {
  apiBaseUrl?: string
  gatewayId?: string
  forceOnScreenKeyboard?: boolean
}

let runtimeConfig: RuntimeConfig = {}
let apiBaseURL: string | null = null
let initialized = false

function resolveEnvBaseURL() {
  const configured = import.meta.env.VITE_API_BASE_URL?.trim()
  return configured || '/api'
}

function normalizeBaseURL(value: string) {
  return value.replace(/\/$/, '')
}

function validateTauriProductionBaseURL(baseURL: string) {
  if (import.meta.env.PROD && isTauri() && !/^https?:\/\//i.test(baseURL)) {
    throw new Error(
      `生产包 API 地址无效（当前：${baseURL}）。` +
        '请在应用安装目录 config.json 中设置 apiBaseUrl，例如 http://192.168.0.101:18084/api。',
    )
  }
}

async function loadConfigFromSources() {
  if (isTauri()) {
    try {
      return await invoke<RuntimeConfig>('load_runtime_config')
    } catch (error) {
      console.warn('[QMS] 读取安装目录 config.json 失败，将使用环境变量兜底', error)
      return {}
    }
  }

  return {}
}

export async function initRuntimeConfig() {
  if (initialized) {
    return runtimeConfig
  }

  initialized = true
  runtimeConfig = await loadConfigFromSources()

  const fromFile = runtimeConfig.apiBaseUrl?.trim()
  apiBaseURL = normalizeBaseURL(fromFile || resolveEnvBaseURL())
  validateTauriProductionBaseURL(apiBaseURL)

  if (fromFile) {
    console.info('[QMS] 使用安装目录 config.json 中的 apiBaseUrl:', apiBaseURL)
  } else {
    console.info('[QMS] 使用环境变量 VITE_API_BASE_URL:', apiBaseURL)
  }

  return runtimeConfig
}

export function getRuntimeConfig() {
  return runtimeConfig
}

export function getApiBaseURL() {
  if (!initialized) {
    return resolveEnvBaseURL()
  }

  return apiBaseURL ?? resolveEnvBaseURL()
}

export function getRuntimeGatewayId() {
  return runtimeConfig.gatewayId?.trim() || ''
}

export function shouldForceOnScreenKeyboardFromConfig() {
  if (typeof runtimeConfig.forceOnScreenKeyboard === 'boolean') {
    return runtimeConfig.forceOnScreenKeyboard
  }

  return import.meta.env.VITE_FORCE_ON_SCREEN_KEYBOARD === 'true'
}
