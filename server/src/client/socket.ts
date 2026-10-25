import { status, token } from './dom.js'
import type { PreviewConfig, PreviewDocument } from './model.js'

export type OutgoingMessage =
  | { type: 'jump'; line: number }
  | { type: 'open_file'; href: string }
  | { type: 'toggle_task'; line: number }
  | { type: 'rendered'; latency_ms?: number }

interface InitMessage {
  type: 'init'
  config?: Partial<PreviewConfig>
  document: PreviewDocument
}

type IncomingMessage =
  | InitMessage
  | { type: 'render'; document: PreviewDocument; sent_at?: number }
  | { type: 'cursor'; line: number }
  | { type: 'error'; error: string }

export interface SocketHandlers {
  onInit: (message: InitMessage) => Promise<void>
  onRender: (document: PreviewDocument, sentAt: number | undefined) => Promise<void>
  onCursor: (line: number) => void
}

let currentSocket: WebSocket | undefined
let reconnectDelay = 250

export function send(message: OutgoingMessage): void {
  if (currentSocket?.readyState === WebSocket.OPEN) {
    currentSocket.send(JSON.stringify(message))
  }
}

/** Connects to the preview server and keeps reconnecting with backoff. */
export function connect(handlers: SocketHandlers): void {
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
  socket.addEventListener('message', async (event: MessageEvent<string>) => {
    try {
      const message = JSON.parse(event.data) as IncomingMessage
      if (message.type === 'init') {
        await handlers.onInit(message)
      } else if (message.type === 'render') {
        await handlers.onRender(message.document, message.sent_at)
      } else if (message.type === 'cursor') {
        handlers.onCursor(message.line)
      } else {
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
    setTimeout(() => connect(handlers), reconnectDelay)
    reconnectDelay = Math.min(reconnectDelay * 2, 5000)
  })
}
