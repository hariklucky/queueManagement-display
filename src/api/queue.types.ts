import type { BusinessTypeValue } from '../views/queueTicket.types'
import type { TicketDisplayData } from '../views/queueTicket.types'

/** 通用接口响应结构 */
export interface ApiResponse<T = TicketApiData> {
  code?: number
  success?: boolean
  message?: string
  msg?: string
  data?: T
  queueNumber?: string
  number?: string
  queueNo?: string
}

/** 后端返回的排队信息 */
export interface TicketApiData {
  queueNumber?: string
  number?: string
  queueNo?: string
  businessType?: string
  business?: string
  businessName?: string
  name?: string
  userName?: string
  customerName?: string
  waitingCount?: number
  waiting?: number
  waitTime?: string
  waitTimeText?: string
  estimatedWaitTime?: string
}

/** 预约取号 - 刷身份证入参 */
export interface AppointmentQueryByIdCardRequest {
  customerNumber: string
}

/** 预约取号 - 手机号入参 */
export interface AppointmentQueryByPhoneRequest {
  customerPhone: string
}

/** 预约取号查询入参 */
export type AppointmentQueryRequest =
  | AppointmentQueryByIdCardRequest
  | AppointmentQueryByPhoneRequest

/** 现场取号入参 */
export interface WalkinTicketRequest {
  customerName: string
  businessType: BusinessTypeValue | string
  customerNumber?: string
  customerPhone?: string
}

export type { TicketDisplayData }
