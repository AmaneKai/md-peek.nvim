import { dirname, extname, resolve } from 'node:path'

const markdownExtensions = new Set(['.md', '.markdown', '.mdx'])

function decodeLinkPath(path: string): string {
  try {
    return decodeURIComponent(path)
  } catch {
    return path
  }
}

/**
 * Turns a link clicked in the preview into a Markdown file path for the editor to open.
 * Returns undefined for links that are not local files (URLs, bare `#anchors`). Links in rendered
 * HTML are untrusted input, so anything that is not a Markdown file is refused.
 */
export function resolveMarkdownLink(documentPath: string, href: string): string | undefined {
  if (!documentPath) {
    throw new Error('cannot open a link without an active Markdown document')
  }

  const pathWithoutAnchor = decodeLinkPath(href.split('#', 1)[0].split('?', 1)[0])
  if (!pathWithoutAnchor || /^[a-z][a-z\d+.-]*:/i.test(pathWithoutAnchor)) {
    return undefined
  }

  const target = resolve(dirname(documentPath), pathWithoutAnchor)
  if (!markdownExtensions.has(extname(target).toLowerCase())) {
    throw new Error(`refusing to open non-Markdown link target: ${pathWithoutAnchor}`)
  }
  return target
}
