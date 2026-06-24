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

instance.interceptors.response.use(
  (response) => response.data,
  (error) => Promise.reject(error),
)

const request = instance as unknown as RequestClient

export default request
