import { PassThrough } from 'node:stream'
import { describe, expect, it, vi } from 'vitest'
import { WebSocket } from 'ws'
import {
  firstMessage,
  start,
  startWithDocument,
  useServerCleanup,
  wsUrl,
  type InitialPreviewMessage,
} from './test-support.js'

useServerCleanup()

type Event = Record<string, unknown>

async function harness() {
  const events: Event[] = []
  const editorInput = new PassThrough()
  const url = await start({ editorInput, onEditorEvent: (event) => events.push(event as Event) })
  const send = (value: unknown) => editorInput.write(`${JSON.stringify(value)}\n`)
  return { url, events, editorInput, send }
}

/** A browser socket that records everything it receives. */
async function browser(url: string) {
  const messages: Event[] = []
  const socket = new WebSocket(wsUrl(url))
  socket.on('message', (data) => messages.push(JSON.parse(data.toString()) as Event))
  await new Promise<void>((resolve, reject) => {
    socket.once('open', () => resolve())
    socket.once('error', reject)
  })
  await vi.waitFor(() => expect(messages.length).toBeGreaterThan(0)) // the init message
  return { socket, messages }
}

const document = (content = '# Hi', path = '/notes/a.md', line = 1) => ({ content, path, line })

describe('editor channel', () => {
  it('ignores blank lines', async () => {
    const { url, events, editorInput, send } = await harness()
    editorInput.write('\n\n   \n')
    send({ type: 'render', document: document() })
    await vi.waitFor(async () =>
      expect((await firstMessage(url)).document.path).toBe('/notes/a.md'),
    )
    expect(events.filter((event) => event.type === 'error').length).toBe(1) // only the spaces line
  })

  it('reports malformed JSON and keeps working afterwards', async () => {
    const { url, events, editorInput, send } = await harness()
    editorInput.write('{not json}\n')
    await vi.waitFor(() => expect(events[0]).toMatchObject({ type: 'error' }))

    send({ type: 'render', document: document('# After', '/notes/after.md') })
    await vi.waitFor(async () =>
      expect((await firstMessage(url)).document.path).toBe('/notes/after.md'),
    )
  })

  it('rejects unknown types and invalid shapes without changing the document', async () => {
    const { url, events, send } = await harness()
    send({ type: 'render', document: document('# Good', '/notes/good.md') })
    await vi.waitFor(async () =>
      expect((await firstMessage(url)).document.path).toBe('/notes/good.md'),
    )

    send({ type: 'explode' })
    send({ type: 'render', document: { content: 42, path: '/x.md', line: 1 } })
    send({ type: 'render', document: { path: '/x.md' } })
    send({ type: 'cursor', line: 0 })
    send({ type: 'cursor', line: 'abc' })
    send({ type: 'cursor' })
    send(null)
    send([1, 2])
    await vi.waitFor(() => expect(events.length).toBe(8))
    expect(events.every((event) => event.type === 'error')).toBe(true)

    const init = await firstMessage(url)
    expect(init.document).toEqual(document('# Good', '/notes/good.md'))
  })

  it('reassembles a message split across writes', async () => {
    const { url, editorInput } = await harness()
    const line = JSON.stringify({
      type: 'render',
      document: document('# Split', '/notes/split.md'),
    })
    editorInput.write(line.slice(0, 20))
    editorInput.write(line.slice(20, 45))
    editorInput.write(`${line.slice(45)}\n`)
    await vi.waitFor(async () =>
      expect((await firstMessage(url)).document.path).toBe('/notes/split.md'),
    )
  })

  it('accepts several messages in one chunk, and CRLF line endings', async () => {
    const { url, editorInput } = await harness()
    const first = JSON.stringify({ type: 'render', document: document('# One', '/notes/one.md') })
    const second = JSON.stringify({ type: 'cursor', line: 7 })
    editorInput.write(`${first}\r\n${second}\r\n`)
    await vi.waitFor(async () => {
      const init = await firstMessage(url)
      expect(init.document).toMatchObject({ path: '/notes/one.md', line: 7 })
    })
  })

  it('handles a multi-megabyte document and unicode content', async () => {
    const { url, send } = await harness()
    const content = `# Big\n\n${'日本語の行 🎉 '.repeat(2000)}\n`.repeat(70)
    expect(content.length).toBeGreaterThan(1_000_000)
    send({ type: 'render', document: document(content, '/notes/big.md') })
    await vi.waitFor(async () => {
      const init = await firstMessage(url)
      expect(init.document.content).toBe(content)
    })
  })

  it('keeps serving after the editor closes its end', async () => {
    const { url, editorInput, send } = await harness()
    send({ type: 'render', document: document('# Last', '/notes/last.md') })
    await vi.waitFor(async () =>
      expect((await firstMessage(url)).document.path).toBe('/notes/last.md'),
    )

    editorInput.end()
    await new Promise((resolve) => setTimeout(resolve, 50))
    expect((await fetch(`${url}/`)).status).toBe(200)
    expect((await firstMessage(url)).document.path).toBe('/notes/last.md')
  })

  it('broadcasts renders and cursor moves to every connected browser', async () => {
    const { url, send } = await harness()
    const one = await browser(url)
    const two = await browser(url)

    send({ type: 'render', document: document('# Shared', '/notes/s.md'), sent_at: 123 })
    send({ type: 'cursor', line: 9 })
    for (const { messages } of [one, two]) {
      await vi.waitFor(() => expect(messages.length).toBe(3))
      expect(messages[1]).toMatchObject({ type: 'render', sent_at: 123 })
      expect(messages[2]).toEqual({ type: 'cursor', line: 9 })
    }
    one.socket.close()
    two.socket.close()
  })

  it('tells a browser that connects later about the latest cursor line', async () => {
    const { url, send } = await harness()
    send({ type: 'render', document: document('# C', '/notes/c.md') })
    send({ type: 'cursor', line: 12 })
    await vi.waitFor(async () => expect((await firstMessage(url)).document.line).toBe(12))
  })
})

describe('browser messages', () => {
  it('answers malformed and unknown messages with an error and stays connected', async () => {
    const { url } = await harness()
    const { socket, messages } = await browser(url)

    socket.send('not json at all')
    socket.send(JSON.stringify({ type: 'nope' }))
    socket.send(JSON.stringify({ type: 'jump', line: 0 }))
    socket.send(JSON.stringify({ type: 'jump' }))
    socket.send(JSON.stringify({ type: 'toggle_task', line: -4 }))
    socket.send(JSON.stringify({ type: 'open_file', href: '' }))
    await vi.waitFor(() => expect(messages.length).toBe(7))
    expect(messages.slice(1).every((message) => message.type === 'error')).toBe(true)
    expect(socket.readyState).toBe(WebSocket.OPEN)
    socket.close()
  })

  it('forwards valid jumps, task toggles and render acknowledgements to the editor', async () => {
    const { url, events } = await harness()
    const { socket } = await browser(url)

    socket.send(JSON.stringify({ type: 'jump', line: '5' }))
    socket.send(JSON.stringify({ type: 'toggle_task', line: 3 }))
    socket.send(JSON.stringify({ type: 'rendered', latency_ms: 12.5 }))
    socket.send(JSON.stringify({ type: 'rendered' }))
    await vi.waitFor(() => expect(events.length).toBe(4))
    expect(events).toEqual([
      { type: 'jump', line: 5 },
      { type: 'toggle_task', line: 3 },
      { type: 'rendered', latency_ms: 12.5 },
      { type: 'rendered' },
    ])
    socket.close()
  })

  it('cannot open a link before a document exists', async () => {
    const { url, events } = await harness()
    const { socket, messages } = await browser(url)
    socket.send(JSON.stringify({ type: 'open_file', href: 'other.md' }))
    await vi.waitFor(() => expect(messages.length).toBe(2))
    expect(messages[1]).toMatchObject({ type: 'error' })
    expect(events).toEqual([])
    socket.close()
  })

  it('opens Markdown links, and ignores URLs and anchors silently', async () => {
    const { url, events, send } = await harness()
    send({ type: 'render', document: document('#', '/notes/index.md') })
    await vi.waitFor(async () =>
      expect((await firstMessage(url)).document.path).toBe('/notes/index.md'),
    )
    const { socket, messages } = await browser(url)

    socket.send(JSON.stringify({ type: 'open_file', href: 'https://example.com/page.md' }))
    socket.send(JSON.stringify({ type: 'open_file', href: '#section' }))
    socket.send(JSON.stringify({ type: 'open_file', href: 'next.md#top' }))
    await vi.waitFor(() => expect(events.length).toBe(1))
    expect(events[0]).toEqual({ type: 'open_file', path: '/notes/next.md' })
    expect(messages.filter((message) => message.type === 'error')).toEqual([])
    socket.close()
  })

  it('refuses to hand non-Markdown targets to the editor', async () => {
    const { url, events, send } = await harness()
    send({ type: 'render', document: document('#', '/notes/index.md') })
    await vi.waitFor(async () =>
      expect((await firstMessage(url)).document.path).toBe('/notes/index.md'),
    )
    const { socket, messages } = await browser(url)

    for (const href of ['../../etc/passwd', '/etc/hosts', 'run.sh', 'photo.png']) {
      socket.send(JSON.stringify({ type: 'open_file', href }))
    }
    await vi.waitFor(() => expect(messages.length).toBe(5))
    expect(events).toEqual([])
    socket.close()
  })

  it('survives a browser that disconnects mid-conversation', async () => {
    const { url, send } = await harness()
    const { socket } = await browser(url)
    socket.terminate()
    send({ type: 'render', document: document('# Still fine', '/notes/fine.md') })
    await vi.waitFor(async () =>
      expect((await firstMessage(url)).document.path).toBe('/notes/fine.md'),
    )
  })
})

describe('first document', () => {
  it('starts empty, so a browser opened too early shows an empty state', async () => {
    const url = await start()
    const init: InitialPreviewMessage = await firstMessage(url)
    expect(init.document).toEqual({ content: '', path: '', line: 1 })
  })

  it('reuses startWithDocument safely across servers', async () => {
    const { url } = await startWithDocument(document('# Two', '/notes/two.md'))
    expect((await firstMessage(url)).document.path).toBe('/notes/two.md')
  })
})
