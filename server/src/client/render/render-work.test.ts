import { describe, expect, it } from 'vitest'
import { LatestTaskQueue, LruCache } from './render-work.js'

describe('latest task queue', () => {
  it('keeps only the newest task before a scheduled batch starts', async () => {
    const completed: number[] = []
    let startBatch: (() => void) | undefined
    const batchScheduled = new Promise<void>((resolve) => {
      startBatch = resolve
    })
    const queue = new LatestTaskQueue<number>(
      (value) => {
        completed.push(value)
      },
      () => batchScheduled,
    )

    const idle = queue.enqueue(1)
    queue.enqueue(2)
    startBatch?.()
    await idle

    expect(completed).toEqual([2])
  })

  it('drops superseded pending work while the current task is running', async () => {
    const completed: number[] = []
    let releaseFirst: (() => void) | undefined
    const firstBlocked = new Promise<void>((resolve) => {
      releaseFirst = resolve
    })
    const queue = new LatestTaskQueue<number>(async (value) => {
      if (value === 1) {
        await firstBlocked
      }
      completed.push(value)
    })

    const idle = queue.enqueue(1)
    await Promise.resolve()
    queue.enqueue(2)
    queue.enqueue(3)
    releaseFirst?.()
    await idle

    expect(completed).toEqual([1, 3])
  })

  it('accepts more work after becoming idle', async () => {
    const completed: string[] = []
    const queue = new LatestTaskQueue<string>((value) => {
      completed.push(value)
    })

    await queue.enqueue('first')
    await queue.enqueue('second')

    expect(completed).toEqual(['first', 'second'])
  })

  it('drains newer work before reporting a task failure', async () => {
    const completed: number[] = []
    let releaseFirst: (() => void) | undefined
    const firstBlocked = new Promise<void>((resolve) => {
      releaseFirst = resolve
    })
    const queue = new LatestTaskQueue<number>(async (value) => {
      if (value === 1) {
        await firstBlocked
        throw new Error('render failed')
      }
      completed.push(value)
    })

    const idle = queue.enqueue(1)
    await Promise.resolve()
    queue.enqueue(2)
    releaseFirst?.()

    await expect(idle).rejects.toThrow('render failed')
    expect(completed).toEqual([2])
  })
})

describe('LRU cache', () => {
  it('evicts the least recently used value', () => {
    const cache = new LruCache<string, number>(2)
    cache.set('first', 1)
    cache.set('second', 2)
    expect(cache.get('first')).toBe(1)

    cache.set('third', 3)

    expect(cache.get('second')).toBeUndefined()
    expect(cache.get('first')).toBe(1)
    expect(cache.get('third')).toBe(3)
  })
})
