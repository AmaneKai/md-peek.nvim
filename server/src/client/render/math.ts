import type renderMathInElement from 'katex/contrib/auto-render'
import type { PreviewConfig } from '../model.js'

type RenderMath = typeof renderMathInElement

let mathRendererPromise: Promise<RenderMath> | undefined

function mightContainMath(text: string): boolean {
  return text.includes('$') || text.includes('\\(') || text.includes('\\[')
}

/** Renders KaTeX in the given blocks only; blocks without any math delimiter are skipped. */
export async function renderMath(scope: readonly Element[], config: PreviewConfig): Promise<void> {
  if (!config.math) {
    return
  }

  const blocks = scope.filter((element) => mightContainMath(element.textContent ?? ''))
  if (blocks.length === 0) {
    return
  }

  try {
    mathRendererPromise ||= import('katex/contrib/auto-render').then((module) => module.default)
    const render = await mathRendererPromise
    for (const block of blocks) {
      render(block as HTMLElement, {
        delimiters: [
          { left: '$$', right: '$$', display: true },
          { left: '\\[', right: '\\]', display: true },
          { left: '\\(', right: '\\)', display: false },
          { left: '$', right: '$', display: false },
        ],
        throwOnError: false,
        ignoredClasses: ['mermaid', 'code-block'],
      })
    }
  } catch (error) {
    console.error('[md-peek] math rendering failed', error)
  }
}
