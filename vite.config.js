import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

const host = process.env.TAURI_DEV_HOST

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const apiTarget = env.VITE_API_TARGET || 'http://127.0.0.1:8080'
  const shouldRewrite = env.VITE_API_PROXY_REWRITE === 'true'
  const enableDebug =
    !!process.env.TAURI_ENV_DEBUG || env.VITE_APP_DEBUG === 'true'

  return {
    plugins: [vue(), tailwindcss()],
    clearScreen: false,
    envPrefix: ['VITE_', 'TAURI_ENV_*'],
    server: {
      port: 5173,
      strictPort: true,
      host: host || false,
      hmr: host
        ? {
            protocol: 'ws',
            host,
            port: 1421,
          }
        : undefined,
      watch: {
        ignored: ['**/src-tauri/**'],
      },
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
      // Vite 8 的 esbuild 降级无法处理 safari13 解构语法，需 >= safari14.1
      target:
        process.env.TAURI_ENV_PLATFORM === 'windows' ? 'chrome105' : 'safari14.1',
      minify: !enableDebug,
      sourcemap: enableDebug,
    },
  }
})
