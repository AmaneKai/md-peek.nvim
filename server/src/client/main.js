import { initDiagramViewer } from './diagram-viewer.js'
import { initInteractions } from './interactions.js'
import { renderDocument } from './render.js'
import { applyConfig } from './settings.js'
import { connect } from './socket.js'
import { defaults, state } from './state.js'
import { revealLine } from './sync.js'
import { initToc } from './toc.js'
import { initToolbar } from './toolbar.js'

initToc()
initDiagramViewer()
initToolbar()
initInteractions()

connect({
  async onInit(message) {
    state.config = { ...defaults, ...message.config }
    applyConfig()
    await renderDocument(message.document)
  },
  onRender: renderDocument,
  onCursor(line) {
    state.latestCursorLine = line
    state.latestDocument.line = line
    state.currentDocument.line = line
    revealLine(line)
  },
})
