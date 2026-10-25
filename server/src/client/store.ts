import { defaults, type PreviewConfig, type PreviewDocument, type TocEntry } from './model.js'

/**
 * Everything the page needs to remember. The only way to change it is to dispatch an action;
 * modules that care about a change subscribe instead of reaching into each other.
 */
export interface PageState {
  config: PreviewConfig
  /** The newest document the editor sent. */
  document: PreviewDocument
  /** The document the page last finished drawing. */
  rendered: PreviewDocument
  cursorLine: number
  rawVisible: boolean
  rendering: boolean
  mermaidInitialized: boolean
  tocEntries: readonly TocEntry[]
  /** The diagram open in the full-screen viewer, if any. */
  diagram: Element | undefined
  /** The image open in the lightbox, if any. */
  zoomedImage: string | undefined
}

export type Action =
  | { type: 'CONFIG_UPDATED'; payload: PreviewConfig }
  | { type: 'DOCUMENT_RECEIVED'; payload: PreviewDocument }
  | { type: 'CURSOR_MOVED'; payload: number }
  | { type: 'RENDER_STARTED' }
  | { type: 'RENDER_FINISHED'; payload: PreviewDocument }
  | { type: 'RENDER_FAILED' }
  | { type: 'TOC_UPDATED'; payload: readonly TocEntry[] }
  | { type: 'RAW_TOGGLED' }
  | { type: 'MERMAID_INITIALIZED' }
  | { type: 'MERMAID_THEME_CHANGED' }
  | { type: 'DIAGRAM_OPENED'; payload: Element }
  | { type: 'DIAGRAM_CLOSED' }
  | { type: 'IMAGE_ZOOMED'; payload: string }
  | { type: 'IMAGE_ZOOM_CLOSED' }

const emptyDocument: PreviewDocument = { content: '', path: '', line: 1 }

export function initialState(): PageState {
  return {
    config: { ...defaults },
    document: emptyDocument,
    rendered: emptyDocument,
    cursorLine: 1,
    rawVisible: false,
    rendering: false,
    mermaidInitialized: false,
    tocEntries: [],
    diagram: undefined,
    zoomedImage: undefined,
  }
}

/** Pure: the same state and action always give the same next state. */
export function reduce(state: PageState, action: Action): PageState {
  switch (action.type) {
    case 'CONFIG_UPDATED':
      return { ...state, config: action.payload }
    case 'DOCUMENT_RECEIVED':
      return { ...state, document: action.payload, cursorLine: action.payload.line }
    case 'CURSOR_MOVED':
      return {
        ...state,
        cursorLine: action.payload,
        document: { ...state.document, line: action.payload },
        rendered: { ...state.rendered, line: action.payload },
      }
    case 'RENDER_STARTED':
      return { ...state, rendering: true }
    case 'RENDER_FINISHED':
      return {
        ...state,
        rendering: false,
        rendered: { ...action.payload, line: state.cursorLine },
      }
    case 'RENDER_FAILED':
      return { ...state, rendering: false }
    case 'TOC_UPDATED':
      return { ...state, tocEntries: action.payload }
    case 'RAW_TOGGLED':
      return { ...state, rawVisible: !state.rawVisible }
    case 'MERMAID_INITIALIZED':
      return { ...state, mermaidInitialized: true }
    case 'MERMAID_THEME_CHANGED':
      return { ...state, mermaidInitialized: false }
    case 'DIAGRAM_OPENED':
      return { ...state, diagram: action.payload }
    case 'DIAGRAM_CLOSED':
      return { ...state, diagram: undefined }
    case 'IMAGE_ZOOMED':
      return { ...state, zoomedImage: action.payload }
    case 'IMAGE_ZOOM_CLOSED':
      return { ...state, zoomedImage: undefined }
  }
}

export type Listener = (state: PageState, previous: PageState, action: Action) => void

export class Store {
  private current: PageState
  private readonly listeners = new Set<Listener>()

  constructor(initial: PageState = initialState()) {
    this.current = initial
  }

  getState(): Readonly<PageState> {
    return this.current
  }

  dispatch(action: Action): void {
    const previous = this.current
    this.current = reduce(previous, action)
    for (const listener of [...this.listeners]) {
      listener(this.current, previous, action)
    }
  }

  /** Returns a function that removes the listener. */
  subscribe(listener: Listener): () => void {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }
}

export const store = new Store()
