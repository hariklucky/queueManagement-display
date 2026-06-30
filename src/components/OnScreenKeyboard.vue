<script setup lang="ts">
import { onMounted, onUnmounted, ref, watch } from 'vue'
import SimpleKeyboard from './SimpleKeyboard.vue'
import {
  activeInputElement,
  applyBackspace,
  applyKeyboardChange,
  applySpace,
  clearKeyboardInput,
  closeOnScreenKeyboard,
  finalizeBufferToCommitted,
  keyboardSessionResetSignal,
  maintainActiveInputFocus,
  onScreenKeyboardType,
  onScreenKeyboardVisible,
  setupKeyboardOutsideDismiss,
  teardownKeyboardOutsideDismiss,
  type OnScreenKeyboardType,
} from '../utils/onScreenKeyboard'

const keyboardRef = ref<InstanceType<typeof SimpleKeyboard> | null>(null)

function resetKeyboardBuffer() {
  requestAnimationFrame(() => {
    keyboardRef.value?.onChangeFocus('')
    finalizeBufferToCommitted()
  })
}

function handleKeyboardInput(value: string) {
  const shouldResetBuffer = applyKeyboardChange(value)
  if (shouldResetBuffer) {
    resetKeyboardBuffer()
  }
}

function handleEmpty() {
  clearKeyboardInput()
  resetKeyboardBuffer()
}

function handleBackspaceCommitted() {
  applyBackspace()
  resetKeyboardBuffer()
}

function handleCommitSpace() {
  applySpace()
  resetKeyboardBuffer()
}

function handleCloseKeyboard() {
  activeInputElement.value?.blur()
  closeOnScreenKeyboard()
}

function handleUpdateKeyboardType(type: OnScreenKeyboardType) {
  onScreenKeyboardType.value = type
  resetKeyboardBuffer()
}

watch(
  () => activeInputElement.value,
  (input, previousInput) => {
    if (!onScreenKeyboardVisible.value || !input || input === previousInput) {
      return
    }

    resetKeyboardBuffer()
  }
)

watch(keyboardSessionResetSignal, () => {
  resetKeyboardBuffer()
})

onMounted(setupKeyboardOutsideDismiss)

onUnmounted(teardownKeyboardOutsideDismiss)
</script>

<template>
  <Teleport to="body">
    <div
      v-if="onScreenKeyboardVisible"
      class="keyboard-shell pointer-events-none fixed inset-x-0 bottom-0 z-[9999]"
    >
      <div
        class="keyboard-panel pointer-events-auto mx-auto w-full max-w-3xl px-3 pb-3 pt-2"
      >
        <div
          class="keyboard-handle mx-auto mb-2 h-1 w-12 rounded-full bg-gray-300/80"
          @mousedown.prevent="maintainActiveInputFocus"
          @touchstart.prevent="maintainActiveInputFocus"
        />
        <SimpleKeyboard
          ref="keyboardRef"
          :keyboard-type="onScreenKeyboardType"
          @on-change="handleKeyboardInput"
          @empty="handleEmpty"
          @backspace-committed="handleBackspaceCommitted"
          @commit-space="handleCommitSpace"
          @close-keyboard="handleCloseKeyboard"
          @update-keyboard-type="handleUpdateKeyboardType"
        />
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.keyboard-shell {
  background: linear-gradient(
    180deg,
    rgba(15, 23, 42, 0) 0%,
    rgba(15, 23, 42, 0.08) 30%,
    rgba(15, 23, 42, 0.18) 100%
  );
  backdrop-filter: blur(2px);
}

.keyboard-panel {
  animation: keyboard-slide-up 0.22s ease-out;
}

@keyframes keyboard-slide-up {
  from {
    opacity: 0;
    transform: translateY(16px);
  }

  to {
    opacity: 1;
    transform: translateY(0);
  }
}
</style>
