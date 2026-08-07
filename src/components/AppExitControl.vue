<script setup lang="ts">
import { nextTick, ref } from 'vue'
import { isElectron } from '../utils/electron'
import {
  KEEP_KEYBOARD_FOCUS_CLASS,
  closeOnScreenKeyboard,
  syncKeyboardSessionValue,
} from '../utils/onScreenKeyboard'

const CLICK_TARGET = 5
const CLICK_WINDOW_MS = 2500

const authVisible = ref(false)
const confirmVisible = ref(false)
const passwordInput = ref('')
const passwordError = ref('')
const passwordInputRef = ref<HTMLInputElement | null>(null)
const quitting = ref(false)

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
  syncKeyboardSessionValue('')
}

async function openAuth() {
  confirmVisible.value = false
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
  closeOnScreenKeyboard()
  confirmVisible.value = true
}

function closeConfirm() {
  if (quitting.value) return
  confirmVisible.value = false
}

async function handleConfirmQuit() {
  if (quitting.value) return

  quitting.value = true
  try {
    if (window.qms?.quitApp) {
      await window.qms.quitApp()
      // 给主进程一点时间退出；若仍在则提示
      window.setTimeout(() => {
        quitting.value = false
        alert('退出应用失败，请手动关闭窗口或重启设备')
      }, 1500)
      return
    }

    if (isElectron()) {
      window.close()
      return
    }

    window.close()
  } catch (error) {
    console.error('[QMS] 退出应用失败', error)
    quitting.value = false
    alert('退出应用失败，请手动关闭窗口或重启设备')
  }
}
</script>

<template>
  <!-- 右上角隐式热区：短时间内连续点击打开退出验证 -->
  <button
    type="button"
    class="fixed right-0 top-0 z-[9990] h-16 w-16 cursor-default border-0 bg-transparent p-0"
    aria-label="退出应用"
    @click="handleCornerClick"
  />

  <Teleport to="body">
    <div
      v-if="authVisible"
      class="fixed inset-0 z-[10020] flex items-center justify-center bg-black/50 px-4"
    >
      <div
        :class="KEEP_KEYBOARD_FOCUS_CLASS"
        class="card-shadow w-full max-w-md rounded-2xl bg-white p-8"
        role="dialog"
        aria-modal="true"
        aria-labelledby="exit-auth-title"
        @click.stop
      >
        <h3 id="exit-auth-title" class="mb-2 text-2xl font-bold text-gray-800">
          身份验证
        </h3>
        <p class="mb-6 text-sm text-gray-500">请输入验证密码后继续退出应用</p>

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

    <div
      v-if="confirmVisible"
      class="fixed inset-0 z-[10020] flex items-center justify-center bg-black/50 px-4"
    >
      <div
        class="card-shadow w-full max-w-md rounded-2xl bg-white p-8 text-center"
        role="dialog"
        aria-modal="true"
        aria-labelledby="exit-confirm-title"
        @click.stop
      >
        <div
          class="mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-full bg-red-50 text-red-500"
        >
          <i class="fas fa-power-off text-3xl"></i>
        </div>
        <h3
          id="exit-confirm-title"
          class="mb-2 text-2xl font-bold text-gray-800"
        >
          确认退出
        </h3>
        <p class="mb-8 text-gray-600">确定要退出报到取号应用吗？</p>

        <div class="flex gap-3">
          <button
            class="flex-1 rounded-xl border-2 border-gray-300 py-3 font-medium text-gray-700 transition-colors hover:bg-gray-50 disabled:opacity-70"
            type="button"
            :disabled="quitting"
            @click="closeConfirm"
          >
            取消
          </button>
          <button
            class="flex-1 rounded-xl bg-red-500 py-3 font-medium text-white transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-70"
            type="button"
            :disabled="quitting"
            @click="handleConfirmQuit"
          >
            {{ quitting ? '退出中...' : '确认退出' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
