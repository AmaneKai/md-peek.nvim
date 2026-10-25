import type { PreviewConfig } from '../model.js'
import { lightScheme } from '../settings.js'
import { store } from '../store.js'
import { selectWithin } from './scope.js'

type Mermaid = typeof import('mermaid').default

// Built as a separate asset by build.mjs; see mermaid-bundle.ts.
const MERMAID_URL = '/mermaid.js'

let mermaidPromise: Promise<Mermaid> | undefined

/** Draws diagrams in the given blocks that have not been drawn yet. */
export async function renderMermaidDiagrams(
  scope: readonly Element[],
  config: PreviewConfig,
): Promise<void> {
  if (!config.mermaid) {
    return
  }

  const diagrams = selectWithin<HTMLElement>(scope, '.mermaid:not([data-processed])')
  if (diagrams.length === 0) {
    return
  }

  mermaidPromise ||= import(MERMAID_URL).then((module: { default: Mermaid }) => module.default)
  const mermaid = await mermaidPromise
  if (!store.getState().mermaidInitialized) {
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: lightScheme() ? 'default' : 'dark',
    })
    store.dispatch({ type: 'MERMAID_INITIALIZED' })
  }

  try {
    await mermaid.run({ nodes: diagrams, suppressErrors: true })
  } catch (error) {
    console.error('[md-peek] Mermaid rendering failed', error)
  }
}
