mod http;
mod touch_keyboard;

#[tauri::command]
fn show_touch_keyboard() -> touch_keyboard::TouchKeyboardResult {
    touch_keyboard::show()
}

#[tauri::command]
fn warm_up_touch_keyboard() {
    touch_keyboard::warm_up();
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_device_info::init())
        .plugin(tauri_plugin_shell::init())
        .setup(|_| {
            #[cfg(target_os = "windows")]
            {
                touch_keyboard::ensure_settings();
                touch_keyboard::warm_up();
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            show_touch_keyboard,
            warm_up_touch_keyboard,
            http::native_http_fetch
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
