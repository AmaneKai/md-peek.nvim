import { article, documentTitle, sourceCode } from '../dom.js'
import type { PreviewDocument } from '../model.js'
import { store } from '../store.js'
import { revealLine, sourceLineNodes } from '../sync.js'
import { buildToc } from '../toc.js'
import { applyVisibility } from '../visibility.js'
import { enrich } from './enrich.js'
import { LatestTaskQueue } from './render-work.js'
import { parseMarkdown } from './parse.js'
import { patchSurface } from './patch.js'
import { sanitizeHtml } from './sanitize.js'

/**
 * One render, as a pipeline: parse -> sanitize -> patch -> enrich -> recalculate.
 * Each stage lives in its own module; this only runs them in order.
 */
async function draw(document_: PreviewDocument): Promise<void> {
  const { config, rawVisible, cursorLine } = store.getState()
  const previousScroll = window.scrollY

  sourceCode.textContent = document_.content
  documentTitle.textContent = document_.path.split(/[\\/]/).pop() || 'Markdown'
  document.title = `md-peek:${location.port} ${documentTitle.textContent}`

  const html = sanitizeHtml(parseMarkdown(document_.content, config), config)
  const { inserted } = patchSurface(article, html)
  applyVisibility(document_.content.trim() === '', rawVisible)

  await enrich(inserted, config)

  // Recalculate everything that depends on the final DOM.
  buildToc()
  sourceLineNodes()
  if (config.preserve_scroll) {
    window.scrollTo({ top: previousScroll })
  }
  revealLine(cursorLine, !config.preserve_scroll || previousScroll === 0)
}

// Only the newest document matters: renders that pile up while one is running collapse to one.
const queue = new LatestTaskQueue<PreviewDocument>(
  async (document_) => {
    store.dispatch({ type: 'RENDER_STARTED' })
    try {
      await draw(document_)
      store.dispatch({ type: 'RENDER_FINISHED', payload: document_ })
    } catch (error) {
      store.dispatch({ type: 'RENDER_FAILED' })
      throw error
    }
  },
  () => new Promise((resolve) => setTimeout(resolve, 0)),
)

export function renderDocument(document_: PreviewDocument): Promise<void> {
  store.dispatch({ type: 'DOCUMENT_RECEIVED', payload: document_ })
  return queue.enqueue(store.getState().document)
}
