import request from '../utils/request'
import type { BusinessTypeOption } from '../views/queueTicket.types'
import type { IdCardInfo } from '../utils/idCardReader.types'
import type {
  ApiResponse,
  AppointmentQueryRequest,
  TerminalBusinessTypeItem,
  TerminalInitData,
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
    '/queue-call/terminal/appointment/query',
    data,
  )
}

/**
 * 预约取号 - 根据身份证号查询
 */
export function getAppointmentTicketByIdCard(idCardInfo: IdCardInfo) {
  return queryAppointmentTicket({
    customerName: idCardInfo.name,
    customerNumber: idCardInfo.idNumber,
    queryType: 'ID_CARD',
  })
}

/**
 * 预约取号 - 根据手机号查询
 */
export function getAppointmentTicketByPhone(phone: string) {
  return queryAppointmentTicket({ customerPhone: phone, queryType: 'PHONE' })
}

/**
 * 终端设备初始化
 * 传入 gatewayId，获取营业厅及业务类型等信息
 */
export function initTerminal(gatewayId: string) {
  return request.get<ApiResponse<TerminalInitData>>(
    '/queue-call/terminal/init',
    { params: { gatewayId } },
  )
}

function flattenBusinessTypeItems(
  items: NonNullable<TerminalInitData['businessTypes']> = [],
): TerminalBusinessTypeItem[] {
  return items.flatMap((item) => {
    const children =
      item.children?.filter((child) => Object.keys(child || {}).length > 0) || []

    if (children.length > 0) {
      return flattenBusinessTypeItems(children)
    }

    return [item]
  })
}

/**
 * 将初始化接口返回的业务类型映射为下拉选项
 */
export function mapBusinessTypes(data: TerminalInitData = {}): BusinessTypeOption[] {
  const payload = data.result || data
  const sourceList =
    payload.businessTypeList ||
    payload.businessTypes ||
    payload.businessList ||
    payload.queueBusinessList ||
    payload.terminalBusinessTypeList ||
    payload.terminalBusinessTypes ||
    payload.records ||
    payload.list ||
    []

  const list: TerminalBusinessTypeItem[] = flattenBusinessTypeItems(sourceList)

  return list
    .map((item: TerminalBusinessTypeItem) => ({
      value:
        item.businessTypeCode ||
        (item.id != null ? String(item.id) : ''),
      label:
        item.businessTypeName ||
        '',
    }))
    .filter((item: BusinessTypeOption) => item.value && item.label)
}

/**
 * 现场终端统一取号
 * 入参: customerName, businessType, customerNumber/customerPhone 至少传一个
 */
export function createWalkinTicket(data: WalkinTicketRequest) {
  return request.post<ApiResponse<TicketApiData>>(
    '/queue-call/terminal/queue/take',
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
export function getResponsePayload<T>(res: ApiResponse<T> | T): T {
  if (res && typeof res === 'object' && 'data' in res && res.data) {
    return res.data
  }

  return res as T
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
export function isApiSuccess(res?: ApiResponse<unknown> | Record<string, unknown>) {
  if (!res) {
    return false
  }

  if ('code' in res && (res.code === 0 || res.code === 200)) {
    return true
  }

  if ('success' in res && res.success === true) {
    return true
  }

  if ('queueNumber' in res || 'number' in res || 'queueNo' in res) {
    return !!(res.queueNumber || res.number || res.queueNo)
  }

  return false
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
