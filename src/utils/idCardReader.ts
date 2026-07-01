import type {
  IdCardInfo,
  IdCardRawData,
  IdCardReadApiData,
  IdCardReadApiResponse,
} from './idCardReader.types'
import { buildApiUrl } from './request'
import { appFetch } from './httpFetch'
import { getBusinessHallId } from './terminalContext'

export interface ReadIdCardOptions {
  /** 单次读卡请求超时（毫秒），默认 10 秒 */
  timeoutMs?: number
  /** 读卡尝试前的回调 */
  onAttempt?: (attempt: number) => void
  /** 用于取消读卡（例如用户关闭弹窗） */
  signal?: AbortSignal
}

export class ReadIdCardCancelledError extends Error {
  constructor() {
    super('读卡已取消')
    this.name = 'ReadIdCardCancelledError'
  }
}

export function isReadIdCardCancelled(error: unknown) {
  return error instanceof ReadIdCardCancelledError
}

const DEFAULT_TIMEOUT_MS = 10_000
const ID_CARD_READ_PATH = '/queue-call/id-card/read'

function createReadIdCardSignal(
  parentSignal?: AbortSignal,
  timeoutMs = DEFAULT_TIMEOUT_MS
) {
  const controller = new AbortController()

  const timer = window.setTimeout(() => {
    if (!controller.signal.aborted) {
      controller.abort(new DOMException('读取身份证超时', 'TimeoutError'))
    }
  }, timeoutMs)

  const cleanup = () => {
    window.clearTimeout(timer)
  }

  const abortWith = (reason: unknown) => {
    cleanup()
    if (!controller.signal.aborted) {
      controller.abort(reason)
    }
  }

  if (parentSignal?.aborted) {
    abortWith(parentSignal.reason ?? new ReadIdCardCancelledError())
    return controller.signal
  }

  parentSignal?.addEventListener(
    'abort',
    () => {
      abortWith(parentSignal.reason ?? new ReadIdCardCancelledError())
    },
    { once: true }
  )

  controller.signal.addEventListener('abort', cleanup, { once: true })

  return controller.signal
}

function throwIfAborted(signal?: AbortSignal) {
  if (signal?.aborted) {
    throw new ReadIdCardCancelledError()
  }
}

function normalizeReadIdCardError(error: unknown, signal?: AbortSignal) {
  throwIfAborted(signal)

  if (isReadIdCardCancelled(error)) {
    return error
  }

  if (error instanceof DOMException && error.name === 'AbortError') {
    return new ReadIdCardCancelledError()
  }

  if (error instanceof DOMException && error.name === 'TimeoutError') {
    return new Error('读取身份证超时，请重新点击按钮后再放置身份证')
  }

  return error
}

/**
 * 标准化身份证读卡器返回的数据字段（兼容旧读卡器 / 宿主注入）
 */
export function normalizeIdCardInfo(raw: IdCardRawData = {}): IdCardInfo {
  return {
    name: raw.name || raw.Name || '',
    idNumber: raw.idNumber || raw.idNum || raw.IDCard || '',
    gender: raw.gender || raw.sex || raw.Sex || '',
    nation: raw.nation || raw.Nation || '',
    address: raw.address || raw.Address || '',
    birthday: raw.birthday || raw.born || raw.Born || '',
    phone: raw.phone || raw.Phone || raw.mobile || '',
  }
}

/** 映射后端 /queue-call/id-card/read 返回的 data */
export function mapIdCardReadApiData(data: IdCardReadApiData = {}): IdCardInfo {
  return {
    name: data.name || '',
    idNumber: data.idNumber || data.idCard || '',
    gender: data.gender || '',
    nation: data.nation || '',
    address: data.address || '',
    birthday: data.birthDate || '',
    phone: '',
  }
}

function buildIdCardReadHeaders() {
  const headers: Record<string, string> = {
    Accept: 'application/json',
  }

  const hallId = getBusinessHallId()
  if (hallId) {
    headers['X-Business-Hall-Id'] = hallId
  }

  return headers
}

async function readIdCardFromBridge(signal?: AbortSignal): Promise<IdCardInfo> {
  throwIfAborted(signal)

  const data = await window.IdCardReader!.read()
  throwIfAborted(signal)

  const idCardInfo = normalizeIdCardInfo(data)
  if (!idCardInfo.name && !idCardInfo.idNumber) {
    throw new Error('未能读取到身份证信息，请将身份证放在读卡器上')
  }

  return idCardInfo
}

async function readIdCardFromApi(signal?: AbortSignal): Promise<IdCardInfo> {
  throwIfAborted(signal)

  const response = await appFetch(buildApiUrl(ID_CARD_READ_PATH), {
    method: 'GET',
    headers: buildIdCardReadHeaders(),
    signal,
  })

  throwIfAborted(signal)

  let payload: IdCardReadApiResponse
  try {
    payload = (await response.json()) as IdCardReadApiResponse
  } catch {
    throw new Error('身份证读卡接口返回了非 JSON 数据，请检查后端服务')
  }

  if (!response.ok) {
    throw new Error(payload.msg || '身份证读卡请求失败，请检查设备')
  }

  if (payload.code !== 0) {
    throw new Error(payload.msg || '读取失败')
  }

  if (!payload.data?.name) {
    throw new Error(payload.msg || '未能读取到身份证姓名，请将证件放在读卡器上')
  }

  return mapIdCardReadApiData(payload.data)
}

/** 单次读卡，未读到证件时会抛错 */
async function readIdCardOnce(signal?: AbortSignal): Promise<IdCardInfo> {
  if (window.IdCardReader?.read) {
    return readIdCardFromBridge(signal)
  }

  return readIdCardFromApi(signal)
}

/**
 * 读取身份证（单次请求，不轮询）。
 */
export async function readIdCard(options: ReadIdCardOptions = {}): Promise<IdCardInfo> {
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS
  const requestSignal = createReadIdCardSignal(options.signal, timeoutMs)

  throwIfAborted(options.signal)
  options.onAttempt?.(1)

  try {
    return await readIdCardOnce(requestSignal)
  } catch (error) {
    throw normalizeReadIdCardError(error, options.signal)
  }
}
