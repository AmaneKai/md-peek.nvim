import DOMPurify from 'dompurify'
import { decorateContent } from './decorate.js'
import { article, documentTitle, emptyState, source, sourceCode } from './dom.js'
import { extractFrontMatter, markdownRenderer } from './markdown.js'
import { renderMath } from './math.js'
import { renderMermaidDiagrams } from './mermaid.js'
import { LatestTaskQueue } from './render-work.js'
import { revealLine, sourceLineNodes } from './sync.js'
import { state } from './state.js'
import { buildToc } from './toc.js'

async function updateRenderedDocument(documentState) {
  const { config } = state
  const previousScrollPosition = window.scrollY
  state.currentDocument = { ...documentState, line: state.latestCursorLine }
  sourceCode.textContent = documentState.content
  documentTitle.textContent = documentState.path.split(/[\\/]/).pop() || 'Markdown'
  document.title = `md-peek:${location.port} ${documentTitle.textContent}`
  const extracted = extractFrontMatter(documentState.content)
  let html =
    extracted.html + markdownRenderer(config, extracted.lineOffset).render(extracted.markdown)

  if (config.sanitize) {
    html = DOMPurify.sanitize(html, { ADD_ATTR: ['target', 'data-source-line'] })
  }

  article.innerHTML = html
  const documentIsEmpty = documentState.content.trim() === ''
  emptyState.hidden = !documentIsEmpty
  article.hidden = documentIsEmpty || state.rawVisible
  source.hidden = !state.rawVisible
  decorateContent()

  await Promise.all([renderMath(documentState.content), renderMermaidDiagrams()])

  buildToc()
  sourceLineNodes()
  if (config.preserve_scroll) {
    window.scrollTo({ top: previousScrollPosition })
  }

  revealLine(state.latestCursorLine, !config.preserve_scroll || previousScrollPosition === 0)
}

const renderQueue = new LatestTaskQueue(
  async (documentState) => {
    state.rendering = true
    try {
      await updateRenderedDocument(documentState)
    } finally {
      state.rendering = false
    }
  },
  () => new Promise((resolve) => setTimeout(resolve, 0)),
)

export async function renderDocument(documentState) {
  state.latestCursorLine = documentState.line
  state.latestDocument = { ...documentState }
  return renderQueue.enqueue(state.latestDocument)
}
