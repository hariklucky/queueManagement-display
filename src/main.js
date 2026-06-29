import { createApp } from 'vue'
import './style.css'
import App from './App.vue'
import { setupDevtoolsShortcut } from './utils/debugDevtools'
import { setupTouchKeyboard } from './utils/touchKeyboard'

setupDevtoolsShortcut()
setupTouchKeyboard()

createApp(App).mount('#app')
