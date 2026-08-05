#!/usr/bin/env bash
# 生成银河麒麟 / X11 环境下的应用启动脚本（deb 与 AppImage 共用）
set -euo pipefail

kylin_ld_linux() {
  case "${1:-$(uname -m)}" in
    aarch64|arm64) echo "ld-linux-aarch64.so.1" ;;
    x86_64|amd64) echo "ld-linux-x86-64.so.2" ;;
    *)
      echo "错误：不支持的架构 \"${1:-$(uname -m)}\"" >&2
      return 1
      ;;
  esac
}

kylin_glib_dir() {
  case "${1:-$(uname -m)}" in
    aarch64|arm64) echo "/lib/aarch64-linux-gnu" ;;
    x86_64|amd64) echo "/lib/x86_64-linux-gnu" ;;
    *)
      echo "错误：不支持的架构 \"${1:-$(uname -m)}\"" >&2
      return 1
      ;;
  esac
}

kylin_lib_search_dirs() {
  local arch_dir
  arch_dir="$(kylin_glib_dir "$1")"
  printf '%s\n' "$arch_dir" "/usr${arch_dir}" "/lib" "/usr/lib"
}

kylin_detect_main_bin() {
  local app_dir="$1"
  local main_bin=""
  local candidate apprun

  for apprun in "$app_dir/AppRun.orig" "$app_dir/AppRun"; do
    [[ -f "$apprun" ]] || continue
    main_bin="$(grep -Eo 'usr/bin/[^[:space:]"'"'"']+' "$apprun" 2>/dev/null | head -n 1 | sed 's|.*/||' || true)"
    if [[ -n "$main_bin" && -f "$app_dir/usr/bin/$main_bin" ]]; then
      printf '%s' "$main_bin"
      return 0
    fi
  done

  # AppImage 解压后可能丢失可执行位，不能依赖 -perm -111
  while IFS= read -r -d '' candidate; do
    [[ -f "$candidate" ]] || continue
    [[ "$candidate" == *.so* ]] && continue
    if file "$candidate" 2>/dev/null | grep -q 'ELF .* executable'; then
      basename "$candidate"
      return 0
    fi
  done < <(find "$app_dir/usr/bin" -maxdepth 1 -type f ! -name '*.so*' -print0 2>/dev/null)

  # 常见命名：Cargo 包名 qms、Tauri productName（如 报到取号）
  for main_bin in qms 报到取号; do
    if [[ -f "$app_dir/usr/bin/$main_bin" ]]; then
      printf '%s' "$main_bin"
      return 0
    fi
  done

  # 若目录里只有一个非 .so 文件，即为主程序
  local -a bins=()
  while IFS= read -r -d '' candidate; do
    bins+=("$candidate")
  done < <(find "$app_dir/usr/bin" -maxdepth 1 -type f ! -name '*.so*' -print0 2>/dev/null)
  if ((${#bins[@]} == 1)); then
    basename "${bins[0]}"
    return 0
  fi

  echo "错误：无法确定主程序（$app_dir/usr/bin）" >&2
  echo "目录内容：" >&2
  ls -la "$app_dir/usr/bin/" >&2 || true
  return 1
}

kylin_ensure_bin_executable() {
  local app_dir="$1"
  local main_bin="$2"
  local bin_path="$app_dir/usr/bin/$main_bin"
  [[ -f "$bin_path" ]] && chmod +x "$bin_path" 2>/dev/null || true
  [[ -x "$app_dir/AppRun" ]] || chmod +x "$app_dir/AppRun" 2>/dev/null || true
}

kylin_ensure_loader_executable() {
  local compat_dir="$1"
  local ld_linux="$2"
  local loader="$compat_dir/$ld_linux"
  [[ -f "$loader" ]] && chmod +x "$loader" 2>/dev/null || true
}

kylin_write_launcher() {
  local output="$1"
  local app_root="$2"
  local main_bin="$3"
  local ld_linux="$4"
  local use_relative="${5:-0}"

  if [[ "$use_relative" == "1" ]]; then
    cat > "$output" <<EOF
#!/bin/sh
HERE="\$(CDPATH= cd -- "\$(dirname "\$0")" && pwd)"
APP_ROOT="\$HERE"
MAIN_BIN="$main_bin"
LD_LINUX="$ld_linux"
LIBPATH="\$APP_ROOT/usr/lib/glibc-compat:\$APP_ROOT/usr/lib"
export PATH="\$APP_ROOT/usr/bin:\${PATH:-/usr/bin:/bin}"
export LD_LIBRARY_PATH="\$LIBPATH\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="\$APP_ROOT/usr/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export DISPLAY="\${DISPLAY:-:0}"
export GDK_BACKEND=x11
export GTK_USE_PORTAL=0
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export GSETTINGS_BACKEND=memory
export LIBGL_ALWAYS_SOFTWARE=1
unset WAYLAND_DISPLAY
LOG_DIR="\${XDG_CACHE_HOME:-\$HOME/.cache}/qms"
mkdir -p "\$LOG_DIR" 2>/dev/null || true
LOG_FILE="\$LOG_DIR/launch.log"

kylin_notify_failure() {
  msg="\$1"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "报到取号" "\$msg" 2>/dev/null || true
  fi
}

kylin_run_app() {
  "\$APP_ROOT/usr/lib/glibc-compat/\$LD_LINUX" \\
    --library-path "\$LIBPATH" \\
    "\$APP_ROOT/usr/bin/\$MAIN_BIN" "\$@"
}

if [ ! -f "\$APP_ROOT/usr/lib/glibc-compat/\$LD_LINUX" ]; then
  echo "错误：缺少 bundled loader: \$APP_ROOT/usr/lib/glibc-compat/\$LD_LINUX" >&2
  kylin_notify_failure "缺少运行时 loader，请重新安装 deb 包"
  exit 127
fi
chmod +x "\$APP_ROOT/usr/lib/glibc-compat/\$LD_LINUX" 2>/dev/null || true
if [ ! -f "\$APP_ROOT/usr/bin/\$MAIN_BIN" ]; then
  echo "错误：缺少主程序: \$APP_ROOT/usr/bin/\$MAIN_BIN" >&2
  kylin_notify_failure "缺少主程序，请重新安装 deb 包"
  exit 127
fi
chmod +x "\$APP_ROOT/usr/bin/\$MAIN_BIN" 2>/dev/null || true

if [ -t 2 ]; then
  exec kylin_run_app "\$@"
else
  {
    echo "=== \$(date '+%Y-%m-%d %H:%M:%S') 启动 ==="
    echo "DISPLAY=\$DISPLAY APP_ROOT=\$APP_ROOT MAIN_BIN=\$MAIN_BIN"
    if kylin_run_app "\$@"; then
      echo "=== 正常退出 ==="
    else
      code=\$?
      echo "=== 启动失败，退出码: \$code ==="
      kylin_notify_failure "启动失败(退出码 \$code)，详见 \$LOG_FILE"
      exit "\$code"
    fi
  } >>"\$LOG_FILE" 2>&1
fi
EOF
  else
    cat > "$output" <<EOF
#!/bin/sh
APP_ROOT="$app_root"
MAIN_BIN="$main_bin"
LD_LINUX="$ld_linux"
LIBPATH="\$APP_ROOT/usr/lib/glibc-compat:\$APP_ROOT/usr/lib"
export PATH="\$APP_ROOT/usr/bin:\${PATH:-/usr/bin:/bin}"
export LD_LIBRARY_PATH="\$LIBPATH\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="\$APP_ROOT/usr/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export DISPLAY="\${DISPLAY:-:0}"
export GDK_BACKEND=x11
export GTK_USE_PORTAL=0
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export GSETTINGS_BACKEND=memory
export LIBGL_ALWAYS_SOFTWARE=1
unset WAYLAND_DISPLAY
LOG_DIR="\${XDG_CACHE_HOME:-\$HOME/.cache}/qms"
mkdir -p "\$LOG_DIR" 2>/dev/null || true
LOG_FILE="\$LOG_DIR/launch.log"

kylin_notify_failure() {
  msg="\$1"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "报到取号" "\$msg" 2>/dev/null || true
  fi
}

kylin_run_app() {
  "\$APP_ROOT/usr/lib/glibc-compat/\$LD_LINUX" \\
    --library-path "\$LIBPATH" \\
    "\$APP_ROOT/usr/bin/\$MAIN_BIN" "\$@"
}

if [ ! -f "\$APP_ROOT/usr/lib/glibc-compat/\$LD_LINUX" ]; then
  echo "错误：缺少 bundled loader: \$APP_ROOT/usr/lib/glibc-compat/\$LD_LINUX" >&2
  kylin_notify_failure "缺少运行时 loader，请重新安装 deb 包"
  exit 127
fi
chmod +x "\$APP_ROOT/usr/lib/glibc-compat/\$LD_LINUX" 2>/dev/null || true
if [ ! -f "\$APP_ROOT/usr/bin/\$MAIN_BIN" ]; then
  echo "错误：缺少主程序: \$APP_ROOT/usr/bin/\$MAIN_BIN" >&2
  kylin_notify_failure "缺少主程序，请重新安装 deb 包"
  exit 127
fi
chmod +x "\$APP_ROOT/usr/bin/\$MAIN_BIN" 2>/dev/null || true

if [ -t 2 ]; then
  exec kylin_run_app "\$@"
else
  {
    echo "=== \$(date '+%Y-%m-%d %H:%M:%S') 启动 ==="
    echo "DISPLAY=\$DISPLAY APP_ROOT=\$APP_ROOT MAIN_BIN=\$MAIN_BIN"
    if kylin_run_app "\$@"; then
      echo "=== 正常退出 ==="
    else
      code=\$?
      echo "=== 启动失败，退出码: \$code ==="
      kylin_notify_failure "启动失败(退出码 \$code)，详见 \$LOG_FILE"
      exit "\$code"
    fi
  } >>"\$LOG_FILE" 2>&1
fi
EOF
  fi
  chmod 755 "$output"
}

kylin_write_debug_launcher() {
  local output="$1"
  local app_root="$2"
  local main_bin="$3"
  local ld_linux="$4"

  cat > "$output" <<EOF
#!/bin/sh
APP_ROOT="$app_root"
MAIN_BIN="$main_bin"
LD_LINUX="$ld_linux"
LIBPATH="\$APP_ROOT/usr/lib/glibc-compat:\$APP_ROOT/usr/lib"
export LD_LIBRARY_PATH="\$LIBPATH"
export DISPLAY="\${DISPLAY:-:0}"
export GDK_BACKEND=x11
export GTK_USE_PORTAL=0
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export LIBGL_ALWAYS_SOFTWARE=1
unset WAYLAND_DISPLAY

echo "=== QMS 启动诊断 ==="
echo "APP_ROOT=\$APP_ROOT"
echo "MAIN_BIN=\$MAIN_BIN"
echo "LIBPATH=\$LIBPATH"
echo
echo "=== 主程序依赖 (bundled loader) ==="
"\$APP_ROOT/usr/lib/glibc-compat/\$LD_LINUX" --library-path "\$LIBPATH" ldd "\$APP_ROOT/usr/bin/\$MAIN_BIN" || true
echo
echo "=== 尝试启动 ==="
exec "\$APP_ROOT/usr/lib/glibc-compat/\$LD_LINUX" \\
  --library-path "\$LIBPATH" \\
  "\$APP_ROOT/usr/bin/\$MAIN_BIN" "\$@"
EOF
  chmod 755 "$output"
}

kylin_find_lib_on_system() {
  local lib_name="$1"
  local dir
  while IFS= read -r dir; do
    [[ -f "$dir/$lib_name" ]] && { printf '%s' "$dir/$lib_name"; return 0; }
  done < <(kylin_lib_search_dirs)
  return 1
}

kylin_copy_runtime_libs() {
  local compat_dir="$1"
  local glib_dir="$2"
  local ld_linux="$3"
  local app_dir="${4:-}"

  mkdir -p "$compat_dir"

  copy_lib() {
    local src="$1"
    local dest_dir="${2:-$compat_dir}"
    if [[ -f "$src" ]]; then
      cp -Lfn "$src" "$dest_dir/"
    fi
  }

  for lib in \
    "$ld_linux" \
    libc.so.6 \
    libm.so.6 \
    libpthread.so.0 \
    libdl.so.2 \
    librt.so.1 \
    libresolv.so.2 \
    libutil.so.1 \
    libnss_files.so.2 \
    libnss_dns.so.2 \
    libnsl.so.1 \
    libnss_compat.so.2 \
    libgcc_s.so.1 \
    libstdc++.so.6; do
    copy_lib "$glib_dir/$lib"
    copy_lib "/usr${glib_dir}/$lib"
  done
  kylin_ensure_loader_executable "$compat_dir" "$ld_linux"

  [[ -n "$app_dir" ]] || return 0

  local libpath="$compat_dir:$app_dir/usr/lib"
  local loader="$compat_dir/$ld_linux"
  local -a targets=()
  local target

  while IFS= read -r -d '' target; do
    targets+=("$target")
  done < <(find "$app_dir/usr/bin" "$app_dir/usr/lib" -type f \( -perm -111 -o -name '*.so*' \) -print0 2>/dev/null)

  kylin_is_glibc_runtime_lib() {
    case "$1" in
      libnss_*|"$ld_linux"|libc.so.6|libm.so.6|libpthread.so.0|libdl.so.2|librt.so.1|libresolv.so.2|libutil.so.1|libgcc_s.so.1|libstdc++.so.6)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }

  local pass missing lib_name lib_path lib_basename
  for pass in 1 2 3 4 5 6; do
    missing=0
    for target in "${targets[@]}"; do
      [[ -f "$target" ]] || continue
      while IFS= read -r line; do
        if [[ "$line" == *" not found" ]]; then
          lib_name="${line%% =>*}"
          lib_name="${lib_name##*[[:space:]]}"
          lib_path="$(kylin_find_lib_on_system "$lib_name" || true)"
          if [[ -n "$lib_path" ]]; then
            if kylin_is_glibc_runtime_lib "$lib_name"; then
              copy_lib "$lib_path" "$compat_dir"
            else
              copy_lib "$lib_path" "$app_dir/usr/lib"
            fi
            missing=1
          else
            echo "警告：仍缺少库 $lib_name（来自 $(basename "$target")）" >&2
          fi
        elif [[ "$line" == *" => "* ]]; then
          lib_path="${line#* => }"
          lib_path="${lib_path%%[[:space:]]*}"
          [[ "$lib_path" == "$app_dir/"* ]] && continue
          lib_basename="$(basename "$lib_path")"
          if kylin_is_glibc_runtime_lib "$lib_basename"; then
            copy_lib "$lib_path" "$compat_dir"
            missing=1
          elif [[ -f "$lib_path" && ! -f "$app_dir/usr/lib/$lib_basename" ]]; then
            copy_lib "$lib_path" "$app_dir/usr/lib"
            missing=1
          fi
        fi
      done < <("$loader" --library-path "$libpath" ldd "$target" 2>/dev/null || true)
    done
    kylin_ensure_loader_executable "$compat_dir" "$ld_linux"
    [[ "$missing" -eq 1 ]] || break
  done
}

kylin_patch_elfs() {
  local app_dir="$1"
  local _compat_dir="$2"
  local _ld_linux="$3"
  local interp_path="$4"

  command -v patchelf >/dev/null 2>&1 || return 0

  local rpath='$ORIGIN/../lib/glibc-compat:$ORIGIN/../lib'
  local target

  # 仅修补 usr/bin 下可执行文件；不要修改 .so 的 interpreter，否则会破坏 WebKit 等库。
  while IFS= read -r -d '' target; do
    [[ -f "$target" ]] || continue
    file "$target" 2>/dev/null | grep -q 'ELF .* executable' || continue
    patchelf --set-interpreter "$interp_path" "$target" 2>/dev/null || true
    patchelf --set-rpath "$rpath" "$target" 2>/dev/null || true
  done < <(find "$app_dir/usr/bin" -maxdepth 1 -type f -print0 2>/dev/null)
}

kylin_verify_bundle() {
  local app_dir="$1"
  local main_bin="$2"
  local ld_linux="$3"
  local strict="${KYLIN_VERIFY_STRICT:-0}"

  local compat_dir="$app_dir/usr/lib/glibc-compat"
  local libpath="$compat_dir:$app_dir/usr/lib"
  local loader="$compat_dir/$ld_linux"
  local main="$app_dir/usr/bin/$main_bin"
  local failed=0
  local missing_lines=()

  if [[ ! -x "$loader" || ! -f "$compat_dir/libc.so.6" ]]; then
    echo "错误：glibc-compat 不完整" >&2
    return 1
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" == *" not found" ]]; then
      # vdso / 可选插件不算致命错误
      if [[ "$line" == *"linux-vdso.so.1"* ]]; then
        continue
      fi
      missing_lines+=("$line")
      failed=1
    fi
  done < <("$loader" --library-path "$libpath" ldd "$main" 2>/dev/null || true)

  if [[ "$failed" -eq 1 ]]; then
    echo "警告：bundled loader 下主程序仍有未解析依赖（安装后可用 qms-debug 排查）：" >&2
    printf '  %s\n' "${missing_lines[@]}" >&2
    if [[ "$strict" == "1" ]]; then
      return 1
    fi
  else
    echo "bundled loader 依赖检查通过。"
  fi

  return 0
}
