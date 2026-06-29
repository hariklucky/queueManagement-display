import axios from 'axios'
import type { RequestClient } from './request.types'
import { getBusinessHallId } from './terminalContext'

const instance = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL || '/api',
  timeout: 10000,
})

instance.interceptors.request.use(
  (config) => {
    const hallId = getBusinessHallId()
    if (hallId) {
      config.headers.set('X-Business-Hall-Id', hallId)
    }
    return config
  },
  (error) => Promise.reject(error),
)

function validateResponseData(data: unknown): unknown {
  if (typeof data === 'string' && data.trimStart().startsWith('<!DOCTYPE')) {
    const baseURL = import.meta.env.VITE_API_BASE_URL || '/api'
    throw new Error(
      `接口返回了 HTML 页面而非 JSON，请检查 VITE_API_BASE_URL（当前：${baseURL}）。` +
        '打包后的桌面应用不会走 Vite 代理，需配置为后端完整地址后重新构建。',
    )
  }

  if (data != null && typeof data !== 'object') {
    throw new Error('接口返回了非 JSON 数据，请检查后端地址与网络连接')
  }

  return data
}

instance.interceptors.response.use(
  (response) => validateResponseData(response.data) as any,
  (error) => Promise.reject(error),
)

const request = instance as unknown as RequestClient

export default request
