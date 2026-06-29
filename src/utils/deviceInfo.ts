import { getDeviceInfo,getNetworkInfo } from 'tauri-plugin-device-info-api'

/** 通过设备信息插件获取终端唯一编号，用作初始化接口的 gatewayId */
export async function getGatewayId(): Promise<string> {
  const { uuid } = await getDeviceInfo()
  const res = await getNetworkInfo()
  
  console.log("网络相关信息",res)
  const gatewayId = uuid?.trim()

  if (!gatewayId) {
    throw new Error('未能获取终端设备编号，请检查设备信息')
  }

  return gatewayId
}
