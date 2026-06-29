import { getDeviceInfo, getNetworkInfo } from 'tauri-plugin-device-info-api'
import { isTauri } from '@tauri-apps/api/core'

/** 通过设备信息插件获取终端唯一编号，用作初始化接口的 gatewayId */
export async function getGatewayId(): Promise<string> {
  const { uuid } = await getDeviceInfo()
  const res = await getNetworkInfo()

  console.log('网络相关信息', res)
  const gatewayId = uuid?.trim()

  if (!gatewayId) {
    throw new Error('未能获取终端设备编号，请检查设备信息')
  }

  return gatewayId
}

/** 优先读设备 UUID，失败时用 .env 中的 VITE_GATEWAY_ID 兜底 */
export async function resolveGatewayId(): Promise<string> {
  const envGatewayId = import.meta.env.VITE_GATEWAY_ID?.trim()

  if (isTauri()) {
    try {
      return await getGatewayId()
    } catch (error) {
      if (envGatewayId) {
        return envGatewayId
      }
      throw error
    }
  }

  if (envGatewayId) {
    return envGatewayId
  }

  throw new Error('开发环境请在 .env.development 中配置 VITE_GATEWAY_ID')
}
