import { statSync } from 'node:fs'
import { extname } from 'node:path'
import {
  type AssetSandboxConfig,
  AssetOutsideRootError,
  AssetTypeNotAllowedError,
  resolveDocumentAssetPath,
} from './asset-path.js'
import type http from 'node:http'
import { contentTypes, sendJson, streamFile } from './respond.js'

export interface AssetHandlerOptions {
  /** Path of the document currently being previewed; empty when there is none. */
  getDocumentPath: () => string
  sandbox: AssetSandboxConfig
}

/** Serves `/asset?path=...` for files a document links to, inside the sandbox only. */
export function createAssetHandler(options: AssetHandlerOptions) {
  return (response: http.ServerResponse, url: URL): void => {
    const requestedPath = url.searchParams.get('path')
    const documentPath = options.getDocumentPath()
    if (!requestedPath || requestedPath.includes('\0') || !documentPath) {
      return sendJson(response, 400, { ok: false, error: 'invalid asset path' })
    }

    try {
      const assetPath = resolveDocumentAssetPath(documentPath, requestedPath, options.sandbox)
      if (!statSync(assetPath).isFile()) {
        return sendJson(response, 404, { ok: false, error: 'asset not found' })
      }

      return streamFile(response, assetPath, {
        'content-type':
          contentTypes[extname(assetPath).toLowerCase()] || 'application/octet-stream',
        'cache-control': 'no-cache',
        // A linked SVG or PDF must never run as a page of its own if someone navigates to it.
        'x-content-type-options': 'nosniff',
        'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'; sandbox",
      })
    } catch (error) {
      if (error instanceof AssetOutsideRootError || error instanceof AssetTypeNotAllowedError) {
        return sendJson(response, 403, { ok: false, error: error.message })
      }
      return sendJson(response, 404, { ok: false, error: 'asset not found' })
    }
  }
}
