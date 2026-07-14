let pendingKeyboardInvokeTimer: ReturnType<typeof setTimeout> | null = null

export function cancelPendingSystemKeyboardInvoke() {
  if (pendingKeyboardInvokeTimer != null) {
    window.clearTimeout(pendingKeyboardInvokeTimer)
    pendingKeyboardInvokeTimer = null
  }
}

export function scheduleSystemKeyboardInvoke(
  callback: () => void,
  delayMs: number
) {
  cancelPendingSystemKeyboardInvoke()
  pendingKeyboardInvokeTimer = window.setTimeout(() => {
    pendingKeyboardInvokeTimer = null
    callback()
  }, delayMs)
}
