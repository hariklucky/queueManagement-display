/// <reference types="vite/client" />

declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<object, object, unknown>
  export default component
}

interface ImportMetaEnv {
  readonly VITE_API_BASE_URL?: string
  readonly VITE_API_TARGET?: string
  readonly VITE_API_PROXY_REWRITE?: string
  readonly VITE_GATEWAY_ID?: string
  readonly VITE_ID_CARD_READER_URL?: string
  readonly VITE_TICKET_PRINTER_URL?: string
  readonly TAURI_ENV_DEBUG?: string
  readonly TAURI_ENV_PLATFORM?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
