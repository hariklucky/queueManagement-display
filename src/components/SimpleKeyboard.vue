<script setup lang="ts">
import { onMounted, watch } from 'vue'
import Keyboard from 'simple-keyboard'
import 'simple-keyboard/build/css/index.css'
import { getPinyinCandidates } from 'pinyin-match-hanzi'
import type { OnScreenKeyboardType } from '../utils/onScreenKeyboard'

const props = withDefaults(
  defineProps<{
    keyboardClass?: string
    maxLength?: string | number
    keyboardType?: OnScreenKeyboardType
  }>(),
  {
    keyboardClass: 'qms-on-screen-keyboard',
    maxLength: '',
    keyboardType: 'chinese',
  }
)

const emit = defineEmits<{
  onChange: [input: string]
  empty: []
  closeKeyboard: []
  updateKeyboardType: [keyboardType: OnScreenKeyboardType]
  backspaceCommitted: []
  commitSpace: []
}>()

let keyboard: Keyboard | null = null

const displayDefault = {
  '{bksp}': '⌫',
  '{lock}': '⇪',
  '{enter}': '确认',
  '{tab}': 'Tab',
  '{shift}': '⇧',
  '{change}': '中/英',
  '{space}': '空格',
  '{clear}': '清空',
  '{close}': '关闭',
}

const numberLayout = {
  default: [
    '1 2 3',
    '4 5 6',
    '7 8 9',
    '0 {bksp}',
    '- + . @',
    '{clear} {space} {close}',
  ],
}

const englishLayout = {
  default: [
    '1 2 3 4 5 6 7 8 9 0 {bksp}',
    'q w e r t y u i o p',
    'a s d f g h j k l {enter}',
    '{shift} z x c v b n m',
    '{change} {clear} {space} {close}',
  ],
  shift: [
    '! @ # $ % ^ & * ( ) {bksp}',
    'Q W E R T Y U I O P',
    'A S D F G H J K L {enter}',
    '{shift} Z X C V B N M',
    '{change} {clear} {space} {close}',
  ],
}

const chineseLayout = {
  default: [
    '1 2 3 4 5 6 7 8 9 0 {bksp}',
    'q w e r t y u i o p',
    'a s d f g h j k l {enter}',
    '{shift} z x c v b n m',
    '{change} {clear} {space} {close}',
  ],
  shift: [
    '! @ # $ % ^ & * ( ) {bksp}',
    'Q W E R T Y U I O P',
    'A S D F G H J K L {enter}',
    '{shift} Z X C V B N M',
    '{change} {clear} {space} {close}',
  ],
}

function initializeKeyboard() {
  const commonOptions = {
    onChange,
    onKeyPress,
    display: displayDefault,
    buttonTheme: [
      { class: 'hg-key-close', buttons: '{close}' },
      { class: 'hg-key-func', buttons: '{change} {clear} {shift} {lock}' },
      { class: 'hg-key-action', buttons: '{enter} {bksp}' },
      { class: 'hg-key-space', buttons: '{space}' },
    ],
    maxLength: props.maxLength,
  }

  let layoutOptions: Record<string, unknown> = {}

  if (props.keyboardType === 'number') {
    layoutOptions = { ...commonOptions, layout: numberLayout }
  } else if (props.keyboardType === 'chinese') {
    layoutOptions = {
      ...commonOptions,
      layout: chineseLayout,
      layoutCandidatesPageSize: 10,
    }
  } else {
    layoutOptions = { ...commonOptions, layout: englishLayout }
  }

  keyboard = new Keyboard(props.keyboardClass, layoutOptions)
}

function applyKeyboardLayout() {
  if (!keyboard) {
    return
  }

  if (props.keyboardType === 'number') {
    keyboard.setOptions({
      layout: numberLayout,
      layoutCandidates: {},
      layoutCandidatesPageSize: 0,
      layoutName: 'default',
    })
  } else if (props.keyboardType === 'chinese') {
    keyboard.setOptions({
      layout: chineseLayout,
      layoutCandidates: {},
      layoutCandidatesPageSize: 10,
      layoutName: 'default',
    })
  } else {
    keyboard.setOptions({
      layout: englishLayout,
      layoutCandidates: {},
      layoutCandidatesPageSize: 0,
      layoutName: 'default',
    })
  }

  keyboard.clearInput()
}

function onChange(input: string) {
  if (props.keyboardType === 'chinese' && keyboard?.options.layoutName === 'default') {
    keyboard.setOptions({
      layoutCandidates: {
        [input]: getPinyinCandidates(input)
          .map((item) => item.w)
          .join(' '),
      },
    })
  }

  emit('onChange', input)
}

function onKeyPress(button: string) {
  if (button === '{bksp}') {
    const current = keyboard?.getInput() ?? ''
    if (current) {
      const next = current.slice(0, -1)
      keyboard?.setInput(next)
      onChange(next)
    } else {
      emit('backspaceCommitted')
    }
    return
  }

  if (button === '{space}') {
    if (props.keyboardType === 'chinese') {
      emit('commitSpace')
      keyboard?.setInput('')
      onChange('')
    } else {
      const current = keyboard?.getInput() ?? ''
      const next = `${current} `
      keyboard?.setInput(next)
      onChange(next)
    }
    return
  }

  if (button === '{close}') {
    emit('closeKeyboard')
    return
  }

  if (button === '{change}') {
    if (props.keyboardType === 'english') {
      emit('updateKeyboardType', 'chinese')
    } else if (props.keyboardType === 'chinese') {
      emit('updateKeyboardType', 'english')
    } else {
      emit('updateKeyboardType', 'english')
    }
    return
  }

  if (button === '{clear}') {
    keyboard?.setInput('')
    emit('empty')
    return
  }

  if (button === '{shift}' || button === '{lock}') {
    handleShift()
  }
}

function handleShift() {
  if (!keyboard) return

  const currentLayout = keyboard.options.layoutName
  const shiftToggle = currentLayout === 'default' ? 'shift' : 'default'
  keyboard.setOptions({ layoutName: shiftToggle })
}

function onChangeFocus(value: string) {
  keyboard?.setInput(value)
}

onMounted(initializeKeyboard)

watch(() => props.keyboardType, applyKeyboardLayout)

defineExpose({
  onChangeFocus,
})
</script>

<template>
  <div :class="keyboardClass"></div>
</template>

<style>
/* ========== 键盘容器 ========== */
.qms-on-screen-keyboard.hg-theme-default {
  width: 100%;
  padding: 16px 14px 18px;
  background: linear-gradient(180deg, #f8fafc 0%, #eef2f8 100%);
  border-radius: 20px 20px 0 0;
  box-shadow: 0 -10px 40px rgba(22, 93, 255, 0.1);
  font-family: 'Noto Sans SC', sans-serif;
  overflow: visible;
}

.qms-on-screen-keyboard .hg-rows {
  width: 100% !important;
}

.qms-on-screen-keyboard .hg-row {
  margin-bottom: 8px !important;
}

.qms-on-screen-keyboard .hg-row .hg-button:not(:last-child),
.qms-on-screen-keyboard .hg-row .hg-button-container:not(:last-child) {
  margin-right: 8px !important;
}

/* ========== 拼音候选栏 ========== */
.qms-on-screen-keyboard .hg-candidate-box {
  position: relative;
  transform: none;
  display: flex;
  align-items: center;
  width: 100%;
  min-height: 58px;
  margin: 0 0 14px;
  padding: 0;
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 14px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06);
  overflow: hidden;
  touch-action: pan-x;
}

.qms-on-screen-keyboard .hg-candidate-box-prev,
.qms-on-screen-keyboard .hg-candidate-box-next {
  display: flex !important;
  flex-shrink: 0;
  align-items: center !important;
  justify-content: center !important;
  align-self: stretch;
  width: 48px;
  min-height: 58px;
  padding: 0 !important;
  color: #9ca3af;
  font-size: 0;
  line-height: 0;
  background: #f9fafb;
  border-right: 1px solid #f3f4f6;
  cursor: pointer;
  user-select: none;
  transition: color 0.15s ease, background 0.15s ease;
}

/* 用 CSS 三角形替代 ◄ ►，保证左右大小一致 */
.qms-on-screen-keyboard .hg-candidate-box-prev::before,
.qms-on-screen-keyboard .hg-candidate-box-next::before {
  content: '';
  display: block;
  width: 0;
  height: 0;
  border-top: 7px solid transparent;
  border-bottom: 7px solid transparent;
}

.qms-on-screen-keyboard .hg-candidate-box-prev::before {
  border-right: 9px solid currentColor;
  margin-left: -2px;
}

.qms-on-screen-keyboard .hg-candidate-box-next::before {
  border-left: 9px solid currentColor;
  margin-right: -2px;
}

.qms-on-screen-keyboard .hg-candidate-box-next {
  border-right: none;
  border-left: 1px solid #f3f4f6;
}

.qms-on-screen-keyboard .hg-candidate-box-btn-active {
  color: #165dff;
  background: #eff6ff;
}

.qms-on-screen-keyboard .hg-candidate-box-prev:not(.hg-candidate-box-btn-active),
.qms-on-screen-keyboard .hg-candidate-box-next:not(.hg-candidate-box-btn-active) {
  opacity: 0.45;
  cursor: default;
}

.qms-on-screen-keyboard ul.hg-candidate-box-list {
  display: flex;
  flex: 1;
  flex-wrap: nowrap;
  align-items: center;
  gap: 8px;
  margin: 0;
  padding: 8px 10px;
  overflow-x: auto;
  overflow-y: hidden;
  list-style: none;
  touch-action: pan-x;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: thin;
}

.qms-on-screen-keyboard li.hg-candidate-box-list-item {
  display: inline-flex;
  flex: 0 0 auto;
  align-items: center;
  justify-content: center;
  width: auto !important;
  min-width: 48px;
  height: 42px;
  margin: 0;
  padding: 0 16px;
  border-radius: 10px;
  background: #f3f4f6;
  color: #1f2937;
  font-size: 20px;
  font-weight: 500;
  line-height: 1;
  white-space: nowrap;
  transition: background 0.15s ease, color 0.15s ease;
}

.qms-on-screen-keyboard li.hg-candidate-box-list-item:hover {
  background: #dbeafe;
  color: #165dff;
  cursor: pointer;
}

.qms-on-screen-keyboard li.hg-candidate-box-list-item:active {
  background: #bfdbfe;
}

/* ========== 按键 ========== */
.qms-on-screen-keyboard .hg-button {
  height: 54px !important;
  border: none !important;
  border-bottom: none !important;
  border-radius: 12px !important;
  background: #fff !important;
  color: #374151 !important;
  font-size: 20px !important;
  font-weight: 500;
  box-shadow:
    0 1px 2px rgba(0, 0, 0, 0.06),
    0 2px 4px rgba(0, 0, 0, 0.04) !important;
  transition: background 0.12s ease, transform 0.08s ease;
}

.qms-on-screen-keyboard .hg-button:active {
  transform: scale(0.97);
}

.qms-on-screen-keyboard .hg-button.hg-activeButton {
  background: #dbeafe !important;
  color: #165dff !important;
}

.qms-on-screen-keyboard .hg-button.hg-key-func {
  background: #e8eef7 !important;
  color: #4b5563 !important;
  font-size: 16px !important;
}

.qms-on-screen-keyboard .hg-button.hg-key-action {
  background: #eff6ff !important;
  color: #165dff !important;
  font-size: 16px !important;
}

.qms-on-screen-keyboard .hg-button.hg-key-space {
  flex-grow: 2;
  font-size: 16px !important;
}

.qms-on-screen-keyboard .hg-button.hg-key-close {
  background: #fff !important;
  color: #6b7280 !important;
  border: 1px solid #e5e7eb !important;
  font-size: 16px !important;
  box-shadow: none !important;
}

/* 数字键盘大按键 */
.qms-on-screen-keyboard.hg-layout-numeric .hg-button {
  height: 64px !important;
  font-size: 24px !important;
}
</style>
