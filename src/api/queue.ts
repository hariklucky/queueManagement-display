import request from '../utils/request'
import type { IdCardInfo } from '../utils/idCardReader.types'
import type {
  ApiResponse,
  AppointmentQueryRequest,
  TicketApiData,
  TicketDisplayData,
  WalkinTicketRequest,
} from './queue.types'

/**
 * 查询可取号预约
 * 刷身份证入参: customerNumber
 * 手机号查询入参: customerPhone
 */
export function queryAppointmentTicket(data: AppointmentQueryRequest) {
  return request.post<ApiResponse<TicketApiData>>(
    '/svr-businesshall-devqueue/terminal/appointment/query',
    data,
  )
}

/**
 * 预约取号 - 根据身份证号查询
 */
export function getAppointmentTicketByIdCard(idCardInfo: IdCardInfo) {
  return queryAppointmentTicket({
    customerNumber: idCardInfo.idNumber,
  })
}

/**
 * 预约取号 - 根据手机号查询
 */
export function getAppointmentTicketByPhone(phone: string) {
  return queryAppointmentTicket({ customerPhone: phone })
}

/**
 * 现场终端统一取号
 * 入参: customerName, businessType, customerNumber/customerPhone 至少传一个
 */
export function createWalkinTicket(data: WalkinTicketRequest) {
  return request.post<ApiResponse<TicketApiData>>(
    '/svr-businesshall-devqueue/terminal/queue/take',
    data,
  )
}

/**
 * 将后端返回数据映射为页面展示格式
 */
export function mapTicketResult(data: TicketApiData = {}): TicketDisplayData {
  return {
    number: data.queueNumber || data.number || data.queueNo || '',
    business: data.businessType || data.business || data.businessName || '',
    name: data.customerName || data.name || data.userName || '',
    waiting: data.waitingCount ?? data.waiting ?? 0,
    time: data.waitTime || data.waitTimeText || data.estimatedWaitTime || '',
  }
}

/**
 * 提取接口中的业务数据
 */
export function getResponsePayload(
  res: ApiResponse<TicketApiData> | TicketApiData,
): TicketApiData {
  if ('data' in res && res.data) {
    return res.data
  }

  return res
}

/**
 * 提取接口错误信息
 */
export function getResponseErrorMessage(
  res: ApiResponse<TicketApiData> | TicketApiData,
  fallback: string,
) {
  if ('message' in res && res.message) {
    return res.message
  }

  if ('msg' in res && res.msg) {
    return res.msg
  }

  return fallback
}

/**
 * 判断接口业务是否成功
 */
export function isApiSuccess(res?: ApiResponse<TicketApiData> | TicketApiData) {
  if (!res) {
    return false
  }

  if ('code' in res && (res.code === 0 || res.code === 200)) {
    return true
  }

  if ('success' in res && res.success === true) {
    return true
  }

  return !!(res.queueNumber || res.number || res.queueNo)
}

/**
 * 提取接口错误信息
 */
export function getApiErrorMessage(
  error: {
    response?: { data?: { message?: string; msg?: string } }
    message?: string
  },
  fallback = '操作失败，请重试',
) {
  return error?.response?.data?.message || error?.response?.data?.msg || error?.message || fallback
}
