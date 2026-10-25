import { toc, tocContent, tocResizer, article } from './dom.js'
import { state } from './state.js'

export function setTocOpen(open) {
  document.body.classList.toggle('toc-closed', !open)
  document.getElementById('toc-toggle').setAttribute('aria-expanded', String(open))
}

export function setTocWidth(requested) {
  const maximum = Math.min(innerWidth * 0.48, 520)
  const width = Math.round(Math.max(240, Math.min(requested, maximum)))
  document.documentElement.style.setProperty('--toc-width', `${width}px`)
  return width
}

export function setActiveToc(heading) {
  for (const entry of state.tocEntries) {
    entry.link.classList.toggle('active', entry.heading === heading)
  }

  const active = state.tocEntries.find((entry) => entry.heading === heading)

  if (active && !active.link.matches(':hover')) {
    active.link.scrollIntoView({ block: 'nearest' })
  }
}

export function updateActiveToc() {
  if (!state.tocEntries.length) {
    return
  }

  const threshold =
    Number.parseFloat(
      getComputedStyle(document.documentElement).getPropertyValue('--toolbar-height'),
    ) + 72
  let active = state.tocEntries[0]

  for (const entry of state.tocEntries) {
    if (entry.heading.getBoundingClientRect().top > threshold) {
      break
    }

    active = entry
  }

  setActiveToc(active.heading)
}

export function buildToc() {
  tocContent.innerHTML = ''
  const headings = [...article.querySelectorAll('h1, h2, h3, h4')]
  state.tocEntries = []

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
    state.tocEntries.push({ heading, link, line: Number(heading.dataset.sourceLine) || 1 })
    fragment.appendChild(link)
  }
  tocContent.appendChild(fragment)
  updateActiveToc()
}

export function initToc() {
  document.getElementById('toc-toggle').addEventListener('click', () => {
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
