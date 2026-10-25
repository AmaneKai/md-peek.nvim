import { store } from './store.js'
import { byId, diagramCanvas, diagramViewer, diagramViewport, diagramZoomLevel } from './dom.js'

interface PanState {
  id: number
  x: number
  y: number
  startX: number
  startY: number
}

let diagramScale = 1
let diagramX = 0
let diagramY = 0
let diagramPan: PanState | null = null

function applyDiagramTransform(): void {
  diagramCanvas.style.transform = `translate(${diagramX}px, ${diagramY}px) scale(${diagramScale})`
  diagramZoomLevel.textContent = `${Math.round(diagramScale * 100)}%`
}

function diagramNaturalSize(): { width: number; height: number } {
  const svg = diagramCanvas.querySelector('svg')
  const width = Number.parseFloat(svg?.getAttribute('width') ?? '')
  const height = Number.parseFloat(svg?.getAttribute('height') ?? '')
  return { width: width || 0, height: height || 0 }
}

function fitDiagram(): void {
  const { width, height } = diagramNaturalSize()
  const rect = diagramViewport.getBoundingClientRect()
  diagramX = 0
  diagramY = 0
  diagramScale =
    width && height ? Math.min((rect.width - 64) / width, (rect.height - 64) / height, 1) : 1
  diagramScale = Math.max(diagramScale, 0.05)
  applyDiagramTransform()
}

function openDiagramViewer(block: Element): void {
  const svg = block.querySelector('svg')
  if (!svg) {
    return
  }

  const clone = svg.cloneNode(true) as SVGSVGElement
  const box = svg.viewBox?.baseVal
  if (box?.width && box?.height) {
    clone.setAttribute('width', String(box.width))
    clone.setAttribute('height', String(box.height))
  }
  clone.style.maxWidth = 'none'

  diagramCanvas.innerHTML = ''
  diagramCanvas.appendChild(clone)
  diagramViewer.showModal()
  diagramViewport.focus({ preventScroll: true })
  fitDiagram()
}

function zoomDiagramAt(clientX: number, clientY: number, factor: number): void {
  const rect = diagramViewport.getBoundingClientRect()
  const cx = clientX - rect.left - rect.width / 2
  const cy = clientY - rect.top - rect.height / 2
  const newScale = Math.min(Math.max(diagramScale * factor, 0.05), 8)
  const pointX = (cx - diagramX) / diagramScale
  const pointY = (cy - diagramY) / diagramScale
  diagramX = cx - pointX * newScale
  diagramY = cy - pointY * newScale
  diagramScale = newScale
  applyDiagramTransform()
}

function zoomDiagramAtCenter(factor: number): void {
  const rect = diagramViewport.getBoundingClientRect()
  zoomDiagramAt(rect.left + rect.width / 2, rect.top + rect.height / 2, factor)
}

function endDiagramPan(event: PointerEvent): void {
  if (diagramPan && event.pointerId === diagramPan.id) {
    diagramPan = null
    diagramViewport.classList.remove('panning')
  }
}

export function initDiagramViewer(): void {
  // Open when something asks for a diagram; tell the store when the dialog closes (Esc included).
  store.subscribe((state, previous) => {
    if (state.diagram && state.diagram !== previous.diagram) {
      openDiagramViewer(state.diagram)
    }
  })
  diagramViewer.addEventListener('close', () => store.dispatch({ type: 'DIAGRAM_CLOSED' }))

  diagramViewport.addEventListener(
    'wheel',
    (event) => {
      event.preventDefault()
      zoomDiagramAt(event.clientX, event.clientY, Math.exp(-event.deltaY * 0.0035))
    },
    { passive: false },
  )

  diagramViewport.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) {
      return
    }
    diagramPan = {
      id: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      startX: diagramX,
      startY: diagramY,
    }
    diagramViewport.setPointerCapture(event.pointerId)
    diagramViewport.classList.add('panning')
    event.preventDefault()
  })
  diagramViewport.addEventListener('pointermove', (event) => {
    if (!diagramPan || event.pointerId !== diagramPan.id) {
      return
    }
    diagramX = diagramPan.startX + (event.clientX - diagramPan.x)
    diagramY = diagramPan.startY + (event.clientY - diagramPan.y)
    applyDiagramTransform()
  })
  diagramViewport.addEventListener('pointerup', endDiagramPan)
  diagramViewport.addEventListener('pointercancel', endDiagramPan)
  diagramViewport.addEventListener('dblclick', () => fitDiagram())

  byId('diagram-zoom-in').addEventListener('click', () => zoomDiagramAtCenter(1.25))
  byId('diagram-zoom-out').addEventListener('click', () => zoomDiagramAtCenter(0.8))
  byId('diagram-zoom-fit').addEventListener('click', () => fitDiagram())
  byId('diagram-close').addEventListener('click', () => diagramViewer.close())
}
