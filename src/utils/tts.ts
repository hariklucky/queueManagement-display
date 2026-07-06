import { invoke, isTauri } from '@tauri-apps/api/core'

function isWindowsTauri() {
  return isTauri() && import.meta.env.TAURI_ENV_PLATFORM === 'windows'
}

function isWebSpeechSupported() {
  return typeof window !== 'undefined' && 'speechSynthesis' in window
}

function pickChineseVoice(voices: SpeechSynthesisVoice[]) {
  return (
    voices.find((voice) => voice.lang === 'zh-CN') ||
    voices.find((voice) => voice.lang.startsWith('zh')) ||
    voices[0]
  )
}

function loadWebVoices(): Promise<SpeechSynthesisVoice[]> {
  const synth = window.speechSynthesis
  const existing = synth.getVoices()
  if (existing.length > 0) {
    return Promise.resolve(existing)
  }

  return new Promise((resolve) => {
    const finish = () => {
      synth.removeEventListener('voiceschanged', finish)
      resolve(synth.getVoices())
    }

    synth.addEventListener('voiceschanged', finish)
    window.setTimeout(finish, 800)
  })
}

async function speakWithWebSpeech(
  text: string,
  options?: { rate?: number; pitch?: number; volume?: number },
) {
  if (!isWebSpeechSupported()) {
    console.warn('[QMS] 当前环境不支持 Web Speech 播报')
    return
  }

  window.speechSynthesis.cancel()

  const voices = await loadWebVoices()
  const utterance = new SpeechSynthesisUtterance(text)
  utterance.lang = 'zh-CN'

  const voice = pickChineseVoice(voices)
  if (voice) {
    utterance.voice = voice
  }

  utterance.rate = options?.rate ?? 1
  utterance.pitch = options?.pitch ?? 1
  utterance.volume = options?.volume ?? 1

  window.speechSynthesis.speak(utterance)
}

export function cancelSpeech() {
  if (isWindowsTauri()) {
    void invoke('native_cancel_speech').catch((error) => {
      console.warn('[QMS] 取消 Windows 原生 TTS 失败', error)
    })
    return
  }

  if (isWebSpeechSupported()) {
    window.speechSynthesis.cancel()
  }
}

export async function speakText(
  text: string,
  options?: { rate?: number; pitch?: number; volume?: number },
) {
  const content = text.trim()
  if (!content) {
    return
  }

  if (isWindowsTauri()) {
    try {
      await invoke('native_speak_text', { text: content })
      return
    } catch (error) {
      console.warn('[QMS] Windows 原生 TTS 失败，尝试 Web Speech 兜底', error)
    }
  }

  try {
    await speakWithWebSpeech(content, options)
  } catch (error) {
    console.warn('[QMS] 语音播报失败，已忽略', error)
  }
}

export function speakWelcome(text: string) {
  return speakText(text)
}
