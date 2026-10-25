import hljs from 'highlight.js/lib/common'
import MarkdownIt from 'markdown-it'
import { full as emoji } from 'markdown-it-emoji'
import footnote from 'markdown-it-footnote'
import taskLists from 'markdown-it-task-lists'
import { copyButtonHtml } from './icons.js'
import { LruCache } from './render-work.js'
import { escapeHtml } from './text.js'

const highlightedCode = new LruCache(128)

export function slugger() {
  const used = new Map()

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

export function extractFrontMatter(markdown) {
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

function highlightCode(content, language) {
  const cacheKey = `${language}\0${content}`
  const cached = highlightedCode.get(cacheKey)
  if (cached !== undefined) {
    return cached
  }

  let highlighted
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

function codeBlockHtml({ line, language = '', highlighted, copyButton }) {
  return [
    `<div class="code-block" data-source-line="${line}">`,
    `<div class="code-tools">${copyButton}</div>`,
    '<pre>',
    `<code class="hljs language-${escapeHtml(language)}">${highlighted}</code>`,
    '</pre>',
    '</div>',
  ].join('')
}

export function markdownRenderer(config, lineOffset = 0) {
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
  renderer.use(taskLists, { enabled: false, label: true, labelAfter: true })

  const nextSlug = slugger()
  const mappedRules = [
    'paragraph_open',
    'blockquote_open',
    'bullet_list_open',
    'ordered_list_open',
    'table_open',
    'dl_open',
  ]

  for (const name of mappedRules) {
    const fallback =
      renderer.renderer.rules[name] ||
      ((tokens, index, options, _env, self) => self.renderToken(tokens, index, options))
    renderer.renderer.rules[name] = (tokens, index, options, env, self) => {
      if (tokens[index].map) {
        tokens[index].attrSet('data-source-line', String(tokens[index].map[0] + 1 + lineOffset))
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
