import { readFileSync } from 'node:fs'
import type http from 'node:http'
import { basename, extname, resolve } from 'node:path'
import { contentTypes, streamFile } from './respond.js'

export interface StaticHandlerOptions {
  /** Directory holding index.html and the bundled client. */
  directory: string
  token: string | undefined
  contentSecurityPolicy: string
}

const publicFiles = new Set(['/client.js', '/mermaid.js', '/style.css', '/katex.min.css'])

/** The page itself and the files it loads: the bundle, styles, lazy chunks and KaTeX fonts. */
export function createStaticHandler(options: StaticHandlerOptions) {
  function servePage(response: http.ServerResponse): void {
    const html = readFileSync(resolve(options.directory, 'index.html'), 'utf8').replace(
      '__MD_PEEK_TOKEN__',
      options.token || '',
    )
    response.writeHead(200, {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      'content-security-policy': options.contentSecurityPolicy,
    })
    response.end(html)
  }

  /** Handles `pathname` and returns true, or returns false if it is not a static file. */
  function serveFile(response: http.ServerResponse, pathname: string): boolean {
    if (publicFiles.has(pathname)) {
      const path = resolve(options.directory, pathname.slice(1))
      streamFile(response, path, {
        'content-type': contentTypes[extname(path)] || 'application/octet-stream',
        'cache-control': 'no-cache',
      })
      return true
    }

    if (/^\/chunks\/[\w.-]+\.js$/.test(pathname)) {
      streamFile(response, resolve(options.directory, pathname.slice(1)), {
        'content-type': 'text/javascript; charset=utf-8',
        'cache-control': 'public, max-age=31536000, immutable',
      })
      return true
    }

    if (pathname.startsWith('/fonts/')) {
      streamFile(response, resolve(options.directory, 'fonts', basename(pathname)), {
        'content-type': 'font/woff2',
        'cache-control': 'public, max-age=31536000, immutable',
      })
      return true
    }

    return false
  }

  return { servePage, serveFile }
}
