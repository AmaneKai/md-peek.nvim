import { realpathSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

/**
 * True when this file is the program being run, not something imported. Node added
 * `import.meta.main` in 22.18 and 24.2; on an older release it is undefined, and a server that
 * only starts under that flag would exit at once without ever listening. Falling back to
 * comparing the script path keeps it working there too.
 */
export function isMainModule(
  meta: { main?: boolean; url: string },
  entryScript: string | undefined = process.argv[1],
): boolean {
  if (meta.main !== undefined) {
    return meta.main
  }
  if (!entryScript) {
    return false
  }

  try {
    return realpathSync(fileURLToPath(meta.url)) === realpathSync(entryScript)
  } catch {
    return false
  }
}
