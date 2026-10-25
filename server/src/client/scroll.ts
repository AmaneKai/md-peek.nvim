/**
 * Smooth scrolling reads well for one step down a document, but holding `j` or jumping with `50j`
 * restarts the animation every few milliseconds, so the preview lags behind the cursor and then
 * catches up. Rapid or long moves scroll instantly; a single calm step still glides.
 */
export interface ScrollContext {
  /** Time of this move and of the previous scrolling move, in milliseconds. */
  now: number
  lastTime: number
  /** Source line of this move and of the previous one. */
  line: number
  lastLine: number
}

export const RAPID_MOVE_MS = 120
export const LARGE_JUMP_LINES = 5

export function chooseScrollBehavior(context: ScrollContext): 'smooth' | 'instant' {
  const rapid = context.now - context.lastTime < RAPID_MOVE_MS
  const largeJump = Math.abs(context.line - context.lastLine) > LARGE_JUMP_LINES
  return rapid || largeJump ? 'instant' : 'smooth'
}
