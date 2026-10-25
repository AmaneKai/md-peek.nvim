import type { PreviewConfig } from '../model.js'
import { decorateContent } from './decorate.js'
import { renderMath } from './math.js'
import { renderMermaidDiagrams } from './mermaid.js'

/**
 * Stage 5: add everything that needs the DOM to the blocks that were just inserted. Link and
 * image handling is immediate; math and diagrams load lazily and run side by side, and one
 * failing must not stop the other.
 */
export async function enrich(inserted: readonly Element[], config: PreviewConfig): Promise<void> {
  decorateContent(inserted)
  await Promise.allSettled([renderMath(inserted, config), renderMermaidDiagrams(inserted, config)])
}
