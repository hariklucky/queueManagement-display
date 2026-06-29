import { isTauri } from '@tauri-apps/api/core'
import { fetch as tauriFetch } from '@tauri-apps/plugin-http'

/**
 * 开发模式走 WebView fetch（走 Vite 代理，DevTools Network 可见）。
 * 打包后走 Tauri 原生 HTTP，绕过 WebView CORS。
 */
export function appFetch(input: string, init?: RequestInit): Promise<Response> {
  if (import.meta.env.DEV || !isTauri()) {
    return fetch(input, init)
  }

  return tauriFetch(input, init)
}
