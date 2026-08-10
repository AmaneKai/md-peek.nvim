import { describe, expect, it } from 'vitest'
import {
  parseBrowserMessage,
  parseCursorLine,
  parseEditorMessage,
  parsePreviewConfig,
  parsePreviewDocument,
} from './protocol.js'

describe('preview protocol', () => {
  it('validates and normalizes document updates', () => {
    expect(parsePreviewDocument({ content: '# Hello', path: '/tmp/readme.md' })).toEqual({
      content: '# Hello',
      path: '/tmp/readme.md',
      line: 1,
    })
    expect(parsePreviewDocument({ content: '', path: '', line: '4' }).line).toBe(4)
  })

  it('rejects malformed document and cursor updates', () => {
    expect(() => parsePreviewDocument({ content: 42, path: '/tmp/readme.md' })).toThrow()
    expect(() => parseCursorLine({ line: 0 })).toThrow()
    expect(() => parseCursorLine({ line: 'not-a-line' })).toThrow()
  })

  it('only accepts known browser message shapes', () => {
    expect(parseBrowserMessage({ type: 'jump', line: '7' })).toEqual({ type: 'jump', line: 7 })
    expect(() => parseBrowserMessage({ type: 'open_file', href: '' })).toThrow()
    expect(() => parseBrowserMessage({ type: 'unknown' })).toThrow()
  })

  it('validates messages from the persistent editor channel', () => {
    expect(
      parseEditorMessage({
        type: 'render',
        document: { content: '# Hello', path: '/tmp/readme.md', line: 3 },
      }),
    ).toMatchObject({ type: 'render', document: { line: 3 } })
    expect(parseEditorMessage({ type: 'cursor', line: '9' })).toEqual({
      type: 'cursor',
      line: 9,
    })
    expect(() => parseEditorMessage({ type: 'render', document: null })).toThrow()
  })

  it('validates preview configuration at the environment boundary', () => {
    expect(parsePreviewConfig('{"toc":false,"max_width":1000}')).toMatchObject({
      toc: false,
      max_width: 1000,
    })
    expect(() => parsePreviewConfig('{"toc":"yes"}')).toThrow()
    expect(() => parsePreviewConfig('not-json')).toThrow()
  })

  it('normalizes empty Lua tables encoded as JSON arrays', () => {
    expect(parsePreviewConfig('{"font":[],"colors":[]}')).toMatchObject({
      font: {},
      colors: {},
    })
  })
})
