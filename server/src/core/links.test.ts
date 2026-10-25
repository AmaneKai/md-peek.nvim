import { describe, expect, it } from 'vitest'
import { resolveMarkdownLink } from './links.js'

const document = '/notes/project/index.md'

describe('resolveMarkdownLink', () => {
  it('resolves relative Markdown links against the document', () => {
    expect(resolveMarkdownLink(document, 'other.md')).toBe('/notes/project/other.md')
    expect(resolveMarkdownLink(document, './sub/page.markdown')).toBe(
      '/notes/project/sub/page.markdown',
    )
    expect(resolveMarkdownLink(document, '../top.mdx')).toBe('/notes/top.mdx')
  })

  it('drops anchors and queries, and decodes percent-escapes', () => {
    expect(resolveMarkdownLink(document, 'other.md#section')).toBe('/notes/project/other.md')
    expect(resolveMarkdownLink(document, 'other.md?x=1#y')).toBe('/notes/project/other.md')
    expect(resolveMarkdownLink(document, 'my%20notes.md')).toBe('/notes/project/my notes.md')
  })

  it('survives a malformed percent-escape', () => {
    expect(resolveMarkdownLink(document, '100%.md')).toBe('/notes/project/100%.md')
  })

  it('ignores URLs and bare anchors', () => {
    for (const href of ['https://example.com/a.md', 'mailto:me@example.com', '#heading', '']) {
      expect(resolveMarkdownLink(document, href)).toBeUndefined()
    }
  })

  it('refuses anything that is not a Markdown file', () => {
    for (const href of ['/etc/hosts', '../../etc/passwd', 'script.sh', 'image.png', 'noext']) {
      expect(() => resolveMarkdownLink(document, href)).toThrow(/non-Markdown/)
    }
  })

  it('matches extensions case-insensitively', () => {
    expect(resolveMarkdownLink(document, 'README.MD')).toBe('/notes/project/README.MD')
  })

  it('needs an open document', () => {
    expect(() => resolveMarkdownLink('', 'other.md')).toThrow(/active Markdown document/)
  })
})
