import { isElectron } from './electron'

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
 * 开发模式：浏览器/Electron 加载 Vite 时走 fetch（代理可见）。
 * 生产 Electron：主进程 net.request，避免 file:// 跨域限制。
 */
export async function appFetch(input: string, init?: RequestInit): Promise<Response> {
  if (import.meta.env.DEV || !isElectron() || !window.qms?.httpFetch) {
    return fetch(input, init)
  }

  const signal = init?.signal
  const fetchPromise = window.qms
    .httpFetch({
      url: input,
      method: init?.method || 'GET',
      headers: normalizeHeaders(init?.headers),
      body: typeof init?.body === 'string' ? init.body : null,
    })
    .then(
      (result: NativeHttpResponse) =>
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
