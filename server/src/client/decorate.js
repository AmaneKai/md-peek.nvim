import { article, token } from './dom.js'
import { alertIcons } from './icons.js'
import { send } from './socket.js'

function localAssetUrl(path) {
  return `/asset?path=${encodeURIComponent(path)}&token=${encodeURIComponent(token)}`
}

/** Post-processes freshly rendered HTML: asset URLs, link behaviour, and GitHub-style alerts. */
export function decorateContent() {
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

    const kind = match[1].toLowerCase()
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
