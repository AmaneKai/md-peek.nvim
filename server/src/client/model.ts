export interface PreviewConfig {
  theme: string
  toc: boolean
  toc_open: boolean
  math: boolean
  mermaid: boolean
  emoji: boolean
  raw_toggle: boolean
  code_copy: boolean
  scroll_sync: boolean
  preserve_scroll: boolean
  breaks: boolean
  linkify: boolean
  typographer: boolean
  allow_html: boolean
  sanitize: boolean
  max_width: number
  colors: Record<string, string>
  font: { ui?: string; mono?: string; size?: number | string }
  custom_css: string
}

export interface PreviewDocument {
  content: string
  path: string
  line: number
}

export interface TocEntry {
  heading: HTMLElement
  link: HTMLAnchorElement
  line: number
}

export const defaults: PreviewConfig = {
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
