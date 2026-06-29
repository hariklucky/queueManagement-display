mod http;
mod touch_keyboard;

#[tauri::command]
fn show_touch_keyboard() -> Result<(), String> {
    touch_keyboard::show()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_device_info::init())
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![show_touch_keyboard, http::native_http_fetch])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
