/** 页面路由状态 */
export type PageType = 'home' | 'appointment' | 'appointmentDetail' | 'walkin' | 'result'

/** 业务类型下拉选项 */
export interface BusinessTypeOption {
  value: string
  label: string
}

/** 预约信息确认页展示数据 */
export interface AppointmentDisplayData {
  number: string
  business: string
  name: string
  phone: string
  time: string
}

/** 取号结果页展示数据 */
export interface TicketDisplayData {
  number: string
  business: string
  name: string
  waiting: number
  time: string
}

/** 取号结果默认展示数据 */
export const DEFAULT_TICKET_RESULT: TicketDisplayData = {
  number: '',
  business: '',
  name: '',
  waiting: 0,
  time: '',
}
