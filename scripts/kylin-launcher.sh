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
echo "=== 主程序依赖 ==="
LD_LIBRARY_PATH="$LIBPATH" /usr/bin/ldd "\$APP_ROOT/usr/bin/\$MAIN_BIN" 2>/dev/null || true
echo
echo "=== WebKit / FreeType ==="
if [ -f "\$APP_ROOT/usr/lib/libwebkit2gtk-4.1.so.0" ]; then
  LD_LIBRARY_PATH="$LIBPATH" /usr/bin/ldd "\$APP_ROOT/usr/lib/libwebkit2gtk-4.1.so.0" 2>/dev/null | grep -E 'freetype|fontconfig|harfbuzz|not found' || true
else
  echo "未找到 libwebkit2gtk-4.1.so.0"
fi
ls -la "\$APP_ROOT/usr/lib/libfreetype.so.6" 2>/dev/null || echo "警告：未 bundled libfreetype.so.6"
if [ -f "\$APP_ROOT/usr/lib/libfreetype.so.6" ]; then
  if nm -D "\$APP_ROOT/usr/lib/libfreetype.so.6" 2>/dev/null | grep -q FT_Get_Color_Glyph_Paint; then
    echo "libfreetype 包含 FT_Get_Color_Glyph_Paint"
  else
    echo "警告：libfreetype 缺少 FT_Get_Color_Glyph_Paint（WebKit 将无法启动）"
  fi
fi
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

kylin_freetype_has_webkit_symbol() {
  local freetype="$1"
  [[ -f "$freetype" ]] || return 1
  # 仅检查动态符号表（WebKit 运行时通过动态链接解析）
  if objdump -T "$freetype" 2>/dev/null | grep -Fq 'FT_Get_Color_Glyph_Paint'; then
    return 0
  fi
  if nm -D --defined-only "$freetype" 2>/dev/null | grep -Fq 'FT_Get_Color_Glyph_Paint'; then
    return 0
  fi
  return 1
}

kylin_freetype_from_webkit_ldd() {
  local app_dir="$1"
  local webkit="$app_dir/usr/lib/libwebkit2gtk-4.1.so.0"
  local libpath line lib_path

  [[ -f "$webkit" ]] || return 1

  libpath="$app_dir/usr/lib"
  line="$(LD_LIBRARY_PATH="$libpath" ldd "$webkit" 2>/dev/null | grep 'libfreetype\.so' | head -n 1 || true)"
  [[ -n "$line" && "$line" != *" not found"* ]] || return 1

  lib_path="${line#* => }"
  lib_path="${lib_path%%[[:space:]]*}"
  [[ -f "$lib_path" ]] || return 1
  printf '%s' "$lib_path"
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
  local deb_url workdir lib_path

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

  workdir="$(mktemp -d)"
  if ! curl -fsSL -o "$workdir/libfreetype6.deb" "$deb_url"; then
    rm -rf "$workdir"
    return 1
  fi
  dpkg-deb -x "$workdir/libfreetype6.deb" "$workdir/extract"
  lib_path="$(find "$workdir/extract" -name 'libfreetype.so.6' | head -n 1 || true)"
  if [[ -z "$lib_path" || ! -f "$lib_path" ]]; then
    rm -rf "$workdir"
    return 1
  fi
  kylin_copy_lib_force "$lib_path" "$dest_dir"
  rm -rf "$workdir"
  return 0
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

kylin_copy_font_and_webkit_libs() {
  local app_dir="$1"
  local lib_name

  echo "=== 内置 WebKit / FreeType 字体栈（避免麒麟系统旧版 libfreetype）==="

  if ! kylin_ensure_freetype_for_webkit "$app_dir"; then
    return 1
  fi

  while IFS= read -r lib_name; do
    [[ -n "$lib_name" ]] || continue
    [[ "$lib_name" == "libfreetype.so.6" ]] && continue
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
  done < <(find "$app_dir/usr/lib" -maxdepth 1 -type f \( -name 'libwebkit*.so.*' -o -name 'libjavascriptcore*.so.*' -o -name 'libfreetype.so.*' -o -name 'libfontconfig.so.*' -o -name 'libharfbuzz*.so.*' -o -name 'libsoup-3.0.so.*' \) -print0 2>/dev/null)
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
          elif [[ "$lib_basename" == libfreetype.so.* || "$lib_basename" == libfontconfig.so.* || "$lib_basename" == libharfbuzz.so.* || "$lib_basename" == libharfbuzz-icu.so.* || "$lib_basename" == libharfbuzz-subset.so.* ]]; then
            :
            # 不通过 ldd 回拷旧版 freetype/font 库，由 kylin_ensure_freetype_for_webkit 统一处理
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

  return 0
}
