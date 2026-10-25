/** Elements in `scope` that match `selector`, counting the scope elements themselves. */
export function selectWithin<T extends Element>(scope: readonly Element[], selector: string): T[] {
  const found = new Set<T>()
  for (const element of scope) {
    if (element.matches(selector)) {
      found.add(element as T)
    }
    for (const match of element.querySelectorAll<T>(selector)) {
      found.add(match)
    }
  }
  return [...found]
}
