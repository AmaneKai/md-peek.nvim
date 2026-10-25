import { article, byId } from './dom.js'
import { checkIcon, copyIcon } from './render/icons.js'
import { send } from './socket.js'
import { store } from './store.js'
import { setTocWidth, updateActiveToc } from './toc.js'

async function copyCode(button: Element): Promise<void> {
  const code = button.closest('.code-block')?.querySelector('code')?.textContent || ''
  await navigator.clipboard.writeText(code)
  button.innerHTML = checkIcon
  button.classList.add('copied')
  setTimeout(() => {
    button.innerHTML = copyIcon
    button.classList.remove('copied')
  }, 1200)
}

export function initInteractions(): void {
  article.addEventListener('click', async (event) => {
    const target = event.target as Element
    const copy = target.closest('.copy-code')
    if (copy) {
      await copyCode(copy)
      return
    }

    if (
      target instanceof HTMLInputElement &&
      target.classList.contains('task-list-item-checkbox')
    ) {
      // Neovim owns the text: leave the box as rendered and let the re-render show the new state.
      event.preventDefault()
      const item = target.closest<HTMLElement>('[data-source-line]')
      if (item) {
        send({ type: 'toggle_task', line: Number(item.dataset.sourceLine) })
      }
      return
    }

    if (target.closest('a, button, input, label, summary')) {
      return
    }

    const image = target.closest('img')
    if (image) {
      store.dispatch({ type: 'IMAGE_ZOOMED', payload: image.src })
      return
    }

    const mermaidBlock = target.closest<HTMLElement>('.mermaid')
    if (mermaidBlock) {
      store.dispatch({ type: 'DIAGRAM_OPENED', payload: mermaidBlock })
      return
    }

    const mapped = target.closest<HTMLElement>('[data-source-line]')
    if (mapped) {
      send({ type: 'jump', line: Number(mapped.dataset.sourceLine) })
    }
  })

  window.addEventListener(
    'scroll',
    () => {
      if (store.getState().rendering) {
        return
      }
      const max = document.documentElement.scrollHeight - innerHeight
      byId('progress').style.width = `${max > 0 ? (scrollY / max) * 100 : 0}%`
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
