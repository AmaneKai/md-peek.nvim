import { describe, expect, it } from 'vitest'
import { defaults } from './model.js'
import { markdownRenderer } from './render/markdown.js'

const render = (source: string, overrides = {}) =>
  markdownRenderer({ ...defaults, ...overrides })
    .render(source)
    .trim()

/** The paragraph's text exactly as a browser would show it, entities decoded. */
const text = (source: string, overrides = {}) =>
  render(source, overrides)
    .replace(/<[^>]+>/g, '')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, '&')

describe('math in Markdown', () => {
  it('leaves emphasis markers inside math alone', () => {
    expect(text('Stars: $a*b*c$ and $2*x + 3*y$')).toBe('Stars: $a*b*c$ and $2*x + 3*y$')
    expect(render('$a*b*c$')).not.toContain('<em>')
    expect(text('Edges: $_x$ and $y_$')).toBe('Edges: $_x$ and $y_$')
  })

  it('keeps the backslashes LaTeX needs', () => {
    expect(text(String.raw`Braces $\{ x \}$ and $a \, b$ and $a \\ b$`)).toBe(
      String.raw`Braces $\{ x \}$ and $a \, b$ and $a \\ b$`,
    )
    expect(text(String.raw`$\sum_{i=1}^n a_i$`)).toBe(String.raw`$\sum_{i=1}^n a_i$`)
  })

  it('never turns math into HTML', () => {
    const html = render('Compare $a<b>c$ and $x<script>alert(1)</script>y$')
    expect(html).not.toContain('<b>')
    expect(html).not.toContain('<script>')
    expect(html).toContain('&lt;b&gt;')
  })

  it('stays safe when raw HTML is switched off', () => {
    const html = render('$<img src=x onerror=alert(1)>$', { allow_html: false })
    expect(html).not.toContain('<img')
  })

  it('handles display math, including across lines', () => {
    const display = String.raw`$$
\int_0^1 x\,dx = \frac{1}{2}
$$`
    expect(text(display)).toBe(display)
  })

  it('does not treat money as math', () => {
    expect(text('It costs $5 and then $10 more.')).toBe('It costs $5 and then $10 more.')
    // ...but ordinary prose around a real formula is untouched.
    expect(text('Then $x$ holds, for $5$ cases.')).toBe('Then $x$ holds, for $5$ cases.')
  })

  it('wraps dollar signs that are not math so KaTeX cannot pair them', () => {
    const html = render('It costs $5 and then $10 more.')
    expect(html.match(/<span class="not-math">\$<\/span>/g)).toHaveLength(2)
    expect(html).not.toContain('math_inline')
    // Real formulas next to prices are still recognised as one piece of text.
    expect(render('A price of $5, then $x+y$.')).toContain('$x+y$.')
    expect(render('A price of $5, then $x+y$.')).toContain('<span class="not-math">$</span>5')
  })

  it('treats an escaped dollar the same way', () => {
    expect(render(String.raw`Escaped \$5 and \$10`)).toBe(
      '<p data-source-line="1">Escaped <span class="not-math">$</span>5 and <span class="not-math">$</span>10</p>',
    )
  })

  it('keeps an escaped dollar sign literal and out of math', () => {
    expect(text(String.raw`Price \$5, formula $a*b$`)).toBe('Price $5, formula $a*b$')
  })

  it('does not look inside code', () => {
    const html = render('Use `$a*b*c$` literally, and $a*b*c$ for math.')
    expect(html).toContain('<code>$a*b*c$</code>')
    expect(html).not.toContain('<em>')
  })

  it('still renders emphasis outside math', () => {
    expect(render('*em* and $x$ and **strong**')).toContain('<em>em</em>')
    expect(render('*em* and $x$ and **strong**')).toContain('<strong>strong</strong>')
  })

  it('does nothing when math is turned off', () => {
    expect(render('$a*b*c$', { math: false })).toContain('<em>')
  })

  it('works inside links, lists and emphasis', () => {
    expect(render('- item $a*b*c$')).toContain('$a*b*c$')
    expect(render('[link $a*b*c$](https://example.com)')).toContain('$a*b*c$')
    expect(render('**bold $a*b*c$ bold**')).toContain('<strong>bold $a*b*c$ bold</strong>')
  })

  it('keeps source-line mapping intact', () => {
    expect(render('a\n\n$x*y*z$')).toContain('data-source-line="3"')
  })
})
