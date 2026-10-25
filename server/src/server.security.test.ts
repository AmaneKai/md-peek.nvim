import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs'
import http from 'node:http'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { WebSocket } from 'ws'
import {
  firstMessage,
  start,
  startWithDocument,
  temporaryDirectories,
  useServerCleanup,
  wsUrl,
} from './test-support.js'

useServerCleanup()

const token = 'a-long-random-session-token'

function documentWithAssets() {
  const root = mkdtempSync(join(tmpdir(), 'md-peek-http-'))
  temporaryDirectories.push(root)
  mkdirSync(join(root, 'docs'))
  writeFileSync(join(root, 'docs', 'README.md'), '# Doc')
  writeFileSync(join(root, 'docs', 'pic.png'), 'png bytes')
  writeFileSync(join(root, 'docs', 'secret.json'), '{"key":1}')
  return { path: join(root, 'docs', 'README.md'), content: '# Doc', line: 1 }
}

/** Sends a raw request so headers like Host can be forged. */
function rawRequest(url: string, path: string, headers: Record<string, string> = {}) {
  const target = new URL(url)
  return new Promise<{ status: number | undefined; body: string }>((resolve, reject) => {
    const request = http.request(
      { hostname: target.hostname, port: target.port, path, headers },
      (response) => {
        let body = ''
        response.on('data', (chunk: Buffer) => (body += chunk.toString()))
        response.on('end', () => resolve({ status: response.statusCode, body }))
      },
    )
    request.on('error', reject)
    request.end()
  })
}

describe('asset endpoint', () => {
  it('serves allowed media with hardening headers', async () => {
    const { url } = await startWithDocument(documentWithAssets())
    const response = await fetch(`${url}/asset?path=pic.png`)
    expect(response.status).toBe(200)
    expect(await response.text()).toBe('png bytes')
    expect(response.headers.get('content-type')).toBe('image/png')
    expect(response.headers.get('x-content-type-options')).toBe('nosniff')
    expect(response.headers.get('content-security-policy')).toContain('sandbox')
  })

  it('refuses types outside the whitelist', async () => {
    const { url } = await startWithDocument(documentWithAssets())
    const response = await fetch(`${url}/asset?path=secret.json`)
    expect(response.status).toBe(403)
    expect(await response.text()).not.toContain('key')
  })

  it('rejects empty, null-byte and traversal paths', async () => {
    const { url } = await startWithDocument(documentWithAssets())
    expect((await fetch(`${url}/asset`)).status).toBe(400)
    expect((await fetch(`${url}/asset?path=`)).status).toBe(400)
    expect((await fetch(`${url}/asset?path=pic.png%00.txt`)).status).toBe(400)
    for (const path of ['../pic.png', '%2e%2e/pic.png', '/etc/hosts', '..%2f..%2fetc%2fhosts']) {
      const response = await fetch(`${url}/asset?path=${path}`)
      expect([403, 404], path).toContain(response.status)
    }
  })

  it('answers 404 for missing files and 4xx for directories, never 200', async () => {
    const { url } = await startWithDocument(documentWithAssets())
    expect((await fetch(`${url}/asset?path=missing.png`)).status).toBe(404)
    expect((await fetch(`${url}/asset?path=.`)).status).toBeGreaterThanOrEqual(400)
  })

  it('answers 400 when no document is open yet', async () => {
    const url = await start()
    expect((await fetch(`${url}/asset?path=pic.png`)).status).toBe(400)
  })

  it('serves files elsewhere in the repository only when asset_root is "git"', async () => {
    const root = mkdtempSync(join(tmpdir(), 'md-peek-http-git-'))
    temporaryDirectories.push(root)
    mkdirSync(join(root, '.git'))
    mkdirSync(join(root, 'docs'))
    mkdirSync(join(root, 'images'))
    writeFileSync(join(root, 'images', 'logo.png'), 'logo')
    const document = { path: join(root, 'docs', 'README.md'), content: '#', line: 1 }
    writeFileSync(document.path, '#')
    const link = `/asset?path=${encodeURIComponent('../images/logo.png')}`

    const strict = await startWithDocument(document)
    expect((await fetch(`${strict.url}${link}`)).status).toBe(403)

    const open = await startWithDocument(
      document,
      {},
      { MD_PEEK_CONFIG: JSON.stringify({ asset_root: 'git' }) },
    )
    const response = await fetch(`${open.url}${link}`)
    expect(response.status).toBe(200)
    expect(await response.text()).toBe('logo')
  })
})

describe('session token', () => {
  const secured = { MD_PEEK_TOKEN: token }

  it('protects the page and the asset endpoint', async () => {
    const { url } = await startWithDocument(documentWithAssets(), {}, secured)
    for (const path of ['/', '/asset?path=pic.png']) {
      expect((await fetch(`${url}${path}`)).status).toBe(401)
      const sep = path.includes('?') ? '&' : '?'
      expect((await fetch(`${url}${path}${sep}token=${token}`)).status).toBe(200)
      expect((await fetch(`${url}${path}`, { headers: { 'x-md-peek-token': token } })).status).toBe(
        200,
      )
    }
  })

  it('rejects wrong tokens of the same and of a different length', async () => {
    const url = await start({}, secured)
    for (const wrong of [token.replace('a', 'b'), 'short', token + 'x', '']) {
      expect((await fetch(`${url}/?token=${wrong}`)).status).toBe(401)
    }
  })

  it('injects the token into the page it serves', async () => {
    const url = await start({}, secured)
    const html = await (await fetch(`${url}/?token=${token}`)).text()
    expect(html).toContain(token)
    expect(html).not.toContain('__MD_PEEK_TOKEN__')
  })

  it('needs the token for WebSocket connections too', async () => {
    const url = await start({}, secured)
    const outcome = (query: string, headers: Record<string, string> = {}) =>
      new Promise<string>((resolve) => {
        const socket = new WebSocket(wsUrl(url, query), { headers })
        socket.once('open', () => {
          socket.close()
          resolve('open')
        })
        socket.once('error', () => resolve('rejected'))
      })

    expect(await outcome('')).toBe('rejected')
    expect(await outcome('?token=wrong')).toBe('rejected')
    expect(await outcome(`?token=${token}`)).toBe('open')
    expect(await outcome('', { 'x-md-peek-token': token })).toBe('open')
    await expect(firstMessage(url, `?token=${token}`)).resolves.toMatchObject({ type: 'init' })
  })

  it('serves the bundle files without a token, since they contain nothing private', async () => {
    const url = await start({}, secured)
    expect((await fetch(`${url}/style.css`)).status).not.toBe(401)
  })
})

describe('request validation', () => {
  it('rejects spoofed Host headers', async () => {
    const url = await start()
    for (const host of ['example.com', 'localhost.evil.com', '127.0.0.1.evil.com:80']) {
      const { status } = await rawRequest(url, '/', { host })
      expect(status, host).toBe(403)
    }
  })

  it('accepts the loopback names', async () => {
    const url = await start()
    const port = new URL(url).port
    for (const host of [`127.0.0.1:${port}`, `localhost:${port}`]) {
      expect((await rawRequest(url, '/', { host })).status, host).toBe(200)
    }
  })

  it('only answers GET', async () => {
    const url = await start()
    for (const method of ['POST', 'PUT', 'DELETE']) {
      expect((await fetch(`${url}/`, { method })).status).toBe(404)
    }
    expect((await fetch(`${url}/render`, { method: 'POST', body: '{}' })).status).toBe(404)
  })

  it('does not serve unknown paths, traversal out of the bundle, or other chunk names', async () => {
    const url = await start()
    for (const path of ['/nope', '/chunks/../index.html', '/chunks/a/b.js', '/fonts/../x']) {
      const { status } = await rawRequest(url, path)
      expect([403, 404], path).toContain(status)
    }
  })

  it('answers 500, and stays up, when a handler throws', async () => {
    const url = await start({ staticDirectory: join(tmpdir(), 'md-peek-no-such-directory') })
    expect((await fetch(`${url}/`)).status).toBe(500)
    expect((await fetch(`${url}/nope`)).status).toBe(404)
  })

  it('rejects WebSocket upgrades on the wrong path or from a foreign origin', async () => {
    const url = await start()
    const outcome = (target: string, headers: Record<string, string> = {}) =>
      new Promise<string>((resolve) => {
        const socket = new WebSocket(target, { headers })
        socket.once('open', () => {
          socket.close()
          resolve('open')
        })
        socket.once('error', () => resolve('rejected'))
      })

    expect(await outcome(url.replace('http', 'ws') + '/not-ws')).toBe('rejected')
    expect(await outcome(wsUrl(url), { origin: 'https://evil.example' })).toBe('rejected')
    expect(await outcome(wsUrl(url), { origin: url })).toBe('open')
  })
})
