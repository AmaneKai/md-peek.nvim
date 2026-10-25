import DOMPurify from 'dompurify'
import type { PreviewConfig } from '../model.js'

/** Stage 3: strip anything dangerous from the HTML, keeping the attributes navigation needs. */
export function sanitizeHtml(html: string, config: PreviewConfig): string {
  if (!config.sanitize) {
    return html
  }
  return DOMPurify.sanitize(html, { ADD_ATTR: ['target', 'data-source-line'] })
}
