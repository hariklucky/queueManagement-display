import type { IdCardInfo, IdCardRawData } from './idCardReader.types'
import { appFetch } from './httpFetch'

export interface ReadIdCardOptions {
  /** 最长等待用户放卡时间（毫秒），默认 30 秒 */
  timeoutMs?: number
  /** 轮询读卡间隔（毫秒），默认 800 */
  intervalMs?: number
  /** 每次尝试读卡前的回调（可用于更新 UI 提示） */
  onAttempt?: (attempt: number) => void
  /** 用于取消轮询（例如用户离开页面） */
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

const DEFAULT_TIMEOUT_MS = 30_000
const DEFAULT_INTERVAL_MS = 800

function throwIfAborted(signal?: AbortSignal) {
  if (signal?.aborted) {
    throw new ReadIdCardCancelledError()
  }
}

function sleep(ms: number, signal?: AbortSignal) {
  throwIfAborted(signal)

  return new Promise<void>((resolve, reject) => {
    const timer = window.setTimeout(() => {
      signal?.removeEventListener('abort', onAbort)
      resolve()
    }, ms)

    const onAbort = () => {
      window.clearTimeout(timer)
      reject(new ReadIdCardCancelledError())
    }

    signal?.addEventListener('abort', onAbort, { once: true })
  })
}

function getErrorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message
  }

  if (typeof error === 'object' && error && 'message' in error) {
    return String((error as { message?: string }).message)
  }

  return String(error)
}

/** 设备/服务不可用时不继续轮询 */
function shouldRetryReadCard(error: unknown) {
  if (isReadIdCardCancelled(error)) {
    return false
  }

  const message = getErrorMessage(error)

  return !(
    message.includes('读卡器连接失败') ||
    message.includes('接口返回了 HTML') ||
    message.includes('非 JSON')
  )
}

/**
 * 标准化身份证读卡器返回的数据字段
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

/** 单次读卡，未读到证件时会抛错 */
async function readIdCardOnce(): Promise<IdCardInfo> {
  if (window.IdCardReader?.read) {
    const data = await window.IdCardReader.read()
    const idCardInfo = normalizeIdCardInfo(data)

    if (!idCardInfo.idNumber) {
      throw new Error('未能读取到身份证号，请将身份证放在读卡器上')
    }

    return idCardInfo
  }

  const readerUrl =
    import.meta.env.VITE_ID_CARD_READER_URL || 'http://127.0.0.1:8989/api/ReadCard'

  const response = await appFetch(readerUrl, {
    method: 'GET',
    headers: { 'Content-Type': 'application/json' },
  })

  if (!response.ok) {
    throw new Error('身份证读卡器连接失败，请检查设备')
  }

  const data = (await response.json()) as IdCardRawData

  if (
    data.result !== undefined &&
    data.result !== 0 &&
    data.result !== '0' &&
    data.code !== 0 &&
    data.code !== 200
  ) {
    throw new Error(data.message || data.msg || '未检测到身份证，请将证件放在读卡器上')
  }

  const idCardInfo = normalizeIdCardInfo(data)

  if (!idCardInfo.idNumber) {
    throw new Error('未能读取到身份证号，请将身份证放在读卡器上')
  }

  return idCardInfo
}

/**
 * 等待用户放卡并读取身份证。
 * 典型流程：用户先点按钮 → 再将身份证放到读卡器 → 系统在超时前轮询读卡接口。
 */
export async function readIdCard(options: ReadIdCardOptions = {}): Promise<IdCardInfo> {
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS
  const intervalMs = options.intervalMs ?? DEFAULT_INTERVAL_MS
  const { signal } = options
  const deadline = Date.now() + timeoutMs
  let attempt = 0
  let lastError: unknown

  while (Date.now() < deadline) {
    throwIfAborted(signal)

    attempt += 1
    options.onAttempt?.(attempt)

    try {
      return await readIdCardOnce()
    } catch (error) {
      if (isReadIdCardCancelled(error)) {
        throw error
      }

      lastError = error

      if (!shouldRetryReadCard(error)) {
        throw error
      }
    }

    await sleep(intervalMs, signal)
  }

  throwIfAborted(signal)

  if (lastError instanceof Error) {
    throw lastError
  }

  throw new Error('读取身份证超时，请重新点击按钮后再放置身份证')
}
