import { article } from './dom.js'
import { state } from './state.js'
import { setActiveToc } from './toc.js'

export function sourceLineNodes() {
  state.sourceNodes = [...article.querySelectorAll(':scope > [data-source-line]')]
    .map((node) => ({ node, line: Number(node.dataset.sourceLine) }))
    .filter((entry) => Number.isFinite(entry.line))
    .sort((a, b) => a.line - b.line)
}

/** Highlights the rendered block for a source line, and optionally scrolls it into view. */
export function revealLine(line, shouldScroll = true) {
  if (!state.sourceNodes.length || state.rawVisible) {
    return
  }

  let match = state.sourceNodes[0]
  for (const entry of state.sourceNodes) {
    if (entry.line > line) {
      break
    }

    match = entry
  }

  if (state.activeNode !== match.node) {
    state.activeNode?.classList.remove('active-source')
    state.activeNode = match.node
    state.activeNode.classList.add('active-source')
  }

  let activeHeading = state.tocEntries[0]
  for (const entry of state.tocEntries) {
    if (entry.line > line) {
      break
    }

    activeHeading = entry
  }

  if (activeHeading) {
    setActiveToc(activeHeading.heading)
  }

  if (shouldScroll && state.config.scroll_sync) {
    match.node.scrollIntoView({ behavior: 'smooth', block: 'center' })
  }
}
