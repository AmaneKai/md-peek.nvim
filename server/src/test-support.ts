import { rmSync } from 'node:fs'
import type http from 'node:http'
import { PassThrough } from 'node:stream'
import { fileURLToPath } from 'node:url'
import { afterEach } from 'vitest'
import { WebSocket } from 'ws'
import { createServer, type PreviewDocument, type PreviewServerOptions } from './core/daemon.js'

export interface InitialPreviewMessage {
  type: 'init'
  document: PreviewDocument
}

let live: http.Server | undefined
export const temporaryDirectories: string[] = []

/** Call once at the top of a test file: closes the server and removes temp files after each test. */
export function useServerCleanup(): void {
  afterEach(async () => {
    if (live?.listening) {
      live.closeAllConnections()
      await new Promise<void>((resolve) => live!.close(() => resolve()))
    }
    live = undefined
    for (const temporaryDirectory of temporaryDirectories.splice(0)) {
      rmSync(temporaryDirectory, { recursive: true, force: true })
    }
  })
}

// src/ holds an index.html, which is all the HTTP tests need from a static directory.
const sourceDirectory = fileURLToPath(new URL('.', import.meta.url))

/** Environment the server reads once, when it is created (token and preview config). */
export type ServerEnvironment = { MD_PEEK_TOKEN?: string; MD_PEEK_CONFIG?: string }

export async function start(
  options: PreviewServerOptions = {},
  environment: ServerEnvironment = {},
): Promise<string> {
  const previous = { ...process.env }
  Object.assign(process.env, environment)
  const server = (() => {
    try {
      return createServer({ staticDirectory: sourceDirectory, ...options })
    } finally {
      for (const key of Object.keys(environment)) {
        if (previous[key] === undefined) {
          delete process.env[key]
        } else {
          process.env[key] = previous[key]
        }
      }
    }
  })()
  live = server
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
  const address = server.address()
  if (!address || typeof address === 'string') {
    throw new Error('missing server address')
  }
  return `http://127.0.0.1:${address.port}`
}

export function wsUrl(url: string, query = ''): string {
  return `${url.replace('http', 'ws')}/ws${query}`
}

/** Resolves with the first message a fresh browser socket receives. */
export function firstMessage<T = InitialPreviewMessage>(
  url: string,
  query = '',
  headers: Record<string, string> = {},
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const socket = new WebSocket(wsUrl(url, query), { headers })
    socket.once('message', (value) => {
      resolve(JSON.parse(value.toString()) as T)
      socket.close()
    })
    socket.once('error', reject)
  })
}

// Documents reach the server only through the editor channel (Neovim's stdin).
export async function startWithDocument(
  document: PreviewDocument,
  options: PreviewServerOptions = {},
  environment: ServerEnvironment = {},
) {
  const editorInput = new PassThrough()
  const url = await start({ editorInput, ...options }, environment)
  editorInput.write(`${JSON.stringify({ type: 'render', document })}\n`)
  // The server consumes stdin asynchronously; wait until a fresh client sees the document.
  for (let attempt = 0; attempt < 50; attempt++) {
    const query = environment.MD_PEEK_TOKEN ? `?token=${environment.MD_PEEK_TOKEN}` : ''
    const init = await firstMessage(url, query)
    if (init.document.path === document.path) {
      return { url, editorInput }
    }
    await new Promise((resolve) => setTimeout(resolve, 10))
  }
  throw new Error('server did not apply the document')
}
