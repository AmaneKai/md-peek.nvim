import http from 'node:http'
import { timingSafeEqual } from 'node:crypto'
import { createReadStream, readFileSync, statSync } from 'node:fs'
import { basename, dirname, extname, resolve } from 'node:path'
import { createInterface, type Interface as ReadlineInterface } from 'node:readline'
import type { Readable } from 'node:stream'
import { fileURLToPath } from 'node:url'
import { WebSocket, WebSocketServer } from 'ws'
import { AssetOutsideDocumentDirectoryError, resolveDocumentAssetPath } from './asset-path.js'
import {
  parseBrowserMessage,
  parseCursorLine,
  parseEditorMessage,
  parsePreviewConfig,
  parsePreviewDocument,
  type PreviewDocument,
} from './protocol.js'

export type { PreviewDocument } from './protocol.js'

const distributionDirectory = dirname(fileURLToPath(import.meta.url))
const authenticationToken = process.env.MD_PEEK_TOKEN
const authenticationTokenBytes = authenticationToken
  ? Buffer.from(authenticationToken, 'utf8')
  : undefined
const initialDocument: PreviewDocument = { content: '', path: '', line: 1 }
const contentSecurityPolicy = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: http: https:",
  "font-src 'self'",
  "connect-src 'self' ws:",
  "object-src 'none'",
  "base-uri 'none'",
].join('; ')

const contentTypes: Record<string, string> = {
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.woff2': 'font/woff2',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.avif': 'image/avif',
  '.ico': 'image/x-icon',
  '.pdf': 'application/pdf',
}

export interface PreviewServerOptions {
  editorInput?: Readable
  onEditorEvent?: (message: unknown) => void
}

function loadPreviewConfig(): Record<string, unknown> {
  try {
    return parsePreviewConfig(process.env.MD_PEEK_CONFIG)
  } catch {
    console.error('[md-peek] invalid preview configuration; using defaults')
    return {}
  }
}

function isLoopbackRequest(request: http.IncomingMessage): boolean {
  try {
    const hostname = new URL(`http://${request.headers.host}`).hostname
    return hostname === '127.0.0.1' || hostname === 'localhost' || hostname === '[::1]'
  } catch {
    return false
  }
}

function isAuthorized(request: http.IncomingMessage, url: URL): boolean {
  if (!authenticationTokenBytes) {
    return true
  }

  return (
    tokenMatches(request.headers['x-md-peek-token']) || tokenMatches(url.searchParams.get('token'))
  )
}

function tokenMatches(candidate: string | string[] | null | undefined): boolean {
  if (typeof candidate !== 'string' || !authenticationTokenBytes) {
    return false
  }

  const candidateBytes = Buffer.from(candidate, 'utf8')
  return (
    candidateBytes.length === authenticationTokenBytes.length &&
    timingSafeEqual(candidateBytes, authenticationTokenBytes)
  )
}

function sendJson(response: http.ServerResponse, status: number, value: unknown): void {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  })
  response.end(JSON.stringify(value))
}

function readRequestBody(request: http.IncomingMessage, limit = 12 * 1024 * 1024): Promise<string> {
  return new Promise((resolveBody, reject) => {
    let size = 0
    const chunks: Buffer[] = []

    request.on('data', (chunk: Buffer) => {
      size += chunk.length
      if (size > limit) {
        reject(new Error('request body is too large'))
        request.destroy()
        return
      }
      chunks.push(chunk)
    })
    request.on('end', () => resolveBody(Buffer.concat(chunks).toString('utf8')))
    request.on('error', reject)
  })
}

function streamFile(
  response: http.ServerResponse,
  path: string,
  headers: http.OutgoingHttpHeaders,
): void {
  response.writeHead(200, headers)
  const stream = createReadStream(path)
  stream.on('error', () => response.destroy())
  stream.pipe(response)
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}

export function createServer(options: PreviewServerOptions = {}) {
  let currentDocument = { ...initialDocument }
  const previewConfig = loadPreviewConfig()
  const browserSockets = new Set<WebSocket>()
  const editorSubscribers = new Set<http.ServerResponse>()
  let editorLines: ReadlineInterface | undefined

  function broadcastToBrowsers(message: unknown): void {
    const payload = JSON.stringify(message)
    for (const browserSocket of browserSockets) {
      if (browserSocket.readyState === WebSocket.OPEN) {
        browserSocket.send(payload)
      }
    }
  }

  function emitToEditors(message: unknown): void {
    options.onEditorEvent?.(message)
    const payload = `${JSON.stringify(message)}\n`
    for (const editorSubscriber of editorSubscribers) {
      editorSubscriber.write(payload)
    }
  }

  function applyEditorMessage(value: unknown): void {
    const message = parseEditorMessage(value)
    if (message.type === 'render') {
      currentDocument = message.document
      broadcastToBrowsers({ type: 'render', document: currentDocument })
      return
    }

    currentDocument.line = message.line
    broadcastToBrowsers({ type: 'cursor', line: currentDocument.line })
  }

  if (options.editorInput) {
    editorLines = createInterface({ input: options.editorInput })
    editorLines.on('line', (line) => {
      if (line === '') {
        return
      }
      try {
        applyEditorMessage(JSON.parse(line))
      } catch (error) {
        emitToEditors({ type: 'error', error: errorMessage(error) })
      }
    })
  }

  async function handleDocumentUpdate(
    request: http.IncomingMessage,
    response: http.ServerResponse,
    pathname: string,
  ): Promise<void> {
    try {
      const body: unknown = JSON.parse(await readRequestBody(request))
      if (pathname === '/render') {
        currentDocument = parsePreviewDocument(body)
        broadcastToBrowsers({ type: 'render', document: currentDocument })
      } else {
        currentDocument.line = parseCursorLine(body)
        broadcastToBrowsers({ type: 'cursor', line: currentDocument.line })
      }
      sendJson(response, 200, { ok: true })
    } catch (error) {
      sendJson(response, 400, { ok: false, error: errorMessage(error) })
    }
  }

  const server = http.createServer(async (request, response) => {
    if (!isLoopbackRequest(request)) {
      return sendJson(response, 403, { ok: false, error: 'loopback host required' })
    }

    const url = new URL(request.url || '/', `http://${request.headers.host}`)
    if (request.method === 'GET' && url.pathname === '/') {
      if (!isAuthorized(request, url)) {
        return sendJson(response, 401, { ok: false, error: 'unauthorized' })
      }

      const html = readFileSync(resolve(distributionDirectory, 'index.html'), 'utf8').replace(
        '__MD_PEEK_TOKEN__',
        authenticationToken || '',
      )
      response.writeHead(200, {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
        'content-security-policy': contentSecurityPolicy,
      })
      return response.end(html)
    }

    const publicFiles = ['/client.js', '/style.css', '/katex.min.css']
    if (request.method === 'GET' && publicFiles.includes(url.pathname)) {
      const path = resolve(distributionDirectory, url.pathname.slice(1))
      return streamFile(response, path, {
        'content-type': contentTypes[extname(path)] || 'application/octet-stream',
        'cache-control': 'no-cache',
      })
    }

    if (request.method === 'GET' && /^\/chunks\/[\w.-]+\.js$/.test(url.pathname)) {
      const path = resolve(distributionDirectory, url.pathname.slice(1))
      return streamFile(response, path, {
        'content-type': 'text/javascript; charset=utf-8',
        'cache-control': 'public, max-age=31536000, immutable',
      })
    }

    if (request.method === 'GET' && url.pathname.startsWith('/fonts/')) {
      const path = resolve(distributionDirectory, 'fonts', basename(url.pathname))
      return streamFile(response, path, {
        'content-type': 'font/woff2',
        'cache-control': 'public, max-age=31536000, immutable',
      })
    }

    if (request.method === 'GET' && url.pathname === '/asset') {
      if (!isAuthorized(request, url)) {
        return sendJson(response, 401, { ok: false, error: 'unauthorized' })
      }

      const requestedPath = url.searchParams.get('path')
      if (!requestedPath || requestedPath.includes('\0') || !currentDocument.path) {
        return sendJson(response, 400, { ok: false, error: 'invalid asset path' })
      }

      try {
        const assetPath = resolveDocumentAssetPath(currentDocument.path, requestedPath)
        if (!statSync(assetPath).isFile()) {
          return sendJson(response, 404, { ok: false, error: 'asset not found' })
        }

        return streamFile(response, assetPath, {
          'content-type':
            contentTypes[extname(assetPath).toLowerCase()] || 'application/octet-stream',
          'cache-control': 'no-cache',
        })
      } catch (error) {
        if (error instanceof AssetOutsideDocumentDirectoryError) {
          return sendJson(response, 403, { ok: false, error: error.message })
        }
        return sendJson(response, 404, { ok: false, error: 'asset not found' })
      }
    }

    if (request.method === 'GET' && url.pathname === '/events') {
      if (!isAuthorized(request, url)) {
        return sendJson(response, 401, { ok: false, error: 'unauthorized' })
      }

      response.writeHead(200, {
        'content-type': 'application/x-ndjson',
        'cache-control': 'no-store',
        connection: 'keep-alive',
      })
      response.write('\n')
      editorSubscribers.add(response)
      request.on('close', () => editorSubscribers.delete(response))
      return
    }

    const acceptsDocumentUpdate =
      request.method === 'POST' && ['/render', '/cursor'].includes(url.pathname)
    if (acceptsDocumentUpdate) {
      if (!isAuthorized(request, url)) {
        return sendJson(response, 401, { ok: false, error: 'unauthorized' })
      }

      return handleDocumentUpdate(request, response, url.pathname)
    }

    return sendJson(response, 404, { ok: false, error: 'not found' })
  })

  const websocketServer = new WebSocketServer({ noServer: true })
  server.on('upgrade', (request, socket, head) => {
    const url = new URL(request.url || '/', `http://${request.headers.host}`)
    if (!isLoopbackRequest(request) || url.pathname !== '/ws' || !isAuthorized(request, url)) {
      return socket.destroy()
    }

    websocketServer.handleUpgrade(request, socket, head, (browserSocket) => {
      websocketServer.emit('connection', browserSocket)
    })
  })

  websocketServer.on('connection', (browserSocket) => {
    browserSockets.add(browserSocket)
    browserSocket.send(
      JSON.stringify({ type: 'init', config: previewConfig, document: currentDocument }),
    )
    browserSocket.on('message', (rawMessage) => {
      try {
        const message = parseBrowserMessage(JSON.parse(rawMessage.toString()))
        if (message.type === 'jump') {
          emitToEditors({ type: 'jump', line: message.line })
          return
        }

        if (!currentDocument.path) {
          throw new Error('cannot open a link without an active Markdown document')
        }

        const pathWithoutAnchor = message.href.split('#', 1)[0].split('?', 1)[0]
        if (pathWithoutAnchor && !/^[a-z][a-z\d+.-]*:/i.test(pathWithoutAnchor)) {
          emitToEditors({
            type: 'open_file',
            path: resolve(dirname(currentDocument.path), pathWithoutAnchor),
          })
        }
      } catch (error) {
        browserSocket.send(JSON.stringify({ type: 'error', error: errorMessage(error) }))
      }
    })
    browserSocket.on('close', () => browserSockets.delete(browserSocket))
  })

  server.on('close', () => {
    editorLines?.close()
    for (const browserSocket of browserSockets) {
      browserSocket.close()
    }
    for (const editorSubscriber of editorSubscribers) {
      editorSubscriber.end()
    }
    websocketServer.close()
  })

  return server
}

if (import.meta.main) {
  const server = createServer({
    editorInput: process.stdin,
    onEditorEvent(message) {
      process.stdout.write(`MD_PEEK_EVENT=${JSON.stringify(message)}\n`)
    },
  })
  server.listen(Number(process.env.MD_PEEK_PORT || 0), '127.0.0.1', () => {
    const address = server.address()
    if (address && typeof address !== 'string') {
      process.stdout.write(`MD_PEEK_URL=http://127.0.0.1:${address.port}/\n`)
    }
  })
}
