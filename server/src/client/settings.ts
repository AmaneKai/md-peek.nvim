import { rawToggle, toc, tocResizer } from './dom.js'
import { store } from './store.js'
import { setTocOpen, setTocWidth } from './toc.js'

function applyConfig(): void {
  const { config } = store.getState()
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

  const variables: string[] = []
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

export function lightScheme(): boolean {
  const override = document.documentElement.dataset.scheme

  if (override === 'light') {
    return true
  }
  if (override === 'dark') {
    return false
  }

  return ['github', 'light'].includes(store.getState().config.theme)
}

/** Re-applies theme, layout and custom CSS whenever the config changes. */
export function initSettings(): void {
  store.subscribe((_state, _previous, action) => {
    if (action.type === 'CONFIG_UPDATED') {
      applyConfig()
    }
  })
}
