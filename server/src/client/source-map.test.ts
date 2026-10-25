import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { markdownRenderer } from './render/markdown.js'
import { defaults } from './model.js'

const entities: Record<string, string> = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
}

const normalize = (text: string) =>
  text
    .replace(/&(?:amp|lt|gt|quot|#39);/g, (entity) => entities[entity])
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]/gu, '')

// Strips what Markdown adds before a block's text, so the source line can be compared with the
// text the browser shows: list markers, task checkboxes, blockquote markers and heading hashes.
const sourceText = (line: string) =>
  normalize(
    line
      .replace(/^[\s>]*(?:(?:[-*+]|\d+[.)])\s+)?(?:\[[ xX]\]\s*)?#*\s*/, '')
      // Link and image targets, reference labels, inline HTML and entities are not shown as text.
      .replace(/\]\([^)]*\)|\]\[[^\]]*\]|<[^>]*>|&\w+;/g, ']'),
  )

interface Mapped {
  tag: string
  line: number
  html: string
  inner: string
}

const voidTags = new Set(['br', 'hr', 'img', 'input', 'path'])

/** Returns the markup between an opening tag and its matching close tag. */
function innerHtml(html: string, from: number, tag: string): string {
  let depth = 1
  for (const match of html.slice(from).matchAll(/<(\/?)(\w+)[^>]*?(\/?)>/g)) {
    if (match[2] !== tag || voidTags.has(tag) || match[3] === '/') {
      continue
    }
    depth += match[1] === '/' ? -1 : 1
    if (depth === 0) {
      return html.slice(from, from + match.index)
    }
  }
  return html.slice(from)
}

function mappedElements(html: string): Mapped[] {
  const elements: Mapped[] = []
  for (const match of html.matchAll(/<(\w+)([^>]*?)\sdata-source-line="(\d+)"([^>]*)>/g)) {
    const start = match.index + match[0].length
    elements.push({
      tag: match[1],
      line: Number(match[3]),
      html: match[0],
      inner: innerHtml(html, start, match[1]),
    })
  }
  return elements
}

export interface SourceMapReport {
  total: number
  correct: number
  failures: string[]
}

/** Renders Markdown and checks that each mapped element points at the line it came from. */
export function checkSourceMap(markdown: string): SourceMapReport {
  const lines = markdown.split('\n')
  const report: SourceMapReport = { total: 0, correct: 0, failures: [] }
  const html = markdownRenderer(defaults).render(markdown)

  for (const element of mappedElements(html)) {
    const source = lines[element.line - 1] ?? ''
    // Code and diagrams point at their opening fence (or first indented line), not their text.
    if (/class="(?:code-block|mermaid)"/.test(element.html)) {
      report.total++
      if (/^\s*(?:```|~~~|\t| {4})/.test(source)) {
        report.correct++
      } else {
        report.failures.push(`line ${element.line}: code block does not start at "${source}"`)
      }
      continue
    }

    const rendered = normalize(element.inner.replace(/<[^>]*>/g, ''))
    const expected = sourceText(source)
    const length = Math.min(rendered.length, expected.length, 12)
    if (length === 0) {
      continue // nothing comparable, e.g. an image-only line, an emoji or display math
    }

    report.total++
    if (rendered.slice(0, length) === expected.slice(0, length)) {
      report.correct++
    } else {
      report.failures.push(`line ${element.line} <${element.tag}>: "${source}" vs "${rendered}"`)
    }
  }

  return report
}

const fixture = readFileSync(new URL('fixtures/source-map.md', import.meta.url), 'utf8')

describe('source line mapping', () => {
  it('maps every block of the fixture to its own line', () => {
    const report = checkSourceMap(fixture)
    expect(report.failures).toEqual([])
    expect(report.total).toBeGreaterThan(30)
  })

  it('gives list items and table rows their own lines', () => {
    const html = markdownRenderer(defaults).render('- a\n- b\n  - c\n\n| x |\n| - |\n| 1 |\n| 2 |')
    const lines = (tag: string) =>
      [...html.matchAll(new RegExp(`<${tag}[^>]*data-source-line="(\\d+)"`, 'g'))].map((m) => m[1])
    expect(lines('li')).toEqual(['1', '2', '3'])
    expect(lines('tr')).toEqual(['5', '7', '8'])
  })

  it('leaves no list item, row, paragraph or heading without a line', () => {
    const html = markdownRenderer(defaults).render(fixture)
    const unmapped = html.match(
      /<(?:li|tr|p|h[1-6]|ul|ol|table|blockquote)(?=[\s>])(?![^>]*data-source-line)[^>]*>/g,
    )
    expect(unmapped).toBeNull()
  })

  it('maps real-world READMEs accurately', () => {
    const here = (path: string) => fileURLToPath(new URL(path, import.meta.url))
    const roots = [here('../../../README.md')]
    const modules = here('../../node_modules')
    if (existsSync(modules)) {
      for (const name of readdirSync(modules).sort()) {
        const readme = `${modules}/${name}/README.md`
        if (!name.startsWith('.') && !name.startsWith('@') && existsSync(readme)) {
          roots.push(readme)
        }
      }
    }

    let total = 0
    let correct = 0
    const failures: string[] = []
    for (const file of roots) {
      const report = checkSourceMap(readFileSync(file, 'utf8'))
      total += report.total
      correct += report.correct
      failures.push(...report.failures.map((failure) => `${file}: ${failure}`))
    }

    const accuracy = correct / total
    expect(total).toBeGreaterThan(200)
    // Failures are oracle gaps (inline `<tags>`, entities, raw HTML), not mapping errors; the first
    // few are attached so a real regression is easy to tell apart.
    expect(accuracy, failures.slice(0, 10).join('\n')).toBeGreaterThanOrEqual(0.99)
  })
})
