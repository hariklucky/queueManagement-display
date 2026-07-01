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

function waitForAbortSignal(signal: AbortSignal) {
  return new Promise<never>((_, reject) => {
    if (signal.aborted) {
      reject(signal.reason ?? new DOMException('Aborted', 'AbortError'))
      return
    }

    signal.addEventListener(
      'abort',
      () => {
        reject(signal.reason ?? new DOMException('Aborted', 'AbortError'))
      },
      { once: true }
    )
  })
}

/**
 * 开发模式：WebView fetch（走 Vite 代理，Network 面板可见 /api 请求）。
 * 生产 Tauri：Rust 原生 HTTP（Network 不显示真实 URL，请看 Console 的 [QMS] 日志）。
 */
export async function appFetch(input: string, init?: RequestInit): Promise<Response> {
  if (import.meta.env.DEV || !isTauri()) {
    return fetch(input, init)
  }

  const signal = init?.signal
  const fetchPromise = invoke<NativeHttpResponse>('native_http_fetch', {
    url: input,
    method: init?.method || 'GET',
    headers: normalizeHeaders(init?.headers),
    body: typeof init?.body === 'string' ? init.body : null,
  }).then(
    (result) =>
      new Response(result.body, {
        status: result.status,
        headers: { 'Content-Type': 'application/json' },
      })
  )

  if (!signal) {
    return fetchPromise
  }

  return Promise.race([fetchPromise, waitForAbortSignal(signal)])
}
