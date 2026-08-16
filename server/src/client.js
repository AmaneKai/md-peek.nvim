import DOMPurify from 'dompurify'
import hljs from 'highlight.js/lib/common'
import MarkdownIt from 'markdown-it'
import { full as emoji } from 'markdown-it-emoji'
import footnote from 'markdown-it-footnote'
import taskLists from 'markdown-it-task-lists'
import { LatestTaskQueue, LruCache } from './render-work.js'

const token = document.querySelector('meta[name="md-peek-token"]')?.content || ''

function requiredElement(identifier) {
  const element = document.getElementById(identifier)

  if (!element) {
    throw new Error(`[md-peek] missing required element: #${identifier}`)
  }

  return element
}

const article = requiredElement('document')
const source = requiredElement('source')
const sourceCode = source.querySelector('code')

if (!sourceCode) {
  throw new Error('[md-peek] missing source code element')
}

const emptyState = requiredElement('empty')
const toc = requiredElement('toc')
const tocContent = requiredElement('toc-content')
const tocResizer = requiredElement('toc-resizer')
const status = requiredElement('status')
const documentTitle = requiredElement('document-title')
const rawToggle = requiredElement('raw-toggle')
const lightbox = requiredElement('lightbox')
const diagramViewer = requiredElement('diagram-viewer')
const diagramViewport = requiredElement('diagram-viewport')
const diagramCanvas = requiredElement('diagram-canvas')
const diagramZoomLevel = requiredElement('diagram-zoom-level')
const toastElement = requiredElement('toast')

const defaults = {
  theme: 'dark',
  toc: true,
  toc_open: false,
  math: true,
  mermaid: true,
  emoji: true,
  raw_toggle: true,
  code_copy: true,
  scroll_sync: true,
  preserve_scroll: true,
  breaks: false,
  linkify: true,
  typographer: false,
  allow_html: true,
  sanitize: true,
  max_width: 920,
  colors: {},
  font: {},
  custom_css: '',
}

let config = { ...defaults }
let currentDocument = { content: '', path: '', line: 1 }
let latestDocument = currentDocument
let currentSocket
let reconnectDelay = 250
let rawVisible = false
let mermaidInitialized = false
let sourceNodes = []
let activeNode
let tocEntries = []
let rendering = false
let latestCursorLine = 1
let mathRendererPromise
let mermaidPromise
const highlightedCode = new LruCache(128)

function toast(message) {
  toastElement.textContent = message
  toastElement.classList.add('show')
  clearTimeout(toastElement.timer)
  toastElement.timer = setTimeout(() => toastElement.classList.remove('show'), 1500)
}

function slugger() {
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

function extractFrontMatter(markdown) {
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

function escapeHtml(value) {
  return String(value).replace(
    /[&<>"']/g,
    (character) =>
      ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;',
      })[character],
  )
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
  const languageLabel = language
    ? `<span class="language-label">${escapeHtml(language)}</span>`
    : ''
  return [
    `<div class="code-block" data-source-line="${line}">`,
    `<div class="code-tools">${languageLabel}${copyButton}</div>`,
    '<pre>',
    `<code class="hljs language-${escapeHtml(language)}">${highlighted}</code>`,
    '</pre>',
    '</div>',
  ].join('')
}

function markdownRenderer(lineOffset = 0) {
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

    const copyButton = config.code_copy
      ? '<button class="copy-code" type="button">Copy</button>'
      : ''
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
    const copyButton = config.code_copy
      ? '<button class="copy-code" type="button">Copy</button>'
      : ''

    return codeBlockHtml({
      line,
      highlighted: escapeHtml(item.content),
      copyButton,
    })
  }

  return renderer
}

function applyConfig() {
  document.documentElement.dataset.theme = config.theme || 'dark'
  document.documentElement.style.setProperty(
    '--content-width',
    `${Number(config.max_width) || 920}px`,
  )
  toc.hidden = !config.toc
  tocResizer.hidden = !config.toc
  setTocOpen(config.toc && config.toc_open)
  rawToggle.hidden = !config.raw_toggle

  let style = document.getElementById('user-theme')

  if (!style) {
    style = document.createElement('style')
    style.id = 'user-theme'
    document.head.appendChild(style)
  }

  const variables = []
  for (const [name, value] of Object.entries(config.colors || {})) {
    variables.push(`--md-${name.replaceAll('_', '-')}: ${value};`)
  }

  const font = config.font || {}

  if (font.ui) {
    variables.push(`--md-font-ui: ${font.ui};`)
  }

  if (font.mono) {
    variables.push(`--md-font-mono: ${font.mono};`)
  }

  if (font.size) {
    const fontSize = typeof font.size === 'number' ? `${font.size}px` : font.size
    variables.push(`--md-font-size: ${fontSize};`)
  }

  style.textContent = `:root { ${variables.join('\n')} }\n${config.custom_css || ''}`

  // v1 stored a permanent generic "dark" override, which meant toggling
  // back from light silently replaced presets such as Tokyo Night. Ignore
  // that stale state and only persist a temporary opposite-scheme override.
  localStorage.removeItem('md-peek:scheme')
  const preference = localStorage.getItem('md-peek:scheme-override-v2')

  if (preference === 'light' || preference === 'dark') {
    document.documentElement.dataset.scheme = preference
  } else {
    delete document.documentElement.dataset.scheme
  }

  const savedTocWidth = Number(localStorage.getItem('md-peek:toc-width'))

  if (savedTocWidth >= 240) {
    setTocWidth(savedTocWidth)
  }
}

function lightScheme() {
  const override = document.documentElement.dataset.scheme

  if (override === 'light') {
    return true
  }
  if (override === 'dark') {
    return false
  }

  return ['github', 'light'].includes(config.theme)
}

function localAssetUrl(path) {
  return `/asset?path=${encodeURIComponent(path)}&token=${encodeURIComponent(token)}`
}

function decorateContent() {
  for (const image of article.querySelectorAll('img[src]')) {
    const source_ = image.getAttribute('src')
    if (source_ && !/^(?:[a-z][a-z\d+.-]*:|\/\/|#)/i.test(source_)) {
      image.src = localAssetUrl(source_)
    }

    image.loading = 'lazy'
  }

  for (const link of article.querySelectorAll('a[href]')) {
    const href = link.getAttribute('href') || ''
    if (/^https?:/i.test(href)) {
      link.target = '_blank'
      link.rel = 'noopener noreferrer'
    } else if (/\.(?:md|markdown|mdown|mkdn|mkd|mdx)(?:[#?].*)?$/i.test(href)) {
      link.addEventListener('click', (event) => {
        event.preventDefault()
        send({ type: 'open_file', href })
      })
    }
  }

  for (const blockquote of article.querySelectorAll('blockquote')) {
    const first = blockquote.querySelector(':scope > p:first-child')
    const match = first?.textContent?.match(/^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*/i)

    if (!match) {
      continue
    }

    blockquote.classList.add('alert', `alert-${match[1].toLowerCase()}`)
    first.innerHTML = first.innerHTML.replace(
      /^\s*\[![^\]]+\]\s*/i,
      `<strong class="alert-title">${match[1]}</strong><br>`,
    )
  }
}

function buildToc() {
  tocContent.innerHTML = ''
  const headings = [...article.querySelectorAll('h1, h2, h3, h4')]
  tocEntries = []

  if (!headings.length) {
    tocContent.innerHTML = '<span class="toc-empty">No headings</span>'
    return
  }

  const fragment = document.createDocumentFragment()
  for (const heading of headings) {
    const link = document.createElement('a')
    link.href = `#${heading.id}`
    link.className = `toc-h${heading.tagName.slice(1)}`
    link.textContent = heading.textContent
    link.title = heading.textContent
    link.addEventListener('click', (event) => {
      event.preventDefault()
      setActiveToc(heading)
      heading.scrollIntoView({ behavior: 'smooth', block: 'start' })
    })
    tocEntries.push({ heading, link, line: Number(heading.dataset.sourceLine) || 1 })
    fragment.appendChild(link)
  }
  tocContent.appendChild(fragment)
  updateActiveToc()
}

function setActiveToc(heading) {
  for (const entry of tocEntries) {
    entry.link.classList.toggle('active', entry.heading === heading)
  }

  const active = tocEntries.find((entry) => entry.heading === heading)

  if (active && !active.link.matches(':hover')) {
    active.link.scrollIntoView({ block: 'nearest' })
  }
}

function updateActiveToc() {
  if (!tocEntries.length) {
    return
  }

  const threshold =
    Number.parseFloat(
      getComputedStyle(document.documentElement).getPropertyValue('--toolbar-height'),
    ) + 72
  let active = tocEntries[0]

  for (const entry of tocEntries) {
    if (entry.heading.getBoundingClientRect().top > threshold) {
      break
    }

    active = entry
  }

  setActiveToc(active.heading)
}

function sourceLineNodes() {
  sourceNodes = [...article.querySelectorAll(':scope > [data-source-line]')]
    .map((node) => ({ node, line: Number(node.dataset.sourceLine) }))
    .filter((entry) => Number.isFinite(entry.line))
    .sort((a, b) => a.line - b.line)
}

function revealLine(line, shouldScroll = true) {
  if (!sourceNodes.length || rawVisible) {
    return
  }

  let match = sourceNodes[0]
  for (const entry of sourceNodes) {
    if (entry.line > line) {
      break
    }

    match = entry
  }

  if (activeNode !== match.node) {
    activeNode?.classList.remove('active-source')
    activeNode = match.node
    activeNode.classList.add('active-source')
  }

  let activeHeading = tocEntries[0]
  for (const entry of tocEntries) {
    if (entry.line > line) {
      break
    }

    activeHeading = entry
  }

  if (activeHeading) {
    setActiveToc(activeHeading.heading)
  }

  if (shouldScroll && config.scroll_sync) {
    match.node.scrollIntoView({ behavior: 'smooth', block: 'center' })
  }
}

function mightContainMath(markdown) {
  return markdown.includes('$') || markdown.includes('\\(') || markdown.includes('\\[')
}

async function renderMath(markdown) {
  if (!config.math || !mightContainMath(markdown)) {
    return
  }

  try {
    mathRendererPromise ||= import('katex/contrib/auto-render').then((module) => module.default)
    const renderMathInElement = await mathRendererPromise
    renderMathInElement(article, {
      delimiters: [
        { left: '$$', right: '$$', display: true },
        { left: '\\[', right: '\\]', display: true },
        { left: '\\(', right: '\\)', display: false },
        { left: '$', right: '$', display: false },
      ],
      throwOnError: false,
      ignoredClasses: ['mermaid', 'code-block'],
    })
  } catch (error) {
    console.error('[md-peek] math rendering failed', error)
  }
}

async function renderMermaidDiagrams() {
  if (!config.mermaid || !article.querySelector('.mermaid')) {
    return
  }

  mermaidPromise ||= import('mermaid').then((module) => module.default)
  const mermaid = await mermaidPromise
  if (!mermaidInitialized) {
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: lightScheme() ? 'default' : 'dark',
    })
    mermaidInitialized = true
  }

  try {
    const diagrams = article.querySelectorAll('.mermaid')
    await mermaid.run({ nodes: diagrams, suppressErrors: true })
  } catch (error) {
    console.error('[md-peek] Mermaid rendering failed', error)
  }
}

async function updateRenderedDocument(documentState) {
  const previousScrollPosition = window.scrollY
  currentDocument = { ...documentState, line: latestCursorLine }
  sourceCode.textContent = documentState.content
  documentTitle.textContent = documentState.path.split(/[\\/]/).pop() || 'Markdown'
  document.title = `md-peek:${location.port} ${documentTitle.textContent}`
  const extracted = extractFrontMatter(documentState.content)
  let html = extracted.html + markdownRenderer(extracted.lineOffset).render(extracted.markdown)

  if (config.sanitize) {
    html = DOMPurify.sanitize(html, { ADD_ATTR: ['target', 'data-source-line'] })
  }

  article.innerHTML = html
  const documentIsEmpty = documentState.content.trim() === ''
  emptyState.hidden = !documentIsEmpty
  article.hidden = documentIsEmpty || rawVisible
  source.hidden = !rawVisible
  decorateContent()

  await Promise.all([renderMath(documentState.content), renderMermaidDiagrams()])

  buildToc()
  sourceLineNodes()
  if (config.preserve_scroll) {
    window.scrollTo({ top: previousScrollPosition })
  }

  revealLine(latestCursorLine, !config.preserve_scroll || previousScrollPosition === 0)
}

async function renderDocument(documentState) {
  latestCursorLine = documentState.line
  latestDocument = { ...documentState }
  return renderQueue.enqueue(latestDocument)
}

const renderQueue = new LatestTaskQueue(
  async (documentState) => {
    rendering = true
    try {
      await updateRenderedDocument(documentState)
    } finally {
      rendering = false
    }
  },
  () => new Promise((resolve) => setTimeout(resolve, 0)),
)

function send(message) {
  if (currentSocket?.readyState === WebSocket.OPEN) {
    currentSocket.send(JSON.stringify(message))
  }
}

function connect() {
  status.textContent = 'Connecting…'
  const protocol = location.protocol === 'https:' ? 'wss' : 'ws'
  const socket = new WebSocket(
    `${protocol}://${location.host}/ws?token=${encodeURIComponent(token)}`,
  )
  currentSocket = socket
  socket.addEventListener('open', () => {
    status.textContent = 'Live'
    reconnectDelay = 250
  })
  socket.addEventListener('message', async (event) => {
    try {
      const message = JSON.parse(event.data)
      if (message.type === 'init') {
        config = { ...defaults, ...(message.config || {}) }
        applyConfig()
        await renderDocument(message.document)
      } else if (message.type === 'render') {
        await renderDocument(message.document)
      } else if (message.type === 'cursor') {
        latestCursorLine = message.line
        latestDocument.line = message.line
        currentDocument.line = message.line
        revealLine(message.line)
      } else if (message.type === 'error') {
        console.error('[md-peek] preview server rejected a browser message', message.error)
      }
    } catch (error) {
      status.textContent = 'Preview error'
      console.error('[md-peek] failed to process preview update', error)
    }
  })
  socket.addEventListener('close', () => {
    if (currentSocket !== socket) {
      return
    }

    status.textContent = 'Reconnecting…'
    setTimeout(connect, reconnectDelay)
    reconnectDelay = Math.min(reconnectDelay * 2, 5000)
  })
}

article.addEventListener('click', async (event) => {
  const copy = event.target.closest('.copy-code')
  if (copy) {
    const code = copy.closest('.code-block')?.querySelector('code')?.textContent || ''
    await navigator.clipboard.writeText(code)
    copy.textContent = 'Copied'
    setTimeout(() => {
      copy.textContent = 'Copy'
    }, 900)
    return
  }

  if (event.target.closest('a, button, input, label, summary')) {
    return
  }

  const image = event.target.closest('img')
  if (image) {
    lightbox.querySelector('img').src = image.src
    lightbox.showModal()
    return
  }

  const mermaidBlock = event.target.closest('.mermaid')
  if (mermaidBlock) {
    openDiagramViewer(mermaidBlock)
    return
  }

  const mapped = event.target.closest('[data-source-line]')
  if (mapped) {
    send({ type: 'jump', line: Number(mapped.dataset.sourceLine) })
  }
})

lightbox.addEventListener('click', (event) => {
  if (event.target === lightbox || event.target.closest('button')) {
    lightbox.close()
  }
})

let diagramScale = 1
let diagramX = 0
let diagramY = 0
let diagramPan = null

function applyDiagramTransform() {
  diagramCanvas.style.transform = `translate(${diagramX}px, ${diagramY}px) scale(${diagramScale})`
  diagramZoomLevel.textContent = `${Math.round(diagramScale * 100)}%`
}

function diagramNaturalSize() {
  const svg = diagramCanvas.querySelector('svg')
  const width = Number.parseFloat(svg?.getAttribute('width'))
  const height = Number.parseFloat(svg?.getAttribute('height'))
  return { width: width || 0, height: height || 0 }
}

function fitDiagram() {
  const { width, height } = diagramNaturalSize()
  const rect = diagramViewport.getBoundingClientRect()
  diagramX = 0
  diagramY = 0
  diagramScale = width && height ? Math.min((rect.width - 64) / width, (rect.height - 64) / height, 1) : 1
  diagramScale = Math.max(diagramScale, 0.05)
  applyDiagramTransform()
}

function openDiagramViewer(block) {
  const svg = block.querySelector('svg')
  if (!svg) {
    return
  }

  const clone = svg.cloneNode(true)
  const box = svg.viewBox?.baseVal
  if (box?.width && box?.height) {
    clone.setAttribute('width', box.width)
    clone.setAttribute('height', box.height)
  }
  clone.style.maxWidth = 'none'

  diagramCanvas.innerHTML = ''
  diagramCanvas.appendChild(clone)
  diagramViewer.showModal()
  diagramViewport.focus({ preventScroll: true })
  fitDiagram()
}

function zoomDiagramAt(clientX, clientY, factor) {
  const rect = diagramViewport.getBoundingClientRect()
  const cx = clientX - rect.left - rect.width / 2
  const cy = clientY - rect.top - rect.height / 2
  const newScale = Math.min(Math.max(diagramScale * factor, 0.05), 8)
  const pointX = (cx - diagramX) / diagramScale
  const pointY = (cy - diagramY) / diagramScale
  diagramX = cx - pointX * newScale
  diagramY = cy - pointY * newScale
  diagramScale = newScale
  applyDiagramTransform()
}

function zoomDiagramAtCenter(factor) {
  const rect = diagramViewport.getBoundingClientRect()
  zoomDiagramAt(rect.left + rect.width / 2, rect.top + rect.height / 2, factor)
}

diagramViewport.addEventListener(
  'wheel',
  (event) => {
    event.preventDefault()
    zoomDiagramAt(event.clientX, event.clientY, Math.exp(-event.deltaY * 0.0035))
  },
  { passive: false },
)

diagramViewport.addEventListener('pointerdown', (event) => {
  if (event.button !== 0) {
    return
  }
  diagramPan = { id: event.pointerId, x: event.clientX, y: event.clientY, startX: diagramX, startY: diagramY }
  diagramViewport.setPointerCapture(event.pointerId)
  diagramViewport.classList.add('panning')
  event.preventDefault()
})
diagramViewport.addEventListener('pointermove', (event) => {
  if (!diagramPan || event.pointerId !== diagramPan.id) {
    return
  }
  diagramX = diagramPan.startX + (event.clientX - diagramPan.x)
  diagramY = diagramPan.startY + (event.clientY - diagramPan.y)
  applyDiagramTransform()
})
function endDiagramPan(event) {
  if (diagramPan && event.pointerId === diagramPan.id) {
    diagramPan = null
    diagramViewport.classList.remove('panning')
  }
}
diagramViewport.addEventListener('pointerup', endDiagramPan)
diagramViewport.addEventListener('pointercancel', endDiagramPan)
diagramViewport.addEventListener('dblclick', () => fitDiagram())

document.getElementById('diagram-zoom-in').addEventListener('click', () => zoomDiagramAtCenter(1.25))
document.getElementById('diagram-zoom-out').addEventListener('click', () => zoomDiagramAtCenter(0.8))
document.getElementById('diagram-zoom-fit').addEventListener('click', () => fitDiagram())
document.getElementById('diagram-close').addEventListener('click', () => diagramViewer.close())

function setTocOpen(open) {
  document.body.classList.toggle('toc-closed', !open)
  document.getElementById('toc-toggle').setAttribute('aria-expanded', String(open))
}

document.getElementById('toc-toggle').addEventListener('click', () => {
  setTocOpen(document.body.classList.contains('toc-closed'))
})

function setTocWidth(requested) {
  const maximum = Math.min(innerWidth * 0.48, 520)
  const width = Math.round(Math.max(240, Math.min(requested, maximum)))
  document.documentElement.style.setProperty('--toc-width', `${width}px`)
  return width
}

let resizingToc = false
tocResizer.addEventListener('pointerdown', (event) => {
  resizingToc = true
  tocResizer.setPointerCapture(event.pointerId)
  document.body.classList.add('toc-resizing')
  event.preventDefault()
})
tocResizer.addEventListener('pointermove', (event) => {
  if (!resizingToc) {
    return
  }
  setTocWidth(event.clientX)
})
tocResizer.addEventListener('pointerup', (event) => {
  if (!resizingToc) {
    return
  }
  resizingToc = false
  tocResizer.releasePointerCapture(event.pointerId)
  document.body.classList.remove('toc-resizing')
  localStorage.setItem('md-peek:toc-width', String(Math.round(toc.getBoundingClientRect().width)))
})
tocResizer.addEventListener('dblclick', () => {
  localStorage.removeItem('md-peek:toc-width')
  setTocWidth(300)
})
rawToggle.addEventListener('click', () => {
  rawVisible = !rawVisible
  article.hidden = rawVisible || currentDocument.content.trim() === ''
  source.hidden = !rawVisible
  rawToggle.classList.toggle('active', rawVisible)
})
document.getElementById('theme-toggle').addEventListener('click', async () => {
  const override = document.documentElement.dataset.scheme
  if (override) {
    delete document.documentElement.dataset.scheme
    localStorage.removeItem('md-peek:scheme-override-v2')
  } else {
    const next = ['github', 'light'].includes(config.theme) ? 'dark' : 'light'
    document.documentElement.dataset.scheme = next
    localStorage.setItem('md-peek:scheme-override-v2', next)
  }
  mermaidInitialized = false
  await renderDocument(latestDocument)
})
document.getElementById('print').addEventListener('click', () => window.print())
document.getElementById('export').addEventListener('click', () => {
  const styles = [...document.styleSheets]
    .map((sheet) => {
      try {
        return [...sheet.cssRules].map((rule) => rule.cssText).join('\n')
      } catch (error) {
        console.warn('[md-peek] stylesheet omitted from HTML export', sheet.href, error)
        return ''
      }
    })
    .join('\n')
  const clone = article.cloneNode(true)
  clone.querySelectorAll('.active-source').forEach((node) => node.classList.remove('active-source'))
  clone.querySelectorAll('.copy-code').forEach((node) => node.remove())
  const html = [
    '<!doctype html><html><head><meta charset="utf-8">',
    `<title>${escapeHtml(documentTitle.textContent)}</title>`,
    `<style>${styles}</style></head>`,
    `<body><main id="viewport">${clone.outerHTML}</main></body></html>`,
  ].join('')
  const url = URL.createObjectURL(new Blob([html], { type: 'text/html' }))
  const link = document.createElement('a')
  link.href = url
  link.download = `${documentTitle.textContent.replace(/\.[^.]+$/, '') || 'document'}.html`
  link.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
  toast('HTML exported')
})

window.addEventListener(
  'scroll',
  () => {
    if (rendering) {
      return
    }
    const max = document.documentElement.scrollHeight - innerHeight
    document.getElementById('progress').style.width = `${max > 0 ? (scrollY / max) * 100 : 0}%`
    updateActiveToc()
  },
  { passive: true },
)

window.addEventListener('resize', () => {
  const current = Number.parseFloat(
    getComputedStyle(document.documentElement).getPropertyValue('--toc-width'),
  )
  if (Number.isFinite(current)) {
    setTocWidth(current)
  }
})

connect()
