import { existsSync, realpathSync } from 'node:fs'
import { dirname, extname, isAbsolute, relative, resolve, sep } from 'node:path'

/** Which files a document may pull in with relative links such as `![](images/logo.png)`. */
export interface AssetSandboxConfig {
  /** Trust everything up to the enclosing git repository root, not just the document's folder. */
  allowGitRoot: boolean
  /** An explicit root directory; takes precedence over `allowGitRoot`. */
  customRoot?: string
  /** Lower-case extensions, with the dot, that may be served. Everything else is refused. */
  allowedExtensions: ReadonlySet<string>
}

export const defaultAssetExtensions: ReadonlySet<string> = new Set([
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.avif',
  '.svg',
  '.ico',
  '.bmp',
  '.pdf',
  '.mp4',
  '.webm',
  '.ogg',
  '.mp3',
  '.wav',
])

export const defaultAssetSandbox: AssetSandboxConfig = {
  allowGitRoot: false,
  allowedExtensions: defaultAssetExtensions,
}

export class AssetOutsideRootError extends Error {
  constructor() {
    super('asset path escapes the allowed directory')
    this.name = 'AssetOutsideRootError'
  }
}

export class AssetTypeNotAllowedError extends Error {
  constructor(extension: string) {
    super(`asset type not allowed: ${extension || '(no extension)'}`)
    this.name = 'AssetTypeNotAllowedError'
  }
}

function findGitRoot(documentDirectory: string): string {
  let current = documentDirectory
  while (true) {
    if (existsSync(resolve(current, '.git'))) {
      return current
    }
    const parent = dirname(current)
    if (parent === current) {
      return documentDirectory
    }
    current = parent
  }
}

function assetRoot(documentDirectory: string, sandbox: AssetSandboxConfig): string {
  if (sandbox.customRoot) {
    return realpathSync(sandbox.customRoot)
  }
  return sandbox.allowGitRoot ? findGitRoot(documentDirectory) : documentDirectory
}

/**
 * Resolves a link target to a real file that is inside the sandbox and of an allowed type.
 * Symlinks are followed first, so both checks apply to where the file really lives.
 */
export function resolveDocumentAssetPath(
  documentPath: string,
  requestedPath: string,
  sandbox: AssetSandboxConfig = defaultAssetSandbox,
): string {
  const documentDirectory = realpathSync(dirname(documentPath))
  const root = assetRoot(documentDirectory, sandbox)
  const unresolvedAssetPath = resolve(documentDirectory, requestedPath.split(/[?#]/, 1)[0])
  const assetPath = realpathSync(unresolvedAssetPath)
  const pathFromRoot = relative(root, assetPath)
  const escapesRoot =
    pathFromRoot === '..' || pathFromRoot.startsWith(`..${sep}`) || isAbsolute(pathFromRoot)

  if (escapesRoot) {
    throw new AssetOutsideRootError()
  }

  const extension = extname(assetPath).toLowerCase()
  if (!sandbox.allowedExtensions.has(extension)) {
    throw new AssetTypeNotAllowedError(extension)
  }

  return assetPath
}
