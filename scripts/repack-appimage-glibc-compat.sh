#!/usr/bin/env bash
# 将 AppImage 自带的 glibc 运行时打包进产物，以便在 glibc 2.31（银河麒麟 V10）等较旧系统上运行。
# Tauri v2 必须在 Ubuntu 22.04+ 构建，产物默认链接 glibc 2.35；通过 bundled loader 绕过宿主机 glibc 版本限制。
set -euo pipefail

APPIMAGE="${1:?用法: $0 <input.AppImage> [output.AppImage]}"
OUTPUT="${2:-$APPIMAGE}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64)
    GLIB_DIR="/lib/aarch64-linux-gnu"
    LD_LINUX="ld-linux-aarch64.so.1"
    APPIMAGE_ARCH="aarch64"
    ;;
  x86_64|amd64)
    GLIB_DIR="/lib/x86_64-linux-gnu"
    LD_LINUX="ld-linux-x86-64.so.2"
    APPIMAGE_ARCH="x86_64"
    ;;
  *)
    echo "错误：不支持的架构 \"${ARCH}\"" >&2
    exit 1
    ;;
esac

if [[ ! -f "$APPIMAGE" ]]; then
  echo "错误：找不到 AppImage: $APPIMAGE" >&2
  exit 1
fi

echo "=== 解压 AppImage ==="
cd "$WORKDIR"
chmod +x "$APPIMAGE"
APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGE" --appimage-extract
ROOT="$WORKDIR/squashfs-root"

if [[ ! -f "$ROOT/AppRun" ]]; then
  echo "错误：AppDir 中缺少 AppRun" >&2
  exit 1
fi

COMPAT_DIR="$ROOT/usr/lib/glibc-compat"
mkdir -p "$COMPAT_DIR"

copy_lib() {
  local src="$1"
  if [[ -f "$src" ]]; then
    cp -Ln "$src" "$COMPAT_DIR/"
  fi
}

collect_glibc_deps() {
  local binary="$1"
  [[ -f "$binary" ]] || return 0
  if ! ldd "$binary" >/dev/null 2>&1; then
    return 0
  fi
  while IFS= read -r lib; do
    [[ -n "$lib" && -f "$lib" ]] && copy_lib "$lib"
  done < <(ldd "$binary" 2>/dev/null | awk -v dir="$GLIB_DIR" '$3 ~ dir { print $3 }')
}

echo "=== 收集 glibc 运行时依赖 ==="
for lib in \
  "$LD_LINUX" \
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
  libgcc_s.so.1; do
  copy_lib "$GLIB_DIR/$lib"
done

while IFS= read -r -d '' target; do
  collect_glibc_deps "$target"
done < <(find "$ROOT/usr/bin" "$ROOT/usr/lib" -type f \( -perm -111 -o -name '*.so*' \) -print0 2>/dev/null)

if [[ ! -f "$COMPAT_DIR/$LD_LINUX" || ! -f "$COMPAT_DIR/libc.so.6" ]]; then
  echo "错误：未能收集完整的 glibc 运行时（缺少 $LD_LINUX 或 libc.so.6）" >&2
  exit 1
fi

MAIN_BIN=""
if [[ -f "$ROOT/AppRun" ]]; then
  MAIN_BIN="$(grep -E 'exec .*usr/bin/' "$ROOT/AppRun" | sed -n 's/.*usr\/bin\/\([^"'"'"'[:space:]]*\).*/\1/p' | head -n 1 || true)"
fi
if [[ -z "$MAIN_BIN" ]]; then
  MAIN_BIN="$(find "$ROOT/usr/bin" -maxdepth 1 -type f -executable -printf '%f\n' 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "$MAIN_BIN" || ! -f "$ROOT/usr/bin/$MAIN_BIN" ]]; then
  echo "错误：无法确定 AppImage 主程序路径" >&2
  exit 1
fi

echo "=== 重写 AppRun（主程序: usr/bin/$MAIN_BIN）==="
cp "$ROOT/AppRun" "$ROOT/AppRun.orig"
cat > "$ROOT/AppRun" <<EOF
#!/bin/sh
HERE="\$(dirname "\$(readlink -f "\$0")")"
LIBPATH="\$HERE/usr/lib/glibc-compat:\$HERE/usr/lib"
export PATH="\$HERE/usr/bin:\${PATH:-}"
export XDG_DATA_DIRS="\$HERE/usr/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GDK_BACKEND=x11
exec "\$HERE/usr/lib/glibc-compat/$LD_LINUX" --library-path "\$LIBPATH" "\$HERE/usr/bin/$MAIN_BIN" "\$@"
EOF
chmod +x "$ROOT/AppRun"

APPIMAGETOOL="$WORKDIR/appimagetool"
if [[ -z "${APPIMAGETOOL_BIN:-}" ]]; then
  echo "=== 下载 appimagetool ==="
  curl -fsSL -o "$APPIMAGETOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${APPIMAGE_ARCH}.AppImage"
  chmod +x "$APPIMAGETOOL"
else
  cp "$APPIMAGETOOL_BIN" "$APPIMAGETOOL"
  chmod +x "$APPIMAGETOOL"
fi

OUTPUT_ABS="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
OUTPUT_TMP="$WORKDIR/$(basename "$OUTPUT")"

echo "=== 重新打包 AppImage ==="
ARCH="$APPIMAGE_ARCH" APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" "$ROOT" "$OUTPUT_TMP"
chmod +x "$OUTPUT_TMP"
mv "$OUTPUT_TMP" "$OUTPUT_ABS"

echo "=== 完成：已生成兼容旧版 glibc 的 AppImage ==="
echo "  $OUTPUT_ABS"
echo "  bundled glibc: $(ls -1 "$COMPAT_DIR" | wc -l | tr -d ' ') 个库文件"
