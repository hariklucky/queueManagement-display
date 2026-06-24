/** 页面路由状态 */
export type PageType = 'home' | 'appointment' | 'walkin' | 'result'

/** 业务类型下拉选项 */
export interface BusinessTypeOption {
  value: string
  label: string
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
  number: 'A008',
  business: '开户办理',
  name: '张三',
  waiting: 3,
  time: '15分钟',
}
