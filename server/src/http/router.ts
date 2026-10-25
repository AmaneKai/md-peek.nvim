import http from 'node:http'
import { isLoopbackRequest } from '../core/security.js'
import { sendJson } from './respond.js'

export interface RouterOptions {
  authorize: (request: http.IncomingMessage, url: URL) => boolean
  servePage: (response: http.ServerResponse) => void
  serveFile: (response: http.ServerResponse, pathname: string) => boolean
  serveAsset: (response: http.ServerResponse, url: URL) => void
}

/** Maps requests to handlers. Only the page and `/asset` need the session token. */
export function createRouter(options: RouterOptions): http.RequestListener {
  const route: http.RequestListener = (request, response) => {
    if (!isLoopbackRequest(request)) {
      return sendJson(response, 403, { ok: false, error: 'loopback host required' })
    }

    const url = new URL(request.url || '/', `http://${request.headers.host}`)
    if (request.method !== 'GET') {
      return sendJson(response, 404, { ok: false, error: 'not found' })
    }

    if (url.pathname === '/' || url.pathname === '/asset') {
      if (!options.authorize(request, url)) {
        return sendJson(response, 401, { ok: false, error: 'unauthorized' })
      }
      return url.pathname === '/' ? options.servePage(response) : options.serveAsset(response, url)
    }

    if (!options.serveFile(response, url.pathname)) {
      return sendJson(response, 404, { ok: false, error: 'not found' })
    }
  }

  // A handler that throws (say, a missing index.html) must answer 500, never take the server down.
  return (request, response) => {
    try {
      route(request, response)
    } catch {
      if (response.headersSent) {
        response.destroy()
      } else {
        sendJson(response, 500, { ok: false, error: 'internal error' })
      }
    }
  }
}
