import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const simpleKeyboardEsm = path.resolve(
  __dirname,
  'node_modules/simple-keyboard/build/index.modern.esm.js'
)

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const apiTarget = env.VITE_API_TARGET || 'http://127.0.0.1:8080'
  const shouldRewrite = env.VITE_API_PROXY_REWRITE === 'true'
  const enableDebug = env.VITE_APP_DEBUG === 'true'

  return {
    // Electron file:// 加载必需相对路径
    base: './',
    plugins: [vue(), tailwindcss()],
    clearScreen: false,
    envPrefix: ['VITE_'],
    optimizeDeps: {
      include: ['simple-keyboard', 'pinyin-match-hanzi'],
    },
    resolve: {
      alias: [
        {
          find: /^simple-keyboard$/,
          replacement: simpleKeyboardEsm,
        },
      ],
    },
    server: {
      port: 5173,
      strictPort: true,
      host: '127.0.0.1',
      proxy: {
        '/api': {
          target: apiTarget,
          changeOrigin: true,
          secure: false,
          ...(shouldRewrite
            ? { rewrite: (path) => path.replace(/^\/api/, '') }
            : {}),
        },
      },
    },
    build: {
      target: 'chrome120',
      minify: !enableDebug,
      sourcemap: enableDebug,
      outDir: 'dist',
    },
  }
})
