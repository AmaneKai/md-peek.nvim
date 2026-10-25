import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import {
  type AssetSandboxConfig,
  AssetOutsideRootError,
  AssetTypeNotAllowedError,
  defaultAssetExtensions,
  resolveDocumentAssetPath,
} from './asset-path.js'

const created: string[] = []

afterEach(() => {
  for (const directory of created.splice(0)) {
    rmSync(directory, { recursive: true, force: true })
  }
})

/**
 * <base>/outside.png            a file next to the repository
 * <base>/repo/.git/             marks the repository root
 * <base>/repo/images/logo.png   outside docs/, inside the repository
 * <base>/repo/docs/README.md    the document
 * <base>/repo/docs/...          assorted assets, including ones that must never be served
 */
function fixture() {
  const base = realpathSync(mkdtempSync(join(tmpdir(), 'md-peek-sandbox-')))
  created.push(base)
  const repo = join(base, 'repo')
  const docs = join(repo, 'docs')
  mkdirSync(join(repo, '.git'), { recursive: true })
  mkdirSync(join(repo, 'images'))
  mkdirSync(join(docs, 'sub'), { recursive: true })
  writeFileSync(join(base, 'outside.png'), 'outside')
  writeFileSync(join(repo, 'images', 'logo.png'), 'logo')
  writeFileSync(join(repo, '.env'), 'SECRET=1')
  for (const name of ['README.md', 'pic.png', 'PHOTO.PNG', 'notes.txt', 'data.json', 'script.ts']) {
    writeFileSync(join(docs, name), name)
  }
  writeFileSync(join(docs, '.env'), 'SECRET=1')
  writeFileSync(join(docs, 'noextension'), 'x')
  writeFileSync(join(docs, 'sub', 'deep.png'), 'deep')
  return { base, repo, docs, document: join(docs, 'README.md') }
}

const sandbox = (overrides: Partial<AssetSandboxConfig> = {}): AssetSandboxConfig => ({
  allowGitRoot: false,
  allowedExtensions: defaultAssetExtensions,
  ...overrides,
})

describe('asset sandbox', () => {
  it('serves images inside the document directory, including subfolders', () => {
    const { docs, document } = fixture()
    expect(resolveDocumentAssetPath(document, 'pic.png', sandbox())).toBe(join(docs, 'pic.png'))
    expect(resolveDocumentAssetPath(document, 'sub/deep.png', sandbox())).toBe(
      join(docs, 'sub', 'deep.png'),
    )
    expect(resolveDocumentAssetPath(document, './sub/../pic.png', sandbox())).toBe(
      join(docs, 'pic.png'),
    )
  })

  it('ignores query strings and fragments on the requested path', () => {
    const { docs, document } = fixture()
    expect(resolveDocumentAssetPath(document, 'pic.png?raw=1#frag', sandbox())).toBe(
      join(docs, 'pic.png'),
    )
  })

  it('matches extensions case-insensitively', () => {
    const { docs, document } = fixture()
    expect(resolveDocumentAssetPath(document, 'PHOTO.PNG', sandbox())).toBe(join(docs, 'PHOTO.PNG'))
  })

  describe('by default (document directory only)', () => {
    it('refuses siblings of the document directory, even inside a git repository', () => {
      const { document } = fixture()
      expect(() => resolveDocumentAssetPath(document, '../images/logo.png', sandbox())).toThrow(
        AssetOutsideRootError,
      )
    })

    it('refuses classic traversal and absolute paths', () => {
      const { base, document } = fixture()
      for (const requested of [
        '../../outside.png',
        '../../../outside.png',
        join(base, 'outside.png'),
        '/etc/hosts',
      ]) {
        expect(() => resolveDocumentAssetPath(document, requested, sandbox())).toThrow()
      }
    })

    it('refuses the repository .env that sat one level up', () => {
      const { document } = fixture()
      expect(() => resolveDocumentAssetPath(document, '../.env', sandbox())).toThrow()
    })
  })

  describe('with allowGitRoot', () => {
    it('serves files elsewhere in the repository but nothing beyond it', () => {
      const { repo, document } = fixture()
      const config = sandbox({ allowGitRoot: true })
      expect(resolveDocumentAssetPath(document, '../images/logo.png', config)).toBe(
        join(repo, 'images', 'logo.png'),
      )
      expect(() => resolveDocumentAssetPath(document, '../../outside.png', config)).toThrow(
        AssetOutsideRootError,
      )
    })

    it('still refuses repository secrets by type', () => {
      const { document } = fixture()
      expect(() =>
        resolveDocumentAssetPath(document, '../.env', sandbox({ allowGitRoot: true })),
      ).toThrow(AssetTypeNotAllowedError)
    })

    it('falls back to the document directory outside a repository', () => {
      const base = realpathSync(mkdtempSync(join(tmpdir(), 'md-peek-norepo-')))
      created.push(base)
      mkdirSync(join(base, 'notes'))
      writeFileSync(join(base, 'notes', 'README.md'), '#')
      writeFileSync(join(base, 'sibling.png'), 'x')
      expect(() =>
        resolveDocumentAssetPath(
          join(base, 'notes', 'README.md'),
          '../sibling.png',
          sandbox({ allowGitRoot: true }),
        ),
      ).toThrow(AssetOutsideRootError)
    })
  })

  describe('with customRoot', () => {
    it('serves anything under the root and nothing outside it', () => {
      const { base, repo, document } = fixture()
      const config = sandbox({ customRoot: repo })
      expect(resolveDocumentAssetPath(document, '../images/logo.png', config)).toBe(
        join(repo, 'images', 'logo.png'),
      )
      expect(() => resolveDocumentAssetPath(document, '../../outside.png', config)).toThrow(
        AssetOutsideRootError,
      )
      expect(base).not.toBe(repo)
    })

    it('wins over allowGitRoot', () => {
      const { docs, document } = fixture()
      const config = sandbox({ allowGitRoot: true, customRoot: docs })
      expect(() => resolveDocumentAssetPath(document, '../images/logo.png', config)).toThrow(
        AssetOutsideRootError,
      )
    })
  })

  describe('file types', () => {
    it('refuses everything that is not an allowed media type', () => {
      const { document } = fixture()
      for (const requested of ['notes.txt', 'data.json', 'script.ts', '.env', 'noextension']) {
        expect(() => resolveDocumentAssetPath(document, requested, sandbox())).toThrow(
          AssetTypeNotAllowedError,
        )
      }
    })

    it('refuses Markdown too: documents are opened in the editor, not served', () => {
      const { document } = fixture()
      expect(() => resolveDocumentAssetPath(document, 'README.md', sandbox())).toThrow(
        AssetTypeNotAllowedError,
      )
    })

    it('can be widened explicitly', () => {
      const { docs, document } = fixture()
      const config = sandbox({ allowedExtensions: new Set(['.txt']) })
      expect(resolveDocumentAssetPath(document, 'notes.txt', config)).toBe(join(docs, 'notes.txt'))
      expect(() => resolveDocumentAssetPath(document, 'pic.png', config)).toThrow(
        AssetTypeNotAllowedError,
      )
    })
  })

  describe('symlinks', () => {
    it('refuses a link that points outside the root', () => {
      const { base, docs, document } = fixture()
      symlinkSync(join(base, 'outside.png'), join(docs, 'escape.png'))
      expect(() => resolveDocumentAssetPath(document, 'escape.png', sandbox())).toThrow(
        AssetOutsideRootError,
      )
    })

    it('refuses a directory link that points outside the root', () => {
      const { base, docs, document } = fixture()
      symlinkSync(base, join(docs, 'linked-dir'))
      expect(() => resolveDocumentAssetPath(document, 'linked-dir/outside.png', sandbox())).toThrow(
        AssetOutsideRootError,
      )
    })

    it('judges the type by the real file, so a .png name cannot disguise a secret', () => {
      const { docs, document } = fixture()
      symlinkSync(join(docs, 'data.json'), join(docs, 'disguised.png'))
      expect(() => resolveDocumentAssetPath(document, 'disguised.png', sandbox())).toThrow(
        AssetTypeNotAllowedError,
      )
    })

    it('follows a link that stays inside the root', () => {
      const { docs, document } = fixture()
      symlinkSync(join(docs, 'pic.png'), join(docs, 'alias.png'))
      expect(resolveDocumentAssetPath(document, 'alias.png', sandbox())).toBe(join(docs, 'pic.png'))
    })

    it('works when the document itself is reached through a link', () => {
      const { base, docs } = fixture()
      symlinkSync(docs, join(base, 'docs-link'))
      expect(
        resolveDocumentAssetPath(join(base, 'docs-link', 'README.md'), 'pic.png', sandbox()),
      ).toBe(join(docs, 'pic.png'))
    })
  })

  it('reports a missing file as an ordinary error, not a sandbox error', () => {
    const { document } = fixture()
    let thrown: unknown
    try {
      resolveDocumentAssetPath(document, 'missing.png', sandbox())
    } catch (error) {
      thrown = error
    }
    expect(thrown).toBeInstanceOf(Error)
    expect(thrown).not.toBeInstanceOf(AssetOutsideRootError)
    expect((thrown as NodeJS.ErrnoException).code).toBe('ENOENT')
  })
})
