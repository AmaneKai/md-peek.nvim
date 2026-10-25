import { initDiagramViewer } from './diagram-viewer.js'
import { initInteractions } from './interactions.js'
import { initLightbox } from './lightbox.js'
import { defaults } from './model.js'
import { renderDocument } from './render/pipeline.js'
import { initSettings } from './settings.js'
import { connect, send } from './socket.js'
import { store } from './store.js'
import { initSync } from './sync.js'
import { initToc } from './toc.js'
import { initToolbar } from './toolbar.js'

initSettings()
initSync()
initToc()
initDiagramViewer()
initLightbox()
initToolbar()
initInteractions()

connect({
  async onInit(message) {
    store.dispatch({ type: 'CONFIG_UPDATED', payload: { ...defaults, ...message.config } })
    await renderDocument(message.document)
    send({ type: 'rendered' })
  },
  async onRender(document, sentAt) {
    await renderDocument(document)
    send({ type: 'rendered', latency_ms: sentAt ? Math.max(0, Date.now() - sentAt) : undefined })
  },
  onCursor(line) {
    store.dispatch({ type: 'CURSOR_MOVED', payload: line })
  },
})
