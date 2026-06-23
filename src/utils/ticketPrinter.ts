import type { TicketPrintData, TicketPrintPayload, TicketPrintResponse } from './ticketPrinter.types'

function formatPrintTime(date = new Date()) {
  return date.toLocaleString('zh-CN', { hour12: false })
}

/**
 * 生成排队小票文本内容
 */
export function buildTicketContent(ticket: TicketPrintData = {
  number: '',
  business: '',
  name: '',
  waiting: 0,
  time: '',
}) {
  return [
    '================================',
    '      智能排队叫号系统',
    '================================',
    '',
    `排队号码：${ticket.number || '-'}`,
    `姓    名：${ticket.name || '-'}`,
    `业务类型：${ticket.business || '-'}`,
    `等待人数：${ticket.waiting ?? '-'}`,
    `预计等待：${ticket.time || '-'}`,
    '',
    `打印时间：${formatPrintTime()}`,
    '================================',
    '请留意叫号，过号作废',
    '================================',
  ].join('\n')
}

/**
 * 打印排队小票
 * 优先使用宿主注入的 window.TicketPrinter，否则请求本地打印服务
 */
export async function printTicket(ticket: TicketPrintData) {
  const content = buildTicketContent(ticket)
  const payload: TicketPrintPayload = {
    content,
    queueNumber: ticket.number,
    name: ticket.name,
    businessType: ticket.business,
    waitingCount: ticket.waiting,
    waitTime: ticket.time,
  }

  if (window.TicketPrinter?.print) {
    await window.TicketPrinter.print(payload)
    return
  }

  const printUrl =
    import.meta.env.VITE_TICKET_PRINTER_URL || 'http://127.0.0.1:8990/api/PrintTicket'

  const response = await fetch(printUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })

  if (!response.ok) {
    throw new Error('小票打印机连接失败，请检查设备')
  }

  const data = (await response.json()) as TicketPrintResponse

  if (
    data.result !== undefined &&
    data.result !== 0 &&
    data.result !== '0' &&
    data.code !== 0 &&
    data.code !== 200
  ) {
    throw new Error(data.message || data.msg || '打印小票失败')
  }
}
