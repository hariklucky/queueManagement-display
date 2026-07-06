// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    #[cfg(target_os = "windows")]
    configure_webview_for_remote_display();

    qms_lib::run()
}

#[cfg(target_os = "windows")]
fn configure_webview_for_remote_display() {
    use std::env;

    const GPU_ARGS: &str =
        "--disable-gpu --disable-gpu-compositing --disable-direct-composition --use-angle=swiftshader";

    match env::var("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS") {
        Ok(existing) if existing.contains("--disable-gpu") => {}
        Ok(existing) if !existing.trim().is_empty() => {
            env::set_var(
                "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS",
                format!("{existing} {GPU_ARGS}"),
            );
        }
        _ => env::set_var("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", GPU_ARGS),
    }
}
