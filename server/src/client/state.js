export const defaults = {
  theme: 'dark',
  toc: true,
  toc_open: false,
  math: true,
  mermaid: true,
  emoji: true,
  raw_toggle: true,
  code_copy: true,
  scroll_sync: true,
  preserve_scroll: true,
  breaks: false,
  linkify: true,
  typographer: false,
  allow_html: true,
  sanitize: true,
  max_width: 920,
  colors: {},
  font: {},
  custom_css: '',
}

const emptyDocument = { content: '', path: '', line: 1 }

// The one place mutable page state lives, so modules can share it without import cycles.
export const state = {
  config: { ...defaults },
  currentDocument: emptyDocument,
  latestDocument: emptyDocument,
  rawVisible: false,
  mermaidInitialized: false,
  sourceNodes: [],
  activeNode: undefined,
  tocEntries: [],
  rendering: false,
  latestCursorLine: 1,
}
