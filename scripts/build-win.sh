#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

expand_path() {
  local path="$1"
  [[ "$path" == "~"* ]] && path="${path/#\~/$HOME}"
  printf '%s' "$path"
}

if [[ -n "${LLVM_HOME:-}" ]]; then
  LLVM_HOME="$(expand_path "$LLVM_HOME")"
  export LLVM_HOME
fi

# 优先使用项目内预编译 LLVM，其次 LLVM_HOME / 常见下载目录 / Homebrew
for llvm_bin in \
  "$ROOT_DIR/.tools/llvm/bin" \
  "${LLVM_HOME:+$LLVM_HOME/bin}" \
  "$HOME/Downloads/LLVM-19.1.7-macOS-X64/bin" \
  "$HOME/Downloads/LLVM-"*"-macOS-X64/bin" \
  /opt/homebrew/opt/llvm/bin \
  /usr/local/opt/llvm/bin; do
  if [[ -n "$llvm_bin" && -x "$llvm_bin/llvm-rc" ]]; then
    export PATH="$llvm_bin:$PATH"
    break
  fi
done

if ! command -v llvm-rc >/dev/null 2>&1; then
  cat <<'EOF'
错误：未找到 llvm-rc（Windows 资源文件编译器）。

推荐方式（无需 brew，避免 SourceForge 下载失败）：

  bash scripts/install-llvm-rc.sh
  npm run tauri:build:win

该脚本会从 GitHub 下载预编译 LLVM（约 1.5GB），解压后即可使用 llvm-rc。

若已手动安装 LLVM，可设置：

  export LLVM_HOME=/path/to/llvm
  npm run tauri:build:win
EOF
  exit 1
fi

# NSIS：makensis 编译器与 Stubs/Plugins 资源可能在不同目录
MAKENSIS_BIN=""
for makensis_dir in \
  "$HOME/Downloads/nsis-3.12-src" \
  "$ROOT_DIR/.tools/nsis-3.12-src" \
  /opt/homebrew/bin \
  /usr/local/bin; do
  makensis_dir="$(expand_path "$makensis_dir")"
  if [[ -x "$makensis_dir/makensis" ]]; then
    MAKENSIS_BIN="$makensis_dir/makensis"
    export PATH="$makensis_dir:$PATH"
    break
  fi
  if [[ -x "$makensis_dir/bin/makensis" ]]; then
    MAKENSIS_BIN="$makensis_dir/bin/makensis"
    export PATH="$makensis_dir/bin:$PATH"
    break
  fi
done

if [[ -z "$MAKENSIS_BIN" ]]; then
  cat <<'EOF'
错误：未找到 macOS 版 makensis。

你下载的 nsis-3.12.zip 里只有 Windows 版 makensis.exe，不能在 Mac 上运行。
请使用 nsis-3.12-src 源码编译（无需 brew / mingw-w64）：

  pip3 install scons
  export PATH="$HOME/Library/Python/3.9/bin:$PATH"
  cd ~/Downloads/nsis-3.12-src
  scons SKIPSTUBS=all SKIPPLUGINS=all SKIPUTILS=all SKIPMISC=all \
    NSIS_CONFIG_CONST_DATA_PATH=no PREFIX="$PWD" install-compiler

资源目录使用 nsis-3.12.zip 解压后的 ~/Downloads/nsis-3.12（含 Stubs/Plugins）。

如果暂时只需要 exe，可执行：npm run tauri:build:win:nobundle
EOF
  exit 1
fi

# Stubs/Plugins 来自 nsis-3.12.zip（不是 src 包）
if [[ -z "${NSISDIR:-}" ]]; then
  for nsis_res in \
    "$HOME/Downloads/nsis-3.12" \
    "$HOME/Downloads/nsis-3.08" \
    "$HOME/Downloads/nsis-3.12-src"; do
    nsis_res="$(expand_path "$nsis_res")"
    if [[ -d "$nsis_res/Stubs" && -d "$nsis_res/Plugins" ]]; then
      export NSISDIR="$nsis_res"
      break
    fi
  done
fi

if [[ -z "${NSISDIR:-}" ]]; then
  cat <<'EOF'
错误：未找到 NSIS 资源目录（需包含 Stubs 和 Plugins）。

请解压你下载的 nsis-3.12.zip，确保存在：
  ~/Downloads/nsis-3.12/Stubs
  ~/Downloads/nsis-3.12/Plugins
EOF
  exit 1
fi

if ! makensis -VERSION >/dev/null 2>&1; then
  cat <<EOF
错误：makensis 无法运行，NSISDIR 可能配置不正确。

当前 makensis: $MAKENSIS_BIN
当前 NSISDIR:  $NSISDIR

请确认 nsis-3.12.zip 已解压到 ~/Downloads/nsis-3.12
EOF
  exit 1
fi

# Tauri 在 macOS 上调用 PATH 中的 makensis（不是 makensis.exe），且会 env_remove NSISDIR。
# 必须用包装脚本在子进程内 export NSISDIR，否则找不到 Include/MUI2.nsh。
NSIS_BIN_DIR="$ROOT_DIR/.tools/nsis-bin"
mkdir -p "$NSIS_BIN_DIR"
for nsis_wrapper in makensis makensis.exe; do
  cat > "$NSIS_BIN_DIR/$nsis_wrapper" <<EOF
#!/usr/bin/env bash
export NSISDIR="$NSISDIR"
exec "$MAKENSIS_BIN" "\$@"
EOF
  chmod +x "$NSIS_BIN_DIR/$nsis_wrapper"
done
export PATH="$NSIS_BIN_DIR:$PATH"
export NSISDIR

# makensis 编译时 PREFIX=src 目录；把 zip 里的 Stubs/Plugins/Include 链到 src 目录作兜底
NSIS_SRC_DIR="$(dirname "$MAKENSIS_BIN")"
for nsis_sub in Stubs Plugins Include; do
  if [[ ! -e "$NSIS_SRC_DIR/$nsis_sub" && -e "$NSISDIR/$nsis_sub" ]]; then
    ln -sfn "$NSISDIR/$nsis_sub" "$NSIS_SRC_DIR/$nsis_sub"
  fi
done
if [[ ! -d "$HOME/Downloads/Stubs" && -d "$NSISDIR/Stubs" ]]; then
  ln -sfn "$NSISDIR/Stubs" "$HOME/Downloads/Stubs"
  ln -sfn "$NSISDIR/Plugins" "$HOME/Downloads/Plugins"
fi

# macOS 只能交叉编译 NSIS 安装包，不能生成 MSI（MSI 需在 Windows 上打包）
npm run tauri -- build --runner cargo-xwin --target x86_64-pc-windows-msvc --bundles nsis "$@"
