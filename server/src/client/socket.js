import { status, token } from './dom.js'

let currentSocket
let reconnectDelay = 250

export function send(message) {
  if (currentSocket?.readyState === WebSocket.OPEN) {
    currentSocket.send(JSON.stringify(message))
  }
}

/** Connects to the preview server and keeps reconnecting with backoff. */
export function connect({ onInit, onRender, onCursor }) {
  status.textContent = 'Connecting…'
  const protocol = location.protocol === 'https:' ? 'wss' : 'ws'
  const socket = new WebSocket(
    `${protocol}://${location.host}/ws?token=${encodeURIComponent(token)}`,
  )
  currentSocket = socket
  socket.addEventListener('open', () => {
    status.textContent = 'Live'
    reconnectDelay = 250
  })
  socket.addEventListener('message', async (event) => {
    try {
      const message = JSON.parse(event.data)
      if (message.type === 'init') {
        await onInit(message)
      } else if (message.type === 'render') {
        await onRender(message.document)
      } else if (message.type === 'cursor') {
        onCursor(message.line)
      } else if (message.type === 'error') {
        console.error('[md-peek] preview server rejected a browser message', message.error)
      }
    } catch (error) {
      status.textContent = 'Preview error'
      console.error('[md-peek] failed to process preview update', error)
    }
  })
  socket.addEventListener('close', () => {
    if (currentSocket !== socket) {
      return
    }

    status.textContent = 'Reconnecting…'
    setTimeout(() => connect({ onInit, onRender, onCursor }), reconnectDelay)
    reconnectDelay = Math.min(reconnectDelay * 2, 5000)
  })
}
