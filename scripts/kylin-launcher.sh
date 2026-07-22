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

kylin_detect_main_bin() {
  local app_dir="$1"
  local main_bin=""

  if [[ -f "$app_dir/AppRun" ]]; then
    main_bin="$(grep -E 'exec .*usr/bin/' "$app_dir/AppRun" | sed -n 's/.*usr\/bin\/\([^"'"'"'[:space:]]*\).*/\1/p' | head -n 1 || true)"
  fi
  if [[ -z "$main_bin" ]]; then
    main_bin="$(find "$app_dir/usr/bin" -maxdepth 1 -type f -perm -111 -printf '%f\n' 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$main_bin" || ! -f "$app_dir/usr/bin/$main_bin" ]]; then
    echo "错误：无法确定主程序（$app_dir/usr/bin）" >&2
    return 1
  fi
  printf '%s' "$main_bin"
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
export XDG_DATA_DIRS="\$APP_ROOT/usr/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GDK_BACKEND=x11
export GTK_USE_PORTAL=0
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export GSETTINGS_BACKEND=memory
unset WAYLAND_DISPLAY
LOG_DIR="\${XDG_CACHE_HOME:-\$HOME/.cache}/qms"
mkdir -p "\$LOG_DIR" 2>/dev/null || true
exec "\$APP_ROOT/usr/lib/glibc-compat/\$LD_LINUX" \\
  --library-path "\$LIBPATH" \\
  "\$APP_ROOT/usr/bin/\$MAIN_BIN" "\$@" \\
  2>>"\$LOG_DIR/launch.log"
EOF
  else
    cat > "$output" <<EOF
#!/bin/sh
APP_ROOT="$app_root"
MAIN_BIN="$main_bin"
LD_LINUX="$ld_linux"
LIBPATH="\$APP_ROOT/usr/lib/glibc-compat:\$APP_ROOT/usr/lib"
export PATH="\$APP_ROOT/usr/bin:\${PATH:-/usr/bin:/bin}"
export XDG_DATA_DIRS="\$APP_ROOT/usr/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GDK_BACKEND=x11
export GTK_USE_PORTAL=0
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export GSETTINGS_BACKEND=memory
unset WAYLAND_DISPLAY
LOG_DIR="\${XDG_CACHE_HOME:-\$HOME/.cache}/qms"
mkdir -p "\$LOG_DIR" 2>/dev/null || true
exec "\$APP_ROOT/usr/lib/glibc-compat/\$LD_LINUX" \\
  --library-path "\$LIBPATH" \\
  "\$APP_ROOT/usr/bin/\$MAIN_BIN" "\$@" \\
  2>>"\$LOG_DIR/launch.log"
EOF
  fi
  chmod 755 "$output"
}

kylin_copy_runtime_libs() {
  local compat_dir="$1"
  local glib_dir="$2"
  local ld_linux="$3"
  local app_dir="${4:-}"

  mkdir -p "$compat_dir"

  copy_lib() {
    local src="$1"
    if [[ -f "$src" ]]; then
      cp -Lfn "$src" "$compat_dir/"
    fi
  }

  collect_from_binary() {
    local binary="$1"
    [[ -f "$binary" ]] || return 0
    if ! ldd "$binary" >/dev/null 2>&1; then
      return 0
    fi
    while IFS= read -r lib; do
      [[ -n "$lib" && -f "$lib" ]] && copy_lib "$lib"
    done < <(ldd "$binary" 2>/dev/null | awk -v dir="$glib_dir" '$3 ~ dir { print $3 }')
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
  done

  if [[ -n "$app_dir" ]]; then
    while IFS= read -r -d '' target; do
      collect_from_binary "$target"
    done < <(find "$app_dir/usr/bin" "$app_dir/usr/lib" -type f \( -perm -111 -o -name '*.so*' \) -print0 2>/dev/null)
  fi
}
