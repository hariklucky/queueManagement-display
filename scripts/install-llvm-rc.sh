#!/usr/bin/env bash
# 下载预编译 LLVM（含 llvm-rc），避免 brew install llvm 从源码编译及 SourceForge 依赖下载失败
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/.tools"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64)
    LLVM_VERSION="19.1.7"
    ARCHIVE_NAME="LLVM-${LLVM_VERSION}-macOS-X64.tar.xz"
    ;;
  arm64)
    LLVM_VERSION="19.1.7"
    ARCHIVE_NAME="LLVM-${LLVM_VERSION}-macOS-ARM64.tar.xz"
    ;;
  *)
    echo "不支持的 CPU 架构: $ARCH"
    exit 1
    ;;
esac

DOWNLOAD_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/${ARCHIVE_NAME}"
ARCHIVE_PATH="$TOOLS_DIR/$ARCHIVE_NAME"
EXTRACT_DIR="$TOOLS_DIR/llvm"

mkdir -p "$TOOLS_DIR"

if [[ -x "$EXTRACT_DIR/bin/llvm-rc" ]]; then
  echo "llvm-rc 已存在: $EXTRACT_DIR/bin/llvm-rc"
  exit 0
fi

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "正在下载 LLVM ${LLVM_VERSION}（约 1.5GB，仅需下载解压，无需编译）..."
  echo "来源: $DOWNLOAD_URL"
  curl -L --retry 5 --retry-delay 3 -C - -o "$ARCHIVE_PATH" "$DOWNLOAD_URL"
fi

echo "正在解压..."
tar -xJf "$ARCHIVE_PATH" -C "$TOOLS_DIR"

# 解压后目录名与压缩包一致，统一链接到 .tools/llvm
EXTRACTED="$(find "$TOOLS_DIR" -maxdepth 1 -type d -name "LLVM-${LLVM_VERSION}-macOS-*" | head -1)"
if [[ -z "$EXTRACTED" || ! -x "$EXTRACTED/bin/llvm-rc" ]]; then
  echo "解压失败或未找到 llvm-rc"
  exit 1
fi

rm -rf "$EXTRACT_DIR"
ln -sfn "$(basename "$EXTRACTED")" "$EXTRACT_DIR"

echo ""
echo "安装完成。llvm-rc 路径:"
echo "  $EXTRACT_DIR/bin/llvm-rc"
echo ""
echo "接下来执行:"
echo "  npm run tauri:build:win"
