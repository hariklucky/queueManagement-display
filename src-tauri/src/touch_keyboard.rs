use serde::Serialize;
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

const CREATE_NO_WINDOW: u32 = 0x08000000;

const TABTIP_PATHS: &[&str] = &[
    r"C:\Program Files\Common Files\microsoft shared\ink\TabTip.exe",
    r"C:\Program Files (x86)\Common Files\Microsoft Shared\Ink\TabTip.exe",
];

/// 通过 PowerShell 调用 COM ITipInvocation.Toggle 显示触摸键盘
const SHOW_TOUCH_KEYBOARD_SCRIPT: &str = r#"
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("4ce576fa-83dc-4F88-951c-9d0782b4e376")]
class UIHostNoLaunch { }

[ComImport, Guid("37c994e7-432b-4834-a2f7-dce1f13b834b")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface ITipInvocation {
    void Toggle(IntPtr hwnd);
}

public static class TouchKeyboardHelper {
    [DllImport("user32.dll")]
    public static extern IntPtr GetDesktopWindow();

    public static void Show() {
        var host = new UIHostNoLaunch();
        var tip = (ITipInvocation)host;
        tip.Toggle(GetDesktopWindow());
        Marshal.ReleaseComObject(host);
    }
}
"@

[TouchKeyboardHelper]::Show()
"#;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TouchKeyboardResult {
    pub method: String,
    pub visible: bool,
}

#[cfg(target_os = "windows")]
mod win {
    use super::*;
    use windows::core::w;
    use windows::Win32::Foundation::HWND;
    use windows::Win32::UI::WindowsAndMessaging::{FindWindowW, IsWindowVisible};

    pub fn is_tabtip_visible() -> bool {
        is_window_visible(w!("IPTip_Main_Window"))
    }

    pub fn is_osk_visible() -> bool {
        is_window_visible(w!("OSKMainClass"))
    }

    fn is_window_visible(class_name: windows::core::PCWSTR) -> bool {
        unsafe {
            let hwnd = FindWindowW(class_name, None).unwrap_or(HWND::default());
            !hwnd.0.is_null() && IsWindowVisible(hwnd).as_bool()
        }
    }

    pub fn invoke_tip_toggle() -> Result<(), String> {
        let output = run_hidden_command(
            "powershell",
            &[
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-WindowStyle",
                "Hidden",
                "-Command",
                SHOW_TOUCH_KEYBOARD_SCRIPT,
            ],
        )?;

        if output.status.success() {
            return Ok(());
        }

        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let detail = if stderr.is_empty() { stdout } else { stderr };

        Err(if detail.is_empty() {
            "TipInvocation 调用失败".into()
        } else {
            detail
        })
    }
}

#[cfg(target_os = "windows")]
fn windows_command(program: &str) -> Command {
    let mut command = Command::new(program);
    command.creation_flags(CREATE_NO_WINDOW);
    command
}

#[cfg(target_os = "windows")]
fn run_hidden_command(program: &str, args: &[&str]) -> Result<std::process::Output, String> {
    windows_command(program)
        .args(args)
        .output()
        .map_err(|error| format!("无法执行 {program}: {error}"))
}

#[cfg(target_os = "windows")]
fn set_registry_dword(path: &str, name: &str, value: u32) {
    let _ = run_hidden_command(
        "reg",
        &[
            "add",
            path,
            "/v",
            name,
            "/t",
            "REG_DWORD",
            "/d",
            &value.to_string(),
            "/f",
        ],
    );
}

/// 启用“未连接键盘时在桌面模式显示触摸键盘”等策略（HKCU，无需管理员）
#[cfg(target_os = "windows")]
pub fn ensure_settings() {
    set_registry_dword(
        r"HKCU\Software\Microsoft\TabletTip\1.7",
        "EnableDesktopModeAutoInvoke",
        1,
    );
    set_registry_dword(
        r"HKCU\Software\Microsoft\TabletTip\1.7",
        "DisableNewKeyboardExperience",
        1,
    );
    set_registry_dword(
        r"HKCU\Software\Microsoft\TabletTip\1.7",
        "EdgeTargetMode",
        1,
    );
}

#[cfg(not(target_os = "windows"))]
pub fn ensure_settings() {}

#[cfg(target_os = "windows")]
fn tabtip_process_running() -> bool {
    run_hidden_command("tasklist", &["/FI", "IMAGENAME eq TabTip.exe", "/NH"])
        .map(|output| {
            String::from_utf8_lossy(&output.stdout)
                .to_ascii_lowercase()
                .contains("tabtip.exe")
        })
        .unwrap_or(false)
}

#[cfg(target_os = "windows")]
fn spawn_tabtip() -> Result<(), String> {
    for path in TABTIP_PATHS {
        if !Path::new(path).exists() {
            continue;
        }

        windows_command(path)
            .spawn()
            .map_err(|error| format!("无法启动 {path}: {error}"))?;

        return Ok(());
    }

    Err("未找到 TabTip.exe".into())
}

#[cfg(target_os = "windows")]
fn ensure_tabtip_running() -> Result<(), String> {
    if tabtip_process_running() {
        return Ok(());
    }

    spawn_tabtip()?;
    thread::sleep(Duration::from_millis(600));
    Ok(())
}

#[cfg(target_os = "windows")]
pub fn warm_up() {
    let _ = ensure_tabtip_running();
}

#[cfg(not(target_os = "windows"))]
pub fn warm_up() {}

#[cfg(target_os = "windows")]
fn wait_for_keyboard_visible(check: fn() -> bool, timeout_ms: u64) -> bool {
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);

    while Instant::now() < deadline {
        if check() {
            return true;
        }

        thread::sleep(Duration::from_millis(120));
    }

    false
}

#[cfg(target_os = "windows")]
fn try_show_tabtip() -> TouchKeyboardResult {
    if ensure_tabtip_running().is_err() {
        return TouchKeyboardResult {
            method: "tabtip".into(),
            visible: false,
        };
    }

    if win::invoke_tip_toggle().is_err() {
        return TouchKeyboardResult {
            method: "tabtip".into(),
            visible: false,
        };
    }

    TouchKeyboardResult {
        method: "tabtip".into(),
        visible: wait_for_keyboard_visible(win::is_tabtip_visible, 900),
    }
}

#[cfg(target_os = "windows")]
fn try_show_osk() -> TouchKeyboardResult {
    if windows_command("osk.exe").spawn().is_err() {
        return TouchKeyboardResult {
            method: "osk".into(),
            visible: false,
        };
    }

    TouchKeyboardResult {
        method: "osk".into(),
        visible: wait_for_keyboard_visible(win::is_osk_visible, 900),
    }
}

/// 唤起 Windows 触摸键盘，并检测键盘窗口是否真正显示
pub fn show() -> TouchKeyboardResult {
    #[cfg(target_os = "windows")]
    {
        ensure_settings();

        let tabtip = try_show_tabtip();
        if tabtip.visible {
            return tabtip;
        }

        let osk = try_show_osk();
        if osk.visible {
            return osk;
        }

        TouchKeyboardResult {
            method: "none".into(),
            visible: false,
        }
    }

    #[cfg(not(target_os = "windows"))]
    TouchKeyboardResult {
        method: "skipped-non-windows".into(),
        visible: false,
    }
}
