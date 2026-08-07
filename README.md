# 报到取号

营业厅现场终端桌面取号应用（预约取号 / 现场取号）。  
技术栈：Vue 3 + Vite + Electron（自带 Chromium，可直接在银河麒麟等 glibc 2.31 环境运行，无需 WebKitGTK）。

---

## 环境准备

- Node.js 20+（可用 `nvm use`）
- npm 10+

```bash
npm install
```

---

## 本地开发（可选）

```bash
# 仅浏览器
npm run dev

# Electron 桌面联调（推荐）
npm run electron:dev
```

---

## 打包说明

打包会先执行前端生产构建（`dist/`），再用 electron-builder 生成安装包，产物在 `release/`。

| 命令 | 产物 | 适用场景 |
|------|------|----------|
| `npm run electron:build:linux:arm64` | `报到取号-<版本>-arm64.deb` | **银河麒麟 ARM64（推荐）** |
| `npm run electron:build:linux:amd64` | `报到取号-<版本>-x64.deb` | Linux x64 |
| `npm run electron:build:win` | `报到取号-<版本>-Setup.exe` | Windows |
| `npm run electron:build` | 按当前系统默认目标 | 本机快速试打包 |

### 1. 打包麒麟 ARM64 deb（最常用）

**推荐用 GitHub Actions**（本机若是 macOS / x64，交叉打 ARM64 Linux 包容易失败）：

1. 打开仓库 **Actions** → **Build Electron ARM64 DEB**
2. 点击 **Run workflow**
3. 完成后下载 artifact：`electron-arm64-deb`
4. 得到类似：`报到取号-0.1.0-arm64.deb`

若已在 **ARM64 Linux** 机器上开发，也可本地执行：

```bash
npm install
npm run electron:build:linux:arm64
```

产物路径：`release/报到取号-*-arm64.deb`

### 2. 打包 Linux amd64 deb

```bash
npm run electron:build:linux:amd64
```

### 3. 打包 Windows 安装包

在 Windows 或可构建 Windows 目标的环境执行：

```bash
npm run electron:build:win
```

产物：`release/报到取号-*-Setup.exe`

### 4. 仅构建前端（不打包安装包）

```bash
npm run build:prod
```

产物：`dist/`

---

## 麒麟终端安装与配置

### 安装

```bash
sudo dpkg -i 报到取号-0.1.0-arm64.deb
# 若提示依赖问题：
sudo apt-get install -f -y
```

启动：

```bash
qms
```

或从应用菜单打开「报到取号」。

### 配置后端地址

生产包通过本地 `config.json` 的 **`apiBaseUrl`** 访问后端。

常见路径（以实际安装目录为准，多为 `/opt/报到取号/`）：

```bash
# 查看安装文件
dpkg -L qms | head

# 写入 / 修改配置（无 nano 时可用）
sudo tee /opt/报到取号/config.json >/dev/null <<'EOF'
{
  "apiBaseUrl": "http://192.168.0.101:18084/api",
  "gatewayId": "",
  "forceOnScreenKeyboard": true
}
EOF
```

也可用应用内入口：

1. 屏幕**左上角**约 2.5 秒内连点 5 次  
2. 输入验证密码（当前年份倒序，如 2026 → `6202`）  
3. 修改 `apiBaseUrl`，勾选是否开机自启后保存  

改完后应用会刷新并按新地址请求。

### 退出应用

屏幕**右上角**连点 5 次 → 同样年份倒序密码 → 确认退出。

---

## 注意事项

1. 打麒麟 ARM64 包请优先用 Actions 的 `ubuntu-22.04-arm`，避免在 Intel Mac 上硬交叉编译。
2. 打包脚本已带 `--publish never`，不会上传 GitHub Release，只需下载 Actions artifact 或取 `release/` 目录文件。
3. Electron 自带 Chromium，**不需要**系统安装 `libwebkit2gtk-4.1`，也无需旧的 glibc-compat 重打包流程。
4. 生产环境不要依赖打包时的 `VITE_API_BASE_URL`；现场以 `config.json` / 应用内设置为准。
5. 按 **F12** 可开关 DevTools，便于现场排查。

---

## 常用脚本一览

| 命令 | 说明 |
|------|------|
| `npm run electron:dev` | 开发联调 |
| `npm run electron:build:linux:arm64` | 打包麒麟 ARM64 deb |
| `npm run electron:build:linux:amd64` | 打包 Linux x64 deb |
| `npm run electron:build:win` | 打包 Windows 安装包 |
| `npm run build:prod` | 仅构建前端 |
