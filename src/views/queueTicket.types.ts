/** 页面路由状态 */
export type PageType = 'home' | 'appointment' | 'walkin' | 'result'

/** 业务类型枚举值 */
export type BusinessTypeValue =
  | 'account-opening'
  | 'account-cancellation'
  | 'information-change'
  | 'business-consulting'
  | 'card-replacement'
  | 'loan-business'

/** 业务类型下拉选项 */
export interface BusinessTypeOption {
  value: BusinessTypeValue
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

/** 业务类型列表 */
export const BUSINESS_TYPES: BusinessTypeOption[] = [
  { value: 'account-opening', label: '开户办理' },
  { value: 'account-cancellation', label: '销户办理' },
  { value: 'information-change', label: '信息变更' },
  { value: 'business-consulting', label: '业务咨询' },
  { value: 'card-replacement', label: '补换卡业务' },
  { value: 'loan-business', label: '贷款业务' },
]

/** 取号结果默认展示数据 */
export const DEFAULT_TICKET_RESULT: TicketDisplayData = {
  number: 'A008',
  business: '开户办理',
  name: '张三',
  waiting: 3,
  time: '15分钟',
}
