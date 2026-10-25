import http from 'node:http'
import { dirname } from 'node:path'
import { createInterface } from 'node:readline'
import type { Readable } from 'node:stream'
import { fileURLToPath } from 'node:url'
import { createAssetHandler } from '../http/asset-handler.js'
import { type AssetSandboxConfig, defaultAssetExtensions } from '../http/asset-path.js'
import { createRouter } from '../http/router.js'
import { createStaticHandler } from '../http/static-handler.js'
import { parseEditorMessage, parsePreviewConfig, type PreviewDocument } from '../protocol.js'
import { createGateway } from '../ws/gateway.js'
import { resolveMarkdownLink } from './links.js'
import { isMainModule } from './main-module.js'
import { buildContentSecurityPolicy, createAuthorizer } from './security.js'

export type { PreviewDocument } from '../protocol.js'

const distributionDirectory = dirname(fileURLToPath(import.meta.url))
const initialDocument: PreviewDocument = { content: '', path: '', line: 1 }

export interface PreviewServerOptions {
  /** Where index.html and the bundles live; defaults to the directory this file runs from. */
  staticDirectory?: string
  /** Editor messages arrive here as one JSON object per line (Neovim's stdin). */
  editorInput?: Readable
  /** Receives events for the editor: jump, open_file, toggle_task, rendered, error. */
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

function assetSandbox(config: Record<string, unknown>): AssetSandboxConfig {
  const root = config.asset_root
  const extensions = config.asset_extensions
  return {
    allowGitRoot: root === 'git',
    customRoot:
      typeof root === 'string' && root !== 'git' && root !== 'document' ? root : undefined,
    allowedExtensions: Array.isArray(extensions)
      ? new Set(extensions.map((extension) => String(extension).toLowerCase()))
      : defaultAssetExtensions,
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}

/** Wires the HTTP routes, the browser gateway and the editor channel into one server. */
export function createServer(options: PreviewServerOptions = {}) {
  let currentDocument = { ...initialDocument }
  const token = process.env.MD_PEEK_TOKEN
  const authorize = createAuthorizer(token)
  const previewConfig = loadPreviewConfig()

  const emitToEditors = (message: unknown) => options.onEditorEvent?.(message)

  const gateway = createGateway({
    authorize,
    getInit: () => ({ type: 'init', config: previewConfig, document: currentDocument }),
    onMessage(message) {
      switch (message.type) {
        case 'jump':
        case 'toggle_task':
          emitToEditors({ type: message.type, line: message.line })
          break
        case 'rendered':
          emitToEditors({ type: 'rendered', latency_ms: message.latency_ms })
          break
        case 'open_file': {
          const path = resolveMarkdownLink(currentDocument.path, message.href)
          if (path) {
            emitToEditors({ type: 'open_file', path })
          }
          break
        }
      }
    },
  })

  function applyEditorMessage(value: unknown): void {
    const message = parseEditorMessage(value)
    if (message.type === 'render') {
      currentDocument = message.document
      gateway.broadcast({ type: 'render', document: currentDocument, sent_at: message.sent_at })
      return
    }

    currentDocument.line = message.line
    gateway.broadcast({ type: 'cursor', line: currentDocument.line })
  }

  const editorLines = options.editorInput
    ? createInterface({ input: options.editorInput })
    : undefined
  editorLines?.on('line', (line) => {
    if (line === '') {
      return
    }
    try {
      applyEditorMessage(JSON.parse(line))
    } catch (error) {
      emitToEditors({ type: 'error', error: errorMessage(error) })
    }
  })

  const staticFiles = createStaticHandler({
    directory: options.staticDirectory ?? distributionDirectory,
    token,
    contentSecurityPolicy: buildContentSecurityPolicy(previewConfig.remote_images !== false),
  })
  const serveAsset = createAssetHandler({
    getDocumentPath: () => currentDocument.path,
    sandbox: assetSandbox(previewConfig),
  })

  const server = http.createServer(
    createRouter({
      authorize,
      servePage: staticFiles.servePage,
      serveFile: staticFiles.serveFile,
      serveAsset,
    }),
  )
  server.on('upgrade', gateway.handleUpgrade)
  server.on('close', () => {
    editorLines?.close()
    gateway.close()
  })

  return server
}

if (isMainModule(import.meta)) {
  const server = createServer({
    editorInput: process.stdin,
    // Every stdout line is one JSON object, so Neovim never has to guess what a line means.
    onEditorEvent(message) {
      process.stdout.write(`${JSON.stringify(message)}\n`)
    },
  })
  // Neovim owns this process; when it goes away (even abruptly) stdin ends, so exit instead of
  // lingering as an orphaned listener.
  process.stdin.on('end', () => process.exit(0))
  server.listen(Number(process.env.MD_PEEK_PORT || 0), '127.0.0.1', () => {
    const address = server.address()
    if (address && typeof address !== 'string') {
      const ready = { type: 'ready', port: address.port, url: `http://127.0.0.1:${address.port}/` }
      process.stdout.write(`${JSON.stringify(ready)}\n`)
    }
  })
}
