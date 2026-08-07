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

function shouldUseNativeHttp(url: string) {
  if (!isElectron() || !window.qms?.httpFetch) {
    return false
  }

  // 相对路径（如 /api）在开发模式走 Vite 代理，便于 Network 面板调试
  if (!/^https?:\/\//i.test(url)) {
    return false
  }

  // 绝对地址一律走主进程，避免 Vite(5173)→后端(18084) 的 CORS 拦截
  return true
}

/**
 * 相对 /api：开发模式用浏览器 fetch（经 Vite 代理）。
 * 绝对 http(s) 地址：Electron 主进程 net.request，避免跨域与 file:// 限制。
 */
export async function appFetch(input: string, init?: RequestInit): Promise<Response> {
  if (!shouldUseNativeHttp(input)) {
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
