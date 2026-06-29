import { reactive, readonly } from 'vue'
import { mapBusinessTypes } from '../api/queue'
import type { TerminalInitData } from '../api/queue.types'
import type { BusinessTypeOption } from '../views/queueTicket.types'

export interface TerminalInitState {
  initialized: boolean
  gatewayId: string
  businessHallId: string
  businessHallName: string
  businessTypes: readonly BusinessTypeOption[]
  raw: TerminalInitData | null
}

const state = reactive<TerminalInitState>({
  initialized: false,
  gatewayId: '',
  businessHallId: '',
  businessHallName: '',
  businessTypes: [],
  raw: null,
})

/** 只读终端初始化状态，可在任意组件或模块中引用 */
export const terminalStore = readonly(state)

export function setTerminalInitData(data: TerminalInitData, gatewayId?: string) {
  const payload = data.result ?? data
  const businessHallId = payload.businessHallId ?? data.businessHallId

  state.gatewayId = gatewayId ?? data.gatewayId ?? ''
  state.businessHallId = businessHallId != null ? String(businessHallId) : ''
  state.businessHallName = String(payload.businessHallName ?? data.businessHallName ?? '')
  state.businessTypes = mapBusinessTypes(data)
  state.raw = data
  state.initialized = true
}

export function getTerminalInitData() {
  return terminalStore
}

export function getBusinessHallId() {
  return state.businessHallId
}

export function setBusinessHallId(id: string) {
  state.businessHallId = id
}
