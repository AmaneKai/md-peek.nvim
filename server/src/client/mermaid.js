import { article } from './dom.js'
import { lightScheme } from './settings.js'
import { state } from './state.js'

let mermaidPromise

export async function renderMermaidDiagrams() {
  if (!state.config.mermaid || !article.querySelector('.mermaid')) {
    return
  }

  mermaidPromise ||= import('mermaid').then((module) => module.default)
  const mermaid = await mermaidPromise
  if (!state.mermaidInitialized) {
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: lightScheme() ? 'default' : 'dark',
    })
    state.mermaidInitialized = true
  }

  try {
    const diagrams = article.querySelectorAll('.mermaid')
    await mermaid.run({ nodes: diagrams, suppressErrors: true })
  } catch (error) {
    console.error('[md-peek] Mermaid rendering failed', error)
  }
}
