import hljs from 'highlight.js/lib/common'
import MarkdownIt from 'markdown-it'
import { full as emoji } from 'markdown-it-emoji'
import footnote from 'markdown-it-footnote'
import taskLists from 'markdown-it-task-lists'
import { copyButtonHtml } from './icons.js'
import { LruCache } from './render-work.js'
import type { PreviewConfig } from '../model.js'
import { escapeHtml } from '../text.js'

const highlightedCode = new LruCache<string, string>(128)

export function slugger(): (text: string) => string {
  const used = new Map<string, number>()

  return (text) => {
    const base =
      text
        .toLowerCase()
        .trim()
        .replace(/<[^>]*>/g, '')
        .replace(/[^\p{L}\p{N}\s-]/gu, '')
        .replace(/\s+/g, '-') || 'section'
    const count = used.get(base) || 0
    used.set(base, count + 1)

    return count ? `${base}-${count}` : base
  }
}

export interface FrontMatter {
  markdown: string
  html: string
  lineOffset: number
}

export function extractFrontMatter(source: string): FrontMatter {
  // A Windows-style buffer reaches us with "\r" left on every line. Dropping it keeps the line
  // count (and so every data-source-line) identical to the editor's.
  const markdown = source.replace(/\r\n/g, '\n')
  if (!markdown.startsWith('---\n')) {
    return { markdown, html: '', lineOffset: 0 }
  }

  const end = markdown.indexOf('\n---', 4)

  if (end < 0) {
    return { markdown, html: '', lineOffset: 0 }
  }

  const body = markdown.slice(4, end)
  const tail = markdown.slice(end + 4)
  const hasTrailingNewline = tail.startsWith('\n')
  const rest = hasTrailingNewline ? tail.slice(1) : tail
  const prefix = markdown.slice(0, end + 4)
  const frontMatter = escapeHtml(body)

  return {
    markdown: rest,
    html: [
      '<details class="frontmatter" data-source-line="1">',
      '<summary>Front matter</summary>',
      `<pre>${frontMatter}</pre>`,
      '</details>',
    ].join(''),
    lineOffset: (prefix.match(/\n/g) || []).length + (hasTrailingNewline ? 1 : 0),
  }
}

function highlightCode(content: string, language: string): string {
  const cacheKey = `${language}\0${content}`
  const cached = highlightedCode.get(cacheKey)
  if (cached !== undefined) {
    return cached
  }

  let highlighted: string
  try {
    if (language && hljs.getLanguage(language)) {
      highlighted = hljs.highlight(content, { language }).value
    } else {
      highlighted = hljs.highlightAuto(content).value
    }
  } catch (error) {
    console.warn('[md-peek] syntax highlighting failed; using plain text', error)
    highlighted = escapeHtml(content)
  }

  highlightedCode.set(cacheKey, highlighted)
  return highlighted
}

interface CodeBlock {
  line: number
  language?: string
  highlighted: string
  copyButton: string
}

function codeBlockHtml({ line, language = '', highlighted, copyButton }: CodeBlock): string {
  return [
    `<div class="code-block" data-source-line="${line}">`,
    `<div class="code-tools">${copyButton}</div>`,
    '<pre>',
    `<code class="hljs language-${escapeHtml(language)}">${highlighted}</code>`,
    '</pre>',
    '</div>',
  ].join('')
}

type InlineRule = Parameters<MarkdownIt['inline']['ruler']['push']>[1]

// `$$...$$` (which may span lines), or `$...$` with no space just inside either dollar, an
// optional escaped `\$` inside, and no digit right after the closing one (so "$5 and $10" is
// money, not math).
const MATH_SPAN = /^\$\$(?:\\[\s\S]|[^\\])+?\$\$|^\$(?![\s$])(?:\\.|[^$\\\n])+?(?<!\s)\$(?!\d)/

/**
 * Keeps math out of Markdown's hands. Left alone, the inline parser would turn `a*b*c` into
 * emphasis, drop the backslash from `\{`, `\,` and `\\`, and read `a<b>c` as a tag, all of which
 * KaTeX needs untouched. The span becomes one token that renders as escaped text, which KaTeX's
 * auto-render then finds in the page.
 *
 * Any other `$` (prices, an escaped `\$`) becomes its own element. KaTeX pairs dollar signs it
 * finds in the same run of text, so "$5 and then $10" would otherwise turn into a formula.
 */
const mathInline: InlineRule = (state, silent) => {
  const first = state.src.charCodeAt(state.pos)
  const escapedDollar = first === 0x5c && state.src.charCodeAt(state.pos + 1) === 0x24
  if (first !== 0x24 && !escapedDollar) {
    return false
  }

  const match = escapedDollar ? null : MATH_SPAN.exec(state.src.slice(state.pos))
  if (!silent) {
    state.push(match ? 'math_inline' : 'plain_dollar', '', 0).content = match ? match[0] : '$'
  }
  state.pos += match ? match[0].length : escapedDollar ? 2 : 1
  return true
}

export function markdownRenderer(config: PreviewConfig, lineOffset = 0): MarkdownIt {
  const renderer = new MarkdownIt({
    html: config.allow_html,
    breaks: config.breaks,
    linkify: config.linkify,
    typographer: config.typographer,
  })

  if (config.emoji) {
    renderer.use(emoji)
  }

  renderer.use(footnote)
  if (config.math) {
    renderer.inline.ruler.before('escape', 'math_inline', mathInline)
    renderer.renderer.rules.math_inline = (tokens, index) => escapeHtml(tokens[index].content)
    renderer.renderer.rules.plain_dollar = () => '<span class="not-math">$</span>'
  }
  // Checkboxes stay clickable; interactions.ts turns a click into a buffer edit in Neovim.
  renderer.use(taskLists, { enabled: true, label: true, labelAfter: true })

  const nextSlug = slugger()
  // Every block that can be clicked or revealed carries its 1-based source line. List items and
  // table rows are mapped too, so a click lands on the item or row, not the start of the list.
  const mappedRules = [
    'paragraph_open',
    'blockquote_open',
    'bullet_list_open',
    'ordered_list_open',
    'list_item_open',
    'table_open',
    'tr_open',
    'dl_open',
  ]

  for (const name of mappedRules) {
    const fallback =
      renderer.renderer.rules[name] ??
      ((tokens, index, options, _env, self) => self.renderToken(tokens, index, options))
    renderer.renderer.rules[name] = (tokens, index, options, env, self) => {
      const { map } = tokens[index]
      if (map) {
        tokens[index].attrSet('data-source-line', String(map[0] + 1 + lineOffset))
      }

      return fallback(tokens, index, options, env, self)
    }
  }

  renderer.renderer.rules.heading_open = (tokens, index, options, _env, self) => {
    const token = tokens[index]
    token.attrSet('id', nextSlug(tokens[index + 1]?.content || 'section'))

    if (token.map) {
      token.attrSet('data-source-line', String(token.map[0] + 1 + lineOffset))
    }

    return self.renderToken(tokens, index, options)
  }

  renderer.renderer.rules.fence = (tokens, index) => {
    const item = tokens[index]
    const language = item.info.trim().split(/\s+/, 1)[0]
    const line = item.map ? item.map[0] + 1 + lineOffset : 1

    if (config.mermaid && ['mermaid', 'mmd'].includes(language.toLowerCase())) {
      return [
        `<div class="mermaid" data-source-line="${line}">`,
        escapeHtml(item.content),
        '</div>',
      ].join('')
    }

    const copyButton = config.code_copy ? copyButtonHtml : ''
    return codeBlockHtml({
      line,
      language,
      highlighted: highlightCode(item.content, language),
      copyButton,
    })
  }

  renderer.renderer.rules.code_block = (tokens, index) => {
    const item = tokens[index]
    const line = item.map ? item.map[0] + 1 + lineOffset : 1
    const copyButton = config.code_copy ? copyButtonHtml : ''

    return codeBlockHtml({
      line,
      highlighted: escapeHtml(item.content),
      copyButton,
    })
  }

  return renderer
}
