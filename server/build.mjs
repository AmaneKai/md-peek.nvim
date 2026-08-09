import * as esbuild from 'esbuild'
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'

rmSync('dist', { recursive: true, force: true })
mkdirSync('dist', { recursive: true })

await esbuild.build({
  entryPoints: ['src/index.ts'],
  bundle: true,
  platform: 'node',
  format: 'esm',
  outfile: 'dist/index.js',
  external: ['ws'],
})

await esbuild.build({
  entryPoints: ['src/client.js'],
  bundle: true,
  platform: 'browser',
  format: 'esm',
  minify: true,
  outfile: 'dist/client.js',
})

for (const file of ['index.html', 'style.css']) {
  cpSync(`src/${file}`, `dist/${file}`)
}

const katexCss = readFileSync('node_modules/katex/dist/katex.min.css', 'utf8').replace(
  /,url\([^)]*\.(?:woff|ttf)\) format\("(?:woff|truetype)"\)/g,
  '',
)
writeFileSync('dist/katex.min.css', katexCss)
mkdirSync('dist/fonts', { recursive: true })
for (const file of readdirSync('node_modules/katex/dist/fonts')) {
  if (file.endsWith('.woff2')) {
    cpSync(`node_modules/katex/dist/fonts/${file}`, `dist/fonts/${file}`)
  }
}
