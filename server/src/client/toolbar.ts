import { article, byId, documentTitle, rawToggle } from './dom.js'
import { invalidateSurface } from './render/patch.js'
import { renderDocument } from './render/pipeline.js'
import { store } from './store.js'
import { escapeHtml } from './text.js'
import { toast } from './toast.js'
import { applyVisibility } from './visibility.js'

function exportHtml(): void {
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
  const clone = article.cloneNode(true) as HTMLElement
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
  link.download = `${(documentTitle.textContent ?? '').replace(/\.[^.]+$/, '') || 'document'}.html`
  link.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
  toast('HTML exported')
}

export function initToolbar(): void {
  rawToggle.addEventListener('click', () => store.dispatch({ type: 'RAW_TOGGLED' }))

  // The raw/rendered switch is a view of the store, whoever flipped it.
  store.subscribe((state, _previous, action) => {
    if (action.type === 'RAW_TOGGLED') {
      applyVisibility(state.rendered.content.trim() === '', state.rawVisible)
      rawToggle.classList.toggle('active', state.rawVisible)
    }
  })

  byId('theme-toggle').addEventListener('click', async () => {
    const override = document.documentElement.dataset.scheme
    if (override) {
      delete document.documentElement.dataset.scheme
      localStorage.removeItem('md-peek:scheme-override-v2')
    } else {
      const next = ['github', 'light'].includes(store.getState().config.theme) ? 'dark' : 'light'
      document.documentElement.dataset.scheme = next
      localStorage.setItem('md-peek:scheme-override-v2', next)
    }
    // Diagrams were drawn with the old theme, so every block has to be built again.
    store.dispatch({ type: 'MERMAID_THEME_CHANGED' })
    invalidateSurface()
    await renderDocument(store.getState().document)
  })

  byId('print').addEventListener('click', () => window.print())
  byId('export').addEventListener('click', exportHtml)
}
