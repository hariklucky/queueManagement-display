import { isElectron } from './electron'

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

function validateElectronProductionBaseURL(baseURL: string) {
  if (import.meta.env.PROD && isElectron() && !/^https?:\/\//i.test(baseURL)) {
    throw new Error(
      `生产包 API 地址无效（当前：${baseURL}）。` +
        '请在应用安装目录 config.json 中设置 apiBaseUrl，例如 http://192.168.0.101:18084/api。',
    )
  }
}

async function loadConfigFromSources() {
  if (isElectron() && window.qms?.loadRuntimeConfig) {
    try {
      return await window.qms.loadRuntimeConfig()
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
  validateElectronProductionBaseURL(apiBaseURL)

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

export async function saveApiBaseUrl(nextUrl: string) {
  const trimmed = nextUrl.trim()
  if (!trimmed) {
    throw new Error('请输入后端请求地址')
  }

  const normalized = normalizeBaseURL(trimmed)
  if (!/^https?:\/\//i.test(normalized)) {
    throw new Error('请输入以 http:// 或 https:// 开头的完整地址，例如 http://192.168.0.101:18084/api')
  }

  if (isElectron() && window.qms?.saveRuntimeConfig) {
    runtimeConfig = await window.qms.saveRuntimeConfig({ apiBaseUrl: normalized })
  } else {
    runtimeConfig = { ...runtimeConfig, apiBaseUrl: normalized }
  }

  apiBaseURL = normalized
  initialized = true
  console.info('[QMS] 已更新 apiBaseUrl:', apiBaseURL)
  return apiBaseURL
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
