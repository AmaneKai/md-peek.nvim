import { token } from '../dom.js'
import { send } from '../socket.js'
import { alertIcons } from './icons.js'
import { selectWithin } from './scope.js'

function localAssetUrl(path: string): string {
  return `/asset?path=${encodeURIComponent(path)}&token=${encodeURIComponent(token)}`
}

/** Post-processes new blocks: asset URLs, link behaviour, and GitHub-style alerts. */
export function decorateContent(scope: readonly Element[]): void {
  for (const image of selectWithin<HTMLImageElement>(scope, 'img[src]')) {
    const source = image.getAttribute('src')
    if (source && !/^(?:[a-z][a-z\d+.-]*:|\/\/|#)/i.test(source)) {
      image.src = localAssetUrl(source)
    }

    image.loading = 'lazy'
  }

  for (const link of selectWithin<HTMLAnchorElement>(scope, 'a[href]')) {
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

  for (const blockquote of selectWithin(scope, 'blockquote')) {
    const first = blockquote.querySelector(':scope > p:first-child')
    const match = first?.textContent?.match(/^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*/i)

    if (!first || !match) {
      continue
    }

    const kind = match[1].toLowerCase() as keyof typeof alertIcons
    const title = document.createElement('p')
    title.className = 'alert-title'
    title.innerHTML = `${alertIcons[kind]}${kind[0].toUpperCase()}${kind.slice(1)}`
    blockquote.classList.add('alert', `alert-${kind}`)
    blockquote.prepend(title)
    first.innerHTML = first.innerHTML.replace(/^\s*\[![^\]]+\]\s*(?:<br>\s*)?/i, '')
    if (!first.innerHTML.trim()) {
      first.remove()
    }
  }
}
