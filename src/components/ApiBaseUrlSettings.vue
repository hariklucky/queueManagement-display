<script setup lang="ts">
import { nextTick, ref } from 'vue'
import { getApiBaseURL, saveApiBaseUrl } from '../utils/runtimeConfig'
import {
  KEEP_KEYBOARD_FOCUS_CLASS,
  syncKeyboardSessionValue,
} from '../utils/onScreenKeyboard'

const CLICK_TARGET = 5
const CLICK_WINDOW_MS = 2500

const authVisible = ref(false)
const settingsVisible = ref(false)
const passwordInput = ref('')
const passwordError = ref('')
const passwordInputRef = ref<HTMLInputElement | null>(null)

const draftUrl = ref('')
const autoLaunchEnabled = ref(false)
const autoLaunchSupported = ref(true)
const autoLaunchHint = ref('')
const saving = ref(false)
const errorMessage = ref('')

let clickCount = 0
let clickTimer: number | undefined

function getVerifyPassword() {
  return String(new Date().getFullYear()).split('').reverse().join('')
}

function handleCornerClick() {
  window.clearTimeout(clickTimer)
  clickCount += 1

  if (clickCount >= CLICK_TARGET) {
    clickCount = 0
    openAuth()
    return
  }

  clickTimer = window.setTimeout(() => {
    clickCount = 0
  }, CLICK_WINDOW_MS)
}

function clearPasswordInput() {
  passwordInput.value = ''
  // 同步清空虚拟键盘内部缓冲，避免界面已空但再次输入时旧密码仍拼接上
  syncKeyboardSessionValue('')
}

async function openAuth() {
  settingsVisible.value = false
  clearPasswordInput()
  passwordError.value = ''
  authVisible.value = true
  await nextTick()
  passwordInputRef.value?.focus()
}

function closeAuth() {
  authVisible.value = false
  clearPasswordInput()
  passwordError.value = ''
}

function handleVerifyPassword() {
  const input = passwordInput.value.trim()
  if (!input) {
    passwordError.value = '请输入验证密码'
    return
  }

  if (input !== getVerifyPassword()) {
    passwordError.value = '验证密码错误'
    clearPasswordInput()
    return
  }

  authVisible.value = false
  clearPasswordInput()
  passwordError.value = ''
  void openSettings()
}

async function openSettings() {
  draftUrl.value = getApiBaseURL()
  errorMessage.value = ''
  autoLaunchEnabled.value = false
  autoLaunchSupported.value = true
  autoLaunchHint.value = ''

  if (window.qms?.getAutoLaunch) {
    try {
      const result = await window.qms.getAutoLaunch()
      autoLaunchEnabled.value = Boolean(result?.enabled)
      autoLaunchSupported.value = result?.supported !== false
      autoLaunchHint.value = String(result?.message || '')
    } catch (error) {
      console.warn('[QMS] 读取开机启动状态失败', error)
    }
  }

  // 主进程未重启时也能识别：Electron 开发页（Vite）在 macOS 上无法写登录项
  if (
    window.qms?.platform === 'darwin' &&
    /^https?:$/i.test(window.location.protocol) &&
    (window.location.hostname === '127.0.0.1' ||
      window.location.hostname === 'localhost')
  ) {
    autoLaunchSupported.value = false
    autoLaunchEnabled.value = false
    autoLaunchHint.value =
      '当前为 macOS 开发模式，系统不允许写入登录项。请使用签名打包后的应用，或到 Linux 终端机上设置。'
  }

  settingsVisible.value = true
}

function closeSettings() {
  if (saving.value) return
  settingsVisible.value = false
  errorMessage.value = ''
}

async function handleSave() {
  if (saving.value) return

  saving.value = true
  errorMessage.value = ''

  try {
    await saveApiBaseUrl(draftUrl.value)

    if (window.qms?.setAutoLaunch && autoLaunchSupported.value) {
      const wanted = autoLaunchEnabled.value
      const result = await window.qms.setAutoLaunch(wanted)
      autoLaunchEnabled.value = Boolean(result?.enabled)

      if (Boolean(result?.enabled) !== wanted) {
        const platform = String(window.qms?.platform || '')
        throw new Error(
          result?.message ||
            (platform === 'darwin'
              ? '开机启动未生效：当前是 macOS 开发模式，系统禁止写入登录项。请到 Linux 终端机或签名打包后的应用上再开此选项。'
              : '开机启动设置未生效，请检查系统权限后重试'),
        )
      }
    }

    settingsVisible.value = false
    window.location.reload()
  } catch (error) {
    errorMessage.value =
      error instanceof Error ? error.message : '保存失败，请重试'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <!-- 左上角隐式热区：短时间内连续点击打开验证 -->
  <button
    type="button"
    class="fixed left-0 top-0 z-[9990] h-16 w-16 cursor-default border-0 bg-transparent p-0"
    aria-label="打开后端地址设置"
    @click="handleCornerClick"
  />

  <Teleport to="body">
    <!-- 验证密码 -->
    <div
      v-if="authVisible"
      class="fixed inset-0 z-[10020] flex items-center justify-center bg-black/50 px-4"
    >
      <div
        :class="KEEP_KEYBOARD_FOCUS_CLASS"
        class="card-shadow w-full max-w-md rounded-2xl bg-white p-8"
        role="dialog"
        aria-modal="true"
        aria-labelledby="api-auth-title"
        @click.stop
      >
        <h3
          id="api-auth-title"
          class="mb-2 text-2xl font-bold text-gray-800"
        >
          身份验证
        </h3>
        <p class="mb-6 text-sm text-gray-500">请输入验证密码后继续修改后端地址</p>

        <label class="mb-2 block text-left text-sm font-medium text-gray-700">
          验证密码
        </label>
        <input
          ref="passwordInputRef"
          v-model="passwordInput"
          type="password"
          inputmode="numeric"
          data-keyboard-type="number"
          class="mb-2 w-full rounded-xl border-2 border-gray-200 px-4 py-3 text-base text-gray-800 outline-none focus:border-primary"
          placeholder="请输入验证密码"
          autocomplete="off"
          @keydown.enter.prevent="handleVerifyPassword"
        />
        <p v-if="passwordError" class="mb-6 text-left text-sm text-red-600">
          {{ passwordError }}
        </p>
        <div v-else class="mb-6 h-5" />

        <div class="flex gap-3">
          <button
            class="flex-1 rounded-xl border-2 border-gray-300 py-3 font-medium text-gray-700 transition-colors hover:bg-gray-50"
            type="button"
            @click="closeAuth"
          >
            取消
          </button>
          <button
            class="flex-1 rounded-xl bg-primary py-3 font-medium text-white transition-opacity hover:opacity-90"
            type="button"
            @click="handleVerifyPassword"
          >
            确认
          </button>
        </div>
      </div>
    </div>

    <!-- 修改后端地址 -->
    <div
      v-if="settingsVisible"
      class="fixed inset-0 z-[10020] flex items-center justify-center bg-black/50 px-4"
    >
      <div
        :class="KEEP_KEYBOARD_FOCUS_CLASS"
        class="card-shadow w-full max-w-lg rounded-2xl bg-white p-8"
        role="dialog"
        aria-modal="true"
        aria-labelledby="api-base-url-title"
        @click.stop
      >
        <h3
          id="api-base-url-title"
          class="mb-2 text-2xl font-bold text-gray-800"
        >
          后端请求地址
        </h3>
        <p class="mb-6 text-sm text-gray-500">
          修改后将写入本地配置并立即生效（页面会刷新）
        </p>

        <label class="mb-2 block text-left text-sm font-medium text-gray-700">
          apiBaseUrl
        </label>
        <input
          v-model="draftUrl"
          type="text"
          class="mb-2 w-full rounded-xl border-2 border-gray-200 px-4 py-3 text-base text-gray-800 outline-none focus:border-primary"
          placeholder="http://192.168.0.101:18084/api"
          autocomplete="off"
          spellcheck="false"
          @keydown.enter.prevent="handleSave"
        />
        <p v-if="errorMessage" class="mb-4 text-left text-sm text-red-600">
          {{ errorMessage }}
        </p>
        <p v-else class="mb-4 text-left text-xs text-gray-400">
          本机联调可用 http://127.0.0.1:18084/api；局域网请填实际 IP
        </p>

        <label
          class="mb-6 flex cursor-pointer items-center gap-3 rounded-xl border-2 border-gray-200 px-4 py-3 text-left"
          :class="{ 'cursor-not-allowed opacity-60': !autoLaunchSupported }"
        >
          <input
            v-model="autoLaunchEnabled"
            type="checkbox"
            class="h-5 w-5 accent-primary"
            :disabled="!autoLaunchSupported"
          />
          <span>
            <span class="block font-medium text-gray-800">开机自动启动</span>
            <span class="block text-xs text-gray-500">
              {{
                autoLaunchHint ||
                '登录桌面后自动打开报到取号'
              }}
            </span>
          </span>
        </label>

        <div class="flex gap-3">
          <button
            class="flex-1 rounded-xl border-2 border-gray-300 py-3 font-medium text-gray-700 transition-colors hover:bg-gray-50 disabled:opacity-70"
            type="button"
            :disabled="saving"
            @click="closeSettings"
          >
            取消
          </button>
          <button
            class="flex-1 rounded-xl bg-primary py-3 font-medium text-white transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-70"
            type="button"
            :disabled="saving"
            @click="handleSave"
          >
            {{ saving ? '保存中...' : '保存' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
