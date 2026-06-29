import { invoke, isTauri } from '@tauri-apps/api/core'

interface NativeHttpResponse {
  status: number
  body: string
}

function normalizeHeaders(headers?: HeadersInit): Record<string, string> {
  const result: Record<string, string> = {}

  if (!headers) {
    return result
  }

  if (headers instanceof Headers) {
    headers.forEach((value, key) => {
      result[key] = value
    })
    return result
  }

  if (Array.isArray(headers)) {
    for (const [key, value] of headers) {
      result[key] = value
    }
    return result
  }

  return { ...headers }
}

/**
 * 开发模式走 WebView fetch（走 Vite 代理）。
 * 生产 Tauri 走 Rust 原生 HTTP，避免 plugin-http 的 response.text() 挂起问题。
 */
export async function appFetch(input: string, init?: RequestInit): Promise<Response> {
  if (import.meta.env.DEV || !isTauri()) {
    return fetch(input, init)
  }

  if (import.meta.env.VITE_APP_DEBUG === 'true') {
    console.info('[QMS HTTP]', init?.method || 'GET', input)
  }

  const result = await invoke<NativeHttpResponse>('native_http_fetch', {
    url: input,
    method: init?.method || 'GET',
    headers: normalizeHeaders(init?.headers),
    body: typeof init?.body === 'string' ? init.body : null,
  })

  if (import.meta.env.VITE_APP_DEBUG === 'true') {
    console.info('[QMS HTTP] 响应', result.status, result.body.slice(0, 200))
  }

  return new Response(result.body, {
    status: result.status,
    headers: { 'Content-Type': 'application/json' },
  })
}
