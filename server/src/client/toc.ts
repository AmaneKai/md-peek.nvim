import { article, byId, toc, tocContent, tocResizer } from './dom.js'
import type { TocEntry } from './model.js'
import { store } from './store.js'

export function setTocOpen(open: boolean): void {
  document.body.classList.toggle('toc-closed', !open)
  byId('toc-toggle').setAttribute('aria-expanded', String(open))
}

export function setTocWidth(requested: number): number {
  const maximum = Math.min(innerWidth * 0.48, 520)
  const width = Math.round(Math.max(240, Math.min(requested, maximum)))
  document.documentElement.style.setProperty('--toc-width', `${width}px`)
  return width
}

export function setActiveToc(heading: HTMLElement): void {
  const { tocEntries } = store.getState()
  for (const entry of tocEntries) {
    entry.link.classList.toggle('active', entry.heading === heading)
  }

  const active = tocEntries.find((entry) => entry.heading === heading)

  if (active && !active.link.matches(':hover')) {
    active.link.scrollIntoView({ block: 'nearest' })
  }
}

export function updateActiveToc(): void {
  const { tocEntries } = store.getState()
  if (tocEntries.length === 0) {
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

export function buildToc(): void {
  tocContent.innerHTML = ''
  const headings = [...article.querySelectorAll<HTMLElement>('h1, h2, h3, h4')]
  const entries: TocEntry[] = []

  if (headings.length === 0) {
    tocContent.innerHTML = '<span class="toc-empty">No headings</span>'
    store.dispatch({ type: 'TOC_UPDATED', payload: entries })
    return
  }

  const fragment = document.createDocumentFragment()
  for (const heading of headings) {
    const link = document.createElement('a')
    link.href = `#${heading.id}`
    link.className = `toc-h${heading.tagName.slice(1)}`
    link.textContent = heading.textContent
    link.title = heading.textContent ?? ''
    link.addEventListener('click', (event) => {
      event.preventDefault()
      setActiveToc(heading)
      heading.scrollIntoView({ behavior: 'smooth', block: 'start' })
    })
    entries.push({ heading, link, line: Number(heading.dataset.sourceLine) || 1 })
    fragment.appendChild(link)
  }
  tocContent.appendChild(fragment)
  store.dispatch({ type: 'TOC_UPDATED', payload: entries })
  updateActiveToc()
}

export function initToc(): void {
  byId('toc-toggle').addEventListener('click', () => {
    setTocOpen(document.body.classList.contains('toc-closed'))
  })

  let resizing = false
  tocResizer.addEventListener('pointerdown', (event) => {
    resizing = true
    tocResizer.setPointerCapture(event.pointerId)
    document.body.classList.add('toc-resizing')
    event.preventDefault()
  })
  tocResizer.addEventListener('pointermove', (event) => {
    if (!resizing) {
      return
    }
    setTocWidth(event.clientX)
  })
  tocResizer.addEventListener('pointerup', (event) => {
    if (!resizing) {
      return
    }
    resizing = false
    tocResizer.releasePointerCapture(event.pointerId)
    document.body.classList.remove('toc-resizing')
    localStorage.setItem('md-peek:toc-width', String(Math.round(toc.getBoundingClientRect().width)))
  })
  tocResizer.addEventListener('dblclick', () => {
    localStorage.removeItem('md-peek:toc-width')
    setTocWidth(300)
  })
}
