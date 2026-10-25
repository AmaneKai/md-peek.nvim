import { article, documentTitle, rawToggle, source } from './dom.js'
import { renderDocument } from './render.js'
import { state } from './state.js'
import { escapeHtml } from './text.js'
import { toast } from './toast.js'

function exportHtml() {
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
}

export function initToolbar() {
  rawToggle.addEventListener('click', () => {
    state.rawVisible = !state.rawVisible
    article.hidden = state.rawVisible || state.currentDocument.content.trim() === ''
    source.hidden = !state.rawVisible
    rawToggle.classList.toggle('active', state.rawVisible)
  })

  document.getElementById('theme-toggle').addEventListener('click', async () => {
    const override = document.documentElement.dataset.scheme
    if (override) {
      delete document.documentElement.dataset.scheme
      localStorage.removeItem('md-peek:scheme-override-v2')
    } else {
      const next = ['github', 'light'].includes(state.config.theme) ? 'dark' : 'light'
      document.documentElement.dataset.scheme = next
      localStorage.setItem('md-peek:scheme-override-v2', next)
    }
    state.mermaidInitialized = false
    await renderDocument(state.latestDocument)
  })

  document.getElementById('print').addEventListener('click', () => window.print())
  document.getElementById('export').addEventListener('click', exportHtml)
}
