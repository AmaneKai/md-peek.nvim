import type http from 'node:http'
import type { Duplex } from 'node:stream'
import { WebSocket, WebSocketServer } from 'ws'
import { isLoopbackRequest, isSameOrigin } from '../core/security.js'
import { type BrowserMessage, parseBrowserMessage } from '../protocol.js'

export interface GatewayOptions {
  authorize: (request: http.IncomingMessage, url: URL) => boolean
  /** The first message each browser receives on connecting: config and the current document. */
  getInit: () => unknown
  /** Called for every valid browser message; a thrown error is sent back to that browser. */
  onMessage: (message: BrowserMessage) => void
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}

/** Owns the browser WebSocket connections: who may connect, fan-out, and message parsing. */
export function createGateway(options: GatewayOptions) {
  const websocketServer = new WebSocketServer({ noServer: true })
  const browserSockets = new Set<WebSocket>()

  websocketServer.on('connection', (browserSocket) => {
    browserSockets.add(browserSocket)
    browserSocket.send(JSON.stringify(options.getInit()))
    browserSocket.on('message', (rawMessage) => {
      try {
        options.onMessage(parseBrowserMessage(JSON.parse(rawMessage.toString())))
      } catch (error) {
        browserSocket.send(JSON.stringify({ type: 'error', error: errorMessage(error) }))
      }
    })
    browserSocket.on('close', () => browserSockets.delete(browserSocket))
  })

  return {
    /** Wire to the HTTP server's `upgrade` event. */
    handleUpgrade(request: http.IncomingMessage, socket: Duplex, head: Buffer): void {
      const url = new URL(request.url || '/', `http://${request.headers.host}`)
      if (
        !isLoopbackRequest(request) ||
        !isSameOrigin(request) ||
        url.pathname !== '/ws' ||
        !options.authorize(request, url)
      ) {
        socket.destroy()
        return
      }

      websocketServer.handleUpgrade(request, socket, head, (browserSocket) => {
        websocketServer.emit('connection', browserSocket)
      })
    },

    broadcast(message: unknown): void {
      const payload = JSON.stringify(message)
      for (const browserSocket of browserSockets) {
        if (browserSocket.readyState === WebSocket.OPEN) {
          browserSocket.send(payload)
        }
      }
    },

    close(): void {
      for (const browserSocket of browserSockets) {
        browserSocket.close()
      }
      websocketServer.close()
    },
  }
}
