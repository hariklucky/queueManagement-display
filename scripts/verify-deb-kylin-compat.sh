#!/usr/bin/env bash
# 检查 deb 是否包含 glibc-compat 运行时（适配 glibc 2.31 麒麟终端）
set -euo pipefail

DEB="${1:?用法: $0 <package.deb>}"
if [[ ! -f "$DEB" ]]; then
  echo "错误：找不到 deb: $DEB" >&2
  exit 1
fi

DEB="$(readlink -f "$DEB")"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "检查 deb: $DEB"

deb_members="$(ar t "$DEB")"
echo "deb 成员: $deb_members"
if grep -qE '\.(zst|zstd)$' <<< "$deb_members"; then
  echo "错误：deb 使用了 zstd 压缩（control/data.tar.zst），银河麒麟旧版 dpkg 无法安装。" >&2
  echo "请使用 dpkg-deb -Zgzip 重新打包。" >&2
  exit 1
fi
if ! grep -qE 'control\.tar\.(gz|xz)$' <<< "$deb_members"; then
  echo "错误：未检测到 gzip/xz 格式的 control.tar" >&2
  exit 1
fi

dpkg-deb -x "$DEB" "$WORKDIR/extract"

if [[ -f "$WORKDIR/extract/opt/qms/usr/lib/glibc-compat/libc.so.6" ]]; then
  echo "已检测到 bundled glibc-compat，可在 glibc 2.31 系统上运行。"
else
  echo "错误：deb 中缺少 opt/qms/usr/lib/glibc-compat/libc.so.6" >&2
  exit 1
fi

if [[ -x "$WORKDIR/extract/opt/qms/AppRun" ]] && find "$WORKDIR/extract/usr/bin" -maxdepth 1 -type f -executable | grep -q .; then
  echo "启动器结构正常（/opt/qms/AppRun + /usr/bin 入口）。"
else
  echo "错误：deb 启动器结构不完整" >&2
  exit 1
fi

if dpkg-deb -I "$DEB" | grep -q 'libwebkit2gtk-4.1'; then
  echo "警告：deb 仍依赖 libwebkit2gtk-4.1，麒麟终端可能无法安装。" >&2
  exit 1
fi

echo "deb 依赖摘要："
dpkg-deb -f "$DEB" Depends

if dpkg-deb -f "$DEB" Depends | grep -qE 'libwebkit2gtk-4\.(0|1)'; then
  echo "警告：deb 声明了 WebKit 依赖，麒麟终端可能因包名不匹配安装失败。" >&2
  exit 1
fi

echo "验证通过。"
