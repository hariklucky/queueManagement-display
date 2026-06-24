<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import {
  createWalkinTicket,
  getAppointmentTicketByIdCard,
  getAppointmentTicketByPhone,
  getApiErrorMessage,
  getResponseErrorMessage,
  getResponsePayload,
  initTerminal,
  isApiSuccess,
  mapBusinessTypes,
  mapTicketResult,
} from '../api/queue'
import type { ApiResponse, TicketApiData } from '../api/queue.types'
import { readIdCard } from '../utils/idCardReader'
import type { IdCardInfo } from '../utils/idCardReader.types'
import { printTicket } from '../utils/ticketPrinter'
import { setBusinessHallId } from '../utils/terminalContext'
import {
  DEFAULT_TICKET_RESULT,
  type BusinessTypeOption,
  type PageType,
  type TicketDisplayData,
} from './queueTicket.types'

const businessTypes = ref<BusinessTypeOption[]>([])
const initLoading = ref(false)

const currentPage = ref<PageType>('home')
const resultSuccess = ref(true)
const errorMessage = ref('')

const resultData = reactive<TicketDisplayData>({ ...DEFAULT_TICKET_RESULT })

const appointmentPhone = ref('')
const scanIdLoading = ref(false)
const queryLoading = ref(false)

const username = ref('')
const phone = ref('')
const walkinIdCardInfo = ref<IdCardInfo | null>(null)
const businessType = ref('')
const scanWalkinLoading = ref(false)
const submitLoading = ref(false)
const phoneLookupLoading = ref(false)

async function loadTerminalInit() {
  const gatewayId = import.meta.env.VITE_GATEWAY_ID?.trim()
  if (!gatewayId) {
    alert('未配置终端设备编号（VITE_GATEWAY_ID），无法加载业务类型')
    return
  }
  if (initLoading.value) return

  initLoading.value = true

  try {
    const res = await initTerminal(gatewayId)
    // const res = await initTerminal()

    if (isApiSuccess(res)) {
      const data = getResponsePayload(res)
      businessTypes.value = mapBusinessTypes(data)

      const businessHallId = data.result?.businessHallId ?? data.businessHallId

      if (businessHallId) {
        setBusinessHallId(String(businessHallId))
      }

     
    } else {
      alert(getResponseErrorMessage(res, '终端初始化失败，请检查设备编号或联系工作人员'))
    }
  } catch (error) {
    alert(getApiErrorMessage(error as Error, '终端初始化失败，请检查网络后重试'))
  } finally {
    initLoading.value = false
  }
}

onMounted(loadTerminalInit)

function goBackHome() {
  currentPage.value = 'home'
}

function resetAppointmentForm() {
  appointmentPhone.value = ''
  scanIdLoading.value = false
  queryLoading.value = false
}

function resetWalkinForm() {
  username.value = ''
  phone.value = ''
  walkinIdCardInfo.value = null
  businessType.value = ''
  scanWalkinLoading.value = false
  submitLoading.value = false
  phoneLookupLoading.value = false
}

function goToAppointment() {
  resetAppointmentForm()
  currentPage.value = 'appointment'
}

function goToWalkin() {
  resetWalkinForm()
  currentPage.value = 'walkin'
}

function goToWalkinFromError() {
  resetWalkinForm()
  currentPage.value = 'walkin'
}

function showSuccessResult(data: TicketDisplayData) {
  Object.assign(resultData, data)
  resultSuccess.value = true
  currentPage.value = 'result'
}

function showErrorResult(message: string) {
  errorMessage.value = message
  resultSuccess.value = false
  currentPage.value = 'result'
}

function validatePhone(phoneNumber: string) {
  return /^1[3-9]\d{9}$/.test(phoneNumber)
}

function filterDigits(value: string) {
  return value.replace(/\D/g, '')
}

function handleAppointmentPhoneInput() {
  appointmentPhone.value = filterDigits(appointmentPhone.value)
}

async function handleTicketSuccess(
  res: ApiResponse<TicketApiData> | TicketApiData,
  fallbackMessage: string,
) {
  if (isApiSuccess(res)) {
    const ticketData = mapTicketResult(getResponsePayload(res))
    showSuccessResult(ticketData)

    try {
      await printTicket(ticketData)
    } catch (error) {
      alert(getApiErrorMessage(error as Error, '取号成功，但小票打印失败，请联系工作人员'))
    }
  } else {
    showErrorResult(getResponseErrorMessage(res, fallbackMessage))
  }
}

async function handleAppointmentQueryResult(
  res: ApiResponse<TicketApiData> | TicketApiData,
  fallbackMessage: string,
) {
  await handleTicketSuccess(res, fallbackMessage)
}

async function handleScanId() {
  if (scanIdLoading.value) return

  scanIdLoading.value = true

  try {
    const idCardInfo = await readIdCard()
    const res = await getAppointmentTicketByIdCard(idCardInfo)
    await handleAppointmentQueryResult(res, '未查询到您的预约信息，请进行现场取号')
  } catch (error) {
    showErrorResult(getApiErrorMessage(error as Error, '读取身份证或查询预约失败，请重试'))
  } finally {
    scanIdLoading.value = false
  }
}

async function handleQueryAppointment() {
  const phoneValue = appointmentPhone.value.trim()

  if (!phoneValue) {
    alert('请输入手机号码')
    return
  }

  if (!validatePhone(phoneValue)) {
    alert('请输入正确的手机号码格式')
    return
  }

  if (queryLoading.value) return

  queryLoading.value = true

  try {
    const res = await getAppointmentTicketByPhone(phoneValue)
    await handleAppointmentQueryResult(res, '暂未查询到对应手机号码的预约信息，请进行现场取号')
  } catch (error) {
    showErrorResult(getApiErrorMessage(error as Error, '查询预约失败，请重试'))
  } finally {
    queryLoading.value = false
  }
}

async function handleScanIdWalkin() {
  if (scanWalkinLoading.value) return

  scanWalkinLoading.value = true

  try {
    const idCardInfo = await readIdCard()

    walkinIdCardInfo.value = idCardInfo
    username.value = idCardInfo.name

    if (idCardInfo.phone) {
      phone.value = filterDigits(idCardInfo.phone)
    }

    if (!idCardInfo.name) {
      alert('未能读取到姓名，请重新放置身份证')
    }
  } catch (error) {
    alert(getApiErrorMessage(error as Error, '读取身份证失败，请重新放置身份证'))
  } finally {
    scanWalkinLoading.value = false
  }
}


async function handleWalkinSubmit() {
  const customerName = username.value.trim()
  const customerPhone = phone.value.trim()
  const customerNumber = walkinIdCardInfo.value?.idNumber?.trim() || ''
  const businessValue = businessType.value

  if (!customerName) {
    alert('请输入用户名')
    return
  }

  if (!businessValue) {
    alert('请选择办理业务类型')
    return
  }

  if (!customerNumber && !customerPhone) {
    alert('请刷身份证或输入手机号码')
    return
  }

  if (customerPhone && !validatePhone(customerPhone)) {
    alert('请输入正确的手机号码格式')
    return
  }

  if (submitLoading.value) return

  submitLoading.value = true

  try {
    const res = await createWalkinTicket({
      customerName,
      businessType: businessValue,
      ...(customerNumber ? { customerNumber } : {}),
      ...(customerPhone ? { customerPhone } : {}),
    })

    await handleTicketSuccess(res, '获取排队号失败，请重试')
  } catch (error) {
    showErrorResult(getApiErrorMessage(error as Error, '获取排队号失败，请重试'))
  } finally {
    submitLoading.value = false
  }
}
</script>

<template>
  <div class="flex min-h-screen flex-col justify-center bg-gradient-to-br from-blue-50 to-indigo-100">
    <div class="container mx-auto w-full max-w-6xl -translate-y-[108px] px-4">
      <!-- 首页 -->
      <section v-if="currentPage === 'home'">
        <header class="mb-10 text-center">
          <h1 class="mb-2 text-[clamp(2rem,5vw,3rem)] font-bold text-gray-800">
            智能排队叫号系统
          </h1>
          <p class="text-lg text-gray-600">请选择您需要的服务</p>
        </header>

        <div class="grid gap-8 md:grid-cols-2">
          <div
            class="card-shadow rounded-2xl bg-white p-10 text-center"
          >
            <div
              class="mx-auto mb-6 flex h-24 w-24 items-center justify-center rounded-full bg-primary/10"
            >
              <i class="fas fa-calendar-check text-5xl text-primary"></i>
            </div>
            <h2 class="mb-4 text-3xl font-semibold text-gray-800">预约取号</h2>
            <p class="mb-6 text-gray-500">已有预约，请点击此处取号</p>
            <button
              class="rounded-full bg-primary px-8 py-3 text-lg font-medium text-white cursor-pointer"
              @click="goToAppointment"
            >
              立即取号
            </button>
          </div>

          <div
            class="card-shadow rounded-2xl bg-white p-10 text-center"
          >
            <div
              class="mx-auto mb-6 flex h-24 w-24 items-center justify-center rounded-full bg-primary/10"
            >
              <i class="fas fa-user-plus text-5xl text-primary"></i>
            </div>
            <h2 class="mb-4 text-3xl font-semibold text-gray-800">现场取号</h2>
            <p class="mb-6 text-gray-500">现场办理，请点击此处取号</p>
            <button
              class="rounded-full bg-primary px-8 py-3 text-lg font-medium text-white cursor-pointer"
              @click="goToWalkin"
            >
              立即取号
            </button>
          </div>
        </div>
      </section>

      <!-- 预约取号 -->
      <section v-else-if="currentPage === 'appointment'">
        <div class="card-shadow mx-auto max-w-2xl rounded-2xl bg-white p-8">
          <div class="mb-8 flex items-center">
            <button
              class="mr-4 text-xl text-gray-600"
              @click="goBackHome"
            >
              <i class="fas fa-arrow-left"></i>
            </button>
            <h2 class="text-2xl font-bold text-gray-800">预约取号</h2>
          </div>

          <div class="space-y-6">
            <p class="mb-4 text-center text-gray-600">
              请刷身份证或输入手机号码查询您的预约信息
            </p>

            <div class="flex flex-col space-y-4">
              <button
                class="flex items-center justify-center space-x-2 rounded-xl border-2 border-dashed border-gray-300 p-4"
                :disabled="scanIdLoading"
                @click="handleScanId"
              >
                <template v-if="scanIdLoading">
                  <i class="fas fa-spinner fa-spin text-xl text-primary"></i>
                  <span class="ml-2 font-medium text-gray-700">正在读取身份证信息...</span>
                </template>
                <template v-else>
                  <i class="fas fa-id-card text-xl text-primary"></i>
                  <span class="font-medium text-gray-700">点击刷身份证</span>
                </template>
              </button>

              <div class="relative">
                <span class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400">
                  <i class="fas fa-phone"></i>
                </span>
                <input
                  v-model="appointmentPhone"
                  class="w-full rounded-xl border border-gray-300 py-3 pl-10 pr-4 outline-none transition-all focus:border-primary focus:ring-2 focus:ring-primary/50"
                  placeholder="请输入手机号码"
                  type="tel"
                  inputmode="numeric"
                  @input="handleAppointmentPhoneInput"
                />
              </div>
            </div>

            <button
              class="mt-6 w-full rounded-xl bg-primary py-4 text-lg font-medium text-white disabled:cursor-not-allowed disabled:opacity-70"
              :disabled="queryLoading"
              @click="handleQueryAppointment"
            >
              <i v-if="queryLoading" class="fas fa-spinner fa-spin mr-2"></i>
              {{ queryLoading ? '查询中...' : '查询预约' }}
            </button>
          </div>
        </div>
      </section>

      <!-- 现场取号 -->
      <section v-else-if="currentPage === 'walkin'">
        <div class="card-shadow mx-auto max-w-2xl rounded-2xl bg-white p-8">
          <div class="mb-8 flex items-center">
            <button
              class="mr-4 text-xl text-gray-600"
              @click="goBackHome"
            >
              <i class="fas fa-arrow-left"></i>
            </button>
            <h2 class="text-2xl font-bold text-gray-800">现场取号</h2>
          </div>

          <form class="space-y-6" @submit.prevent="handleWalkinSubmit">
            <div class="flex flex-col space-y-2">
              <label class="font-medium text-gray-700">用户名</label>
              <div class="relative">
                <span class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400">
                  <i class="fas fa-user"></i>
                </span>
                <input
                  v-model="username"
                  class="w-full rounded-xl border border-gray-300 py-3 pl-10 pr-4 outline-none transition-all focus:border-primary focus:ring-2 focus:ring-primary/50"
                  placeholder="请输入用户名"
                  type="text"
                />
              </div>
            </div>

            <div class="flex flex-col space-y-2">
              <label class="font-medium text-gray-700">电话号码</label>
              <div class="relative">
                <span class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400">
                  <i class="fas fa-phone"></i>
                </span>
                <input
                  v-model="phone"
                  class="w-full rounded-xl border border-gray-300 py-3 pl-10 pr-4 outline-none transition-all focus:border-primary focus:ring-2 focus:ring-primary/50 disabled:opacity-70"
                  placeholder="请输入手机号码"
                  type="tel"
                  inputmode="numeric"
                  :disabled="phoneLookupLoading"
                />
              </div>
            </div>

            <div class="flex flex-col space-y-2">
              <label class="font-medium text-gray-700">办理业务类型</label>
              <div class="relative">
                <span class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400">
                  <i class="fas fa-briefcase"></i>
                </span>
                <input
                  v-model="businessType"
                  class="w-full rounded-xl border border-gray-300 py-3 pl-10 pr-4 outline-none transition-all focus:border-primary focus:ring-2 focus:ring-primary/50"
                  :disabled="initLoading"
                  list="businessTypesList"
                  placeholder="请选择或输入业务类型"
                />
                <datalist id="businessTypesList">
                  <option
                    v-for="item in businessTypes"
                    :key="item.value"
                    :value="item.value"
                  >
                    {{ item.label }}
                  </option>
                </datalist>
              </div>
            </div>

            <div class="flex space-x-4 pt-4">
              <button
                class="flex-1 rounded-xl border-2 border-primary py-3 font-medium text-primary disabled:cursor-not-allowed disabled:opacity-70"
                type="button"
                :disabled="scanWalkinLoading"
                @click="handleScanIdWalkin"
              >
                <i
                  class="mr-2"
                  :class="scanWalkinLoading ? 'fas fa-spinner fa-spin' : 'fas fa-id-card'"
                ></i>
                {{ scanWalkinLoading ? '正在读取身份证信息...' : '刷身份证自动填写' }}
              </button>
            </div>

            <button
              class="mt-6 w-full rounded-xl bg-primary py-4 text-lg font-medium text-white disabled:cursor-not-allowed disabled:opacity-70"
              type="submit"
              :disabled="submitLoading"
            >
              <i v-if="submitLoading" class="fas fa-spinner fa-spin mr-2"></i>
              {{ submitLoading ? '正在生成号码' : '获取排队号' }}
            </button>
          </form>
        </div>
      </section>

      <!-- 取号结果 -->
      <section v-else-if="currentPage === 'result'">
        <div class="card-shadow mx-auto max-w-2xl rounded-2xl bg-white p-10 text-center">
          <div v-if="resultSuccess">
            <div class="mb-6">
              <div
                class="mb-4 inline-flex h-20 w-20 items-center justify-center rounded-full bg-green-100 text-green-500"
              >
                <i class="fas fa-check-circle text-5xl"></i>
              </div>
              <h2 class="mb-2 text-2xl font-bold text-gray-800">取号成功!</h2>
              <p class="text-gray-500">您已成功获取排队号码</p>
            </div>

            <div
              class="mb-6 rounded-xl border-2 border-dashed border-primary/30 bg-primary/5 p-8"
            >
              <p class="mb-2 text-gray-600">您的排队号码</p>
              <p class="mb-4 text-6xl font-bold text-primary">{{ resultData.number }}</p>
              <p class="text-gray-600">
                当前等待人数:
                <span class="font-semibold text-gray-800">{{ resultData.waiting }}</span>
              </p>
            </div>

            <div class="mb-6 rounded-xl bg-gray-50 p-4 text-left">
              <p class="mb-2 text-gray-700">
                <span class="font-medium">业务类型：</span>
                <span>{{ resultData.business }}</span>
              </p>
              <p class="mb-2 text-gray-700">
                <span class="font-medium">预计等待时间：</span>
                <span>{{ resultData.time }}</span>
              </p>
              <p class="text-gray-700">
                <span class="font-medium">姓名：</span>
                <span>{{ resultData.name }}</span>
              </p>
            </div>
          </div>

          <div v-else>
            <div class="mb-6">
              <div
                class="mb-4 inline-flex h-20 w-20 items-center justify-center rounded-full bg-red-100 text-red-500"
              >
                <i class="fas fa-exclamation-circle text-5xl"></i>
              </div>
              <h2 class="mb-2 text-2xl font-bold text-gray-800">未查询到预约信息</h2>
              <p class="text-gray-500">{{ errorMessage }}</p>
            </div>

            <div class="mb-6 flex space-x-4">
              <button
                class="flex-1 rounded-xl bg-primary py-3 font-medium text-white"
                @click="goToWalkinFromError"
              >
                前去现场取号
              </button>
            </div>
          </div>

          <div class="flex space-x-4 pt-4">
            <button
              class="flex-1 rounded-xl border-2 border-primary py-3 font-medium text-primary"
              @click="goBackHome"
            >
              返回首页
            </button>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>
