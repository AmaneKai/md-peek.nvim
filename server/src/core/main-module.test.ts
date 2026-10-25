import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { afterEach, describe, expect, it } from 'vitest'
import { isMainModule } from './main-module.js'

const created: string[] = []
afterEach(() => {
  for (const directory of created.splice(0)) {
    rmSync(directory, { recursive: true, force: true })
  }
})

function script() {
  const directory = mkdtempSync(join(tmpdir(), 'md-peek-main-'))
  created.push(directory)
  const path = join(directory, 'index.js')
  writeFileSync(path, '')
  return { directory, path, url: pathToFileURL(path).href }
}

describe('isMainModule', () => {
  it('trusts import.meta.main when the runtime provides it', () => {
    const { url, path } = script()
    expect(isMainModule({ main: true, url }, '/somewhere/else.js')).toBe(true)
    expect(isMainModule({ main: false, url }, path)).toBe(false)
  })

  describe('on a runtime without import.meta.main', () => {
    it('recognises the script that was run', () => {
      const { url, path } = script()
      expect(isMainModule({ url }, path)).toBe(true)
    })

    it('is false when another script was run and this one was only imported', () => {
      const { url } = script()
      expect(isMainModule({ url }, '/usr/local/bin/other.js')).toBe(false)
    })

    it('sees through symlinks to the same file', () => {
      const { directory, url, path } = script()
      const link = join(directory, 'link.js')
      symlinkSync(path, link)
      expect(isMainModule({ url }, link)).toBe(true)
    })

    it('is false without a script path or for a path that does not exist', () => {
      const { url } = script()
      expect(isMainModule({ url }, undefined)).toBe(false)
      expect(isMainModule({ url }, '/no/such/file.js')).toBe(false)
    })
  })
})
