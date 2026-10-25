import { describe, expect, it } from 'vitest'
import { blockSignature, diffBlocks } from './diff.js'

describe('diffBlocks', () => {
  it('reports identical lists as all prefix', () => {
    expect(diffBlocks(['a', 'b', 'c'], ['a', 'b', 'c'])).toEqual({ prefix: 3, suffix: 0 })
  })

  it('finds a change in the middle', () => {
    expect(diffBlocks(['a', 'b', 'c', 'd'], ['a', 'X', 'c', 'd'])).toEqual({ prefix: 1, suffix: 2 })
  })

  it('finds an insertion', () => {
    expect(diffBlocks(['a', 'b'], ['a', 'new', 'b'])).toEqual({ prefix: 1, suffix: 1 })
  })

  it('finds a deletion', () => {
    expect(diffBlocks(['a', 'gone', 'b'], ['a', 'b'])).toEqual({ prefix: 1, suffix: 1 })
  })

  it('handles changes at either end', () => {
    expect(diffBlocks(['a', 'b', 'c'], ['X', 'b', 'c'])).toEqual({ prefix: 0, suffix: 2 })
    expect(diffBlocks(['a', 'b', 'c'], ['a', 'b', 'X'])).toEqual({ prefix: 2, suffix: 0 })
  })

  it('handles empty lists', () => {
    expect(diffBlocks([], [])).toEqual({ prefix: 0, suffix: 0 })
    expect(diffBlocks([], ['a', 'b'])).toEqual({ prefix: 0, suffix: 0 })
    expect(diffBlocks(['a', 'b'], [])).toEqual({ prefix: 0, suffix: 0 })
  })

  it('never lets the prefix and suffix overlap on repeated blocks', () => {
    // Removing one of three identical blocks must not report the same block twice.
    const diff = diffBlocks(['x', 'x', 'x'], ['x', 'x'])
    expect(diff.prefix + diff.suffix).toBeLessThanOrEqual(2)
    expect(diff).toEqual({ prefix: 2, suffix: 0 })
  })

  it('keeps prefix and suffix within both lists for any input', () => {
    const alphabet = ['a', 'b', 'c']
    for (let trial = 0; trial < 200; trial++) {
      const make = () =>
        Array.from(
          { length: Math.floor(Math.random() * 7) },
          () => alphabet[Math.floor(Math.random() * 3)],
        )
      const before = make()
      const after = make()
      const { prefix, suffix } = diffBlocks(before, after)
      expect(prefix + suffix).toBeLessThanOrEqual(Math.min(before.length, after.length))
      // Rebuilding from the kept head and tail plus the changed middle must give `after`.
      const middle = after.slice(prefix, after.length - suffix)
      expect([
        ...before.slice(0, prefix),
        ...middle,
        ...before.slice(before.length - suffix),
      ]).toEqual(after)
    }
  })
})

describe('blockSignature', () => {
  it('ignores source-line attributes, wherever they appear', () => {
    expect(
      blockSignature('<ul data-source-line="3"><li class="a" data-source-line="12">x</li></ul>'),
    ).toBe('<ul><li class="a">x</li></ul>')
  })

  it('ignores the random ids the task-list plugin generates', () => {
    const one = '<li><input id="task-item-481920"><label for="task-item-481920"> a</label></li>'
    const two = '<li><input id="task-item-77"><label for="task-item-77"> a</label></li>'
    expect(blockSignature(one)).toBe(blockSignature(two))
  })

  it('still tells genuinely different blocks apart', () => {
    expect(blockSignature('<p data-source-line="1">a</p>')).not.toBe(
      blockSignature('<p data-source-line="1">b</p>'),
    )
  })
})
