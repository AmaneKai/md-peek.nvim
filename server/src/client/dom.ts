export const token =
  document.querySelector<HTMLMetaElement>('meta[name="md-peek-token"]')?.content ?? ''

function requiredElement<T extends HTMLElement = HTMLElement>(identifier: string): T {
  const element = document.getElementById(identifier)

  if (!element) {
    throw new Error(`[md-peek] missing required element: #${identifier}`)
  }

  return element as T
}

export const article = requiredElement('document')
export const source = requiredElement('source')
const sourceCodeElement = source.querySelector('code')

if (!sourceCodeElement) {
  throw new Error('[md-peek] missing source code element')
}

export const sourceCode: HTMLElement = sourceCodeElement

export const emptyState = requiredElement('empty')
export const toc = requiredElement('toc')
export const tocContent = requiredElement('toc-content')
export const tocResizer = requiredElement('toc-resizer')
export const status = requiredElement('status')
export const documentTitle = requiredElement('document-title')
export const rawToggle = requiredElement('raw-toggle')
export const lightbox = requiredElement<HTMLDialogElement>('lightbox')
export const diagramViewer = requiredElement<HTMLDialogElement>('diagram-viewer')
export const diagramViewport = requiredElement('diagram-viewport')
export const diagramCanvas = requiredElement('diagram-canvas')
export const diagramZoomLevel = requiredElement('diagram-zoom-level')
export const toastElement = requiredElement('toast')

/** Looks up an element that index.html is known to contain. */
export function byId<T extends HTMLElement = HTMLElement>(identifier: string): T {
  return requiredElement<T>(identifier)
}
