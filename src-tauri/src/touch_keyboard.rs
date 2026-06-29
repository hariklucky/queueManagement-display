/// 唤起 Windows 触摸键盘（TabTip）
pub fn show() -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        use std::process::Command;

        const CREATE_NO_WINDOW: u32 = 0x08000000;
        const SCRIPT: &str = r#"
$tip = New-Object -ComObject UIHostNoLaunch
$inv = $tip.GetType().InvokeMember(
  'TipInvocation',
  [System.Reflection.BindingFlags]::InvokeMethod,
  $null,
  $tip,
  $null
)
$inv.Toggle($null)
"#;

        Command::new("powershell")
            .args(["-NoProfile", "-WindowStyle", "Hidden", "-Command", SCRIPT])
            .creation_flags(CREATE_NO_WINDOW)
            .spawn()
            .map_err(|error| format!("无法打开触摸键盘: {error}"))?;

        Ok(())
    }

    #[cfg(not(target_os = "windows"))]
    {
        Ok(())
    }
}
