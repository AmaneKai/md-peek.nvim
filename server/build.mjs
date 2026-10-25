import * as esbuild from 'esbuild'
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'

const browser = { bundle: true, platform: 'browser', format: 'esm', minify: true, outdir: 'dist' }

/** The Node server Neovim runs. `ws` stays external: it is the one runtime dependency. */
function bundleServer() {
  return esbuild.build({
    entryPoints: ['src/core/daemon.ts'],
    bundle: true,
    platform: 'node',
    format: 'esm',
    outfile: 'dist/index.js',
    external: ['ws'],
  })
}

/** The page's script, split so KaTeX only downloads when a document has math. */
function bundleClient() {
  return esbuild.build({
    ...browser,
    entryPoints: { client: 'src/client/main.ts' },
    splitting: true,
    entryNames: '[name]',
    chunkNames: 'chunks/[name]-[hash]',
    // Loaded on demand at runtime; built separately by bundleMermaid.
    external: ['/mermaid.js'],
  })
}

/** Mermaid lazy-loads a chunk per diagram type; as one file it is a single committed asset. */
function bundleMermaid() {
  return esbuild.build({
    ...browser,
    entryPoints: { mermaid: 'src/client/mermaid-bundle.ts' },
    entryNames: '[name]',
  })
}

function copyPage() {
  for (const file of ['index.html', 'style.css']) {
    cpSync(`src/${file}`, `dist/${file}`)
  }
}

/** KaTeX's stylesheet without the legacy font formats; modern browsers only need woff2. */
function copyKatex() {
  const css = readFileSync('node_modules/katex/dist/katex.min.css', 'utf8').replace(
    /,url\([^)]*\.(?:woff|ttf)\) format\("(?:woff|truetype)"\)/g,
    '',
  )
  writeFileSync('dist/katex.min.css', css)

  mkdirSync('dist/fonts', { recursive: true })
  for (const file of readdirSync('node_modules/katex/dist/fonts')) {
    if (file.endsWith('.woff2')) {
      cpSync(`node_modules/katex/dist/fonts/${file}`, `dist/fonts/${file}`)
    }
  }
}

rmSync('dist', { recursive: true, force: true })
mkdirSync('dist', { recursive: true })

await Promise.all([bundleServer(), bundleClient(), bundleMermaid()])
copyPage()
copyKatex()
