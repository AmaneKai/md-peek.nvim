import { describe, expect, it } from 'vitest'
import { extractFrontMatter, markdownRenderer } from './render/markdown.js'
import { defaults } from './model.js'

const lines = ['---', 'title: Note', '---', '# Heading', '', 'Body text.']

function mappedLines(source: string): string[] {
  const { markdown, lineOffset } = extractFrontMatter(source)
  const html = markdownRenderer(defaults, lineOffset).render(markdown)
  return [...html.matchAll(/data-source-line="(\d+)"/g)].map((match) => match[1])
}

describe('front matter', () => {
  it('extracts a block and offsets the following lines', () => {
    const result = extractFrontMatter(lines.join('\n'))
    expect(result.html).toContain('title: Note')
    expect(result.lineOffset).toBe(3)
    expect(result.markdown.startsWith('# Heading')).toBe(true)
  })

  it('treats CRLF text exactly like LF text', () => {
    const lf = lines.join('\n')
    const crlf = lines.join('\r\n')
    expect(extractFrontMatter(crlf)).toEqual(extractFrontMatter(lf))
    expect(mappedLines(crlf)).toEqual(['4', '6'])
    expect(mappedLines(crlf)).toEqual(mappedLines(lf))
  })

  it('leaves documents without front matter alone', () => {
    expect(extractFrontMatter('# Plain\n\ntext')).toEqual({
      markdown: '# Plain\n\ntext',
      html: '',
      lineOffset: 0,
    })
    expect(extractFrontMatter('---\nunterminated').html).toBe('')
  })
})
