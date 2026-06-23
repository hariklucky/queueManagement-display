# 排队叫号

面向营业厅现场终端的桌面取号应用，支持预约取号与现场取号，集成身份证读卡与小票打印能力。前端基于 Vue 3 + Vite，桌面端基于 Tauri 2 打包为原生应用。

## 技术栈

| 类别 | 技术 |
|------|------|
| 前端框架 | Vue 3（`<script setup>`） |
| 构建工具 | Vite 8 |
| 样式 | Tailwind CSS 4 |
| 桌面端 | Tauri 2 |
| HTTP 请求 | Axios |
| 语言 | JavaScript / TypeScript |

## 功能说明

- **预约取号**：刷身份证或输入手机号查询预约并取号
- **现场取号**：填写信息、选择业务类型后获取排队号
- **身份证读卡**：调用本地读卡服务（`127.0.0.1:8989`）或宿主注入的 `window.IdCardReader`
- **小票打印**：取号成功后调用本地打印服务（`127.0.0.1:8990`）
- **全屏展示**：默认 1280×1024 全屏窗口，适合自助终端使用

## 环境要求

- **Node.js**：`24.15.0`（项目根目录有 `.nvmrc`，可使用 `nvm use`）
- **npm**：随 Node.js 安装即可
- **Rust**：Tauri 桌面开发与打包需要（[安装说明](https://www.rust-lang.org/tools/install)）
- **系统依赖**：按 [Tauri 官方文档](https://v2.tauri.app/start/prerequisites/) 安装对应平台依赖

### 外部服务

运行完整业务流程时，需确保以下服务可用：

| 服务 | 默认地址 | 说明 |
|------|----------|------|
| 排队后端 API | `http://localhost:8080`（开发） | 预约查询、现场取号等接口 |
| 身份证读卡 | `http://127.0.0.1:8989/api/ReadCard` | 读取身份证信息 |
| 小票打印 | `http://127.0.0.1:8990/api/PrintTicket` | 打印排队小票 |

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
# 接口基础路径（axios 请求前缀）
VITE_API_BASE_URL=/api

# 开发时代理目标（仅 dev 模式生效）
VITE_API_TARGET=http://localhost:8080

# 是否去掉代理路径中的 /api 前缀
VITE_API_PROXY_REWRITE=false

# 读卡器、打印机本地服务地址（生产/测试环境）
VITE_ID_CARD_READER_URL=http://127.0.0.1:8989/api/ReadCard
VITE_TICKET_PRINTER_URL=http://127.0.0.1:8990/api/PrintTicket
```

开发模式下，`/api` 请求会通过 Vite 代理转发到 `VITE_API_TARGET`，无需额外处理跨域。

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

### 打包桌面应用

```bash
npm run tauri:build
```

打包前会自动执行 `npm run build:prod`，最终安装包输出在：

```
src-tauri/target/release/bundle/
```

Windows 平台会生成 **MSI** 与 **NSIS** 安装包（见 `tauri.conf.json` 中 `bundle.targets` 配置）。

### 在 macOS 上交叉编译 Windows 安装包

```bash
npm run tauri:build:win
```

需要预先安装 `cargo-xwin` 及 Windows 交叉编译工具链。

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
│   ├── utils/            # 请求封装、读卡、打印等工具
│   ├── views/
│   │   └── QueueTicket.vue   # 主页面（取号流程）
│   ├── App.vue
│   └── main.js
├── src-tauri/            # Tauri 桌面端（Rust）
│   ├── src/
│   ├── tauri.conf.json   # 窗口、打包等配置
│   └── Cargo.toml
├── .env.development      # 开发环境变量
├── .env.test             # 测试环境变量
├── .env.production       # 生产环境变量
├── vite.config.js        # Vite 配置（含 API 代理）
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
| `npm run tauri:build` | 打包 Tauri 桌面应用 |
| `npm run tauri:build:win` | 交叉编译 Windows 安装包 |

## 注意事项

1. **端口占用**：开发服务器固定使用 `5173` 端口（`strictPort: true`），被占用时需先释放。
2. **生产 API**：打包后不再走 Vite 代理，请根据实际部署修改 `.env.production` 中的 `VITE_API_BASE_URL`，或确保前端与后端同域且 `/api` 可访问。
3. **读卡与打印**：两项能力依赖本机服务，部署终端时需同步安装并启动对应程序。
4. **窗口配置**：应用名称、窗口尺寸、全屏等行为可在 `src-tauri/tauri.conf.json` 中调整。
