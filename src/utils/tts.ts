function isSpeechSupported() {
  return typeof window !== 'undefined' && 'speechSynthesis' in window
}

function pickChineseVoice(voices: SpeechSynthesisVoice[]) {
  return (
    voices.find((voice) => voice.lang === 'zh-CN') ||
    voices.find((voice) => voice.lang.startsWith('zh')) ||
    voices[0]
  )
}

function loadVoices(): Promise<SpeechSynthesisVoice[]> {
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

export function cancelSpeech() {
  if (!isSpeechSupported()) {
    return
  }

  window.speechSynthesis.cancel()
}

export async function speakText(
  text: string,
  options?: { rate?: number; pitch?: number; volume?: number },
) {
  if (!isSpeechSupported()) {
    console.warn('[QMS] 当前环境不支持系统语音播报')
    return
  }

  cancelSpeech()

  const voices = await loadVoices()
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

export function speakWelcome(text: string) {
  return speakText(text)
}
