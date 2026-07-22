# 报到取号

面向营业厅现场终端的桌面取号应用，支持预约取号与现场取号，集成身份证读卡与小票打印能力。前端基于 Vue 3 + Vite，桌面端基于 Tauri 2 打包为原生应用。

## 技术栈

| 类别 | 技术 |
|------|------|
| 前端框架 | Vue 3（`<script setup>`） |
| 构建工具 | Vite 8 |
| 样式 | Tailwind CSS 4 |
| 桌面端 | Tauri 2 |
| HTTP 请求 | 开发模式走 Vite 代理；生产包走 Tauri Rust 原生请求 |
| 虚拟键盘 | simple-keyboard + 拼音候选 |
| 语言 | JavaScript / TypeScript |

## 功能说明

- **预约取号**：刷身份证或输入手机号查询预约并取号
- **现场取号**：填写信息、选择业务类型后获取排队号
- **身份证读卡**：调用后端读卡接口，或宿主注入的 `window.IdCardReader`
- **应用内虚拟键盘**：触屏终端支持中文拼音、英文、数字输入（可配置强制使用，跳过系统键盘）
- **全屏展示**：默认 1280×1024 全屏窗口，适合自助终端使用

## 环境要求

- **Node.js**：`24.15.0`（项目根目录有 `.nvmrc`，可使用 `nvm use`）
- **npm**：随 Node.js 安装即可
- **Rust**：Tauri 桌面开发与打包需要（[安装说明](https://www.rust-lang.org/tools/install)）
- **系统依赖**：按 [Tauri 官方文档](https://v2.tauri.app/start/prerequisites/) 安装对应平台依赖

### 外部服务

运行完整业务流程时，需确保后端 API 可访问：

| 服务 | 默认地址（开发） | 说明 |
|------|------------------|------|
| 排队后端 API | `http://localhost:18084` | 预约查询、现场取号、读卡等接口 |
| 开发代理前缀 | `/api` | 仅 `npm run dev` / `tauri:dev` 时由 Vite 转发 |

## 快速开始

### 1. 安装依赖

```bash
npm install
```

### 2. 配置环境变量

项目按 Vite 模式加载环境文件：

| 文件 | 用途 |
|------|------|
| `.env.development` | 本地开发 |
| `.env.test` | 测试环境构建 |
| `.env.production` | 生产环境构建 |

主要变量说明：

```bash
# 接口基础路径
VITE_API_BASE_URL=/api

# 开发时代理目标（仅 dev 模式生效）
VITE_API_TARGET=http://localhost:18084

# 是否去掉代理路径中的 /api 前缀
VITE_API_PROXY_REWRITE=false

# 终端设备编号
VITE_GATEWAY_ID=Eq032511250004

# 触屏终端强制使用应用内虚拟键盘（true 时不调用 Windows TabTip）
VITE_FORCE_ON_SCREEN_KEYBOARD=true

# 开启前端调试日志（生产包可配合 F12 DevTools）
VITE_APP_DEBUG=true
```

开发模式下，`/api` 请求会通过 Vite 代理转发到 `VITE_API_TARGET`，无需额外处理跨域。

### 3. 生产部署配置（config.json）

打包后的桌面应用**优先读取安装目录下的 `config.json`**，可覆盖 `.env.production` 中的默认值，无需重新打包。

首次启动时，若安装目录不存在 `config.json`，会自动从 `config.example.json` 生成一份。

模板见项目根目录 `config.example.json`：

```json
{
  "apiBaseUrl": "http://192.168.0.101:18084/api",
  "gatewayId": "",
  "forceOnScreenKeyboard": true
}
```

| 字段 | 说明 |
|------|------|
| `apiBaseUrl` | 后端 API 根地址，需为完整 `http://` 或 `https://` 地址 |
| `gatewayId` | 终端设备编号 |
| `forceOnScreenKeyboard` | 是否强制使用应用内虚拟键盘 |

## 启动命令

### 仅启动前端（浏览器调试）

```bash
npm run dev
```

启动后访问：<http://localhost:5173>

适用于快速调试页面与接口联调，不包含 Tauri 桌面能力。

### 启动桌面应用（推荐）

```bash
npm run tauri:dev
```

等价于 `tauri dev`，会自动执行 `npm run dev` 并打开 Tauri 桌面窗口，支持热更新。

## 打包命令

### 仅打包前端静态资源

```bash
# 生产环境
npm run build
# 或
npm run build:prod

# 开发环境配置打包
npm run build:dev

# 测试环境配置打包
npm run build:test
```

产物输出目录：`dist/`

### 打包桌面应用（本机平台）

```bash
npm run tauri:build
```

打包前会自动执行 `npm run build:prod`，最终安装包输出在：

```
src-tauri/target/release/bundle/
```

Windows 平台默认生成 **MSI** 安装包（见 `src-tauri/tauri.conf.json` 中 `bundle.targets` 配置）。

### 在 macOS 上交叉编译 Windows 安装包

项目已内置 Windows 构建脚本：

```bash
npm run tauri:build:win
```

该命令会通过 `cargo-xwin` 交叉编译 `x86_64-pc-windows-msvc` 目标，并生成 NSIS 安装包。

如果只想先验证跨编译是否成功、不做安装包封装：

```bash
npm run tauri:build:win:nobundle
```

#### 第一次使用前请先安装以下工具

1. 安装 Rust Windows 目标：

```bash
rustup target add x86_64-pc-windows-msvc
```

2. 安装 `cargo-xwin`：

```bash
cargo install cargo-xwin
```

3. 安装 `llvm-rc`（推荐，避免 brew 下载失败）：

```bash
npm run install:llvm-rc
```

4. 安装 NSIS（macOS 上需使用源码编译版 `makensis`，详见 `scripts/build-win.sh` 提示）

> 如果你的环境里 `cargo-xwin` 首次执行仍提示缺少 Windows SDK/CRT，它会自动拉取所需组件；首次构建时间会较长。

#### 产物目录

```text
src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/
```

#### 常见问题

- **提示找不到 `llvm-rc`**
  - 执行 `npm run install:llvm-rc`
- **提示找不到 `cargo-xwin`**
  - 执行 `cargo install cargo-xwin`
  - 确认 `$HOME/.cargo/bin` 已加入 `PATH`
- **提示缺少 Windows target**
  - 执行 `rustup target add x86_64-pc-windows-msvc`
- **首次构建特别慢**
  - `cargo-xwin` 首次会下载 Windows 工具链缓存，属正常现象

### 打包麒麟（银河麒麟 / Linux）安装包

麒麟桌面版（Debian 系）使用 **`.deb`** 安装包；服务器版（RPM 系）使用 **`.rpm`**。

#### 在麒麟 / Linux 本机打包

```bash
# 安装系统依赖（Ubuntu / 麒麟桌面版 apt 示例）
sudo apt update
sudo apt install -y build-essential curl wget file libssl-dev \
  libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev \
  libwebkit2gtk-4.1-dev dpkg-dev

npm install
npm run tauri:build:kylin
```

产物目录：

```text
src-tauri/target/release/bundle/deb/
```

安装示例：

```bash
sudo dpkg -i src-tauri/target/release/bundle/deb/*.deb
sudo apt install -f -y
```

#### 在 macOS / Windows 上通过 Docker 打包 deb

Tauri 无法从 macOS 直接交叉编译 Linux 安装包，项目已通过 Docker 提供麒麟 deb 打包方案。

**环境准备：**

1. 安装并启动 [Docker Desktop](https://docs.docker.com/desktop/setup/install/mac-install/)
2. macOS Ventura 13 请使用 **Docker Desktop 4.44.x Intel 版**（4.49+ 要求 macOS 14）
3. 若拉取 Docker Hub 镜像超时，配置镜像加速或使用国内基础镜像

**打包命令：**

```bash
# 自动检测平台：非 Linux 时走 Docker
npm run tauri:build:kylin

# 国内网络推荐（使用 DaoCloud 基础镜像）
npm run tauri:build:kylin:cn

# 显式使用 Docker
npm run tauri:build:kylin:docker

# 仅编译可执行文件，不封装安装包
npm run tauri:build:kylin:nobundle

# 强制重建 Docker 镜像
bash scripts/build-kylin-docker.sh --rebuild-image
```

**Docker 镜像加速（推荐一次配置）：**

Docker Desktop → Settings → Docker Engine，添加：

```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run"
  ]
}
```

#### 麒麟打包命令一览

| 命令 | 说明 |
|------|------|
| `npm run tauri:build:kylin` | 默认打 deb；macOS 自动走 Docker |
| `npm run tauri:build:kylin:deb` | 仅生成 deb |
| `npm run tauri:build:kylin:rpm` | 仅生成 rpm（需 RPM 系 Linux 本机） |
| `npm run tauri:build:kylin:all` | 同时生成 deb + rpm |
| `npm run tauri:build:kylin:cn` | 使用国内镜像源打 deb |
| `npm run tauri:build:kylin:docker` | 显式走 Docker 打 deb |
| `npm run tauri:build:kylin:nobundle` | 只编译，不封装安装包 |

## 预览命令

本地预览已构建的前端产物：

```bash
# 默认预览
npm run preview

# 以 production 模式预览
npm run preview:prod
```

## 项目结构

```
queueManagement-display/
├── src/
│   ├── api/              # 排队相关 API
│   ├── components/       # 虚拟键盘等组件
│   ├── utils/            # 请求封装、读卡、运行时配置、键盘逻辑
│   ├── views/
│   │   └── QueueTicket.vue   # 主页面（取号流程）
│   ├── App.vue
│   └── main.js
├── src-tauri/            # Tauri 桌面端（Rust）
│   ├── src/
│   ├── tauri.conf.json   # 窗口、打包等配置
│   └── Cargo.toml
├── docker/
│   └── Dockerfile.kylin  # 麒麟 deb 打包镜像
├── scripts/
│   ├── build-win.sh      # macOS 交叉编译 Windows
│   ├── build-kylin.sh    # 麒麟 / Linux 本机打包
│   └── build-kylin-docker.sh
├── config.example.json   # 部署配置模板（打包时一并分发）
├── .env.development
├── .env.test
├── .env.production
├── vite.config.js
└── package.json
```

## 常用脚本一览

| 命令 | 说明 |
|------|------|
| `npm run dev` | 启动 Vite 开发服务器 |
| `npm run build` | 生产模式构建前端 |
| `npm run build:dev` | 开发模式配置构建前端 |
| `npm run build:test` | 测试模式配置构建前端 |
| `npm run build:prod` | 生产模式构建前端（同 `build`） |
| `npm run preview` | 预览构建产物 |
| `npm run tauri:dev` | 启动 Tauri 桌面开发模式 |
| `npm run tauri:build` | 打包 Tauri 桌面应用（本机平台） |
| `npm run tauri:build:win` | macOS 交叉编译 Windows 安装包 |
| `npm run tauri:build:kylin` | 打包麒麟 deb（macOS 自动走 Docker） |
| `npm run tauri:build:kylin:cn` | 使用国内镜像打麒麟 deb |

## 注意事项

1. **端口占用**：开发服务器固定使用 `5173` 端口（`strictPort: true`），被占用时需先释放。
2. **生产 API 地址**：打包后不再走 Vite 代理。优先修改安装目录 `config.json` 中的 `apiBaseUrl`；也可在打包前修改 `.env.production` 中的 `VITE_API_BASE_URL`。
3. **读卡能力**：读卡请求走主 API 地址下的 `/queue-call/id-card/read`；若宿主注入了 `window.IdCardReader`，则优先使用本地桥接。
4. **虚拟键盘**：触屏终端建议保持 `forceOnScreenKeyboard: true`；Windows 未开启时会先尝试 TabTip，失败后再回退到应用内键盘。
5. **窗口配置**：应用名称、窗口尺寸、全屏等行为可在 `src-tauri/tauri.conf.json` 中调整。
6. **麒麟 Docker 打包**：首次构建需下载 Ubuntu 基础镜像并编译 Rust，Intel Mac 约 20～40 分钟，之后会快很多。
