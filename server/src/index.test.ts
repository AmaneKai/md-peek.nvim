import { afterEach, describe, expect, it, vi } from 'vitest'
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import http from 'node:http'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { PassThrough } from 'node:stream'
import { WebSocket } from 'ws'
import { createServer, type PreviewDocument, type PreviewServerOptions } from './server.js'

interface InitialPreviewMessage {
  type: 'init'
  document: PreviewDocument
}

let live: http.Server | undefined
const temporaryDirectories: string[] = []

afterEach(async () => {
  if (live?.listening) {
    await new Promise<void>((resolve) => live!.close(() => resolve()))
  }
  live = undefined
  for (const temporaryDirectory of temporaryDirectories.splice(0)) {
    rmSync(temporaryDirectory, { recursive: true, force: true })
  }
})

async function start(options: PreviewServerOptions = {}) {
  const server = createServer(options)
  live = server
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
  const address = server.address()
  if (!address || typeof address === 'string') {
    throw new Error('missing server address')
  }
  return `http://127.0.0.1:${address.port}`
}

// Documents reach the server only through the editor channel (Neovim's stdin).
async function startWithDocument(document: PreviewDocument, options: PreviewServerOptions = {}) {
  const editorInput = new PassThrough()
  const url = await start({ editorInput, ...options })
  editorInput.write(`${JSON.stringify({ type: 'render', document })}\n`)
  // The server consumes stdin asynchronously; wait until a fresh client sees the document.
  for (let attempt = 0; attempt < 50; attempt++) {
    const init = await new Promise<InitialPreviewMessage>((resolve, reject) => {
      const socket = new WebSocket(url.replace('http', 'ws') + '/ws')
      socket.once('message', (value) => {
        resolve(JSON.parse(value.toString()) as InitialPreviewMessage)
        socket.close()
      })
      socket.once('error', reject)
    })
    if (init.document.path === document.path) {
      return { url, editorInput }
    }
    await new Promise((resolve) => setTimeout(resolve, 10))
  }
  throw new Error('server did not apply the document')
}

describe('preview server', () => {
  it('gives new websocket clients the latest document', async () => {
    const document = { content: '# Hello', path: '/tmp/readme.md', line: 1 }
    const { url, editorInput } = await startWithDocument(document)

    const message = await new Promise<InitialPreviewMessage>((resolve, reject) => {
      const socket = new WebSocket(url.replace('http', 'ws') + '/ws')
      socket.once('message', (value) => {
        resolve(JSON.parse(value.toString()) as InitialPreviewMessage)
        socket.close()
      })
      socket.once('error', reject)
    })
    expect(message.type).toBe('init')
    expect(message.document).toEqual(document)
    editorInput.destroy()
  })

  it('uses persistent editor input and output for bidirectional updates', async () => {
    const editorInput = new PassThrough()
    let receiveEditorEvent: ((message: unknown) => void) | undefined
    const editorEvent = new Promise<unknown>((resolve) => {
      receiveEditorEvent = resolve
    })
    const url = await start({
      editorInput,
      onEditorEvent(message) {
        receiveEditorEvent?.(message)
      },
    })
    const socket = new WebSocket(url.replace('http', 'ws') + '/ws')
    await new Promise<void>((resolve, reject) => {
      socket.once('message', () => resolve())
      socket.once('error', reject)
    })

    const document = { content: '# From stdin', path: '/tmp/stdin.md', line: 4 }
    const browserUpdate = new Promise<Record<string, unknown>>((resolve, reject) => {
      socket.once('message', (value) => resolve(JSON.parse(value.toString())))
      socket.once('error', reject)
    })
    editorInput.write(`${JSON.stringify({ type: 'render', document })}\n`)
    await expect(browserUpdate).resolves.toEqual({ type: 'render', document })

    socket.send(JSON.stringify({ type: 'jump', line: 8 }))
    await expect(editorEvent).resolves.toEqual({ type: 'jump', line: 8 })
    socket.close()
    editorInput.destroy()
  })

  it('decodes percent-encoded Markdown link targets for the editor', async () => {
    const events: unknown[] = []
    const { url, editorInput } = await startWithDocument(
      { content: '', path: '/notes/index.md', line: 1 },
      { onEditorEvent: (event) => events.push(event) },
    )
    const socket = new WebSocket(url.replace('http', 'ws') + '/ws')
    await new Promise<void>((resolve) => socket.once('open', () => resolve()))
    socket.send(JSON.stringify({ type: 'open_file', href: 'my%20notes.md#top' }))

    await vi.waitFor(() =>
      expect(events).toEqual([{ type: 'open_file', path: '/notes/my notes.md' }]),
    )
    socket.close()
    editorInput.destroy()
  })

  it('refuses link targets that are not Markdown files', async () => {
    const events: unknown[] = []
    const { url, editorInput } = await startWithDocument(
      { content: '', path: '/notes/index.md', line: 1 },
      { onEditorEvent: (event) => events.push(event) },
    )
    const socket = new WebSocket(url.replace('http', 'ws') + '/ws')
    await new Promise<void>((resolve) => socket.once('message', () => resolve()))
    const reply = new Promise<Record<string, unknown>>((resolve) =>
      socket.once('message', (value) => resolve(JSON.parse(value.toString()))),
    )
    socket.send(JSON.stringify({ type: 'open_file', href: '../../etc/hosts' }))

    await expect(reply).resolves.toMatchObject({ type: 'error' })
    expect(events).toEqual([])
    socket.close()
    editorInput.destroy()
  })

  it('rejects WebSocket handshakes from a foreign origin', async () => {
    const url = await start()
    const outcome = await new Promise<string>((resolve) => {
      const socket = new WebSocket(url.replace('http', 'ws') + '/ws', {
        headers: { origin: 'https://evil.example' },
      })
      socket.once('open', () => resolve('open'))
      socket.once('error', () => resolve('rejected'))
    })
    expect(outcome).toBe('rejected')
  })

  it('serves a CSP without a wildcard ws: and honours remote_images', async () => {
    const original = process.env.MD_PEEK_CONFIG
    process.env.MD_PEEK_CONFIG = JSON.stringify({ remote_images: false })
    try {
      const url = await start()
      const csp = (await fetch(`${url}/`)).headers.get('content-security-policy') ?? ''
      expect(csp).toContain("img-src 'self' data:;")
      expect(csp).not.toMatch(/connect-src[^;]*\sws:(\s|;|$)/)
    } finally {
      if (original === undefined) {
        delete process.env.MD_PEEK_CONFIG
      } else {
        process.env.MD_PEEK_CONFIG = original
      }
    }
  })

  it('reports malformed persistent editor messages', async () => {
    const editorInput = new PassThrough()
    const editorEvent = new Promise<unknown>((resolve) => {
      void start({ editorInput, onEditorEvent: resolve })
    })

    editorInput.write('{not-json}\n')

    await expect(editorEvent).resolves.toMatchObject({ type: 'error' })
    editorInput.destroy()
  })

  it('rejects non-loopback Host headers', async () => {
    const url = await start()
    const target = new URL(url)
    const status = await new Promise<number | undefined>((resolve, reject) => {
      const request = http.request(
        {
          hostname: target.hostname,
          port: target.port,
          path: '/',
          headers: { host: 'example.com' },
        },
        (response) => {
          response.resume()
          response.on('end', () => resolve(response.statusCode))
        },
      )
      request.on('error', reject)
      request.end()
    })
    expect(status).toBe(403)
  })

  it('only serves assets contained by the document directory', async () => {
    const fixtureRoot = mkdtempSync(join(tmpdir(), 'md-peek-assets-'))
    temporaryDirectories.push(fixtureRoot)
    const documentDirectory = join(fixtureRoot, 'document')
    const documentPath = join(documentDirectory, 'README.md')
    const localAssetPath = join(documentDirectory, 'local.txt')
    const secretPath = join(fixtureRoot, 'secret.txt')
    mkdirSync(documentDirectory)
    writeFileSync(documentPath, '# Fixture')
    writeFileSync(localAssetPath, 'local asset')
    writeFileSync(secretPath, 'top secret content')
    symlinkSync(secretPath, join(documentDirectory, 'linked-secret.txt'))

    const { url } = await startWithDocument({
      content: '# Fixture',
      path: documentPath,
      line: 1,
    })

    const localAssetResponse = await fetch(`${url}/asset?path=local.txt`)
    expect(localAssetResponse.status).toBe(200)
    expect(await localAssetResponse.text()).toBe('local asset')

    const traversalResponse = await fetch(
      `${url}/asset?path=${encodeURIComponent('../secret.txt')}`,
    )
    expect(traversalResponse.status).toBe(403)
    expect(await traversalResponse.text()).not.toContain('top secret content')

    const symlinkResponse = await fetch(`${url}/asset?path=linked-secret.txt`)
    expect(symlinkResponse.status).toBe(403)
    expect(await symlinkResponse.text()).not.toContain('top secret content')
  })

  it('serves assets reached via .. when they stay inside the repository root', async () => {
    const repositoryRoot = mkdtempSync(join(tmpdir(), 'md-peek-assets-'))
    temporaryDirectories.push(repositoryRoot)
    const documentDirectory = join(repositoryRoot, 'docs')
    const documentPath = join(documentDirectory, 'README.md')
    const imagesDirectory = join(repositoryRoot, 'images')
    const imagePath = join(imagesDirectory, 'logo.png')
    const outsidePath = join(repositoryRoot, '..', 'secret.txt')
    mkdirSync(join(repositoryRoot, '.git'))
    mkdirSync(documentDirectory)
    mkdirSync(imagesDirectory)
    writeFileSync(documentPath, '# Fixture')
    writeFileSync(imagePath, 'sibling image')
    writeFileSync(outsidePath, 'top secret content')
    temporaryDirectories.push(outsidePath)

    const { url } = await startWithDocument({
      content: '# Fixture',
      path: documentPath,
      line: 1,
    })

    const siblingAssetResponse = await fetch(
      `${url}/asset?path=${encodeURIComponent('../images/logo.png')}`,
    )
    expect(siblingAssetResponse.status).toBe(200)
    expect(await siblingAssetResponse.text()).toBe('sibling image')

    const traversalResponse = await fetch(
      `${url}/asset?path=${encodeURIComponent('../../secret.txt')}`,
    )
    expect(traversalResponse.status).toBe(403)
    expect(await traversalResponse.text()).not.toContain('top secret content')
  })
})
