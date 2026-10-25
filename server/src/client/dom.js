export const token = document.querySelector('meta[name="md-peek-token"]')?.content || ''

function requiredElement(identifier) {
  const element = document.getElementById(identifier)

  if (!element) {
    throw new Error(`[md-peek] missing required element: #${identifier}`)
  }

  return element
}

export const article = requiredElement('document')
export const source = requiredElement('source')
export const sourceCode = source.querySelector('code')

if (!sourceCode) {
  throw new Error('[md-peek] missing source code element')
}

export const emptyState = requiredElement('empty')
export const toc = requiredElement('toc')
export const tocContent = requiredElement('toc-content')
export const tocResizer = requiredElement('toc-resizer')
export const status = requiredElement('status')
export const documentTitle = requiredElement('document-title')
export const rawToggle = requiredElement('raw-toggle')
export const lightbox = requiredElement('lightbox')
export const diagramViewer = requiredElement('diagram-viewer')
export const diagramViewport = requiredElement('diagram-viewport')
export const diagramCanvas = requiredElement('diagram-canvas')
export const diagramZoomLevel = requiredElement('diagram-zoom-level')
export const toastElement = requiredElement('toast')
