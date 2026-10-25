import { article } from './dom.js'
import { chooseScrollBehavior } from './scroll.js'
import { store } from './store.js'
import { setActiveToc } from './toc.js'

interface SourceNode {
  node: HTMLElement
  line: number
}

// Caches of the current DOM, rebuilt after every render; they are not application state.
let sourceNodes: SourceNode[] = []
let activeNode: HTMLElement | undefined
let lastScrollTime = Number.NEGATIVE_INFINITY
let lastScrollLine = 0

/** Indexes every element that carries a source line, in line order. */
export function sourceLineNodes(): void {
  sourceNodes = [...article.querySelectorAll<HTMLElement>('[data-source-line]')]
    .map((node) => ({ node, line: Number(node.dataset.sourceLine) }))
    .filter((entry) => Number.isFinite(entry.line))
    .sort((a, b) => a.line - b.line)
}

/** Highlights the rendered block for a source line, and optionally scrolls it into view. */
export function revealLine(line: number, shouldScroll = true): void {
  const { rawVisible, tocEntries, config } = store.getState()
  if (sourceNodes.length === 0 || rawVisible) {
    return
  }

  let match = sourceNodes[0]
  for (const entry of sourceNodes) {
    if (entry.line > line) {
      break
    }

    match = entry
  }

  if (activeNode !== match.node) {
    activeNode?.classList.remove('active-source')
    activeNode = match.node
    activeNode.classList.add('active-source')
  }

  let activeHeading = tocEntries[0]
  for (const entry of tocEntries) {
    if (entry.line > line) {
      break
    }

    activeHeading = entry
  }

  if (activeHeading) {
    setActiveToc(activeHeading.heading)
  }

  if (shouldScroll && config.scroll_sync) {
    const now = performance.now()
    match.node.scrollIntoView({
      behavior: chooseScrollBehavior({
        now,
        lastTime: lastScrollTime,
        line,
        lastLine: lastScrollLine,
      }),
      block: 'center',
    })
    lastScrollTime = now
    lastScrollLine = line
  }
}

/** Follows the editor's cursor: every move highlights the matching block. */
export function initSync(): void {
  store.subscribe((_state, _previous, action) => {
    if (action.type === 'CURSOR_MOVED') {
      revealLine(action.payload)
    }
  })
}
