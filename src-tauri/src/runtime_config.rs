use serde::{Deserialize, Serialize};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use tauri::path::BaseDirectory;
use tauri::{AppHandle, Manager};

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeConfig {
    pub api_base_url: Option<String>,
    pub gateway_id: Option<String>,
    pub force_on_screen_keyboard: Option<bool>,
}

fn resolve_install_dir(app: &AppHandle) -> Option<PathBuf> {
    if let Ok(dir) = app.path().executable_dir() {
        return Some(dir);
    }

    std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.to_path_buf()))
}

fn install_config_path(app: &AppHandle) -> Option<PathBuf> {
    resolve_install_dir(app).map(|dir| dir.join("config.json"))
}

fn user_config_path(app: &AppHandle) -> Option<PathBuf> {
    app.path()
        .app_config_dir()
        .ok()
        .map(|dir| dir.join("config.json"))
}

fn resolve_example_config_path(app: &AppHandle) -> Option<PathBuf> {
    for key in [
        "../config.example.json",
        "config.example.json",
        "_up_/config.example.json",
    ] {
        if let Ok(path) = app.path().resolve(key, BaseDirectory::Resource) {
            if path.is_file() {
                return Some(path);
            }
        }
    }

    if let Ok(resource_dir) = app.path().resource_dir() {
        for path in [
            resource_dir.join("config.example.json"),
            resource_dir.join("_up_").join("config.example.json"),
            resource_dir.join("resources").join("config.example.json"),
            resource_dir
                .join("resources")
                .join("_up_")
                .join("config.example.json"),
        ] {
            if path.is_file() {
                return Some(path);
            }
        }
    }

    None
}

fn copy_example_to(config_path: &Path, example_path: &Path) -> io::Result<()> {
    if let Some(parent) = config_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::copy(example_path, config_path)?;
    Ok(())
}

fn locate_existing_config(app: &AppHandle) -> Option<PathBuf> {
    for path in [install_config_path(app), user_config_path(app)].into_iter().flatten() {
        if path.is_file() {
            return Some(path);
        }
    }
    None
}

fn ensure_config_at(target: &Path, example_path: &Path, label: &str) -> bool {
    if target.is_file() {
        return true;
    }

    match copy_example_to(target, example_path) {
        Ok(_) => {
            eprintln!(
                "[QMS] 已在{label}生成 config.json: {}",
                target.display()
            );
            true
        }
        Err(error) => {
            eprintln!(
                "[QMS] 复制 config.example.json 到{label}失败 {}: {error}",
                target.display()
            );
            false
        }
    }
}

pub fn ensure_install_config(app: &AppHandle) {
    if let Some(install_dir) = resolve_install_dir(app) {
        eprintln!("[QMS] 应用安装目录: {}", install_dir.display());
    }

    if locate_existing_config(app).is_some() {
        return;
    }

    let Some(example_path) = resolve_example_config_path(app) else {
        eprintln!("[QMS] 未找到 config.example.json 模板，无法初始化 config.json");
        return;
    };

    eprintln!("[QMS] 使用配置模板: {}", example_path.display());

    if let Some(install_path) = install_config_path(app) {
        if ensure_config_at(&install_path, &example_path, "安装目录") {
            return;
        }
    }

    if let Some(user_path) = user_config_path(app) {
        ensure_config_at(&user_path, &example_path, "用户配置目录");
    }
}

#[tauri::command]
pub fn load_runtime_config(app: AppHandle) -> RuntimeConfig {
    let Some(config_path) = locate_existing_config(&app) else {
        eprintln!("[QMS] 未找到 config.json（已检查安装目录与用户配置目录）");
        return RuntimeConfig::default();
    };

    let text = match fs::read_to_string(&config_path) {
        Ok(content) => content,
        Err(error) => {
            eprintln!(
                "[QMS] 读取 config.json 失败 {}: {error}",
                config_path.display()
            );
            return RuntimeConfig::default();
        }
    };

    match serde_json::from_str::<RuntimeConfig>(&text) {
        Ok(config) => {
            eprintln!("[QMS] 已加载 config.json: {}", config_path.display());
            config
        }
        Err(error) => {
            eprintln!(
                "[QMS] config.json 解析失败 {}: {error}",
                config_path.display()
            );
            RuntimeConfig::default()
        }
    }
}
