import { realpathSync } from 'node:fs'
import { dirname, isAbsolute, relative, resolve, sep } from 'node:path'

export class AssetOutsideDocumentDirectoryError extends Error {
  constructor() {
    super('asset path escapes the document directory')
    this.name = 'AssetOutsideDocumentDirectoryError'
  }
}

export function resolveDocumentAssetPath(documentPath: string, requestedPath: string): string {
  const documentDirectory = realpathSync(dirname(documentPath))
  const unresolvedAssetPath = resolve(documentDirectory, requestedPath.split(/[?#]/, 1)[0])
  const assetPath = realpathSync(unresolvedAssetPath)
  const pathFromDocumentDirectory = relative(documentDirectory, assetPath)
  const escapesDocumentDirectory =
    pathFromDocumentDirectory === '..' ||
    pathFromDocumentDirectory.startsWith(`..${sep}`) ||
    isAbsolute(pathFromDocumentDirectory)

  if (escapesDocumentDirectory) {
    throw new AssetOutsideDocumentDirectoryError()
  }

  return assetPath
}
