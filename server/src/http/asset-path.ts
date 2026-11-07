import { existsSync, realpathSync } from 'node:fs'
import { dirname, extname, isAbsolute, relative, resolve, sep } from 'node:path'

/** Which files a document may pull in with relative links such as `![](images/logo.png)`. */
export interface AssetSandboxConfig {
  /** Trust everything up to the enclosing git repository root, not just the document's folder. */
  allowGitRoot: boolean
  /** An explicit root directory; takes precedence over `allowGitRoot`. */
  customRoot?: string
  /**
   * Further directories, besides the root above, that may be served from. Entries that do not
   * exist on this machine are ignored, so one config can be shared across machines.
   */
  extraRoots?: readonly string[]
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

function assetRoots(documentDirectory: string, sandbox: AssetSandboxConfig): string[] {
  const roots: string[] = []
  if (sandbox.customRoot) {
    roots.push(realpathSync(sandbox.customRoot))
  } else {
    roots.push(sandbox.allowGitRoot ? findGitRoot(documentDirectory) : documentDirectory)
  }
  for (const extra of sandbox.extraRoots ?? []) {
    try {
      roots.push(realpathSync(extra))
    } catch {
      // Missing on this machine: skip it rather than fail the whole preview.
    }
  }
  return roots
}

function isInside(root: string, path: string): boolean {
  const pathFromRoot = relative(root, path)
  return !(pathFromRoot === '..' || pathFromRoot.startsWith(`..${sep}`) || isAbsolute(pathFromRoot))
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
  const roots = assetRoots(documentDirectory, sandbox)
  const unresolvedAssetPath = resolve(documentDirectory, requestedPath.split(/[?#]/, 1)[0])
  const assetPath = realpathSync(unresolvedAssetPath)

  if (!roots.some((root) => isInside(root, assetPath))) {
    throw new AssetOutsideRootError()
  }

  const extension = extname(assetPath).toLowerCase()
  if (!sandbox.allowedExtensions.has(extension)) {
    throw new AssetTypeNotAllowedError(extension)
  }

  return assetPath
}
