/** 开发模式或 .env.production 中 VITE_APP_DEBUG=true 时输出 HTTP 日志 */
export function isHttpLogEnabled() {
  return import.meta.env.DEV || import.meta.env.VITE_APP_DEBUG === 'true'
}

interface HttpLogRequest {
  method: string
  url: string
  headers?: Record<string, string>
  body?: string
}

interface HttpLogResponse {
  status: number
  durationMs: number
  bodyPreview: string
  data?: unknown
}

export function logHttpRequest({ method, url, headers, body }: HttpLogRequest) {
  if (!isHttpLogEnabled()) {
    return
  }

  console.groupCollapsed(`[QMS] → ${method} ${url}`)
  console.info('请求地址', url)
  if (headers && Object.keys(headers).length > 0) {
    console.info('请求头', headers)
  }
  if (body) {
    try {
      console.info('请求体', JSON.parse(body))
    } catch {
      console.info('请求体', body)
    }
  }
  console.groupEnd()
}

export function logHttpResponse(
  method: string,
  url: string,
  { status, durationMs, bodyPreview, data }: HttpLogResponse,
) {
  if (!isHttpLogEnabled()) {
    return
  }

  const ok = status >= 200 && status < 300
  const label = ok ? '←' : '✗'
  const logFn = ok ? console.info : console.error

  console.groupCollapsed(`[QMS] ${label} ${method} ${url} (${status}, ${durationMs}ms)`)
  logFn('状态码', status)
  logFn('耗时', `${durationMs}ms`)
  if (data !== undefined) {
    logFn('响应数据', data)
  } else {
    logFn('响应预览', bodyPreview)
  }
  console.groupEnd()
}

export function logHttpError(method: string, url: string, error: unknown, durationMs: number) {
  if (!isHttpLogEnabled()) {
    return
  }

  console.groupCollapsed(`[QMS] ✗ ${method} ${url} (失败, ${durationMs}ms)`)
  console.error('错误', error)
  console.groupEnd()
}
