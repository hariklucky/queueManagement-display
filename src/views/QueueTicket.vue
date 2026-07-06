<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, reactive, ref, watch } from "vue";
import {
  createWalkinTicket,
  getAppointmentTicketByIdCard,
  getAppointmentTicketByPhone,
  getApiErrorMessage,
  getResponseErrorMessage,
  getResponsePayload,
  initTerminal,
  isApiSuccess,
  mapTicketResult,
  takeAppointmentTicket,
} from "../api/queue";
import type {
  ApiResponse,
  AppointmentItem,
  TicketApiData,
} from "../api/queue.types";
import {
  isReadIdCardCancelled,
  readIdCard,
} from "../utils/idCardReader";
import type { IdCardInfo } from "../utils/idCardReader.types";
import { setTerminalInitData, terminalStore } from "../utils/terminalContext";
import {
  DEFAULT_TICKET_RESULT,
  type AppointmentDisplayData,
  type BusinessTypeOption,
  type PageType,
  type TicketDisplayData,
} from "./queueTicket.types";
import {
  activeInputElement,
  closeOnScreenKeyboard,
  isActiveKeyboardInput,
  isRecentKeepKeyboardFocusInteraction,
  KEEP_KEYBOARD_FOCUS_CLASS,
  onScreenKeyboardVisible,
  registerSubmitPassthrough,
  syncKeyboardSessionValue,
} from "../utils/onScreenKeyboard";

const businessTypes = computed(() => terminalStore.businessTypes);

const filteredBusinessTypes = computed(() => {
  const query = businessTypeDisplay.value.trim().toLowerCase();
  if (!query) {
    return businessTypes.value;
  }

  return businessTypes.value.filter((item) =>
    item.label.toLowerCase().includes(query)
  );
});

const showBusinessTypeDropdown = computed(
  () => businessTypeDropdownOpen.value && filteredBusinessTypes.value.length > 0
);
const initLoading = ref(false);

const currentPage = ref<PageType>("home");
const resultSuccess = ref(true);
const errorMessage = ref("");
const errorTitle = ref("未查询到预约信息");

const resultData = reactive<TicketDisplayData>({ ...DEFAULT_TICKET_RESULT });
const appointmentDetailData = reactive<AppointmentDisplayData>({
  number: "",
  business: "",
  name: "",
  phone: "",
  time: "",
});

const appointmentPhone = ref("");
const appointmentTakeLoading = ref(false);
const scanIdLoading = ref(false);
const appointmentIdCardModalVisible = ref(false);
const queryLoading = ref(false);

const username = ref("");
const phone = ref("");
const walkinIdCardInfo = ref<IdCardInfo | null>(null);
const businessType = ref("");
const businessTypeDisplay = ref("");
const businessTypeInputRef = ref<HTMLInputElement | null>(null);
const businessTypeDropdownOpen = ref(false);
const scanWalkinLoading = ref(false);
const walkinIdCardModalVisible = ref(false);
const submitLoading = ref(false);
const phoneLookupLoading = ref(false);
const walkinSubmitRef = ref<HTMLButtonElement | null>(null);
const appointmentQueryRef = ref<HTMLButtonElement | null>(null);
const formTipMessage = ref("");
const formTipVisible = ref(false);

let walkinIdCardAbort: AbortController | null = null;
let appointmentIdCardAbort: AbortController | null = null;
let formTipTimer: number | undefined;

function abortWalkinIdCardReadInFlight() {
  walkinIdCardAbort?.abort()
  walkinIdCardAbort = null
}

function cancelWalkinIdCardRead() {
  abortWalkinIdCardReadInFlight()
  scanWalkinLoading.value = false
  walkinIdCardModalVisible.value = false
}

function closeWalkinIdCardModal() {
  cancelWalkinIdCardRead();
}

function abortAppointmentIdCardReadInFlight() {
  appointmentIdCardAbort?.abort()
  appointmentIdCardAbort = null
}

function cancelAppointmentIdCardRead() {
  abortAppointmentIdCardReadInFlight()
  scanIdLoading.value = false
  appointmentIdCardModalVisible.value = false
}

function closeAppointmentIdCardModal() {
  cancelAppointmentIdCardRead();
}

function closeActiveIdCardModal() {
  if (walkinIdCardModalVisible.value) {
    closeWalkinIdCardModal();
  } else {
    closeAppointmentIdCardModal();
  }
}

function cancelAllIdCardReads() {
  cancelWalkinIdCardRead();
  cancelAppointmentIdCardRead();
}

async function loadTerminalInit() {
  if (initLoading.value) return;

  initLoading.value = true;

  try {
    const res = await initTerminal();

    if (isApiSuccess(res)) {
      const data = getResponsePayload(res);
      setTerminalInitData(data, "");
    } else {
      alert(
        getResponseErrorMessage(
          res,
          "终端初始化失败，请检查设备编号或联系工作人员"
        )
      );
    }
  } catch (error) {
    alert(
      getApiErrorMessage(error as Error, "终端初始化失败，请检查网络后重试")
    );
  } finally {
    initLoading.value = false;
  }
}

onMounted(() => {
  void loadTerminalInit();
});

onUnmounted(() => {
  cancelAllIdCardReads();
  registerSubmitPassthrough(null, null);
  window.clearTimeout(formTipTimer);
});

watch(
  [currentPage, walkinSubmitRef, appointmentQueryRef],
  () => {
    if (currentPage.value === "walkin" && walkinSubmitRef.value) {
      registerSubmitPassthrough(walkinSubmitRef.value, handleWalkinSubmit);
      return;
    }

    if (currentPage.value === "appointment" && appointmentQueryRef.value) {
      registerSubmitPassthrough(
        appointmentQueryRef.value,
        handleQueryAppointment
      );
      return;
    }

    registerSubmitPassthrough(null, null);
  },
  { flush: "post" }
);

function showFormTip(message: string) {
  formTipMessage.value = message;
  formTipVisible.value = true;
  window.clearTimeout(formTipTimer);
  formTipTimer = window.setTimeout(() => {
    formTipVisible.value = false;
  }, 3000);
}

function goBackHome() {
  cancelAllIdCardReads();
  currentPage.value = "home";
}

function resetAppointmentForm() {
  cancelAppointmentIdCardRead();
  appointmentPhone.value = "";
  appointmentTakeLoading.value = false;
  queryLoading.value = false;
}

function resetWalkinForm() {
  cancelWalkinIdCardRead();
  username.value = "";
  phone.value = "";
  walkinIdCardInfo.value = null;
  businessType.value = "";
  businessTypeDisplay.value = "";
  submitLoading.value = false;
  phoneLookupLoading.value = false;
}

function goToAppointment() {
  resetAppointmentForm();
  currentPage.value = "appointment";
}

function goToWalkin() {
  resetWalkinForm();
  currentPage.value = "walkin";
}

function goToWalkinFromError() {
  resetWalkinForm();
  currentPage.value = "walkin";
}

function showSuccessResult(data: TicketDisplayData) {
  Object.assign(resultData, data);
  resultSuccess.value = true;
  currentPage.value = "result";
}

function showErrorResult(message: string, title = "未查询到预约信息") {
  errorMessage.value = message;
  errorTitle.value = title;
  resultSuccess.value = false;
  currentPage.value = "result";
}

function showAppointmentDetail(appointment: AppointmentItem) {
  const matchedBusiness = businessTypes.value.find(
    (item) => item.value === appointment.businessType
  );

  appointmentDetailData.number = appointment.appointmentId || "--";
  appointmentDetailData.business =
    matchedBusiness?.label || appointment.businessType || "--";
  appointmentDetailData.name = appointment.customerName || "--";
  appointmentDetailData.phone = appointment.customerPhone || "--";
  appointmentDetailData.time =
    appointment.appointmentDate &&
    appointment.appointmentStartTime &&
    appointment.appointmentEndTime
      ? `${appointment.appointmentDate} ${appointment.appointmentStartTime} - ${appointment.appointmentEndTime}`
      : appointment.appointmentDate || "--";

  currentPage.value = "appointmentDetail";
}

function validatePhone(phoneNumber: string) {
  return /^1[3-9]\d{9}$/.test(phoneNumber);
}

function filterDigits(value: string) {
  return value.replace(/\D/g, "");
}

function handleAppointmentPhoneInput() {
  appointmentPhone.value = filterDigits(appointmentPhone.value);
}

function handleBusinessTypeInput() {
  const displayValue = businessTypeDisplay.value.trim();
  const matchedItem = businessTypes.value.find(
    (item) => item.label === displayValue
  );

  businessType.value = matchedItem?.value || "";
  businessTypeDropdownOpen.value = true;
}

function handleBusinessTypeFocus() {
  businessTypeDropdownOpen.value = true;
}

function handleBusinessTypeBlur() {
  window.setTimeout(() => {
    const input = businessTypeInputRef.value;
    if (!input) {
      businessTypeDropdownOpen.value = false;
      return;
    }

    if (document.activeElement === input) {
      return;
    }

    if (
      onScreenKeyboardVisible.value &&
      activeInputElement.value === input
    ) {
      return;
    }

    if (isRecentKeepKeyboardFocusInteraction()) {
      return;
    }

    businessTypeDropdownOpen.value = false;
  }, 120);
}

function selectBusinessType(item: BusinessTypeOption) {
  businessTypeDisplay.value = item.label;
  businessType.value = item.value;
  businessTypeDropdownOpen.value = false;

  if (isActiveKeyboardInput(businessTypeInputRef.value)) {
    syncKeyboardSessionValue(item.label);
  }
}

function clearBusinessType() {
  businessTypeDisplay.value = "";
  businessType.value = "";

  if (isActiveKeyboardInput(businessTypeInputRef.value)) {
    syncKeyboardSessionValue("");
  }

  businessTypeDropdownOpen.value = true;
  businessTypeInputRef.value?.focus({ preventScroll: true });
}

function formatResultTime(value: string) {
  if (!value) return "--";

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  const hours = String(date.getHours()).padStart(2, "0");
  const minutes = String(date.getMinutes()).padStart(2, "0");
  const seconds = String(date.getSeconds()).padStart(2, "0");

  return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
}

async function handleTicketSuccess(
  res: ApiResponse<TicketApiData> | TicketApiData,
  fallbackMessage: string,
  fallbackName = ""
) {
  if (isApiSuccess(res)) {
    const ticketData = mapTicketResult(
      getResponsePayload(res),
      businessTypes.value
    );

    if (!ticketData.name && fallbackName) {
      ticketData.name = fallbackName;
    }

    showSuccessResult(ticketData);

  } else {
    showErrorResult(getResponseErrorMessage(res, fallbackMessage), "取号失败");
  }
}

async function handleAppointmentQueryResult(
  res: ApiResponse<TicketApiData> | TicketApiData,
  fallbackMessage: string
) {
  const payload = getResponsePayload(res);
  if (Array.isArray(payload.appointments)) {
    if (payload.appointments.length === 0) {
      showErrorResult(fallbackMessage);
      return;
    }

    showAppointmentDetail(payload.appointments[0]);
    return;
  }

  await handleTicketSuccess(res, fallbackMessage);
}

async function handleAppointmentTakeTicket() {
  
  if (appointmentTakeLoading.value) return;

  if (!appointmentDetailData.number || appointmentDetailData.number === "--") {
    alert("未获取到预约编号，无法取号");
    return;
  }

  appointmentTakeLoading.value = true;

  try {
    const res = await takeAppointmentTicket({
      appointmentId: appointmentDetailData.number,
      ticketType: "00",
    });
    await handleTicketSuccess(
      res,
      getResponseErrorMessage(res, "预约取号失败，请重试"),
      appointmentDetailData.name
    );
  } catch (error) {
    showErrorResult(
      getApiErrorMessage(error as Error, "预约取号失败，请重试"),
      "取号失败"
    );
  } finally {
    appointmentTakeLoading.value = false;
  }
}

function goBackAppointmentQuery() {
  cancelAppointmentIdCardRead();
  currentPage.value = "appointment";
}

async function handleScanId() {
  if (scanIdLoading.value) return

  abortAppointmentIdCardReadInFlight()
  closeOnScreenKeyboard()
  activeInputElement.value?.blur()

  appointmentIdCardModalVisible.value = true
  scanIdLoading.value = true
  appointmentIdCardAbort = new AbortController()
  const readSignal = appointmentIdCardAbort.signal

  await waitForIdCardModalPaint()

  if (readSignal.aborted) {
    scanIdLoading.value = false
    appointmentIdCardAbort = null
    return
  }

  try {
    const idCardInfo = await readIdCard({
      signal: readSignal,
      timeoutMs: 10_000,
    })

    appointmentIdCardModalVisible.value = false;

    const res = await getAppointmentTicketByIdCard(idCardInfo);
    await handleAppointmentQueryResult(
      res,
      "未查询到您的预约信息，请进行现场取号"
    );
  } catch (error) {
    if (isReadIdCardCancelled(error)) {
      return;
    }

    appointmentIdCardModalVisible.value = false;

    showErrorResult(
      getApiErrorMessage(error as Error, "读取身份证或查询预约失败，请重试")
    );
  } finally {
    scanIdLoading.value = false;
    appointmentIdCardAbort = null;
  }
}

async function handleQueryAppointment() {
  const phoneValue = appointmentPhone.value.trim();

  if (!phoneValue) {
    showFormTip("请输入手机号码");
    return;
  }

  if (!validatePhone(phoneValue)) {
    showFormTip("请输入正确的手机号码格式");
    return;
  }

  closeOnScreenKeyboard();

  if (queryLoading.value) return;

  queryLoading.value = true;

  try {
    const res = await getAppointmentTicketByPhone(phoneValue);
    await handleAppointmentQueryResult(
      res,
      "暂未查询到对应手机号码的预约信息，请进行现场取号"
    );
  } catch (error) {
    showErrorResult(getApiErrorMessage(error as Error, "查询预约失败，请重试"));
  } finally {
    queryLoading.value = false;
  }
}

async function waitForIdCardModalPaint() {
  await nextTick()
  await new Promise<void>((resolve) => {
    requestAnimationFrame(() => resolve())
  })
}

async function handleScanIdWalkin() {
  if (scanWalkinLoading.value) return

  abortWalkinIdCardReadInFlight()
  closeOnScreenKeyboard()
  activeInputElement.value?.blur()

  walkinIdCardModalVisible.value = true
  scanWalkinLoading.value = true
  walkinIdCardAbort = new AbortController()
  const readSignal = walkinIdCardAbort.signal

  await waitForIdCardModalPaint()

  if (readSignal.aborted) {
    scanWalkinLoading.value = false
    walkinIdCardAbort = null
    return
  }

  try {
    const idCardInfo = await readIdCard({
      signal: readSignal,
      timeoutMs: 10_000,
    })

    walkinIdCardInfo.value = idCardInfo
    username.value = idCardInfo.name

    if (idCardInfo.phone) {
      phone.value = filterDigits(idCardInfo.phone)
    }

    walkinIdCardModalVisible.value = false

    if (!idCardInfo.name) {
      alert('未能读取到姓名，请重新放置身份证')
    }
  } catch (error) {
    if (isReadIdCardCancelled(error)) {
      return
    }

    walkinIdCardModalVisible.value = false
    alert(
      getApiErrorMessage(error as Error, '读取身份证失败，请重新放置身份证')
    )
  } finally {
    scanWalkinLoading.value = false
    walkinIdCardAbort = null
  }
}

function resolveWalkinBusinessType() {
  const displayValue = businessTypeDisplay.value.trim();
  if (!displayValue) {
    businessType.value = "";
    return "";
  }

  const matchedItem = businessTypes.value.find(
    (item) => item.label === displayValue
  );

  if (matchedItem) {
    businessType.value = matchedItem.value;
    return matchedItem.value;
  }

  return businessType.value;
}

async function handleWalkinSubmit() {
  const customerName = username.value.trim();
  const customerPhone = phone.value.trim();
  const customerNumber = walkinIdCardInfo.value?.idNumber?.trim() || "";
  const businessValue = resolveWalkinBusinessType();

  if (!customerName) {
    showFormTip("请输入用户名");
    return;
  }

  if (!businessValue) {
    showFormTip("请选择办理业务类型");
    return;
  }

  if (!customerNumber && !customerPhone) {
    showFormTip("请刷身份证或输入手机号码");
    return;
  }

  if (customerPhone && !validatePhone(customerPhone)) {
    showFormTip("请输入正确的手机号码格式");
    return;
  }

  closeOnScreenKeyboard();
  businessTypeInputRef.value?.blur();

  if (submitLoading.value) return;

  submitLoading.value = true;

  try {
    const res = await createWalkinTicket({
      customerName,
      businessType: businessValue,
      ...(customerNumber ? { customerNumber } : {}),
      ...(customerPhone ? { customerPhone } : {}),
      ticketType: "01",
    });
    await handleTicketSuccess(
      res,
      res.errMsg || "获取排队号失败，请重试",
      customerName
    );
  } catch (error) {
    showErrorResult(
      getApiErrorMessage(error as Error, "获取排队号失败，请重试"),
      "取号失败"
    );
  } finally {
    submitLoading.value = false;
  }
}
</script>

<template>
  <div
    class="flex min-h-screen flex-col justify-center bg-gradient-to-br from-blue-50 to-indigo-100"
  >
    <div
      class="container mx-auto w-full max-w-6xl -translate-y-[108px] px-4"
      v-if="currentPage === 'home'"
    >
      <!-- 首页 -->
      <section>
        <header class="mb-10 text-center">
          <h1 class="mb-2 text-[clamp(2rem,5vw,3rem)] font-bold text-gray-800">
            智能排队叫号系统
          </h1>
          <p class="text-lg text-gray-600">请选择您需要的服务</p>
        </header>

        <div class="grid gap-8 md:grid-cols-2">
          <div class="card-shadow rounded-2xl bg-white p-10 text-center">
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

          <div class="card-shadow rounded-2xl bg-white p-10 text-center">
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
    </div>
    <div class="container mx-auto w-full max-w-6xl px-4" v-else>
      <!-- 预约取号 -->
      <section v-if="currentPage === 'appointment'">
        <div class="card-shadow mx-auto max-w-2xl rounded-2xl bg-white p-8">
          <div class="mb-8 flex items-center">
            <button class="mr-4 text-xl text-gray-600" @click="goBackHome">
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
                class="flex items-center justify-center space-x-2 rounded-xl border-2 border-dashed border-gray-300 p-4 disabled:cursor-not-allowed disabled:opacity-70"
                type="button"
                :disabled="scanIdLoading"
                @click="handleScanId"
              >
                <i class="fas fa-id-card text-xl text-primary"></i>
                <span class="font-medium text-gray-700">点击刷身份证</span>
              </button>

              <div class="relative">
                <span
                  class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400"
                >
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
              ref="appointmentQueryRef"
              class="mt-6 w-full rounded-xl bg-primary py-4 text-lg font-medium text-white disabled:cursor-not-allowed disabled:opacity-70"
              type="button"
              :disabled="queryLoading"
              @click="handleQueryAppointment"
            >
              <i v-if="queryLoading" class="fas fa-spinner fa-spin mr-2"></i>
              {{ queryLoading ? "查询中..." : "查询预约" }}
            </button>
          </div>
        </div>
      </section>

      <!-- 预约信息确认 -->
      <section v-else-if="currentPage === 'appointmentDetail'">
        <div class="card-shadow mx-auto max-w-2xl rounded-2xl bg-white p-8">
          <div class="mb-8 flex items-center">
            <button
              class="mr-4 text-xl text-gray-600"
              @click="goBackAppointmentQuery"
            >
              <i class="fas fa-arrow-left"></i>
            </button>
            <h2 class="text-2xl font-bold text-gray-800">预约信息</h2>
          </div>

          <div class="mb-8 rounded-2xl bg-gray-50 p-6 text-left space-y-4">
            <p class="text-gray-700">
              <span class="font-medium">预约编号：</span>
              <span>{{ appointmentDetailData.number }}</span>
            </p>
            <p class="text-gray-700">
              <span class="font-medium">业务类型：</span>
              <span>{{ appointmentDetailData.business }}</span>
            </p>
            <p class="text-gray-700">
              <span class="font-medium">姓名：</span>
              <span>{{ appointmentDetailData.name }}</span>
            </p>
            <p class="text-gray-700">
              <span class="font-medium">手机号：</span>
              <span>{{ appointmentDetailData.phone }}</span>
            </p>
            <p class="text-gray-700">
              <span class="font-medium">预约时间：</span>
              <span>{{ appointmentDetailData.time }}</span>
            </p>
          </div>

          <div class="flex flex-col space-y-4">
            <button
              class="w-full rounded-xl bg-primary py-4 text-lg font-medium text-white disabled:cursor-not-allowed disabled:opacity-70"
              :disabled="appointmentTakeLoading"
              @click="handleAppointmentTakeTicket"
            >
              <i
                v-if="appointmentTakeLoading"
                class="fas fa-spinner fa-spin mr-2"
              ></i>
              {{ appointmentTakeLoading ? "获取中..." : "获取排队号" }}
            </button>
            <button
              class="w-full rounded-xl border-2 border-primary py-4 text-lg font-medium text-primary"
              @click="goBackAppointmentQuery"
            >
              返回查询页
            </button>
          </div>
        </div>
      </section>

      <!-- 现场取号 -->
      <section v-else-if="currentPage === 'walkin'">
        <div class="card-shadow mx-auto max-w-2xl rounded-2xl bg-white p-8">
          <div class="mb-8 flex items-center">
            <button class="mr-4 text-xl text-gray-600" @click="goBackHome">
              <i class="fas fa-arrow-left"></i>
            </button>
            <h2 class="text-2xl font-bold text-gray-800">现场取号</h2>
          </div>

          <form class="space-y-6" @submit.prevent="handleWalkinSubmit">
            <div class="flex flex-col space-y-2">
              <label class="font-medium text-gray-700">用户名</label>
              <div class="relative">
                <span
                  class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400"
                >
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
                <span
                  class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400"
                >
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
                <ul
                  v-if="showBusinessTypeDropdown"
                  :class="KEEP_KEYBOARD_FOCUS_CLASS"
                  class="absolute inset-x-0 bottom-full z-[120] mb-1 box-border max-h-48 w-full touch-pan-y overflow-x-hidden overflow-y-auto rounded-xl border border-gray-200 bg-white py-1 shadow-[0_-4px_20px_rgba(15,23,42,0.12)]"
                  @mousedown.prevent
                >
                  <li
                    v-for="item in filteredBusinessTypes"
                    :key="item.value"
                    class="cursor-pointer px-4 py-2.5 text-gray-800 transition-colors hover:bg-blue-50 active:bg-blue-100"
                    @mousedown="selectBusinessType(item)"
                  >
                    {{ item.label }}
                  </li>
                </ul>
                <span
                  class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400"
                >
                  <i class="fas fa-briefcase"></i>
                </span>
                <input
                  ref="businessTypeInputRef"
                  v-model="businessTypeDisplay"
                  class="w-full rounded-xl border border-gray-300 py-3 pl-10 pr-12 outline-none transition-all focus:border-primary focus:ring-2 focus:ring-primary/50"
                  :disabled="initLoading"
                  placeholder="请选择业务类型"
                  @blur="handleBusinessTypeBlur"
                  @focus="handleBusinessTypeFocus"
                  @input="handleBusinessTypeInput"
                />
                <button
                  v-if="businessTypeDisplay"
                  class="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 transition-colors hover:text-gray-600 disabled:cursor-not-allowed"
                  type="button"
                  :disabled="initLoading"
                  @mousedown.prevent="clearBusinessType"
                >
                  <i class="fas fa-times-circle"></i>
                </button>
              </div>
            </div>

            <div class="flex space-x-4 pt-4">
              <button
                class="flex-1 rounded-xl border-2 border-primary py-3 font-medium text-primary disabled:cursor-not-allowed disabled:opacity-70"
                type="button"
                :disabled="scanWalkinLoading"
                @click.stop="handleScanIdWalkin"
              >
                <i class="fas fa-id-card mr-2"></i>
                刷身份证自动填写
              </button>
            </div>

            <button
              ref="walkinSubmitRef"
              class="mt-6 w-full rounded-xl bg-primary py-4 text-lg font-medium text-white disabled:cursor-not-allowed disabled:opacity-70"
              type="button"
              :disabled="submitLoading"
              @click="handleWalkinSubmit"
            >
              <i v-if="submitLoading" class="fas fa-spinner fa-spin mr-2"></i>
              {{ submitLoading ? "正在生成号码" : "获取排队号" }}
            </button>
          </form>
        </div>
      </section>

      <!-- 取号结果 -->
      <section v-else-if="currentPage === 'result'">
        <div
          class="card-shadow mx-auto max-w-2xl rounded-2xl bg-white p-10 text-center"
        >
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
              <p class="mb-4 text-6xl font-bold text-primary">
                {{ resultData.number }}
              </p>
              <p class="text-gray-600">
                当前等待人数:
                <span class="font-semibold text-gray-800">{{
                  resultData.waiting
                }}</span>
              </p>
            </div>

            <div class="mb-6 rounded-xl bg-gray-50 p-4 text-left">
              <p class="mb-2 text-gray-700">
                <span class="font-medium">业务类型：</span>
                <span>{{ resultData.business }}</span>
              </p>
              <p class="mb-2 text-gray-700">
                <span class="font-medium">预计等待时间：</span>
                <span>{{ formatResultTime(resultData.time) }}</span>
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
              <h2 class="mb-2 text-2xl font-bold text-gray-800">
                {{ errorTitle }}
              </h2>
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

    <!-- 表单校验提示（置于键盘之上） -->
    <Teleport to="body">
      <div
        v-if="formTipVisible"
        class="pointer-events-none fixed inset-x-0 top-10 z-[10001] flex justify-center px-4"
      >
        <div
          class="rounded-xl bg-gray-900/90 px-6 py-3 text-base font-medium text-white shadow-lg"
          role="alert"
        >
          {{ formTipMessage }}
        </div>
      </div>
    </Teleport>

    <!-- 刷身份证提示弹窗（预约取号 / 现场取号共用） -->
    <Teleport to="body">
      <div
        v-if="walkinIdCardModalVisible || appointmentIdCardModalVisible"
        class="fixed inset-0 z-[10000] flex items-center justify-center bg-black/50 px-4"
      >
        <div
          class="card-shadow w-full max-w-md rounded-2xl bg-white p-8 text-center"
          role="dialog"
          aria-modal="true"
          aria-labelledby="id-card-modal-title"
        >
          <div
            class="mx-auto mb-5 flex h-20 w-20 items-center justify-center rounded-full bg-blue-50 text-primary"
          >
            <i class="fas fa-id-card text-4xl"></i>
          </div>
          <h3
            id="id-card-modal-title"
            class="mb-2 text-2xl font-bold text-gray-800"
          >
            请您刷取身份证
          </h3>
          <p class="mb-6 text-gray-600">
            请将身份证放置在读卡器感应区，系统将自动读取身份证信息
          </p>
          <div class="mb-8 flex items-center justify-center text-primary">
            <i class="fas fa-spinner fa-spin mr-2 text-xl"></i>
            <span class="font-medium">正在等待读卡...</span>
          </div>
          <button
            class="w-full rounded-xl border-2 border-gray-300 py-3 font-medium text-gray-700 transition-colors hover:bg-gray-50"
            type="button"
            @click="closeActiveIdCardModal"
          >
            关闭
          </button>
        </div>
      </div>
    </Teleport>
  </div>
</template>
