import { describe, expect, it } from 'vitest'
import { chooseScrollBehavior, LARGE_JUMP_LINES, RAPID_MOVE_MS } from './scroll.js'

const base = { now: 10_000, lastTime: 0, line: 20, lastLine: 19 }

describe('chooseScrollBehavior', () => {
  it('glides on a single calm step', () => {
    expect(chooseScrollBehavior(base)).toBe('smooth')
  })

  it('jumps straight there when moves come quickly, as when holding j', () => {
    expect(chooseScrollBehavior({ ...base, lastTime: base.now - 45 })).toBe('instant')
    expect(chooseScrollBehavior({ ...base, lastTime: base.now - (RAPID_MOVE_MS - 1) })).toBe(
      'instant',
    )
  })

  it('glides again once the cursor has been still for a moment', () => {
    expect(chooseScrollBehavior({ ...base, lastTime: base.now - RAPID_MOVE_MS })).toBe('smooth')
  })

  it('jumps straight there for a long move, in either direction', () => {
    expect(chooseScrollBehavior({ ...base, line: 19 + LARGE_JUMP_LINES + 1 })).toBe('instant')
    expect(chooseScrollBehavior({ ...base, line: 19 - LARGE_JUMP_LINES - 1 })).toBe('instant')
  })

  it('still glides for a move of exactly the threshold', () => {
    expect(chooseScrollBehavior({ ...base, line: 19 + LARGE_JUMP_LINES })).toBe('smooth')
  })
})
