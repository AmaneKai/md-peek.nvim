import { toastElement } from './dom.js'

export function toast(message) {
  toastElement.textContent = message
  toastElement.classList.add('show')
  clearTimeout(toastElement.timer)
  toastElement.timer = setTimeout(() => toastElement.classList.remove('show'), 1500)
}
