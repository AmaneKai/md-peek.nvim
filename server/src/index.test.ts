import { describe, expect, it, vi } from 'vitest'
import http from 'node:http'
import { PassThrough } from 'node:stream'
import { WebSocket } from 'ws'
import { firstMessage, start, startWithDocument, useServerCleanup, wsUrl } from './test-support.js'

useServerCleanup()

describe('preview server', () => {
  it('gives new websocket clients the latest document', async () => {
    const document = { content: '# Hello', path: '/tmp/readme.md', line: 1 }
    const { url, editorInput } = await startWithDocument(document)

    const message = await firstMessage(url)
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
    const socket = new WebSocket(wsUrl(url))
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
    const socket = new WebSocket(wsUrl(url))
    await new Promise<void>((resolve) => socket.once('open', () => resolve()))
    socket.send(JSON.stringify({ type: 'open_file', href: 'my%20notes.md#top' }))

    await vi.waitFor(() =>
      expect(events).toEqual([{ type: 'open_file', path: '/notes/my notes.md' }]),
    )
    socket.close()
    editorInput.destroy()
  })

  it('forwards task toggles from the browser to the editor', async () => {
    const events: unknown[] = []
    const { url, editorInput } = await startWithDocument(
      { content: '- [ ] a', path: '/notes/todo.md', line: 1 },
      { onEditorEvent: (event) => events.push(event) },
    )
    const socket = new WebSocket(wsUrl(url))
    await new Promise<void>((resolve) => socket.once('open', () => resolve()))
    socket.send(JSON.stringify({ type: 'toggle_task', line: 1 }))

    await vi.waitFor(() => expect(events).toEqual([{ type: 'toggle_task', line: 1 }]))
    socket.close()
    editorInput.destroy()
  })

  it('refuses link targets that are not Markdown files', async () => {
    const events: unknown[] = []
    const { url, editorInput } = await startWithDocument(
      { content: '', path: '/notes/index.md', line: 1 },
      { onEditorEvent: (event) => events.push(event) },
    )
    const socket = new WebSocket(wsUrl(url))
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
      const socket = new WebSocket(wsUrl(url), {
        headers: { origin: 'https://evil.example' },
      })
      socket.once('open', () => resolve('open'))
      socket.once('error', () => resolve('rejected'))
    })
    expect(outcome).toBe('rejected')
  })

  it('serves a CSP without a wildcard ws: and honours remote_images', async () => {
    const url = await start({}, { MD_PEEK_CONFIG: JSON.stringify({ remote_images: false }) })
    const csp = (await fetch(`${url}/`)).headers.get('content-security-policy') ?? ''
    expect(csp).toContain("img-src 'self' data:;")
    expect(csp).not.toMatch(/connect-src[^;]*\sws:(\s|;|$)/)
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
})
