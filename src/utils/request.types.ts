/** 后端错误响应结构 */
export interface ApiErrorResponse {
  message?: string
  msg?: string
  code?: number
}

/** 请求错误 */
export interface RequestError {
  message?: string
  response?: {
    status?: number
    data?: ApiErrorResponse
  }
}

export interface RequestConfig {
  params?: Record<string, string | number | boolean | undefined>
}

/** 封装后的请求客户端（响应拦截器已返回 data） */
export interface RequestClient {
  get<T = unknown>(url: string, config?: RequestConfig): Promise<T>
  post<T = unknown>(url: string, data?: unknown, config?: RequestConfig): Promise<T>
  put<T = unknown>(url: string, data?: unknown, config?: RequestConfig): Promise<T>
  delete<T = unknown>(url: string, config?: RequestConfig): Promise<T>
}
