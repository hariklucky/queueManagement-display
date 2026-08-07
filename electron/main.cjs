const {
  app,
  BrowserWindow,
  ipcMain,
  net,
  shell,
} = require('electron')
const path = require('node:path')
const fs = require('node:fs')
const { spawn } = require('node:child_process')

const isDev = !app.isPackaged
const DEV_SERVER_URL = process.env.VITE_DEV_SERVER_URL || 'http://127.0.0.1:5173'

/** @type {BrowserWindow | null} */
let mainWindow = null

function getInstallDir() {
  if (process.env.PORTABLE_EXECUTABLE_DIR) {
    return process.env.PORTABLE_EXECUTABLE_DIR
  }
  return path.dirname(app.getPath('exe'))
}

function getInstallConfigPath() {
  return path.join(getInstallDir(), 'config.json')
}

function getUserDataConfigPath() {
  return path.join(app.getPath('userData'), 'config.json')
}

function getExampleConfigPath() {
  const candidates = [
    path.join(process.resourcesPath || '', 'config.example.json'),
    path.join(app.getAppPath(), 'config.example.json'),
    path.join(__dirname, '..', 'config.example.json'),
  ]
  return candidates.find((p) => fs.existsSync(p)) || null
}

function readJsonConfig(configPath) {
  if (!configPath || !fs.existsSync(configPath)) {
    return null
  }

  try {
    const raw = fs.readFileSync(configPath, 'utf8')
    const parsed = JSON.parse(raw)
    return parsed && typeof parsed === 'object' ? parsed : null
  } catch (error) {
    console.warn('[QMS] 解析 config.json 失败', configPath, error)
    return null
  }
}

function ensureRuntimeConfig() {
  const configPath = getInstallConfigPath()
  if (fs.existsSync(configPath)) {
    return configPath
  }

  const examplePath = getExampleConfigPath()
  if (!examplePath) {
    return null
  }

  try {
    fs.copyFileSync(examplePath, configPath)
  } catch (error) {
    console.warn('[QMS] 无法写入安装目录 config.json，将仅读取示例配置', error)
    return examplePath
  }

  return configPath
}

function loadRuntimeConfig() {
  // 应用内修改优先写入 userData，读取时优先使用
  const userDataConfig = readJsonConfig(getUserDataConfigPath())
  if (userDataConfig) {
    return userDataConfig
  }

  const configPath = ensureRuntimeConfig()
  return readJsonConfig(configPath) || {}
}

function saveRuntimeConfig(partial) {
  const patch = partial && typeof partial === 'object' ? partial : {}
  const next = {
    ...loadRuntimeConfig(),
    ...patch,
  }

  const payload = `${JSON.stringify(next, null, 2)}\n`
  const userDataPath = getUserDataConfigPath()
  const installPath = getInstallConfigPath()

  fs.mkdirSync(path.dirname(userDataPath), { recursive: true })
  fs.writeFileSync(userDataPath, payload, 'utf8')

  try {
    fs.writeFileSync(installPath, payload, 'utf8')
  } catch (error) {
    console.warn('[QMS] 无法写入安装目录 config.json，已保存到用户目录', error)
  }

  return next
}

function createWindow() {
  mainWindow = new BrowserWindow({
    title: '报到取号',
    width: 1280,
    height: 1024,
    minWidth: 1280,
    minHeight: 1024,
    fullscreen: true,
    center: true,
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  })

  if (isDev) {
    mainWindow.loadURL(DEV_SERVER_URL)
  } else {
    mainWindow.loadFile(path.join(__dirname, '..', 'dist', 'index.html'))
  }

  mainWindow.on('closed', () => {
    mainWindow = null
  })
}

function nativeHttpFetch({ url, method, headers, body }) {
  return new Promise((resolve, reject) => {
    try {
      const request = net.request({
        method: method || 'GET',
        url,
      })

      if (headers && typeof headers === 'object') {
        for (const [key, value] of Object.entries(headers)) {
          if (value != null) {
            request.setHeader(key, String(value))
          }
        }
      }

      const chunks = []
      request.on('response', (response) => {
        response.on('data', (chunk) => {
          chunks.push(Buffer.from(chunk))
        })
        response.on('end', () => {
          resolve({
            status: response.statusCode || 0,
            body: Buffer.concat(chunks).toString('utf8'),
          })
        })
        response.on('error', (error) => {
          reject(error)
        })
      })

      request.on('error', (error) => {
        reject(error)
      })

      if (typeof body === 'string' && body.length > 0) {
        request.write(body)
      }
      request.end()
    } catch (error) {
      reject(error)
    }
  })
}

function resolveTabTipPath() {
  const candidates = [
    'C:\\Program Files\\Common Files\\microsoft shared\\ink\\TabTip.exe',
    'C:\\Program Files (x86)\\Common Files\\Microsoft Shared\\Ink\\TabTip.exe',
  ]
  return candidates.find((p) => fs.existsSync(p)) || null
}

function showTouchKeyboard() {
  if (process.platform !== 'win32') {
    return { method: 'skipped-non-windows', visible: false }
  }

  const tabTip = resolveTabTipPath()
  if (!tabTip) {
    return { method: 'none', visible: false }
  }

  try {
    spawn(tabTip, [], {
      detached: true,
      stdio: 'ignore',
      windowsHide: true,
    }).unref()
    return { method: 'tabtip', visible: true }
  } catch (error) {
    console.warn('[QMS] 启动 TabTip 失败', error)
    return { method: 'none', visible: false }
  }
}

function warmUpTouchKeyboard() {
  if (process.platform !== 'win32') {
    return
  }
  showTouchKeyboard()
}

function registerIpc() {
  ipcMain.handle('qms:load-runtime-config', () => loadRuntimeConfig())

  ipcMain.handle('qms:save-runtime-config', (_event, partial) => {
    try {
      return saveRuntimeConfig(partial)
    } catch (error) {
      throw new Error(error?.message || String(error))
    }
  })

  ipcMain.handle('qms:http-fetch', async (_event, payload) => {
    try {
      return await nativeHttpFetch(payload || {})
    } catch (error) {
      throw new Error(error?.message || String(error))
    }
  })

  ipcMain.handle('qms:show-touch-keyboard', () => showTouchKeyboard())
  ipcMain.handle('qms:warm-up-touch-keyboard', () => {
    warmUpTouchKeyboard()
    return true
  })

  ipcMain.handle('qms:toggle-devtools', () => {
    if (!mainWindow) {
      return false
    }
    if (mainWindow.webContents.isDevToolsOpened()) {
      mainWindow.webContents.closeDevTools()
    } else {
      mainWindow.webContents.openDevTools({ mode: 'detach' })
    }
    return true
  })

  ipcMain.handle('qms:open-external', async (_event, url) => {
    if (typeof url === 'string' && /^https?:\/\//i.test(url)) {
      await shell.openExternal(url)
      return true
    }
    return false
  })

  ipcMain.handle('qms:quit-app', () => {
    scheduleAppQuit()
    return true
  })

  ipcMain.on('qms:quit-app', () => {
    scheduleAppQuit()
  })
}

function scheduleAppQuit() {
  // 延迟到当前 IPC 回包之后，避免渲染进程误报退出失败
  setImmediate(() => {
    for (const win of BrowserWindow.getAllWindows()) {
      try {
        win.removeAllListeners('close')
        if (!win.isDestroyed()) {
          win.destroy()
        }
      } catch (error) {
        console.warn('[QMS] 销毁窗口失败', error)
      }
    }
    mainWindow = null
    try {
      app.exit(0)
    } catch (error) {
      console.warn('[QMS] app.exit 失败，改用 process.exit', error)
      process.exit(0)
    }
  })
}

app.whenReady().then(() => {
  ensureRuntimeConfig()
  registerIpc()
  createWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow()
    }
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit()
  }
})
