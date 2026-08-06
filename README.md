# 报到取号

面向营业厅现场终端的桌面取号应用，支持预约取号与现场取号，集成身份证读卡与小票打印能力。前端基于 Vue 3 + Vite，桌面端基于 Electron 打包（自带 Chromium，适配银河麒麟 glibc 2.31，无需 WebKitGTK 4.1）。

## 技术栈

| 类别 | 技术 |
|------|------|
| 前端框架 | Vue 3（`<script setup>`） |
| 构建工具 | Vite 8 |
| 样式 | Tailwind CSS 4 |
| 桌面端 | Electron |
| HTTP 请求 | 开发模式走 Vite 代理；生产包走 Electron 主进程请求 |
| 虚拟键盘 | simple-keyboard + 拼音候选 |
| 语言 | JavaScript / TypeScript |

## 功能说明

- **预约取号**：刷身份证或输入手机号查询预约并取号
- **现场取号**：填写信息、选择业务类型后获取排队号
- **身份证读卡**：调用后端读卡接口，或宿主注入的 `window.IdCardReader`
- **应用内虚拟键盘**：触屏终端支持中文拼音、英文、数字输入（可配置强制使用，跳过系统键盘）
- **全屏展示**：默认 1280×1024 全屏窗口，适合自助终端使用

## 环境要求

- **Node.js**：建议 20+（可用 `nvm use` 配合 `.nvmrc`）
- **npm**：随 Node.js 安装即可
- **无需 Rust / WebKitGTK 开发包**

### 外部服务

| 服务 | 默认地址（开发） | 说明 |
|------|------------------|------|
| 排队后端 API | `http://localhost:18084` | 预约查询、现场取号、读卡等接口 |
| 开发代理前缀 | `/api` | 仅 `npm run dev` / `electron:dev` 时由 Vite 转发 |

## 快速开始

### 1. 安装依赖

```bash
npm install
```

### 2. 配置环境变量

| 文件 | 用途 |
|------|------|
| `.env.development` | 本地开发 |
| `.env.test` | 测试环境构建 |
| `.env.production` | 生产环境构建 |

主要变量：

```bash
VITE_API_BASE_URL=/api
VITE_API_TARGET=http://localhost:18084
VITE_API_PROXY_REWRITE=false
VITE_GATEWAY_ID=Eq032511250004
VITE_FORCE_ON_SCREEN_KEYBOARD=true
VITE_APP_DEBUG=true
```

### 3. 生产部署配置（config.json）

打包后的桌面应用**优先读取安装目录下的 `config.json`**。首次启动若不存在，会从 `config.example.json` 自动生成。

```json
{
  "apiBaseUrl": "http://192.168.0.101:18084/api",
  "gatewayId": "",
  "forceOnScreenKeyboard": true
}
```

## 启动命令

### 仅启动前端（浏览器）

```bash
npm run dev
```

访问 <http://127.0.0.1:5173>

### 启动 Electron 桌面应用（推荐）

```bash
npm run electron:dev
```

会先启动 Vite，再打开 Electron 窗口。

## 打包命令

### 仅构建前端

```bash
npm run build:prod
```

产物：`dist/`

### 打包桌面安装包

```bash
# 本机默认目标
npm run electron:build

# 银河麒麟 ARM64 deb（推荐在 ARM64 Linux / GitHub Actions 上执行）
npm run electron:build:linux:arm64

# Linux amd64 deb
npm run electron:build:linux:amd64

# Windows 安装包
npm run electron:build:win
```

产物目录：`release/`

### GitHub Actions

仓库工作流 **Build Electron ARM64 DEB**（`workflow_dispatch`）会在 `ubuntu-22.04-arm` 上产出 ARM64 `.deb` artifact。

### 麒麟终端安装

```bash
sudo dpkg -i 报到取号-*.deb
# 如有依赖提示：
sudo apt install -f -y
```

安装后可执行命令一般为 `qms`，或从应用菜单打开「报到取号」。

在安装目录旁编辑 `config.json`（与可执行文件同目录，或按发行版路径查找），设置后端 `apiBaseUrl`。

Electron 自带 Chromium，**不依赖** 系统 `libwebkit2gtk-4.1`，也无需 glibc-compat 重打包。

## 项目结构

```
queueManagement-display/
├── src/                 # Vue 前端
├── electron/
│   ├── main.cjs         # Electron 主进程（窗口 / IPC / HTTP / TabTip）
│   └── preload.cjs      # 预加载桥 window.qms
├── config.example.json
├── vite.config.js
└── package.json
```

## 常用脚本

| 命令 | 说明 |
|------|------|
| `npm run dev` | Vite 开发服务器 |
| `npm run electron:dev` | Electron + Vite 联调 |
| `npm run build:prod` | 构建前端 |
| `npm run electron:build:linux:arm64` | 打包麒麟 ARM64 deb |
| `npm run electron:build:win` | 打包 Windows NSIS |

## 注意事项

1. 开发服务器固定 `5173` 端口。
2. 生产包 API 地址优先改安装目录 `config.json` 的 `apiBaseUrl`。
3. 触屏终端建议 `forceOnScreenKeyboard: true`；Windows 未强制时会尝试 TabTip。
4. 按 F12 可在 Electron 生产包中开关 DevTools。
