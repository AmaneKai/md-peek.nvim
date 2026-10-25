import type { PreviewConfig } from '../model.js'
import { extractFrontMatter, markdownRenderer } from './markdown.js'

/**
 * Stage 1-2: pull off front matter (counting its lines) and turn the rest into HTML whose
 * blocks carry `data-source-line`, so every block still maps to a line of the buffer.
 */
export function parseMarkdown(content: string, config: PreviewConfig): string {
  const frontMatter = extractFrontMatter(content)
  return (
    frontMatter.html + markdownRenderer(config, frontMatter.lineOffset).render(frontMatter.markdown)
  )
}
