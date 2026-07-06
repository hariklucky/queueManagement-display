#[cfg(target_os = "windows")]
mod platform {
    use std::sync::{Mutex, OnceLock};
    use std::time::{Duration, Instant};

    use windows::{
        core::HSTRING,
        Foundation::{AsyncStatus, IAsyncOperation},
        Media::Core::MediaSource,
        Media::Playback::{MediaPlaybackState, MediaPlayer},
        Media::SpeechSynthesis::SpeechSynthesizer,
        Win32::System::Com::{CoInitializeEx, COINIT_APARTMENTTHREADED},
    };

    static ACTIVE_PLAYER: OnceLock<Mutex<Option<MediaPlayer>>> = OnceLock::new();

    fn player_slot() -> &'static Mutex<Option<MediaPlayer>> {
        ACTIVE_PLAYER.get_or_init(|| Mutex::new(None))
    }

    fn wait_async<T: windows::core::RuntimeType>(
        operation: &IAsyncOperation<T>,
    ) -> windows::core::Result<T> {
        loop {
            match operation.Status()? {
                AsyncStatus::Completed => return operation.GetResults(),
                AsyncStatus::Error => {
                    return Err(match operation.ErrorCode() {
                        Ok(hr) => windows::core::Error::from(hr),
                        Err(error) => error,
                    });
                }
                AsyncStatus::Canceled => {
                    return Err(windows::core::Error::new(
                        windows::core::HRESULT(0x800704C7u32 as i32),
                        "TTS operation canceled",
                    ));
                }
                _ => std::thread::sleep(Duration::from_millis(20)),
            }
        }
    }

    fn pick_chinese_voice(synth: &SpeechSynthesizer) {
        let Ok(voices) = SpeechSynthesizer::AllVoices() else {
            return;
        };

        let Ok(count) = voices.Size() else {
            return;
        };

        for index in 0..count {
            let Ok(voice) = voices.GetAt(index) else {
                continue;
            };

            let Ok(lang) = voice.Language() else {
                continue;
            };

            let lang = lang.to_string();
            if lang.starts_with("zh") {
                let _ = synth.SetVoice(&voice);
                break;
            }
        }
    }

    fn wait_for_playback(player: &MediaPlayer) {
        std::thread::sleep(Duration::from_millis(120));

        let Ok(session) = player.PlaybackSession() else {
            std::thread::sleep(Duration::from_secs(2));
            return;
        };

        let deadline = Instant::now() + Duration::from_secs(30);
        loop {
            let Ok(state) = session.PlaybackState() else {
                break;
            };

            if state != MediaPlaybackState::Playing || Instant::now() >= deadline {
                break;
            }

            std::thread::sleep(Duration::from_millis(50));
        }
    }

    pub fn speak(text: &str) -> Result<(), String> {
        let text = text.trim();
        if text.is_empty() {
            return Ok(());
        }

        unsafe {
            let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
        }

        cancel();

        let synthesizer =
            SpeechSynthesizer::new().map_err(|error| format!("创建语音合成器失败: {error}"))?;
        pick_chinese_voice(&synthesizer);

        let stream = wait_async(
            &synthesizer
                .SynthesizeTextToStreamAsync(&HSTRING::from(text))
                .map_err(|error| format!("合成语音失败: {error}"))?,
        )
        .map_err(|error| format!("等待语音合成失败: {error}"))?;

        let content_type = stream
            .ContentType()
            .unwrap_or_else(|_| HSTRING::from("audio/mpeg"));

        let source = MediaSource::CreateFromStream(&stream, &content_type)
            .map_err(|error| format!("创建音频源失败: {error}"))?;

        let player =
            MediaPlayer::new().map_err(|error| format!("创建音频播放器失败: {error}"))?;
        player
            .SetSource(&source)
            .map_err(|error| format!("设置语音流失败: {error}"))?;
        player
            .Play()
            .map_err(|error| format!("播放语音失败: {error}"))?;

        if let Ok(mut slot) = player_slot().lock() {
            *slot = Some(player);
        }

        if let Ok(slot) = player_slot().lock() {
            if let Some(active) = slot.as_ref() {
                wait_for_playback(active);
            }
        }

        if let Ok(mut slot) = player_slot().lock() {
            slot.take();
        }

        Ok(())
    }

    pub fn cancel() {
        let Ok(mut slot) = player_slot().lock() else {
            return;
        };

        if let Some(player) = slot.take() {
            let _ = player.Pause();
        }
    }
}

#[cfg(not(target_os = "windows"))]
mod platform {
    pub fn speak(_text: &str) -> Result<(), String> {
        Err("Windows 原生 TTS 仅支持 Windows 平台".to_string())
    }

    pub fn cancel() {}
}

pub fn speak(text: &str) -> Result<(), String> {
    platform::speak(text)
}

pub fn cancel() {
    platform::cancel();
}

#[tauri::command]
pub fn native_speak_text(text: String) -> Result<(), String> {
    let text = text.trim().to_string();
    if text.is_empty() {
        return Ok(());
    }

    std::thread::spawn(move || {
        if let Err(error) = speak(&text) {
            eprintln!("[QMS] Windows 原生 TTS 播报失败: {error}");
        }
    });

    Ok(())
}

#[tauri::command]
pub fn native_cancel_speech() {
    cancel();
}
