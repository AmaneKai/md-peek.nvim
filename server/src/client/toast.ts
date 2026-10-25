import { toastElement } from './dom.js'

let hideTimer: ReturnType<typeof setTimeout> | undefined

export function toast(message: string): void {
  toastElement.textContent = message
  toastElement.classList.add('show')
  clearTimeout(hideTimer)
  hideTimer = setTimeout(() => toastElement.classList.remove('show'), 1500)
}
