import { article } from './dom.js'
import { state } from './state.js'

let mathRendererPromise

function mightContainMath(markdown) {
  return markdown.includes('$') || markdown.includes('\\(') || markdown.includes('\\[')
}

export async function renderMath(markdown) {
  if (!state.config.math || !mightContainMath(markdown)) {
    return
  }

  try {
    mathRendererPromise ||= import('katex/contrib/auto-render').then((module) => module.default)
    const renderMathInElement = await mathRendererPromise
    renderMathInElement(article, {
      delimiters: [
        { left: '$$', right: '$$', display: true },
        { left: '\\[', right: '\\]', display: true },
        { left: '\\(', right: '\\)', display: false },
        { left: '$', right: '$', display: false },
      ],
      throwOnError: false,
      ignoredClasses: ['mermaid', 'code-block'],
    })
  } catch (error) {
    console.error('[md-peek] math rendering failed', error)
  }
}
