export class LatestTaskQueue<T> {
  private pending: T | undefined
  private running: Promise<void> | undefined

  constructor(
    private readonly runTask: (value: T) => Promise<void> | void,
    private readonly waitToStart: () => Promise<void> = () => Promise.resolve(),
  ) {}

  enqueue(value: T): Promise<void> {
    this.pending = value
    this.running ||= this.drain()
    return this.running
  }

  private async drain(): Promise<void> {
    // Let callers choose a batching boundary, such as the next animation frame.
    await this.waitToStart()
    let firstError: unknown
    try {
      while (this.pending !== undefined) {
        const value = this.pending
        this.pending = undefined
        try {
          await this.runTask(value)
        } catch (error) {
          firstError ??= error
        }
      }
    } finally {
      this.running = undefined
    }
    if (firstError !== undefined) {
      throw firstError
    }
  }
}

export class LruCache<K, V> {
  private readonly values = new Map<K, V>()

  constructor(private readonly maximumSize: number) {
    if (!Number.isInteger(maximumSize) || maximumSize < 1) {
      throw new Error('maximum cache size must be a positive integer')
    }
  }

  get(key: K): V | undefined {
    if (!this.values.has(key)) {
      return undefined
    }

    const value = this.values.get(key) as V
    this.values.delete(key)
    this.values.set(key, value)
    return value
  }

  set(key: K, value: V): void {
    this.values.delete(key)
    this.values.set(key, value)
    if (this.values.size > this.maximumSize) {
      const oldestKey = this.values.keys().next().value as K
      this.values.delete(oldestKey)
    }
  }
}
