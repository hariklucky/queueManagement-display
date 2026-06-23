import type { AxiosError, AxiosRequestConfig } from 'axios'

/** 后端错误响应结构 */
export interface ApiErrorResponse {
  message?: string
  msg?: string
  code?: number
}

/** axios 请求错误 */
export type RequestError = AxiosError<ApiErrorResponse>

/** 封装后的请求客户端（响应拦截器已返回 data） */
export interface RequestClient {
  get<T = unknown>(url: string, config?: AxiosRequestConfig): Promise<T>
  post<T = unknown>(url: string, data?: unknown, config?: AxiosRequestConfig): Promise<T>
  put<T = unknown>(url: string, data?: unknown, config?: AxiosRequestConfig): Promise<T>
  delete<T = unknown>(url: string, config?: AxiosRequestConfig): Promise<T>
}
