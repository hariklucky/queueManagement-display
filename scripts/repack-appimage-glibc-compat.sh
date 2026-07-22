#!/usr/bin/env bash
# 将 AppImage 自带的 glibc 运行时打包进产物，以便在 glibc 2.31（银河麒麟 V10）等较旧系统上运行。
# Tauri v2 必须在 Ubuntu 22.04+ 构建，产物默认链接 glibc 2.35；通过 bundled loader 绕过宿主机 glibc 版本限制。
set -euo pipefail

APPIMAGE="${1:?用法: $0 <input.AppImage> [output.AppImage]}"
OUTPUT="${2:-$APPIMAGE}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kylin-launcher.sh
source "$SCRIPT_DIR/kylin-launcher.sh"

if [[ ! -f "$APPIMAGE" ]]; then
  echo "错误：找不到 AppImage: $APPIMAGE" >&2
  exit 1
fi

APPIMAGE="$(readlink -f "$APPIMAGE")"
if [[ "$OUTPUT" != /* ]]; then
  OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
fi

ARCH="$(uname -m)"
LD_LINUX="$(kylin_ld_linux "$ARCH")"
GLIB_DIR="$(kylin_glib_dir "$ARCH")"
case "$ARCH" in
  aarch64|arm64) APPIMAGE_ARCH="aarch64" ;;
  x86_64|amd64) APPIMAGE_ARCH="x86_64" ;;
  *)
    echo "错误：不支持的架构 \"${ARCH}\"" >&2
    exit 1
    ;;
esac

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "=== 解压 AppImage ==="
echo "输入: $APPIMAGE"
cd "$WORKDIR"
chmod +x "$APPIMAGE"
APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGE" --appimage-extract
ROOT="$WORKDIR/squashfs-root"

if [[ ! -f "$ROOT/AppRun" ]]; then
  echo "错误：AppDir 中缺少 AppRun" >&2
  exit 1
fi

COMPAT_DIR="$ROOT/usr/lib/glibc-compat"
echo "=== 收集 glibc / libstdc++ 运行时依赖 ==="
kylin_copy_runtime_libs "$COMPAT_DIR" "$GLIB_DIR" "$LD_LINUX" "$ROOT"

if [[ ! -f "$COMPAT_DIR/$LD_LINUX" || ! -f "$COMPAT_DIR/libc.so.6" ]]; then
  echo "错误：未能收集完整的 glibc 运行时（缺少 $LD_LINUX 或 libc.so.6）" >&2
  exit 1
fi

MAIN_BIN="$(kylin_detect_main_bin "$ROOT")"
echo "=== 重写 AppRun（主程序: usr/bin/$MAIN_BIN）==="
cp "$ROOT/AppRun" "$ROOT/AppRun.orig"
kylin_write_launcher "$ROOT/AppRun" "" "$MAIN_BIN" "$LD_LINUX" 1

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

OUTPUT_TMP="$WORKDIR/$(basename "$OUTPUT")"

echo "=== 重新打包 AppImage ==="
ARCH="$APPIMAGE_ARCH" APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" "$ROOT" "$OUTPUT_TMP"
chmod +x "$OUTPUT_TMP"
mv "$OUTPUT_TMP" "$OUTPUT"

echo "=== 完成：已生成兼容旧版 glibc 的 AppImage ==="
echo "  $OUTPUT"
echo "  bundled glibc: $(ls -1 "$COMPAT_DIR" | wc -l | tr -d ' ') 个库文件"
