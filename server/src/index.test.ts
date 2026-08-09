import { afterEach, describe, expect, it } from 'vitest'
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import http from 'node:http'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { WebSocket } from 'ws'
import { createServer, type PreviewDocument } from './index.js'

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

async function start() {
  const server = createServer()
  live = server
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
  const address = server.address()
  if (!address || typeof address === 'string') {
    throw new Error('missing server address')
  }
  return `http://127.0.0.1:${address.port}`
}

describe('preview server', () => {
  it('accepts a render and gives new websocket clients the latest document', async () => {
    const url = await start()
    const document = { content: '# Hello', path: '/tmp/readme.md', line: 1 }
    const response = await fetch(`${url}/render`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(document),
    })
    expect(await response.json()).toEqual({ ok: true })

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

    const url = await start()
    const renderResponse = await fetch(`${url}/render`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ content: '# Fixture', path: documentPath, line: 1 }),
    })
    expect(renderResponse.status).toBe(200)

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
})
