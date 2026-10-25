/**
 * Finds what changed between two lists of block signatures by matching them from both ends.
 * Editing one paragraph leaves a long identical head and tail, so only the middle differs.
 */
export interface BlockDiff {
  /** How many blocks at the start are identical. */
  prefix: number
  /** How many blocks at the end are identical (never overlapping the prefix). */
  suffix: number
}

export function diffBlocks(before: readonly string[], after: readonly string[]): BlockDiff {
  let prefix = 0
  while (prefix < before.length && prefix < after.length && before[prefix] === after[prefix]) {
    prefix++
  }

  let suffix = 0
  while (
    suffix < before.length - prefix &&
    suffix < after.length - prefix &&
    before[before.length - 1 - suffix] === after[after.length - 1 - suffix]
  ) {
    suffix++
  }

  return { prefix, suffix }
}

/**
 * Reduces a block's HTML to what identifies its content. Source-line attributes shift whenever a
 * line is added above a block, and the task-list plugin picks a random id for every checkbox on
 * every render; neither means the block changed.
 */
export function blockSignature(html: string): string {
  return html.replace(/ data-source-line="\d+"/g, '').replace(/task-item-\d+/g, 'task-item')
}
