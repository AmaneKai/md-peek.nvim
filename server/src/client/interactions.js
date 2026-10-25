import { openDiagramViewer } from './diagram-viewer.js'
import { article, lightbox } from './dom.js'
import { checkIcon, copyIcon } from './icons.js'
import { send } from './socket.js'
import { state } from './state.js'
import { setTocWidth, updateActiveToc } from './toc.js'

async function copyCode(button) {
  const code = button.closest('.code-block')?.querySelector('code')?.textContent || ''
  await navigator.clipboard.writeText(code)
  button.innerHTML = checkIcon
  button.classList.add('copied')
  setTimeout(() => {
    button.innerHTML = copyIcon
    button.classList.remove('copied')
  }, 1200)
}

export function initInteractions() {
  article.addEventListener('click', async (event) => {
    const copy = event.target.closest('.copy-code')
    if (copy) {
      await copyCode(copy)
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

  window.addEventListener(
    'scroll',
    () => {
      if (state.rendering) {
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
}
