import { describe, expect, it, vi } from 'vitest'
import { defaults } from './model.js'
import { initialState, reduce, Store } from './store.js'

const document = { content: '# Hi', path: '/a.md', line: 4 }

describe('reduce', () => {
  it('is pure: it never mutates the state it is given', () => {
    const state = initialState()
    const frozen = Object.freeze({ ...state })
    const next = reduce(frozen, { type: 'RAW_TOGGLED' })
    expect(next.rawVisible).toBe(true)
    expect(frozen.rawVisible).toBe(false)
  })

  it('takes the cursor from a received document', () => {
    const next = reduce(initialState(), { type: 'DOCUMENT_RECEIVED', payload: document })
    expect(next.document).toEqual(document)
    expect(next.cursorLine).toBe(4)
  })

  it('keeps every copy of the cursor line in step', () => {
    let state = reduce(initialState(), { type: 'DOCUMENT_RECEIVED', payload: document })
    state = reduce(state, { type: 'RENDER_FINISHED', payload: document })
    state = reduce(state, { type: 'CURSOR_MOVED', payload: 9 })
    expect([state.cursorLine, state.document.line, state.rendered.line]).toEqual([9, 9, 9])
  })

  it('tracks rendering from start to finish', () => {
    let state = reduce(initialState(), { type: 'RENDER_STARTED' })
    expect(state.rendering).toBe(true)
    state = reduce(state, { type: 'RENDER_FINISHED', payload: document })
    expect(state.rendering).toBe(false)
    expect(state.rendered.content).toBe('# Hi')
  })

  it('resets mermaid initialisation when the theme changes', () => {
    let state = reduce(initialState(), { type: 'MERMAID_INITIALIZED' })
    expect(state.mermaidInitialized).toBe(true)
    state = reduce(state, { type: 'MERMAID_THEME_CHANGED' })
    expect(state.mermaidInitialized).toBe(false)
  })

  it('opens and closes the viewers', () => {
    const element = { tagName: 'div' } as unknown as Element
    let state = reduce(initialState(), { type: 'DIAGRAM_OPENED', payload: element })
    expect(state.diagram).toBe(element)
    state = reduce(state, { type: 'DIAGRAM_CLOSED' })
    expect(state.diagram).toBeUndefined()
    state = reduce(state, { type: 'IMAGE_ZOOMED', payload: 'a.png' })
    expect(state.zoomedImage).toBe('a.png')
    state = reduce(state, { type: 'IMAGE_ZOOM_CLOSED' })
    expect(state.zoomedImage).toBeUndefined()
  })

  it('replaces the config wholesale', () => {
    const config = { ...defaults, theme: 'github' }
    expect(reduce(initialState(), { type: 'CONFIG_UPDATED', payload: config }).config.theme).toBe(
      'github',
    )
  })
})

describe('Store', () => {
  it('notifies subscribers with the new and previous state and the action', () => {
    const store = new Store()
    const listener = vi.fn()
    store.subscribe(listener)

    store.dispatch({ type: 'RAW_TOGGLED' })

    expect(listener).toHaveBeenCalledTimes(1)
    const [state, previous, action] = listener.mock.calls[0]
    expect(state.rawVisible).toBe(true)
    expect(previous.rawVisible).toBe(false)
    expect(action).toEqual({ type: 'RAW_TOGGLED' })
    expect(store.getState().rawVisible).toBe(true)
  })

  it('stops notifying once unsubscribed', () => {
    const store = new Store()
    const listener = vi.fn()
    const unsubscribe = store.subscribe(listener)
    unsubscribe()
    store.dispatch({ type: 'RAW_TOGGLED' })
    expect(listener).not.toHaveBeenCalled()
  })

  it('lets a listener dispatch without breaking the others', () => {
    const store = new Store()
    const seen: string[] = []
    store.subscribe((_state, _previous, action) => {
      seen.push(action.type)
      if (action.type === 'RAW_TOGGLED') {
        store.dispatch({ type: 'RENDER_STARTED' })
      }
    })
    store.subscribe((_state, _previous, action) => seen.push(`second:${action.type}`))

    store.dispatch({ type: 'RAW_TOGGLED' })

    expect(store.getState()).toMatchObject({ rawVisible: true, rendering: true })
    expect(seen).toContain('RENDER_STARTED')
    expect(seen).toContain('second:RAW_TOGGLED')
  })
})
