import { article, emptyState, source } from './dom.js'

/** Shows the rendered article, the raw source, or the empty-document message. */
export function applyVisibility(contentIsEmpty: boolean, rawVisible: boolean): void {
  emptyState.hidden = !contentIsEmpty
  article.hidden = contentIsEmpty || rawVisible
  source.hidden = !rawVisible
}
