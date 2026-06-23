/** 身份证读卡器原始返回数据（字段名因厂商而异） */
export interface IdCardRawData {
  name?: string
  Name?: string
  idNumber?: string
  idNum?: string
  IDCard?: string
  gender?: string
  sex?: string
  Sex?: string
  nation?: string
  Nation?: string
  address?: string
  Address?: string
  birthday?: string
  born?: string
  Born?: string
  phone?: string
  Phone?: string
  mobile?: string
  result?: number | string
  code?: number
  message?: string
  msg?: string
}

/** 标准化后的身份证信息 */
export interface IdCardInfo {
  name: string
  idNumber: string
  gender: string
  nation: string
  address: string
  birthday: string
  phone: string
}

/** 宿主注入的身份证读卡器 */
export interface IdCardReaderBridge {
  read: () => Promise<IdCardRawData>
}

declare global {
  interface Window {
    IdCardReader?: IdCardReaderBridge
  }
}

export {}
