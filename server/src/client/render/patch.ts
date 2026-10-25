import { blockSignature, diffBlocks } from './diff.js'

// What each block looked like when it was inserted, before math, diagrams or link handling
// changed it. Comparing against this (not the live DOM) is what makes unchanged blocks reusable.
const signatures = new WeakMap<Node, string>()
let epoch = 0

function signatureOf(node: Node): string {
  if (node.nodeType === Node.ELEMENT_NODE) {
    return blockSignature((node as Element).outerHTML)
  }
  return `#text:${node.textContent}`
}

/** Forget every stored signature so the next patch replaces the whole surface. */
export function invalidateSurface(): void {
  epoch++
}

function stored(node: Node): string {
  return signatures.get(node) ?? `#unknown:${Math.random()}`
}

function copySourceLines(from: Node, to: Node): void {
  if (from.nodeType !== Node.ELEMENT_NODE || to.nodeType !== Node.ELEMENT_NODE) {
    return
  }
  const sources = [from as Element, ...(from as Element).querySelectorAll('[data-source-line]')]
  const targets = [to as Element, ...(to as Element).querySelectorAll('[data-source-line]')]
  if (sources.length !== targets.length) {
    return
  }
  sources.forEach((source, index) => {
    const line = targets[index].getAttribute('data-source-line')
    if (line !== null && source.hasAttribute('data-source-line')) {
      source.setAttribute('data-source-line', line)
    }
  })
}

export interface PatchResult {
  /** Elements that are new or changed; only these need math, diagrams and link handling. */
  inserted: Element[]
  /** How many existing blocks were left exactly as they were. */
  reused: number
}

/**
 * Stage 4: make `root` show `html` while touching as little as possible. Blocks that did not
 * change keep their DOM nodes, so rendered diagrams, math, zoom and selection survive an edit.
 */
export function patchSurface(root: HTMLElement, html: string): PatchResult {
  const template = document.createElement('template')
  template.innerHTML = html
  const next = [...template.content.childNodes]
  const current = [...root.childNodes]

  const nextSignatures = next.map((node) => `${epoch}:${signatureOf(node)}`)
  const currentSignatures = current.map(stored)
  const { prefix, suffix } = diffBlocks(currentSignatures, nextSignatures)

  // Unchanged blocks may have moved to a new line; refresh their line numbers in place.
  for (let index = 0; index < prefix; index++) {
    copySourceLines(current[index], next[index])
  }
  for (let offset = 1; offset <= suffix; offset++) {
    copySourceLines(current[current.length - offset], next[next.length - offset])
  }

  const anchor = suffix > 0 ? current[current.length - suffix] : null
  for (const removed of current.slice(prefix, current.length - suffix)) {
    removed.remove()
  }

  const inserted: Element[] = []
  next.slice(prefix, next.length - suffix).forEach((node, index) => {
    signatures.set(node, nextSignatures[prefix + index])
    root.insertBefore(node, anchor)
    if (node.nodeType === Node.ELEMENT_NODE) {
      inserted.push(node as Element)
    }
  })

  // Keep the signature of retained nodes current with this epoch.
  for (let index = 0; index < prefix; index++) {
    signatures.set(current[index], nextSignatures[index])
  }
  for (let offset = 1; offset <= suffix; offset++) {
    signatures.set(current[current.length - offset], nextSignatures[next.length - offset])
  }

  return { inserted, reused: prefix + suffix }
}
