import { type ChildProcess, spawn } from 'node:child_process'
import { existsSync, mkdtempSync, rmSync } from 'node:fs'
import type http from 'node:http'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { readFileSync } from 'node:fs'
import { PassThrough } from 'node:stream'
import { afterEach, describe, expect, it } from 'vitest'
import { WebSocket } from 'ws'
import { createServer } from './core/daemon.js'

const distribution = fileURLToPath(new URL('../dist/', import.meta.url))
const built = existsSync(join(distribution, 'client.js'))

// These drive real browsers, so each one is skipped when that browser is not installed.
function findBinary(candidates: string[]): string | undefined {
  return candidates.find((candidate) => (candidate.includes('/') ? existsSync(candidate) : false))
}

const chrome = findBinary([
  process.env.MD_PEEK_CHROME ?? '',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium-browser',
  '/usr/bin/chromium',
])
const firefox = findBinary([
  process.env.MD_PEEK_FIREFOX ?? '',
  '/Applications/Firefox.app/Contents/MacOS/firefox',
  '/usr/bin/firefox',
])

const document = [
  '# Sync',
  '',
  '- [ ] open task',
  '- [x] done task',
  '- plain item',
  '',
  '| a | b |',
  '| - | - |',
  '| 1 | 2 |',
  '| 3 | 4 |',
  '',
].join('\n')

let server: http.Server | undefined
let browser: ChildProcess | undefined
const temporaryDirectories: string[] = []

afterEach(async () => {
  if (browser && browser.exitCode === null) {
    const exited = new Promise((resolve) => browser!.once('exit', resolve))
    browser.kill('SIGKILL')
    await exited
  }
  browser = undefined
  if (server?.listening) {
    await new Promise<void>((resolve) => {
      server!.closeAllConnections()
      server!.close(() => resolve())
    })
  }
  server = undefined
  for (const directory of temporaryDirectories.splice(0)) {
    // Browser helper processes can still be flushing files for a moment after the main one exits.
    rmSync(directory, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 })
  }
})

async function startPreview(content: string = document) {
  const events: Array<Record<string, unknown>> = []
  const editorInput = new PassThrough()
  server = createServer({
    staticDirectory: distribution,
    editorInput,
    onEditorEvent: (event) => events.push(event as Record<string, unknown>),
  })
  await new Promise<void>((resolve) => server!.listen(0, '127.0.0.1', resolve))
  const address = server.address()
  if (!address || typeof address === 'string') {
    throw new Error('missing server address')
  }
  const render = { type: 'render', document: { content, path: '/tmp/e2e.md', line: 1 } }
  editorInput.write(`${JSON.stringify(render)}\n`)
  return { url: `http://127.0.0.1:${address.port}/`, events, editorInput }
}

function profileDirectory(): string {
  const directory = mkdtempSync(join(tmpdir(), 'md-peek-e2e-'))
  temporaryDirectories.push(directory)
  return directory
}

async function waitFor<T>(read: () => T | undefined | Promise<T | undefined>, timeout = 20000) {
  const deadline = Date.now() + timeout
  while (Date.now() < deadline) {
    const value = await read()
    if (value) {
      return value
    }
    await new Promise((resolve) => setTimeout(resolve, 50))
  }
  throw new Error('timed out waiting for the browser')
}

interface CdpResponse {
  id: number
  result: {
    targetId?: string
    sessionId?: string
    result?: { value?: unknown }
  }
}

/** A minimal Chrome DevTools Protocol client: just enough to open a page and run script in it. */
async function openChromePage(binary: string, url: string) {
  browser = spawn(
    binary,
    [
      '--headless=new',
      '--no-first-run',
      '--remote-debugging-port=0',
      `--user-data-dir=${profileDirectory()}`,
      'about:blank',
    ],
    { stdio: ['ignore', 'ignore', 'pipe'] },
  )
  const endpoint = await new Promise<string>((resolve, reject) => {
    let output = ''
    browser!.stderr!.on('data', (chunk: Buffer) => {
      output += chunk.toString()
      const match = output.match(/DevTools listening on (ws:\/\/\S+)/)
      if (match) {
        resolve(match[1])
      }
    })
    browser!.once('exit', () => reject(new Error('browser exited before DevTools was ready')))
  })

  const socket = new WebSocket(endpoint)
  await new Promise<void>((resolve, reject) => {
    socket.once('open', () => resolve())
    socket.once('error', reject)
  })

  let nextId = 0
  const pending = new Map<number, (value: CdpResponse) => void>()
  socket.on('message', (data) => {
    const message = JSON.parse(data.toString()) as CdpResponse
    pending.get(message.id)?.(message)
  })
  const call = (method: string, params: object = {}, sessionId?: string) =>
    new Promise<CdpResponse>((resolve) => {
      const id = ++nextId
      pending.set(id, resolve)
      socket.send(JSON.stringify({ id, method, params, sessionId }))
    })

  const { result: target } = await call('Target.createTarget', { url })
  const { result: attached } = await call('Target.attachToTarget', {
    targetId: target.targetId,
    flatten: true,
  })
  const sessionId = attached.sessionId

  return {
    async evaluate<T>(expression: string): Promise<T> {
      const response = await call(
        'Runtime.evaluate',
        { expression, returnByValue: true },
        sessionId,
      )
      return response.result.result?.value as T
    },
    close: () => socket.close(),
  }
}

/**
 * Serialises the rendered article with run-specific details removed: generated ids, and the inside
 * of diagrams, whose SVG depends on the browser's font metrics.
 */
const normalizedDocument = `(() => {
  const clone = document.getElementById('document').cloneNode(true)
  for (const diagram of clone.querySelectorAll('.mermaid')) diagram.innerHTML = '[diagram]'
  for (const node of clone.querySelectorAll('.active-source')) node.classList.remove('active-source')
  return clone.outerHTML
    .replace(/task-item-\\d+/g, 'task-item-N')
    .replaceAll('><', '>\\n<')
})()`

describe.skipIf(!chrome || !built)('preview in Chrome', () => {
  it('renders and turns clicks into editor events at item and row granularity', async () => {
    const { url, events, editorInput } = await startPreview()
    const page = await openChromePage(chrome!, url)

    await waitFor(() => page.evaluate<boolean>("!!document.querySelector('#document tr')"))
    await waitFor(() => events.find((event) => event.type === 'rendered'))

    const click = (selector: string) =>
      page.evaluate(`document.querySelector(${JSON.stringify(selector)}).click()`)
    const lastEvent = () => events.at(-1)

    // The second list item and the last table row each know their own source line.
    await click('li:nth-child(3)')
    await waitFor(() => lastEvent()?.type === 'jump')
    expect(lastEvent()).toEqual({ type: 'jump', line: 5 })

    await click('tbody tr:nth-child(2)')
    await waitFor(() => lastEvent()?.line === 10)
    expect(lastEvent()).toEqual({ type: 'jump', line: 10 })

    // A checkbox asks the editor to flip its task; it does not flip itself.
    await click('li.task-list-item input')
    await waitFor(() => lastEvent()?.type === 'toggle_task')
    expect(lastEvent()).toEqual({ type: 'toggle_task', line: 3 })
    expect(
      await page.evaluate<boolean>("document.querySelector('li.task-list-item input').checked"),
    ).toBe(false)

    page.close()
    editorInput.destroy()
  }, 60000)

  it('renders the sample document to the committed DOM snapshot', async () => {
    const sample = readFileSync(
      new URL('./client/fixtures/render-sample.md', import.meta.url),
      'utf8',
    )
    const { url, editorInput } = await startPreview(sample)
    const page = await openChromePage(chrome!, url)

    // Wait for the lazy-loaded renderers: KaTeX and the mermaid diagram.
    await waitFor(() =>
      page.evaluate<boolean>(
        "!!document.querySelector('#document .katex') && !!document.querySelector('.mermaid[data-processed]')",
      ),
    )
    const dom = await page.evaluate<string>(normalizedDocument)

    await expect(dom).toMatchFileSnapshot('./__snapshots__/render-sample.html')
    page.close()
    editorInput.destroy()
  }, 60000)

  it('patches edits in place and matches a from-scratch render after every edit', async () => {
    const sample = readFileSync(
      new URL('./client/fixtures/render-sample.md', import.meta.url),
      'utf8',
    )
    const { url, events, editorInput } = await startPreview(sample)
    const page = await openChromePage(chrome!, url)
    const renders = () => events.filter((event) => event.type === 'rendered').length
    const waitForRender = async (action: () => unknown | Promise<unknown>) => {
      const before = renders()
      await action()
      await waitFor(() => renders() > before)
    }
    const waitForDiagram = () =>
      waitFor(() =>
        page.evaluate<boolean>(
          "!!document.querySelector('#document .katex') && !!document.querySelector('.mermaid[data-processed]')",
        ),
      )
    const edit = (content: string) =>
      waitForRender(() =>
        editorInput.write(
          `${JSON.stringify({ type: 'render', document: { content, path: '/tmp/e2e.md', line: 1 } })}\n`,
        ),
      )
    const dom = () => page.evaluate<string>(normalizedDocument)

    await waitFor(() => renders() > 0 || undefined)
    await waitForDiagram()

    // Tag nodes so we can tell afterwards whether they were kept or rebuilt.
    await page.evaluate(`(() => {
      const mark = (name, node) => { node.__kept = name }
      mark('title', document.querySelector('#document h1'))
      mark('table', document.querySelector('#document table'))
      mark('diagram', document.querySelector('#document .mermaid'))
      mark('svg', document.querySelector('#document .mermaid svg'))
      mark('math', document.querySelector('#document .katex-display'))
    })()`)
    const kept = (selector: string) =>
      page.evaluate<string | null>(
        `document.querySelector(${JSON.stringify(selector)})?.__kept ?? null`,
      )

    const fresh = async () => {
      await waitForRender(() => page.evaluate('location.reload()'))
      await waitForDiagram()
      return dom()
    }

    let content = sample

    // 1. Edit one paragraph: every other block must be the very same node.
    content = content.replace('Intro paragraph with', 'Edited intro with')
    await edit(content)
    expect(
      await page.evaluate<string>("document.querySelector('#document p').textContent"),
    ).toContain('Edited intro with')
    expect(await kept('#document h1')).toBe('title')
    expect(await kept('#document table')).toBe('table')
    expect(await kept('#document .mermaid svg')).toBe('svg')
    expect(await kept('#document .katex-display')).toBe('math')
    const afterEdit = await dom()

    // 2. Insert a paragraph near the top: everything below shifts down one line, yet stays put.
    content = content.replace('# Title\n', '# Title\n\nA brand new paragraph.\n')
    await edit(content)
    expect(await kept('#document table')).toBe('table')
    expect(await kept('#document .mermaid svg')).toBe('svg')
    const afterInsert = await dom()
    expect(afterInsert).toContain('A brand new paragraph.')
    expect(afterInsert).not.toBe(afterEdit)

    // 3. Change the diagram: only that block is drawn again.
    content = content.replace('A-->B;', 'A-->C;')
    await edit(content)
    await waitFor(async () =>
      (
        await page.evaluate<string>("document.querySelector('.mermaid svg')?.textContent ?? ''")
      ).includes('C'),
    )
    expect(await kept('#document .mermaid svg')).toBeNull()
    expect(await kept('#document table')).toBe('table')

    // 4. Remove the table.
    content = content.replace(/\| a \| b \|\n\| - \| - \|\n\| 1 \| 2 \|\n\| 3 \| 4 \|\n/, '')
    await edit(content)
    expect(await page.evaluate<boolean>("!document.querySelector('#document table')")).toBe(true)
    expect(await kept('#document h1')).toBe('title')

    // After all those in-place edits the page must equal a render from scratch.
    const patched = await dom()
    expect(await fresh()).toBe(patched)

    page.close()
    editorInput.destroy()
  }, 120000)

  it('renders math that Markdown syntax used to break', async () => {
    const tricky = [
      'Stars: $a*b*c$ and $2*x + 3*y$',
      '',
      String.raw`Braces and spacing: $\{ x \}$ and $a \, b$`,
      '',
      'Underscores at the edges: $_x$ and subscripts $x_1 + x_2 = y_3$',
      '',
      'Money is not math: it costs $5 and then $10 more.',
      '',
    ].join('\n')
    const { url, editorInput } = await startPreview(tricky)
    const page = await openChromePage(chrome!, url)

    await waitFor(() => page.evaluate<boolean>("!!document.querySelector('#document .katex')"))
    const result = await page.evaluate<{
      formulas: number
      errors: number
      emphasis: number
      text: string
    }>(`({
      formulas: document.querySelectorAll('#document .katex').length,
      errors: document.querySelectorAll('#document .katex-error').length,
      emphasis: document.querySelectorAll('#document em').length,
      text: document.querySelector('#document p:last-of-type').textContent,
    })`)

    // Six formulas, none of them failing, and nothing mistaken for emphasis.
    expect(result.formulas).toBe(6)
    expect(result.errors).toBe(0)
    expect(result.emphasis).toBe(0)
    expect(result.text).toBe('Money is not math: it costs $5 and then $10 more.')

    page.close()
    editorInput.destroy()
  }, 60000)
})

describe.skipIf(!firefox || !built)('preview in Firefox', () => {
  it('loads the page, connects and renders', async () => {
    const { url, events, editorInput } = await startPreview()
    browser = spawn(
      firefox!,
      ['--headless', '--new-instance', '--profile', profileDirectory(), url],
      { stdio: 'ignore' },
    )

    // `rendered` is only sent by the page after its script ran and drew the document.
    const rendered = await waitFor(() => events.find((event) => event.type === 'rendered'), 45000)
    expect(rendered).toMatchObject({ type: 'rendered' })
    editorInput.destroy()
  }, 60000)
})
