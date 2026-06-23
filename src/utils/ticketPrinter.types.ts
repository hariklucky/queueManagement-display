import type { TicketDisplayData } from '../views/queueTicket.types'

/** 打印小票展示数据 */
export type TicketPrintData = TicketDisplayData

/** 发送给打印服务的请求体 */
export interface TicketPrintPayload {
  content: string
  queueNumber: string
  name: string
  businessType: string
  waitingCount: number
  waitTime: string
}

/** 打印服务响应 */
export interface TicketPrintResponse {
  result?: number | string
  code?: number
  message?: string
  msg?: string
}

/** 宿主注入的小票打印机 */
export interface TicketPrinterBridge {
  print: (payload: TicketPrintPayload) => Promise<void>
}

declare global {
  interface Window {
    TicketPrinter?: TicketPrinterBridge
  }
}

export {}
