import http from 'node:http'
import { timingSafeEqual } from 'node:crypto'

export function buildContentSecurityPolicy(allowRemoteImages: boolean): string {
  return [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    `img-src 'self' data:${allowRemoteImages ? ' http: https:' : ''}`,
    "font-src 'self'",
    // The page only ever talks to this loopback server, never to an arbitrary ws: host.
    "connect-src 'self' ws://127.0.0.1:* ws://localhost:*",
    "object-src 'none'",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join('; ')
}

export function isLoopbackRequest(request: http.IncomingMessage): boolean {
  try {
    const hostname = new URL(`http://${request.headers.host}`).hostname
    return hostname === '127.0.0.1' || hostname === 'localhost' || hostname === '[::1]'
  } catch {
    return false
  }
}

// Browsers always send Origin on WebSocket handshakes, so a page on another origin that can
// reach the loopback port is rejected even before the token is checked.
export function isSameOrigin(request: http.IncomingMessage): boolean {
  const origin = request.headers.origin
  if (origin === undefined) {
    return true
  }

  try {
    return new URL(origin).host === request.headers.host
  } catch {
    return false
  }
}

/** Accepts the session token from a header or query string; no configured token allows all. */
export function createAuthorizer(token: string | undefined) {
  const tokenBytes = token ? Buffer.from(token, 'utf8') : undefined

  function tokenMatches(candidate: string | string[] | null | undefined): boolean {
    if (typeof candidate !== 'string' || !tokenBytes) {
      return false
    }

    const candidateBytes = Buffer.from(candidate, 'utf8')
    return (
      candidateBytes.length === tokenBytes.length && timingSafeEqual(candidateBytes, tokenBytes)
    )
  }

  return (request: http.IncomingMessage, url: URL): boolean => {
    if (!tokenBytes) {
      return true
    }

    return (
      tokenMatches(request.headers['x-md-peek-token']) ||
      tokenMatches(url.searchParams.get('token'))
    )
  }
}
