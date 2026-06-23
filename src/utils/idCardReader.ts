import type { IdCardInfo, IdCardRawData } from './idCardReader.types'

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

/**
 * 调用身份证感应器读取证件信息
 * 优先使用宿主注入的 window.IdCardReader，否则请求本地读卡服务
 */
export async function readIdCard(): Promise<IdCardInfo> {
  if (window.IdCardReader?.read) {
    const data = await window.IdCardReader.read()
    return normalizeIdCardInfo(data)
  }

  const readerUrl =
    import.meta.env.VITE_ID_CARD_READER_URL || 'http://127.0.0.1:8989/api/ReadCard'

  const response = await fetch(readerUrl, {
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
    throw new Error(data.message || data.msg || '读取身份证失败，请重新放置身份证')
  }

  const idCardInfo = normalizeIdCardInfo(data)

  if (!idCardInfo.idNumber) {
    throw new Error('未能读取到身份证号，请重新放置身份证')
  }

  return idCardInfo
}
