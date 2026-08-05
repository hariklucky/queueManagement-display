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
  local arch="${1:-$(uname -m)}"
  local arch_dir
  arch_dir="$(kylin_glib_dir "$arch")"
  printf '%s\n' "$arch_dir" "/usr${arch_dir}" "/lib" "/usr/lib" "/lib/${arch}" "/usr/lib/${arch}"
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
export LD_LIBRARY_PATH="\$LIBPATH"
export XDG_DATA_DIRS="\$APP_ROOT/usr/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export DISPLAY="\${DISPLAY:-:0}"
export GDK_BACKEND=x11
export GTK_USE_PORTAL=0
export GTK_MODULES=""
export GTK_IM_MODULE=""
export NO_AT_BRIDGE=1
export GSK_RENDERER=cairo
export GDK_RENDERING=image
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_ACCELERATED_2D_CANVAS=1
export GSETTINGS_BACKEND=memory
export LIBGL_ALWAYS_SOFTWARE=1
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
export GALLIUM_DRIVER=llvmpipe
unset WAYLAND_DISPLAY
unset LD_PRELOAD

kylin_prepare_runtime() {
  case "\$(uname -m)" in
    aarch64|arm64) WEBKIT_LIB_ARCH=aarch64-linux-gnu ;;
    x86_64|amd64) WEBKIT_LIB_ARCH=x86_64-linux-gnu ;;
    *) WEBKIT_LIB_ARCH=aarch64-linux-gnu ;;
  esac
  export WEBKIT_EXEC_PATH="\$APP_ROOT/usr/lib/\$WEBKIT_LIB_ARCH/webkit2gtk-4.1"
  export APPDIR="\$APP_ROOT"
  cd "\$APP_ROOT/usr" 2>/dev/null || cd "\$APP_ROOT" || exit 1
}

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
  exec "\$APP_ROOT/usr/bin/\$MAIN_BIN" "\$@"
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
kylin_prepare_runtime

if [ -t 2 ]; then
  kylin_run_app "\$@"
else
  {
    echo "=== \$(date '+%Y-%m-%d %H:%M:%S') 启动 ==="
    echo "DISPLAY=\$DISPLAY APP_ROOT=\$APP_ROOT MAIN_BIN=\$MAIN_BIN"
    echo "INTERP=\$(readelf -l "\$APP_ROOT/usr/bin/\$MAIN_BIN" 2>/dev/null | grep 'Requesting program interpreter' || true)"
    if "\$APP_ROOT/usr/bin/\$MAIN_BIN" "\$@"; then
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
export LD_LIBRARY_PATH="\$LIBPATH"
export XDG_DATA_DIRS="\$APP_ROOT/usr/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export DISPLAY="\${DISPLAY:-:0}"
export GDK_BACKEND=x11
export GTK_USE_PORTAL=0
export GTK_MODULES=""
export GTK_IM_MODULE=""
export NO_AT_BRIDGE=1
export GSK_RENDERER=cairo
export GDK_RENDERING=image
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_ACCELERATED_2D_CANVAS=1
export GSETTINGS_BACKEND=memory
export LIBGL_ALWAYS_SOFTWARE=1
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
export GALLIUM_DRIVER=llvmpipe
unset WAYLAND_DISPLAY
unset LD_PRELOAD

kylin_prepare_runtime() {
  case "\$(uname -m)" in
    aarch64|arm64) WEBKIT_LIB_ARCH=aarch64-linux-gnu ;;
    x86_64|amd64) WEBKIT_LIB_ARCH=x86_64-linux-gnu ;;
    *) WEBKIT_LIB_ARCH=aarch64-linux-gnu ;;
  esac
  export WEBKIT_EXEC_PATH="\$APP_ROOT/usr/lib/\$WEBKIT_LIB_ARCH/webkit2gtk-4.1"
  export APPDIR="\$APP_ROOT"
  cd "\$APP_ROOT/usr" 2>/dev/null || cd "\$APP_ROOT" || exit 1
}

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
  exec "\$APP_ROOT/usr/bin/\$MAIN_BIN" "\$@"
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
kylin_prepare_runtime

if [ -t 2 ]; then
  kylin_run_app "\$@"
else
  {
    echo "=== \$(date '+%Y-%m-%d %H:%M:%S') 启动 ==="
    echo "DISPLAY=\$DISPLAY APP_ROOT=\$APP_ROOT MAIN_BIN=\$MAIN_BIN"
    echo "INTERP=\$(readelf -l "\$APP_ROOT/usr/bin/\$MAIN_BIN" 2>/dev/null | grep 'Requesting program interpreter' || true)"
    if "\$APP_ROOT/usr/bin/\$MAIN_BIN" "\$@"; then
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
export GTK_MODULES=""
export GTK_IM_MODULE=""
export NO_AT_BRIDGE=1
export GSK_RENDERER=cairo
export GDK_RENDERING=image
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_ACCELERATED_2D_CANVAS=1
export LIBGL_ALWAYS_SOFTWARE=1
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
export GALLIUM_DRIVER=llvmpipe
unset WAYLAND_DISPLAY
unset LD_PRELOAD

kylin_prepare_runtime() {
  case "\$(uname -m)" in
    aarch64|arm64) WEBKIT_LIB_ARCH=aarch64-linux-gnu ;;
    x86_64|amd64) WEBKIT_LIB_ARCH=x86_64-linux-gnu ;;
    *) WEBKIT_LIB_ARCH=aarch64-linux-gnu ;;
  esac
  export WEBKIT_EXEC_PATH="\$APP_ROOT/usr/lib/\$WEBKIT_LIB_ARCH/webkit2gtk-4.1"
  export APPDIR="\$APP_ROOT"
  cd "\$APP_ROOT/usr" 2>/dev/null || cd "\$APP_ROOT" || exit 1
}

kylin_sym_ok() {
  _lib="\$1"
  _sym="\$2"
  objdump -T "\$_lib" 2>/dev/null | grep -Fq "\$_sym" && return 0
  nm -D --defined-only "\$_lib" 2>/dev/null | grep -Fq "\$_sym" && return 0
  return 1
}

echo "=== QMS 启动诊断 ==="
echo "APP_ROOT=\$APP_ROOT"
echo "MAIN_BIN=\$MAIN_BIN"
echo "LIBPATH=\$LIBPATH"
echo
echo "=== 内置 WebKit 运行时库 ==="
for lib in libfreetype.so.6 libgbm.so.1 libdrm.so.2 libwebkit2gtk-4.1.so.0 libgtk-3.so.0 libglib-2.0.so.0; do
  if [ -f "\$APP_ROOT/usr/lib/\$lib" ]; then
    echo "  已内置: \$lib"
  else
    echo "  缺少: \$lib"
  fi
done
echo
_launch_ok=1
echo "=== WebKit 子进程 ==="
kylin_prepare_runtime
for helper in WebKitNetworkProcess WebKitWebProcess WebKitGPUProcess; do
  if [ -x "\$WEBKIT_EXEC_PATH/\$helper" ]; then
    echo "  已内置: \$helper"
  else
    echo "  缺少: \$helper"
    if [ "\$helper" = "WebKitNetworkProcess" ]; then
      _launch_ok=0
    fi
  fi
done
echo "WEBKIT_EXEC_PATH=\$WEBKIT_EXEC_PATH"
echo
echo "=== FreeType / GBM 符号 ==="
if [ -f "\$APP_ROOT/usr/lib/libfreetype.so.6" ]; then
  if kylin_sym_ok "\$APP_ROOT/usr/lib/libfreetype.so.6" FT_Get_Color_Glyph_Paint; then
    echo "libfreetype 包含 FT_Get_Color_Glyph_Paint"
  else
    echo "错误：libfreetype 缺少 FT_Get_Color_Glyph_Paint" >&2
    _launch_ok=0
  fi
else
  echo "错误：未 bundled libfreetype.so.6" >&2
  _launch_ok=0
fi
if [ -f "\$APP_ROOT/usr/lib/libgbm.so.1" ]; then
  if kylin_sym_ok "\$APP_ROOT/usr/lib/libgbm.so.1" gbm_bo_create_with_modifiers2; then
    echo "libgbm 包含 gbm_bo_create_with_modifiers2"
  else
    echo "错误：libgbm 缺少 gbm_bo_create_with_modifiers2" >&2
    _launch_ok=0
  fi
else
  echo "错误：未 bundled libgbm.so.1" >&2
  _launch_ok=0
fi
echo
echo "=== 子进程 loader 检查 ==="
_helper="\$WEBKIT_EXEC_PATH/WebKitNetworkProcess"
if [ -x "\$_helper" ]; then
  _interp="\$(readelf -l "\$_helper" 2>/dev/null | awk '/Requesting program interpreter/ { gsub(/[][]/, "", \$NF); print \$NF; exit }')"
  if [ -n "\$_interp" ]; then
    echo "WebKitNetworkProcess interpreter: \$_interp"
    if [ ! -f "\$_interp" ]; then
      echo "错误：子进程 loader 不存在（Linux 会报「没有那个文件或目录」）" >&2
      _launch_ok=0
    fi
  fi
else
  echo "错误：缺少 WebKitNetworkProcess: \$_helper" >&2
  _launch_ok=0
fi
echo
if [ "\${_launch_ok:-1}" = "0" ]; then
  echo "=== 诊断未通过，跳过启动 ===" >&2
  echo "请重新安装最新 deb 包（需含 WebKit 子进程与新版 FreeType/GBM）。" >&2
  exit 1
fi
echo "=== 尝试启动 ==="
kylin_prepare_runtime
exec "\$APP_ROOT/usr/bin/\$MAIN_BIN" "\$@"
EOF
  chmod 755 "$output"
}

kylin_find_lib_on_system() {
  local lib_name="$1"
  local dir path
  while IFS= read -r dir; do
    [[ -f "$dir/$lib_name" ]] && { printf '%s' "$dir/$lib_name"; return 0; }
  done < <(kylin_lib_search_dirs "${2:-}")
  if command -v ldconfig >/dev/null 2>&1; then
    path="$(ldconfig -p 2>/dev/null | awk -v name="$lib_name" '$1 == name { print $NF; exit }')"
    if [[ -n "$path" && -f "$path" ]]; then
      printf '%s' "$path"
      return 0
    fi
  fi
  # 兜底：部分 CI 环境 ldconfig 缓存未刷新
  path="$(find /usr/lib /lib -name "$lib_name" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$path" && -f "$path" ]]; then
    printf '%s' "$path"
    return 0
  fi
  return 1
}

kylin_find_lib_in_app() {
  local lib_name="$1"
  local app_dir="$2"
  local candidate
  for candidate in \
    "$app_dir/usr/lib/$lib_name" \
    "$app_dir/usr/lib/$(uname -m)-linux-gnu/$lib_name"; do
    [[ -f "$candidate" ]] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}

kylin_lib_has_dynamic_symbol() {
  local lib="$1"
  local symbol="$2"
  [[ -f "$lib" ]] || return 1
  if objdump -T "$lib" 2>/dev/null | grep -Fq "$symbol"; then
    return 0
  fi
  if nm -D --defined-only "$lib" 2>/dev/null | grep -Fq "$symbol"; then
    return 0
  fi
  return 1
}

kylin_freetype_has_webkit_symbol() {
  kylin_lib_has_dynamic_symbol "$1" 'FT_Get_Color_Glyph_Paint'
}

kylin_gbm_has_webkit_symbol() {
  kylin_lib_has_dynamic_symbol "$1" 'gbm_bo_create_with_modifiers2'
}

kylin_freetype_from_webkit_ldd() {
  kylin_webkit_ldd_lib_path "$1" 'libfreetype\.so'
}

kylin_bundle_single_lib_deps() {
  local lib_file="$1"
  local app_dir="$2"
  local line lib_name lib_path

  [[ -f "$lib_file" ]] || return 0

  while IFS= read -r line; do
    if [[ "$line" == *" not found" ]]; then
      lib_name="${line%% =>*}"
      lib_name="${lib_name##*[[:space:]]}"
      lib_path="$(kylin_find_lib_on_system "$lib_name" || true)"
      [[ -n "$lib_path" ]] && kylin_copy_lib_force "$lib_path" "$app_dir/usr/lib"
    elif [[ "$line" == *" => "* ]]; then
      lib_path="${line#* => }"
      lib_path="${lib_path%%[[:space:]]*}"
      [[ "$lib_path" == "$app_dir/"* ]] && continue
      lib_name="$(basename "$lib_path")"
      [[ -f "$lib_path" && ! -f "$app_dir/usr/lib/$lib_name" ]] && \
        kylin_copy_lib_force "$lib_path" "$app_dir/usr/lib"
    fi
  done < <(ldd "$lib_file" 2>/dev/null || true)
}

kylin_fetch_noble_freetype() {
  local dest_dir="$1"
  local deb_url

  case "$(uname -m)" in
    aarch64|arm64)
      deb_url="http://ports.ubuntu.com/pool/main/f/freetype/libfreetype6_2.13.2+dfsg-1build3_arm64.deb"
      ;;
    x86_64|amd64)
      deb_url="http://archive.ubuntu.com/ubuntu/pool/main/f/freetype/libfreetype6_2.13.2+dfsg-1build3_amd64.deb"
      ;;
    *)
      return 1
      ;;
  esac

  kylin_extract_deb_libs "$deb_url" "$dest_dir" 'libfreetype.so.6'
}

kylin_extract_deb_libs() {
  local deb_url="$1"
  local dest_dir="$2"
  local lib_name="${3:-}"
  local workdir lib_path

  workdir="$(mktemp -d)"
  if ! curl -fsSL -o "$workdir/pkg.deb" "$deb_url"; then
    rm -rf "$workdir"
    return 1
  fi
  dpkg-deb -x "$workdir/pkg.deb" "$workdir/extract"
  if [[ -n "$lib_name" ]]; then
    lib_path="$(find "$workdir/extract" -name "$lib_name" | head -n 1 || true)"
    if [[ -z "$lib_path" || ! -f "$lib_path" ]]; then
      rm -rf "$workdir"
      return 1
    fi
    kylin_copy_lib_force "$lib_path" "$dest_dir"
  else
    while IFS= read -r -d '' lib_path; do
      kylin_copy_lib_force "$lib_path" "$dest_dir"
    done < <(find "$workdir/extract" \( -name '*.so' -o -name '*.so.*' \) -type f -print0 2>/dev/null)
  fi
  rm -rf "$workdir"
  return 0
}

kylin_fetch_jammy_gbm_stack() {
  local dest_dir="$1"
  local drm_url gbm_url

  case "$(uname -m)" in
    aarch64|arm64)
      drm_url="http://ports.ubuntu.com/pool/main/libd/libdrm/libdrm2_2.4.113-2~ubuntu0.22.04.1_arm64.deb"
      gbm_url="http://ports.ubuntu.com/pool/main/m/mesa/libgbm1_23.2.1-1ubuntu3.1~22.04.3_arm64.deb"
      ;;
    x86_64|amd64)
      drm_url="http://archive.ubuntu.com/ubuntu/pool/main/libd/libdrm/libdrm2_2.4.113-2~ubuntu0.22.04.1_amd64.deb"
      gbm_url="http://archive.ubuntu.com/ubuntu/pool/main/m/mesa/libgbm1_23.2.1-1ubuntu3.1~22.04.3_amd64.deb"
      ;;
    *)
      return 1
      ;;
  esac

  kylin_extract_deb_libs "$drm_url" "$dest_dir" || return 1
  kylin_extract_deb_libs "$gbm_url" "$dest_dir" || return 1
  return 0
}

kylin_fetch_noble_gbm_stack() {
  local dest_dir="$1"
  local drm_url gbm_url

  case "$(uname -m)" in
    aarch64|arm64)
      drm_url="http://ports.ubuntu.com/pool/main/libd/libdrm/libdrm2_2.4.122-1~ubuntu0.24.04.1_arm64.deb"
      gbm_url="http://ports.ubuntu.com/pool/main/m/mesa/libgbm1_24.2.8-1ubuntu1~24.04.1_arm64.deb"
      ;;
    x86_64|amd64)
      drm_url="http://archive.ubuntu.com/ubuntu/pool/main/libd/libdrm/libdrm2_2.4.122-1~ubuntu0.24.04.1_amd64.deb"
      gbm_url="http://archive.ubuntu.com/ubuntu/pool/main/m/mesa/libgbm1_24.2.8-1ubuntu1~24.04.1_amd64.deb"
      ;;
    *)
      return 1
      ;;
  esac

  kylin_extract_deb_libs "$drm_url" "$dest_dir" || return 1
  kylin_extract_deb_libs "$gbm_url" "$dest_dir" || return 1
  return 0
}

kylin_webkit_ldd_lib_path() {
  local app_dir="$1"
  local lib_pattern="$2"
  local webkit="$app_dir/usr/lib/libwebkit2gtk-4.1.so.0"
  local libpath line lib_path

  [[ -f "$webkit" ]] || return 1
  libpath="$app_dir/usr/lib"
  line="$(LD_LIBRARY_PATH="$libpath" ldd "$webkit" 2>/dev/null | grep "$lib_pattern" | head -n 1 || true)"
  [[ -n "$line" && "$line" != *" not found"* ]] || return 1
  lib_path="${line#* => }"
  lib_path="${lib_path%%[[:space:]]*}"
  [[ -f "$lib_path" ]] || return 1
  printf '%s' "$lib_path"
}

# WebKit 4.1 依赖 FreeType >= 2.10.4（FT_Get_Color_Glyph_Paint），麒麟系统自带版本过旧，必须内置构建机库。
kylin_explicit_app_libs() {
  cat <<'EOF'
libfreetype.so.6
libfontconfig.so.1
libharfbuzz.so.0
libharfbuzz-icu.so.0
libharfbuzz-subset.so.0
libpng16.so.16
libjpeg.so.8
libwebp.so.7
libwebpmux.so.3
libwebpdemux.so.2
libbrotlicommon.so.1
libbrotlidec.so.1
libbrotlienc.so.1
libexpat.so.1
libxml2.so.2
libxslt.so.1
libsqlite3.so.0
libepoxy.so.0
libgbm.so.1
libdrm.so.2
libgtk-3.so.0
libgdk-3.so.0
libglib-2.0.so.0
libgobject-2.0.so.0
libgio-2.0.so.0
libjavascriptcoregtk-4.1.so.0
libwebkit2gtk-4.1.so.0
libsoup-3.0.so.0
libicuuc.so.70
libicudata.so.70
libicui18n.so.70
EOF
}

kylin_copy_lib_force() {
  local src="$1"
  local dest_dir="$2"
  [[ -f "$src" ]] || return 1
  mkdir -p "$dest_dir"
  cp -Lf "$src" "$dest_dir/"
}

kylin_copy_named_lib_to_app() {
  local lib_name="$1"
  local app_dir="$2"
  local lib_path

  lib_path="$(kylin_find_lib_on_system "$lib_name" || true)"
  if [[ -z "$lib_path" ]]; then
    lib_path="$(kylin_find_lib_in_app "$lib_name" "$app_dir" || true)"
  fi
  if [[ -n "$lib_path" ]]; then
    kylin_copy_lib_force "$lib_path" "$app_dir/usr/lib"
    return 0
  fi
  return 1
}

kylin_ensure_freetype_for_webkit() {
  local app_dir="$1"
  local dest="$app_dir/usr/lib/libfreetype.so.6"
  local lib_path

  if kylin_freetype_has_webkit_symbol "$dest"; then
    echo "  libfreetype.so.6 已满足 WebKit 要求（含 FT_Get_Color_Glyph_Paint）"
    return 0
  fi

  lib_path="$(kylin_freetype_from_webkit_ldd "$app_dir" || true)"
  if [[ -n "$lib_path" ]]; then
    echo "  内置 libfreetype.so.6（WebKit ldd）<- $lib_path"
    kylin_copy_lib_force "$lib_path" "$app_dir/usr/lib"
    if kylin_freetype_has_webkit_symbol "$dest"; then
      return 0
    fi
  fi

  lib_path="$(kylin_find_lib_on_system libfreetype.so.6 || true)"
  if [[ -n "$lib_path" ]]; then
    echo "  内置 libfreetype.so.6（系统）<- $lib_path"
    kylin_copy_lib_force "$lib_path" "$app_dir/usr/lib"
    if kylin_freetype_has_webkit_symbol "$dest"; then
      return 0
    fi
  fi

  echo "  系统 FreeType 版本过旧，下载 Ubuntu 24.04 libfreetype6..."
  if kylin_fetch_noble_freetype "$app_dir/usr/lib"; then
    kylin_bundle_single_lib_deps "$dest" "$app_dir"
    if kylin_freetype_has_webkit_symbol "$dest"; then
      echo "  已使用 Ubuntu 24.04 libfreetype.so.6"
      return 0
    fi
  fi

  echo "错误：无法获取含 FT_Get_Color_Glyph_Paint 的 libfreetype.so.6" >&2
  return 1
}

kylin_ensure_gbm_for_webkit() {
  local app_dir="$1"
  local dest="$app_dir/usr/lib/libgbm.so.1"
  local lib_path

  if kylin_gbm_has_webkit_symbol "$dest"; then
    echo "  libgbm.so.1 已满足 WebKit 要求（含 gbm_bo_create_with_modifiers2）"
    return 0
  fi

  lib_path="$(kylin_webkit_ldd_lib_path "$app_dir" 'libgbm\.so' || true)"
  if [[ -n "$lib_path" ]]; then
    echo "  内置 libgbm.so.1（WebKit ldd）<- $lib_path"
    kylin_copy_lib_force "$lib_path" "$app_dir/usr/lib"
    if kylin_gbm_has_webkit_symbol "$dest"; then
      return 0
    fi
  fi

  lib_path="$(kylin_find_lib_on_system libgbm.so.1 || true)"
  if [[ -n "$lib_path" ]]; then
    echo "  内置 libgbm.so.1（系统）<- $lib_path"
    kylin_copy_lib_force "$lib_path" "$app_dir/usr/lib"
    if kylin_gbm_has_webkit_symbol "$dest"; then
      return 0
    fi
  fi

  echo "  系统 GBM 版本过旧，尝试下载 Ubuntu 22.04 libgbm1 + libdrm2..."
  if kylin_fetch_jammy_gbm_stack "$app_dir/usr/lib"; then
    kylin_bundle_single_lib_deps "$dest" "$app_dir"
    if kylin_gbm_has_webkit_symbol "$dest"; then
      echo "  已使用 Ubuntu 22.04 libgbm.so.1"
      return 0
    fi
  fi

  echo "  警告：Jammy GBM 仍不满足要求，尝试 Ubuntu 24.04（部分麒麟 CPU 可能 Illegal instruction）..." >&2
  if kylin_fetch_noble_gbm_stack "$app_dir/usr/lib"; then
    kylin_bundle_single_lib_deps "$dest" "$app_dir"
    if kylin_gbm_has_webkit_symbol "$dest"; then
      echo "  已使用 Ubuntu 24.04 libgbm.so.1"
      return 0
    fi
  fi

  echo "错误：无法获取含 gbm_bo_create_with_modifiers2 的 libgbm.so.1" >&2
  return 1
}

kylin_ensure_gtk_glib_bundled() {
  local app_dir="$1"
  local lib_name

  echo "=== 补全 GTK / GLib 栈（避免加载麒麟系统 GTK 模块）==="
  for lib_name in \
    libgtk-3.so.0 libgdk-3.so.0 libglib-2.0.so.0 libgobject-2.0.so.0 libgio-2.0.so.0 \
    libgmodule-2.0.so.0 libpango-1.0.so.0 libpangocairo-1.0.so.0 libcairo.so.2 \
    libpangoft2-1.0.so.0 libatk-1.0.so.0 libatk-bridge-2.0.so.0; do
    if [[ -f "$app_dir/usr/lib/$lib_name" ]]; then
      continue
    fi
    if kylin_copy_named_lib_to_app "$lib_name" "$app_dir"; then
      echo "  已补全: $lib_name"
    fi
  done
}

kylin_multilib_dir() {
  case "${1:-$(uname -m)}" in
    aarch64|arm64) echo "aarch64-linux-gnu" ;;
    x86_64|amd64) echo "x86_64-linux-gnu" ;;
    *)
      echo "错误：不支持的架构 \"${1:-$(uname -m)}\"" >&2
      return 1
      ;;
  esac
}

kylin_webkit_helper_dir() {
  local app_dir="$1"
  echo "$app_dir/usr/lib/$(kylin_multilib_dir)/webkit2gtk-4.1"
}

kylin_same_path() {
  local a="$1" b="$2"
  [[ -e "$a" && -e "$b" ]] || return 1
  if command -v readlink >/dev/null 2>&1; then
    a="$(readlink -f "$a" 2>/dev/null || echo "$a")"
    b="$(readlink -f "$b" 2>/dev/null || echo "$b")"
  fi
  [[ "$a" == "$b" ]]
}

kylin_install_webkit_helper() {
  local src_file="$1"
  local dest_dir="$2"
  local helper_name dest_file

  [[ -f "$src_file" ]] || return 1
  helper_name="$(basename "$src_file")"
  dest_file="$dest_dir/$helper_name"
  if kylin_same_path "$src_file" "$dest_file"; then
    chmod +x "$dest_file" 2>/dev/null || true
    echo "  已存在: $helper_name ($dest_file)"
    return 0
  fi
  cp -f "$src_file" "$dest_dir/"
  chmod +x "$dest_file"
  echo "  已内置: $helper_name <- $src_file"
  return 0
}

kylin_fetch_webkit_helpers_from_deb() {
  local dest_dir="$1"
  local helper_path helper_dir helper pkg

  if command -v dpkg >/dev/null 2>&1; then
    for pkg in libwebkit2gtk-4.1-0 libwebkit2gtk-4.0-37; do
      helper_path="$(dpkg -L "$pkg" 2>/dev/null | grep '/WebKitNetworkProcess$' | head -n 1 || true)"
      [[ -n "$helper_path" && -f "$helper_path" ]] && break
      helper_path=""
    done
    if [[ -n "$helper_path" && -f "$helper_path" ]]; then
      helper_dir="${helper_path%/*}"
      for helper in WebKitNetworkProcess WebKitWebProcess WebKitGPUProcess; do
        [[ -f "$helper_dir/$helper" ]] || continue
        kylin_install_webkit_helper "$helper_dir/$helper" "$dest_dir"
      done
      [[ -x "$dest_dir/WebKitNetworkProcess" ]] && return 0
    fi
  fi

  local deb_url
  case "$(uname -m)" in
    aarch64|arm64)
      deb_url="http://ports.ubuntu.com/pool/main/w/webkit2gtk/libwebkit2gtk-4.1-0_2.44.0-2_arm64.deb"
      ;;
    x86_64|amd64)
      deb_url="http://archive.ubuntu.com/ubuntu/pool/main/w/webkit2gtk/libwebkit2gtk-4.1-0_2.44.0-2_amd64.deb"
      ;;
    *)
      return 1
      ;;
  esac

  local workdir="$dest_dir/.webkit-helper-fetch"
  rm -rf "$workdir"
  mkdir -p "$workdir"
  if ! curl -fsSL -o "$workdir/pkg.deb" "$deb_url"; then
    rm -rf "$workdir"
    return 1
  fi
  dpkg-deb -x "$workdir/pkg.deb" "$workdir/extract"
  helper_path="$(find "$workdir/extract" -name 'WebKitNetworkProcess' -type f | head -n 1 || true)"
  if [[ -z "$helper_path" || ! -f "$helper_path" ]]; then
    rm -rf "$workdir"
    return 1
  fi
  helper_dir="${helper_path%/*}"
  for helper in WebKitNetworkProcess WebKitWebProcess WebKitGPUProcess; do
    [[ -f "$helper_dir/$helper" ]] || continue
    kylin_install_webkit_helper "$helper_dir/$helper" "$dest_dir"
  done
  rm -rf "$workdir"
  [[ -x "$dest_dir/WebKitNetworkProcess" ]]
}

kylin_copy_webkit_helpers() {
  local app_dir="$1"
  local multilib dest src helper found_helper

  multilib="$(kylin_multilib_dir)"
  dest="$(kylin_webkit_helper_dir "$app_dir")"
  mkdir -p "$dest"

  echo "=== 内置 WebKit 子进程（WebKitNetworkProcess 等）==="
  if [[ -f "$dest/WebKitNetworkProcess" ]]; then
    chmod +x "$dest/WebKitNetworkProcess" 2>/dev/null || true
    for helper in WebKitWebProcess WebKitGPUProcess; do
      [[ -f "$dest/$helper" ]] && chmod +x "$dest/$helper" 2>/dev/null || true
    done
    echo "  已存在: WebKitNetworkProcess ($dest/WebKitNetworkProcess)"
    for helper in WebKitWebProcess WebKitGPUProcess; do
      [[ -f "$dest/$helper" ]] && echo "  已存在: $helper"
    done
    return 0
  fi

  for src in \
    "$app_dir/usr/lib/$multilib/webkit2gtk-4.1" \
    "/usr/lib/$multilib/webkit2gtk-4.1" \
    "/usr/libexec/webkit2gtk-4.1" \
    "/usr/lib/webkit2gtk-4.1"; do
    [[ -d "$src" ]] || continue
    [[ "$(readlink -f "$src" 2>/dev/null || echo "$src")" == "$(readlink -f "$dest" 2>/dev/null || echo "$dest")" ]] && continue
    for helper in WebKitNetworkProcess WebKitWebProcess WebKitGPUProcess; do
      [[ -f "$src/$helper" ]] || continue
      kylin_install_webkit_helper "$src/$helper" "$dest"
    done
    [[ -x "$dest/WebKitNetworkProcess" ]] && return 0
  done

  if [[ ! -x "$dest/WebKitNetworkProcess" ]]; then
    found_helper="$(find "$app_dir" -name 'WebKitNetworkProcess' -type f 2>/dev/null | head -n 1 || true)"
    if [[ -n "$found_helper" && -f "$found_helper" ]]; then
      src="${found_helper%/*}"
      if ! kylin_same_path "$src" "$dest"; then
        for helper in WebKitNetworkProcess WebKitWebProcess WebKitGPUProcess; do
          [[ -f "$src/$helper" ]] || continue
          kylin_install_webkit_helper "$src/$helper" "$dest"
        done
      fi
    fi
  fi

  if [[ ! -x "$dest/WebKitNetworkProcess" ]]; then
    echo "  构建机未找到 WebKit 子进程，尝试下载 Ubuntu 22.04 libwebkit2gtk-4.1-0..."
    kylin_fetch_webkit_helpers_from_deb "$dest" || true
  fi

  if [[ ! -x "$dest/WebKitNetworkProcess" ]]; then
    echo "错误：未找到 WebKitNetworkProcess，WebKit 无法在麒麟上运行" >&2
    echo "  期望路径: $dest/WebKitNetworkProcess" >&2
    return 1
  fi
  return 0
}

kylin_patch_webkit_helpers() {
  local app_dir="$1"
  local interp_path="$2"
  local dest helper multilib

  command -v patchelf >/dev/null 2>&1 || return 0
  multilib="$(kylin_multilib_dir)"
  dest="$app_dir/usr/lib/$multilib/webkit2gtk-4.1"
  [[ -d "$dest" ]] || return 0

  local rpath='$ORIGIN/../../glibc-compat:$ORIGIN/../..'
  for helper in WebKitNetworkProcess WebKitWebProcess WebKitGPUProcess; do
    [[ -f "$dest/$helper" ]] || continue
    file "$dest/$helper" 2>/dev/null | grep -q 'ELF .* executable' || continue
    patchelf --set-interpreter "$interp_path" "$dest/$helper" 2>/dev/null || true
    patchelf --set-rpath "$rpath" "$dest/$helper" 2>/dev/null || true
  done
}

kylin_verify_webkit_helpers() {
  local app_dir="$1"
  local strict="${KYLIN_VERIFY_STRICT:-0}"
  local dest

  dest="$(kylin_webkit_helper_dir "$app_dir")"
  if [[ -x "$dest/WebKitNetworkProcess" ]]; then
    echo "WebKit 子进程已内置: $dest/WebKitNetworkProcess"
    return 0
  fi

  echo "错误：缺少 WebKit 子进程 $dest/WebKitNetworkProcess" >&2
  [[ "$strict" == "1" ]] && return 1
  return 0
}

kylin_copy_font_and_webkit_libs() {
  local app_dir="$1"
  local lib_name

  echo "=== 内置 WebKit 运行时库（FreeType / GBM 等，避免麒麟系统旧版库）==="

  if ! kylin_ensure_freetype_for_webkit "$app_dir"; then
    return 1
  fi
  if ! kylin_ensure_gbm_for_webkit "$app_dir"; then
    return 1
  fi
  kylin_ensure_gtk_glib_bundled "$app_dir"
  if ! kylin_copy_webkit_helpers "$app_dir"; then
    return 1
  fi

  while IFS= read -r lib_name; do
    [[ -n "$lib_name" ]] || continue
    [[ "$lib_name" == "libfreetype.so.6" || "$lib_name" == "libgbm.so.1" ]] && continue
    if [[ -f "$app_dir/usr/lib/$lib_name" ]]; then
      echo "  已存在: $lib_name"
    elif kylin_copy_named_lib_to_app "$lib_name" "$app_dir"; then
      echo "  已补全: $lib_name"
    else
      echo "  可选库未找到（AppImage 可能已打包）: $lib_name"
    fi
  done < <(kylin_explicit_app_libs)

  local icu_lib
  for icu_lib in /usr/lib/*/libicuuc.so.* /lib/*/libicuuc.so.*; do
    [[ -f "$icu_lib" ]] || continue
    kylin_copy_lib_force "$icu_lib" "$app_dir/usr/lib"
    kylin_copy_lib_force "${icu_lib%/*}/libicudata.so.${icu_lib##*.so.}" "$app_dir/usr/lib" 2>/dev/null || true
    kylin_copy_lib_force "${icu_lib%/*}/libicui18n.so.${icu_lib##*.so.}" "$app_dir/usr/lib" 2>/dev/null || true
    break
  done
}

kylin_patch_webkit_rpath() {
  local app_dir="$1"
  command -v patchelf >/dev/null 2>&1 || return 0

  local lib rpath='$ORIGIN'
  while IFS= read -r -d '' lib; do
    file "$lib" 2>/dev/null | grep -q 'ELF .* shared object' || continue
    patchelf --set-rpath "$rpath" "$lib" 2>/dev/null || true
  done < <(find "$app_dir/usr/lib" -maxdepth 1 -type f \( -name 'libwebkit*.so.*' -o -name 'libjavascriptcore*.so.*' -o -name 'libfreetype.so.*' -o -name 'libfontconfig.so.*' -o -name 'libharfbuzz*.so.*' -o -name 'libsoup-3.0.so.*' -o -name 'libgbm.so.*' -o -name 'libdrm.so.*' -o -name 'libgtk-3.so.*' -o -name 'libgdk-3.so.*' -o -name 'libglib-2.0.so.*' -o -name 'libgobject-2.0.so.*' -o -name 'libgio-2.0.so.*' \) -print0 2>/dev/null)
}

kylin_verify_gbm_for_webkit() {
  local app_dir="$1"
  local strict="${KYLIN_VERIFY_STRICT:-0}"
  local gbm="$app_dir/usr/lib/libgbm.so.1"

  if [[ ! -f "$gbm" ]]; then
    echo "错误：未内置 libgbm.so.1，WebKit 将回退到麒麟系统旧版 GBM" >&2
    [[ "$strict" == "1" ]] && return 1
    return 0
  fi

  if kylin_gbm_has_webkit_symbol "$gbm"; then
    echo "libgbm 已包含 gbm_bo_create_with_modifiers2（WebKit 所需）。"
    return 0
  fi

  echo "错误：内置 libgbm.so.1 缺少 gbm_bo_create_with_modifiers2" >&2
  [[ "$strict" == "1" ]] && return 1
  return 0
}

kylin_verify_freetype_for_webkit() {
  local app_dir="$1"
  local strict="${KYLIN_VERIFY_STRICT:-0}"
  local freetype="$app_dir/usr/lib/libfreetype.so.6"

  if [[ ! -f "$freetype" ]]; then
    echo "错误：未内置 libfreetype.so.6，WebKit 将回退到麒麟系统旧版 FreeType" >&2
    [[ "$strict" == "1" ]] && return 1
    return 0
  fi

  if kylin_freetype_has_webkit_symbol "$freetype"; then
    echo "libfreetype 已包含 FT_Get_Color_Glyph_Paint（WebKit 所需）。"
    return 0
  fi

  echo "错误：内置 libfreetype.so.6 缺少 FT_Get_Color_Glyph_Paint" >&2
  [[ "$strict" == "1" ]] && return 1
  return 0
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
    local force="${3:-0}"
    if [[ ! -f "$src" ]]; then
      return 1
    fi
    mkdir -p "$dest_dir"
    if [[ "$force" == "1" || "$dest_dir" == "$app_dir/usr/lib" ]]; then
      cp -Lf "$src" "$dest_dir/"
    else
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
          elif [[ "$lib_basename" == libfreetype.so.* || "$lib_basename" == libfontconfig.so.* || "$lib_basename" == libharfbuzz.so.* || "$lib_basename" == libharfbuzz-icu.so.* || "$lib_basename" == libharfbuzz-subset.so.* || "$lib_basename" == libgbm.so.* || "$lib_basename" == libdrm.so.* || "$lib_basename" == libgtk-3.so.* || "$lib_basename" == libgdk-3.so.* || "$lib_basename" == libglib-2.0.so.* || "$lib_basename" == libgobject-2.0.so.* || "$lib_basename" == libgio-2.0.so.* ]]; then
            :
            # 不通过 ldd 回拷旧版字体/GBM 库，由 ensure 步骤统一处理
          elif [[ -f "$lib_path" && ! -f "$app_dir/usr/lib/$lib_basename" ]]; then
            copy_lib "$lib_path" "$app_dir/usr/lib" 1
            missing=1
          fi
        fi
      done < <("$loader" --library-path "$libpath" ldd "$target" 2>/dev/null || true)
    done
    kylin_ensure_loader_executable "$compat_dir" "$ld_linux"
    [[ "$missing" -eq 1 ]] || break
  done

  kylin_copy_font_and_webkit_libs "$app_dir" || return 1
  kylin_patch_webkit_rpath "$app_dir"
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

  kylin_verify_freetype_for_webkit "$app_dir" || return 1
  kylin_verify_gbm_for_webkit "$app_dir" || return 1
  kylin_verify_webkit_helpers "$app_dir" || return 1

  return 0
}
