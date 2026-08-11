import { existsSync, realpathSync } from 'node:fs'
import { dirname, isAbsolute, relative, resolve, sep } from 'node:path'

export class AssetOutsideDocumentDirectoryError extends Error {
  constructor() {
    super('asset path escapes the document directory')
    this.name = 'AssetOutsideDocumentDirectoryError'
  }
}

// Assets are trusted up to the enclosing git repository root (e.g. a `docs/`
// page referencing a sibling `../images/`), falling back to the document's
// own directory when it isn't inside a repository.
function findAssetRoot(documentDirectory: string): string {
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

export function resolveDocumentAssetPath(documentPath: string, requestedPath: string): string {
  const documentDirectory = realpathSync(dirname(documentPath))
  const assetRoot = findAssetRoot(documentDirectory)
  const unresolvedAssetPath = resolve(documentDirectory, requestedPath.split(/[?#]/, 1)[0])
  const assetPath = realpathSync(unresolvedAssetPath)
  const pathFromAssetRoot = relative(assetRoot, assetPath)
  const escapesAssetRoot =
    pathFromAssetRoot === '..' ||
    pathFromAssetRoot.startsWith(`..${sep}`) ||
    isAbsolute(pathFromAssetRoot)

  if (escapesAssetRoot) {
    throw new AssetOutsideDocumentDirectoryError()
  }

  return assetPath
}
