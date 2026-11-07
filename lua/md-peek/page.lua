--- The single self-contained viewer page: markup, stylesheet and a small inline script.
local highlight = require("md-peek.highlight")

local M = {}

local STYLE = [==[
:root { color-scheme: dark;--md-bg: #17191d;--md-fg: #d7dae0;--md-surface: #20232a;--md-surface-2: #292d36;--md-border: #353a45;--md-muted: #8b93a5;--md-accent: #70a5eb;--md-heading: #edf1f7;--md-code: #242830;--md-danger: #ef6b73;--md-success: #8ccf7e;--md-warning: #e5c07b;--md-important: #c397f7;--hl-keyword: #c792ea;--hl-string: #addb67;--hl-title: #addb67;--hl-number: #f78c6c;--hl-variable: #82aaff;--hl-function: #ffcb6b;--hl-meta: #89ddff;--md-font-ui: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif, 'Apple Color Emoji', 'Segoe UI Emoji';--md-font-mono: ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace;--md-font-size: 16px;--content-width: 920px;--toolbar-height: 50px;--toc-width: 300px }
:root[data-theme='github'], :root[data-theme='light'] { color-scheme: light;--md-bg: #ffffff;--md-fg: #1f2328;--md-surface: #f6f8fa;--md-surface-2: #eff2f5;--md-border: #d1d9e0;--md-muted: #59636e;--md-accent: #0969da;--md-heading: #1f2328;--md-code: #f6f8fa;--md-danger: #d1242f;--md-success: #1a7f37;--md-warning: #9a6700;--md-important: #8250df;--hl-keyword: #cf222e;--hl-string: #0a3069;--hl-title: #953800;--hl-number: #0550ae;--hl-variable: #953800;--hl-function: #8250df;--hl-meta: #0550ae }
:root[data-theme='tokyonight'] { --md-bg: #1a1b26;--md-fg: #c0caf5;--md-surface: #24283b;--md-surface-2: #292e42;--md-border: #3b4261;--md-muted: #787c99;--md-accent: #7aa2f7;--md-heading: #c0caf5;--md-code: #1f2335;--md-danger: #f7768e;--md-success: #9ece6a;--md-warning: #e0af68;--md-important: #bb9af7;--hl-keyword: #bb9af7;--hl-string: #9ece6a;--hl-title: #2ac3de;--hl-number: #ff9e64;--hl-variable: #7dcfff;--hl-function: #7aa2f7;--hl-meta: #89ddff }
:root[data-theme='gruvbox'] { --md-bg: #282828;--md-fg: #ebdbb2;--md-surface: #32302f;--md-surface-2: #3c3836;--md-border: #504945;--md-muted: #a89984;--md-accent: #fe8019;--md-heading: #fabd2f;--md-code: #32302f;--md-danger: #fb4934;--md-success: #b8bb26;--md-warning: #fabd2f;--md-important: #d3869b;--hl-keyword: #fb4934;--hl-string: #b8bb26;--hl-title: #fabd2f;--hl-number: #d3869b;--hl-variable: #83a598;--hl-function: #fabd2f;--hl-meta: #8ec07c }
:root[data-theme='rose-pine'] { --md-bg: #191724;--md-fg: #e0def4;--md-surface: #1f1d2e;--md-surface-2: #26233a;--md-border: #403d52;--md-muted: #908caa;--md-accent: #c4a7e7;--md-heading: #e0def4;--md-code: #1f1d2e;--md-danger: #eb6f92;--md-success: #9ccfd8;--md-warning: #f6c177;--md-important: #c4a7e7;--hl-keyword: #31748f;--hl-string: #f6c177;--hl-title: #9ccfd8;--hl-number: #ebbcba;--hl-variable: #9ccfd8;--hl-function: #ebbcba;--hl-meta: #c4a7e7 }
:root[data-scheme='light'] { color-scheme: light;--md-bg: #ffffff;--md-fg: #1f2328;--md-surface: #f6f8fa;--md-surface-2: #eff2f5;--md-border: #d1d9e0;--md-muted: #59636e;--md-accent: #0969da;--md-heading: #1f2328;--md-code: #f6f8fa;--md-danger: #d1242f;--md-success: #1a7f37;--md-warning: #9a6700;--md-important: #8250df;--hl-keyword: #cf222e;--hl-string: #0a3069;--hl-title: #953800;--hl-number: #0550ae;--hl-variable: #953800;--hl-function: #8250df;--hl-meta: #0550ae }
:root[data-scheme='dark'] { color-scheme: dark;--md-bg: #17191d;--md-fg: #d7dae0;--md-surface: #20232a;--md-surface-2: #292d36;--md-border: #353a45;--md-muted: #8b93a5;--md-accent: #70a5eb;--md-heading: #edf1f7;--md-code: #242830;--md-danger: #ef6b73;--md-success: #8ccf7e;--md-warning: #e5c07b;--md-important: #c397f7;--hl-keyword: #c792ea;--hl-string: #addb67;--hl-title: #addb67;--hl-number: #f78c6c;--hl-variable: #82aaff;--hl-function: #ffcb6b;--hl-meta: #89ddff }
:root[data-theme='github'][data-scheme='dark'] { --md-bg: #0d1117;--md-fg: #f0f6fc;--md-surface: #151b23;--md-surface-2: #212830;--md-border: #3d444d;--md-muted: #9198a1;--md-accent: #4493f8;--md-heading: #f0f6fc;--md-code: #151b23;--md-danger: #f85149;--md-success: #3fb950;--md-warning: #d29922;--md-important: #ab7df8;--hl-keyword: #ff7b72;--hl-string: #a5d6ff;--hl-title: #ffa657;--hl-number: #79c0ff;--hl-variable: #ffa657;--hl-function: #d2a8ff;--hl-meta: #79c0ff }
* { box-sizing: border-box }
html { scroll-padding-top: calc(var(--toolbar-height) + 24px) }
body { margin: 0;background: var(--md-bg);color: var(--md-fg);font-family: var(--md-font-ui);font-size: var(--md-font-size);transition: background-color 0.16s, color 0.16s }
button { font: inherit }
#progress { position: fixed;z-index: 100;top: 0;left: 0;width: 0;height: 2px;background: var(--md-accent) }
#toolbar { position: fixed;z-index: 90;inset: 0 0 auto 0;height: var(--toolbar-height);display: flex;align-items: center;gap: 12px;padding: 0 14px;background: color-mix(in srgb, var(--md-bg) 91%, transparent);border-bottom: 1px solid var(--md-border);backdrop-filter: blur(14px) }
#toolbar button { border: 1px solid transparent;border-radius: 6px;padding: 5px 9px;color: var(--md-muted);background: transparent;cursor: pointer;font-size: 12px }
#toolbar button:hover, #toolbar button.active { color: var(--md-fg);background: var(--md-surface);border-color: var(--md-border) }
#toc-toggle { font-size: 18px !important }
#title-wrap { min-width: 0;display: flex;align-items: baseline;gap: 9px;flex: 1 }
#document-title { overflow: hidden;text-overflow: ellipsis;white-space: nowrap;font-size: 13px }
#status { color: var(--md-muted);font-size: 10px }
.toolbar-actions { display: flex;align-items: center;gap: 3px }
#toc { position: fixed;z-index: 70;top: var(--toolbar-height);bottom: 0;left: 0;width: var(--toc-width);min-width: 240px;max-width: min(48vw, 520px);padding: 26px 14px 48px;overflow: auto;background: var(--md-surface);border-right: 1px solid var(--md-border);transition: transform 0.18s ease }
#toc-heading { position: sticky;z-index: 2;top: -26px;margin: -26px -14px 14px;padding: 23px 19px 11px;color: var(--md-muted);background: color-mix(in srgb, var(--md-surface) 94%, transparent);border-bottom: 1px solid color-mix(in srgb, var(--md-border) 70%, transparent);backdrop-filter: blur(10px);font-size: 10px;font-weight: 700;letter-spacing: 0.11em;text-transform: uppercase }
#toc-content { display: flex;flex-direction: column;gap: 4px }
#toc a { display: -webkit-box;padding: 7px 9px;overflow: hidden;color: var(--md-muted);border-left: 2px solid transparent;border-radius: 0 6px 6px 0;text-decoration: none;white-space: normal;overflow-wrap: anywhere;-webkit-box-orient: vertical;-webkit-line-clamp: 3;line-clamp: 3;line-height: 1.38;font-size: 12px }
#toc a:hover { color: var(--md-fg);background: var(--md-surface-2) }
#toc a:hover { -webkit-line-clamp: unset;line-clamp: unset }
#toc a.active { color: var(--md-fg);border-left-color: var(--md-accent);background: color-mix(in srgb, var(--md-accent) 10%, transparent) }
#toc .toc-h1 { color: color-mix(in srgb, var(--md-fg) 88%, var(--md-muted));font-weight: 620 }
#toc .toc-h2 { margin-left: 9px;padding-left: 12px }
#toc .toc-h3 { margin-left: 19px;padding-left: 12px;font-size: 11.5px }
#toc .toc-h4 { margin-left: 29px;padding-left: 12px;font-size: 11px }
.toc-empty { padding: 6px;color: var(--md-muted);font-size: 11px }
.toc-closed #toc { transform: translateX(-100%) }
#toc-resizer { position: fixed;z-index: 82;top: var(--toolbar-height);bottom: 0;left: calc(var(--toc-width) - 4px);width: 8px;cursor: col-resize;touch-action: none;transition: background-color 0.12s, opacity 0.18s }
#toc-resizer::after { content: '';position: absolute;top: 0;bottom: 0;left: 3px;width: 2px;background: transparent;transition: background-color 0.12s }
#toc-resizer:hover::after, .toc-resizing #toc-resizer::after { background: var(--md-accent) }
.toc-closed #toc-resizer { opacity: 0;pointer-events: none }
.toc-resizing { cursor: col-resize !important;user-select: none !important }
#viewport { max-width: calc(var(--content-width) + 152px);min-height: 100vh;margin-left: var(--toc-width);padding: calc(var(--toolbar-height) + 56px) 76px 150px;transition: margin-left 0.18s ease }
.toc-closed #viewport { margin-left: auto;margin-right: auto }
.markdown-body { max-width: var(--content-width);margin: 0 auto;line-height: 1.5;overflow-wrap: break-word }
.markdown-body > :first-child { margin-top: 0 !important }
.markdown-body > :last-child { margin-bottom: 0 !important }
.markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4, .markdown-body h5, .markdown-body h6 { margin-top: 24px;margin-bottom: 16px;color: var(--md-heading);font-weight: 600;line-height: 1.25 }
.markdown-body h1, .markdown-body h2 { padding-bottom: 0.3em;border-bottom: 1px solid color-mix(in srgb, var(--md-border) 70%, transparent) }
.markdown-body h1 { font-size: 2em }
.markdown-body h2 { font-size: 1.5em }
.markdown-body h3 { font-size: 1.25em }
.markdown-body h4 { font-size: 1em }
.markdown-body h5 { font-size: 0.875em }
.markdown-body h6 { color: var(--md-muted);font-size: 0.85em }
.markdown-body ul, .markdown-body ol { padding-left: 2em }
.markdown-body ul ul, .markdown-body ul ol, .markdown-body ol ol, .markdown-body ol ul { margin-top: 0;margin-bottom: 0 }
.markdown-body li + li { margin-top: 0.25em }
.markdown-body li > p { margin-top: 16px }
.markdown-body dl { padding: 0 }
.markdown-body dl dt { margin-top: 16px;padding: 0;font-size: 1em;font-style: italic;font-weight: 600 }
.markdown-body dl dd { margin-bottom: 16px;padding: 0 16px }
.markdown-body a { color: var(--md-accent);text-decoration: none }
.markdown-body a:hover { text-decoration: underline }
.markdown-body strong, .markdown-body b { font-weight: 600 }
.markdown-body hr { height: 0.25em;margin: 24px 0;padding: 0;border: 0;background: var(--md-border) }
.markdown-body img { max-width: 100%;box-sizing: content-box;background: var(--md-bg);cursor: zoom-in }
.markdown-body a > img { cursor: pointer }
.markdown-body blockquote { margin-left: 0;margin-right: 0;padding: 0 1em;color: var(--md-muted);border-left: 0.25em solid var(--md-border) }
.markdown-body blockquote > :first-child { margin-top: 0 }
.markdown-body blockquote > :last-child { margin-bottom: 0 }
.markdown-body kbd { display: inline-block;padding: 3px 5px;color: var(--md-fg);border: 1px solid color-mix(in srgb, var(--md-border) 70%, transparent);border-bottom-color: var(--md-border);border-radius: 6px;background: var(--md-surface);box-shadow: inset 0 -1px 0 color-mix(in srgb, var(--md-border) 70%, transparent);font: 11px/10px var(--md-font-mono);vertical-align: middle }
.markdown-body code, .markdown-body kbd, .markdown-body samp, .markdown-body pre, #source code { font-family: var(--md-font-mono);font-size: 85% }
.markdown-body :not(pre) > code { margin: 0;padding: 0.2em 0.4em;border-radius: 6px;background: color-mix(in srgb, var(--md-muted) 20%, transparent);white-space: break-spaces }
.markdown-body table { display: block;width: max-content;max-width: 100%;overflow: auto;border-spacing: 0;border-collapse: collapse;font-variant: tabular-nums }
.markdown-body th, .markdown-body td { padding: 6px 13px;border: 1px solid var(--md-border) }
.markdown-body th { font-weight: 600 }
.markdown-body tr { background: var(--md-bg);border-top: 1px solid color-mix(in srgb, var(--md-border) 70%, transparent) }
.markdown-body tr:nth-child(2n) { background: var(--md-surface) }
.code-block { position: relative;border-radius: 6px;background: var(--md-code) }
.code-block pre { margin: 0;padding: 16px;overflow: auto;line-height: 1.45;word-wrap: normal }
.code-block code { display: inline;padding: 0;margin: 0;overflow: visible;font-size: 100%;line-height: inherit;white-space: pre;word-break: normal;background: transparent;border: 0 }
.code-tools { position: absolute;z-index: 2;top: 8px;right: 8px;display: flex;opacity: 0;transition: opacity 0.12s }
.code-block:hover .code-tools, .code-tools:focus-within { opacity: 1 }
.copy-code { display: grid;place-items: center;width: 32px;height: 32px;padding: 0;color: var(--md-muted);border: 1px solid var(--md-border);border-radius: 6px;background: var(--md-surface-2);cursor: pointer;transition: color 0.12s, background-color 0.12s }
.copy-code:hover { color: var(--md-fg);background: color-mix(in srgb, var(--md-surface-2) 70%, var(--md-border)) }
.copy-code.copied { color: var(--md-success) }
.octicon { display: inline-block;flex-shrink: 0;fill: currentColor;vertical-align: text-bottom }
.task-list-item { list-style-type: none }
.task-list-item + .task-list-item { margin-top: 4px }
.task-list-item-checkbox { margin: 0 0.2em 0.25em -1.4em;vertical-align: middle;accent-color: var(--md-accent);cursor: pointer }
tr[data-source-line].active-source { border-radius: 0;box-shadow: none }
tr[data-source-line].active-source::before { display: none }
.footnotes { margin-top: 24px;padding-top: 16px;border-top: 1px solid var(--md-border);color: var(--md-muted);font-size: 12px }
.footnotes-sep { display: none }
.footnote-backref { margin-left: 4px }
.frontmatter { margin-bottom: 16px;color: var(--md-muted);border: 1px solid var(--md-border);border-radius: 6px;background: var(--md-surface);font-size: 12px }
.frontmatter summary { padding: 8px 16px;cursor: pointer }
.frontmatter pre { margin: 0;padding: 16px;overflow: auto;border-top: 1px solid var(--md-border);font-family: var(--md-font-mono) }
.markdown-body .alert { --alert-color: var(--md-accent);padding: 0.5rem 1rem;color: inherit;border-left: 0.25em solid var(--alert-color) }
.alert-title { display: flex;align-items: center;gap: 8px;color: var(--alert-color);font-weight: 500;line-height: 1 }
.markdown-body .alert-tip { --alert-color: var(--md-success) }
.markdown-body .alert-important { --alert-color: var(--md-important) }
.markdown-body .alert-warning { --alert-color: var(--md-warning) }
.markdown-body .alert-caution { --alert-color: var(--md-danger) }
[data-source-line] { --active-tint: color-mix(in srgb, var(--md-accent) 8%, transparent);position: relative;scroll-margin-top: calc(var(--toolbar-height) + 26px);transition: box-shadow 0.16s, background-color 0.16s }
[data-source-line].active-source { border-radius: 0 6px 6px 0;background-color: var(--active-tint);box-shadow: 0 0 0 6px var(--active-tint) }
[data-source-line].active-source::before { content: '';position: absolute;top: -6px;bottom: -6px;left: -6px;width: 3px;background: var(--md-accent) }
#source { max-width: var(--content-width);min-height: 65vh;margin: 0 auto;padding: 20px;overflow: auto;color: var(--md-fg);border: 1px solid var(--md-border);border-radius: 6px;background: var(--md-code);line-height: 1.55;white-space: pre-wrap;tab-size: 2 }
#empty { padding: 20vh 0;color: var(--md-muted);text-align: center }
#lightbox { width: 100vw;max-width: none;height: 100vh;max-height: none;padding: 0;border: 0;background: rgba(0, 0, 0, 0.88);cursor: zoom-out }
#lightbox::backdrop { background: rgba(0, 0, 0, 0.88) }
#lightbox img { position: absolute;inset: 50% auto auto 50%;max-width: 92vw;max-height: 92vh;transform: translate(-50%, -50%) }
#lightbox button { position: absolute;z-index: 2;top: 15px;right: 19px;color: #fff;border: 0;background: transparent;cursor: pointer;font-size: 28px }
#toast { position: fixed;z-index: 120;right: 18px;bottom: 18px;padding: 8px 12px;color: var(--md-fg);border: 1px solid var(--md-border);border-radius: 6px;background: var(--md-surface);box-shadow: 0 8px 28px rgba(0, 0, 0, 0.25);opacity: 0;transform: translateY(8px);transition: 0.15s;pointer-events: none;font-size: 12px }
#toast.show { opacity: 1;transform: translateY(0) }
@media (max-width: 1100px) and (min-width: 761px) {
  #viewport { max-width: calc(var(--content-width) + 76px);padding-left: 38px;padding-right: 38px }
}
@media (max-width: 760px) {
  #toc { width: min(84vw, 330px);min-width: 0;max-width: none;resize: none;box-shadow: 10px 0 30px rgba(0, 0, 0, 0.25) }
  #viewport { margin-left: 0;padding: calc(var(--toolbar-height) + 38px) 24px 110px }
  body:not(.toc-closed) #toc { transform: translateX(0) }
  #toc-resizer { display: none }
  .toolbar-actions button { padding: 5px 6px !important }
  #export, #print { font-size: 0 !important }
  #export::after { content: '↓';font-size: 14px }
  #print::after { content: '⎙';font-size: 14px }
}
@media print {
  :root { color-scheme: light !important;--md-bg: #fff !important;--md-fg: #111 !important;--md-surface: #f5f5f5 !important;--md-surface-2: #eee !important;--md-border: #ccc !important;--md-muted: #555 !important;--md-accent: #111 !important;--md-heading: #111 !important;--md-code: #f5f5f5 !important }
  html, body { background: #fff !important;color: #111 !important }
  body { transition: none }
  #toolbar, #toc, #toc-resizer, #progress, #toast, #lightbox, #diagram-viewer { display: none !important }
  #viewport { width: auto;max-width: none;min-height: 0;margin: 0 !important;padding: 0 !important }
  .markdown-body, #source { width: auto;max-width: none }
  #source { min-height: 0;padding: 0;overflow: visible;color: #111;border: 0;background: #fff;white-space: pre-wrap;overflow-wrap: anywhere }
  .copy-code, .code-tools { display: none !important }
  .markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4, .markdown-body h5, .markdown-body h6 { break-after: avoid-page }
  .markdown-body blockquote, .markdown-body table, .markdown-body img, .code-block, .frontmatter, .mermaid, .katex-display { break-inside: avoid-page }
  .markdown-body table { display: table;width: 100%;overflow: visible }
  .markdown-body th, .markdown-body td { overflow-wrap: anywhere }
  .code-block, .code-block pre, .mermaid, .katex-display { overflow: visible }
  .code-block code { white-space: pre-wrap;overflow-wrap: anywhere }
  .hljs, .hljs * { color: #111 !important }
  .mermaid svg { max-width: 100%;height: auto }
  [data-source-line].active-source { box-shadow: none;background: transparent }
  [data-source-line].active-source::before { display: none }
  a { color: inherit !important;text-decoration: underline }
}
.hljs { color: var(--md-fg);background: transparent }
.hl-comment { color: var(--hl-comment, var(--md-muted));font-style: italic }
.hl-keyword { color: var(--hl-keyword) }
.hl-string { color: var(--hl-string) }
.hl-number { color: var(--hl-number) }
.hl-function { color: var(--hl-function) }
.hl-type { color: var(--hl-type, var(--hl-title)) }
.hl-title { color: var(--hl-title) }
.hl-constant { color: var(--hl-constant, var(--hl-number)) }
.hl-operator { color: var(--hl-operator, var(--hl-meta)) }
.hl-property { color: var(--hl-property, var(--hl-variable)) }
.hl-builtin { color: var(--hl-builtin, var(--hl-variable)) }
.hl-punctuation { color: var(--hl-punctuation, var(--md-muted)) }
.hl-tag { color: var(--hl-tag, var(--hl-keyword)) }
pre.mermaid { padding: 14px 16px;overflow: auto;border: 1px solid var(--md-border);border-radius: 6px;background: var(--md-code);font-family: var(--md-font-mono);font-size: 85% }
.math-display { margin: 1em 0;overflow-x: auto;text-align: center }
math { font-size: 1.12em }
.math-error { color: var(--md-danger) }
.footnote-ref a { text-decoration: none }
#diagram-viewer { width: 94vw; height: 92vh; max-width: none; padding: 0; border: 1px solid var(--md-border); border-radius: 8px; background: var(--md-bg); color: var(--md-fg); overflow: hidden; touch-action: none; cursor: grab }
#diagram-viewer::backdrop { background: rgba(0, 0, 0, 0.7) }
#diagram-close { position: absolute; z-index: 2; top: 10px; right: 12px; border: 0; background: var(--md-surface); color: var(--md-fg); border-radius: 6px; font-size: 22px; cursor: pointer }
#diagram-canvas { width: 100%; height: 100%; display: flex; align-items: center; justify-content: center; transform-origin: center }
#diagram-canvas svg { max-width: 90%; max-height: 90% }
pre.mermaid.rendered { background: transparent; border-color: transparent; text-align: center; white-space: normal; cursor: zoom-in }
pre.mermaid.rendered svg { max-width: 100%; height: auto }
pre.mermaid.failed { border-color: var(--md-danger) }
img.broken { opacity: 0.6; outline: 1px dashed var(--md-danger) }
]==]

local BODY = [==[
<div id="progress"></div>
<header id="toolbar">
  <button id="toc-toggle" title="Toggle table of contents" aria-label="Toggle table of contents" aria-expanded="false">☰</button>
  <div id="title-wrap"><strong id="document-title">Markdown</strong><span id="status">Connecting…</span></div>
  <div class="toolbar-actions">
    <button id="raw-toggle" title="Toggle rendered/source view">&lt;/&gt;</button>
    <button id="theme-toggle" title="Toggle light/dark theme">◐</button>
    <button id="export" title="Download rendered HTML">↓ HTML</button>
    <button id="print" title="Print or save as PDF">Print</button>
  </div>
</header>
<aside id="toc"><div id="toc-heading">On this page</div><div id="toc-content"></div></aside>
<div id="toc-resizer" aria-hidden="true"></div>
<main id="viewport">
  <article id="document" class="markdown-body"></article>
  <pre id="source" hidden><code></code></pre>
  <div id="empty">Start writing Markdown in Neovim.</div>
</main>
<dialog id="lightbox"><button aria-label="Close">×</button><img alt="Expanded preview"></dialog>
<dialog id="diagram-viewer"><button id="diagram-close" aria-label="Close">×</button><div id="diagram-canvas"></div></dialog>
<div id="toast" role="status"></div>]==]

local SCRIPT = [==[
const C = __CONFIG__, $ = (s) => document.querySelector(s), doc = $('#document'), root = document.documentElement;
const act = (body) => fetch('/act?token=' + C.token, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }).catch(() => {});
const toast = (text) => { const t = $('#toast'); t.textContent = text; t.classList.add('show'); clearTimeout(toast.t); toast.t = setTimeout(() => t.classList.remove('show'), 1400); };
let tocLinks = [], lastScrolledLine = 0;
const setToc = (open) => { document.body.classList.toggle('toc-closed', !open); $('#toc-toggle').setAttribute('aria-expanded', open); };
setToc(C.toc && C.toc_open);
if (!C.toc) { $('#toc-toggle').hidden = $('#toc').hidden = true; }
if (!C.raw_toggle) $('#raw-toggle').hidden = true;

// Incoming HTML is parsed by the browser's own (inert) <template> parser, reduced to an allowlist,
// and only then adopted. Local assets and Markdown links are rewritten on the parsed elements.
const TAGS = new Set(('a abbr audio b blockquote br caption code dd del details div dl dt em figcaption figure h1 h2 h3 h4 h5 h6 hr i img input ins kbd li mark ol p picture pre rp rt ruby s section small source span strong sub summary sup table tbody td tfoot th thead tr u ul video ' +
  'math mrow mi mn mo mtext mspace msub msup msubsup mfrac msqrt mroot mover munder munderover mtable mtr mtd menclose mstyle').split(' '));
const ATTRS = new Set(('href src alt title width height align colspan rowspan open id class name start type style data-source-line data-line data-md-link loading checked disabled controls display xmlns notation columnalign columnalignment stretchy largeop mathvariant accent linethickness displaystyle linebreak').split(' '));
const RESERVED = new Set('progress toolbar toc-toggle title-wrap document-title status toc toc-heading toc-content toc-resizer viewport document source empty lightbox toast diagram-viewer diagram-canvas diagram-close'.split(' '));
const isLocal = (v) => !!v && !/^[a-z][a-z0-9+.-]*:/i.test(v) && !/^[/#]/.test(v);
const unsafeUrl = (v, image) => { const s = v.replace(/[\u0000- \u007f-\u009f]+/g, '').toLowerCase(); return /^(javascript|vbscript):/.test(s) || (/^data:/.test(s) && !(image && /^data:image\/(png|jpeg|gif|webp);base64,/.test(s))); };
function tidy(content, assets) {
  for (const el of [...content.querySelectorAll('*')]) {
    if (!content.contains(el)) continue;
    const tag = el.localName;
    if (C.sanitize) {
      if (!TAGS.has(tag) || (tag === 'input' && el.getAttribute('type') !== 'checkbox')) { const shown = document.createElement('span'); shown.className = 'escaped-html'; shown.textContent = el.outerHTML; el.replaceWith(shown); continue; }
      for (const a of [...el.attributes]) {
        const n = a.name, v = a.value;
        const keep = ATTRS.has(n) && !(n === 'name' && tag !== 'a') && !(n === 'type' && !['ol', 'li', 'input'].includes(tag)) && !(n === 'id' && RESERVED.has(v)) &&
          !(n === 'style' && !/^\s*text-align:\s*(left|right|center)\s*;?\s*$/.test(v)) && !((n === 'href' || n === 'src') && unsafeUrl(v, n === 'src'));
        if (!keep) el.removeAttribute(n);
      }
    }
    for (const n of ['src', 'poster']) {
      const v = el.getAttribute(n);
      if (['img', 'video', 'audio', 'source'].includes(tag) && isLocal(v)) {
        let path = v.split(/[?#]/)[0]; try { path = decodeURIComponent(path); } catch (e) {}
        el.setAttribute(n, '/asset?path=' + encodeURIComponent(path).replace(/%2F/g, '/') + (assets[v] ? '&v=' + assets[v] : '') + '&token=' + C.token);
      }
    }
    if (tag === 'img') el.setAttribute('loading', 'lazy');
    if (tag === 'a') {
      const href = el.getAttribute('href') || '';
      if (isLocal(href) && /\.(md|markdown)$/i.test(href.split(/[?#]/)[0])) el.dataset.mdLink = href;
      else if (/^(https?:)?\/\//i.test(href)) { el.target = '_blank'; el.rel = 'noopener noreferrer'; }
    }
    if (tag === 'div' && el.classList.contains('code-block') && C.code_copy && !el.querySelector('.code-tools')) {
      el.insertAdjacentHTML('afterbegin', '<div class="code-tools"><button class="copy-code" title="Copy code">Copy</button></div>');
    }
  }
}
const hashed = (el) => el._h || (el._h = el.outerHTML);
function patch(html, assets) {
  const tpl = document.createElement('template'); tpl.innerHTML = html; tidy(tpl.content, assets || {});
  const old = [...doc.children], fresh = [...tpl.content.children];
  let a = 0, b = 0;
  while (a < old.length && a < fresh.length && hashed(old[a]) === fresh[a].outerHTML) a++;
  while (b < old.length - a && b < fresh.length - a && hashed(old[old.length - 1 - b]) === fresh[fresh.length - 1 - b].outerHTML) b++;
  old.slice(a, old.length - b).forEach((el) => el.remove());
  const anchor = old[old.length - b] || null;
  fresh.slice(a, fresh.length - b).forEach((el) => { el._h = el.outerHTML; doc.insertBefore(document.adoptNode(el), anchor); });
  $('#empty').hidden = doc.children.length > 0;
}
function buildToc() {
  const box = $('#toc-content'); box.textContent = ''; tocLinks = [];
  doc.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach((h) => {
    const a = document.createElement('a'); a.href = '#' + h.id; a.textContent = h.textContent; a.className = 'toc-h' + h.tagName[1]; a.dataset.line = h.dataset.sourceLine || 0;
    a.onclick = (e) => { e.preventDefault(); h.scrollIntoView({ block: 'start' }); };
    box.appendChild(a); tocLinks.push(a);
  });
  if (!tocLinks.length) box.innerHTML = '<div class="toc-empty">No headings</div>';
}
function sync(line, scroll) {
  let best = null, bestLine = 0;
  doc.querySelectorAll('[data-source-line]').forEach((el) => { const n = +el.dataset.sourceLine; if (n <= line && n >= bestLine) { best = el; bestLine = n; } });
  doc.querySelectorAll('.active-source').forEach((el) => el.classList.remove('active-source'));
  if (best) { best.classList.add('active-source'); if (scroll && C.scroll_sync) best.scrollIntoView({ block: 'nearest' }); }
  let current = null; tocLinks.forEach((a) => { if (+a.dataset.line <= line) current = a; a.classList.remove('active'); });
  if (current) current.classList.add('active');
}

// Mermaid: loaded on demand from the server (which caches it), and each diagram's SVG is kept per
// source and colour scheme so an unchanged diagram never re-renders or flickers.
const diagrams = new Map();
let mermaidReady = null, diagramId = 0;
const scheme = () => root.dataset.scheme || (getComputedStyle(root).colorScheme.includes('dark') ? 'dark' : 'light');
const loadMermaid = () => mermaidReady || (mermaidReady = new Promise((ok, fail) => {
  const s = document.createElement('script'); s.nonce = C.nonce; s.src = '/mermaid.js?token=' + C.token;
  s.onload = () => ok(window.mermaid); s.onerror = () => { mermaidReady = null; fail(new Error('mermaid is not available (offline, or curl is missing)')); }; document.head.appendChild(s);
}));
async function drawDiagrams() {
  const mode = scheme(), pending = [];
  if (!C.mermaid) return;
  for (const el of doc.querySelectorAll('pre.mermaid')) {
    const source = el._src || (el._src = el.textContent), key = mode + '\0' + source;
    if (el.dataset.mode === mode && el.classList.contains('rendered')) continue;
    if (diagrams.has(key)) { el.innerHTML = diagrams.get(key); el.dataset.mode = mode; el.classList.add('rendered'); } else pending.push([el, source, key]);
  }
  if (!pending.length) return;
  try {
    const mermaid = await loadMermaid();
    mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: mode === 'light' ? 'default' : 'dark' });
    for (const [el, source, key] of pending) {
      try { const { svg } = await mermaid.render('mmd' + ++diagramId, source); diagrams.set(key, svg); el.innerHTML = svg; el.dataset.mode = mode; el.classList.add('rendered'); el.classList.remove('failed'); el.title = ''; }
      catch (e) { el.classList.add('failed'); el.title = String(e.message || e).split('\n')[0]; document.getElementById('dmmd' + diagramId)?.remove(); }
    }
  } catch (e) { pending.forEach(([el]) => { el.classList.add('failed'); el.title = e.message; }); }
}
const viewer = $('#diagram-viewer'), canvas = $('#diagram-canvas');
let zoom = 1, panX = 0, panY = 0, drag = null;
const place = () => { canvas.style.transform = 'translate(' + panX + 'px,' + panY + 'px) scale(' + zoom + ')'; };
viewer.addEventListener('wheel', (e) => { e.preventDefault(); zoom = Math.min(8, Math.max(0.2, zoom * (e.deltaY < 0 ? 1.1 : 0.9))); place(); }, { passive: false });
viewer.addEventListener('pointerdown', (e) => { if (e.target.closest('button')) return; drag = { x: e.clientX - panX, y: e.clientY - panY }; viewer.setPointerCapture(e.pointerId); });
viewer.addEventListener('pointermove', (e) => { if (drag) { panX = e.clientX - drag.x; panY = e.clientY - drag.y; place(); } });
viewer.addEventListener('pointerup', () => { drag = null; });
viewer.addEventListener('dblclick', () => { zoom = 1; panX = panY = 0; place(); });
$('#diagram-close').onclick = () => viewer.close();

function onRender(m) {
  document.title = m.title + ' — md-peek:' + location.port;
  $('#document-title').textContent = m.title; $('#status').textContent = m.path || '';
  $('#source code').textContent = m.raw || '';
  patch(m.html, m.assets); buildToc(); drawDiagrams();
  if (m.line) { const move = !(C.preserve_scroll && m.line === lastScrolledLine); sync(m.line, move); if (move) lastScrolledLine = m.line; }
  if (m.sent_at) act({ type: 'rendered', latency_ms: Math.max(0, Date.now() - m.sent_at) });
}
const initial = $('#initial'); if (initial && initial.textContent) onRender(JSON.parse(initial.textContent));
const es = new EventSource('/events?token=' + C.token);
es.onopen = () => { $('#status').textContent = ''; };
es.onerror = () => { $('#status').textContent = 'Disconnected'; };
es.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.type === 'render') onRender(m);
  else if (m.type === 'theme') $('#nvim-theme').textContent = m.css;
  else if (m.type === 'cursor') { lastScrolledLine = m.line; sync(m.line, true); }
};
doc.addEventListener('click', (e) => {
  const t = e.target;
  const copy = t.closest('.copy-code');
  if (copy) {
    const code = copy.closest('.code-block').querySelector('code').textContent;
    (navigator.clipboard ? navigator.clipboard.writeText(code) : Promise.reject()).catch(() => { const x = document.createElement('textarea'); x.value = code; document.body.appendChild(x); x.select(); document.execCommand('copy'); x.remove(); });
    copy.textContent = 'Copied'; copy.classList.add('copied'); setTimeout(() => { copy.textContent = 'Copy'; copy.classList.remove('copied'); }, 1200); return;
  }
  if (t.matches('.task-list-item-checkbox')) { act({ type: 'toggle_task', line: +t.dataset.line }); return; }
  const md = t.closest('a[data-md-link]');
  if (md) { e.preventDefault(); act({ type: 'open_file', href: md.dataset.mdLink }); return; }
  if (t.closest('a')) return;
  const diagram = t.closest('pre.mermaid.rendered');
  if (diagram) { canvas.innerHTML = diagram.innerHTML; zoom = 1; panX = panY = 0; place(); viewer.showModal(); return; }
  if (t.tagName === 'IMG') { $('#lightbox img').src = t.src; $('#lightbox').showModal(); return; }
  const block = t.closest('[data-source-line]');
  if (block) act({ type: 'jump', line: +block.dataset.sourceLine });
});
$('#lightbox').addEventListener('click', () => $('#lightbox').close());
$('#toc-toggle').onclick = () => setToc(document.body.classList.contains('toc-closed'));
$('#raw-toggle').onclick = (e) => { const on = $('#source').hidden; $('#source').hidden = !on; doc.hidden = on; e.currentTarget.classList.toggle('active', on); };
const store = { get: () => { try { return localStorage.getItem('md-peek-scheme'); } catch (e) { return null; } }, set: (v) => { try { localStorage.setItem('md-peek-scheme', v); } catch (e) {} } };
const saved = store.get(); if (!root.dataset.scheme && C.theme !== 'nvim' && (saved === 'light' || saved === 'dark')) root.dataset.scheme = saved;
$('#theme-toggle').onclick = () => {
  root.dataset.scheme = scheme() === 'dark' ? 'light' : 'dark'; store.set(root.dataset.scheme);
  act({ type: 'set_scheme', scheme: root.dataset.scheme }); drawDiagrams();
};
const progress = () => { const el = document.scrollingElement, max = el.scrollHeight - el.clientHeight; $('#progress').style.width = (max > 0 ? Math.min(100, el.scrollTop / max * 100) : 0) + '%'; };
addEventListener('scroll', progress, { passive: true, capture: true }); addEventListener('resize', progress); new ResizeObserver(progress).observe(doc);
doc.addEventListener('error', (e) => { if (e.target.tagName === 'IMG') { e.target.title = 'Image could not be loaded (missing, or outside preview.asset_root): ' + (e.target.getAttribute('alt') || ''); e.target.classList.add('broken'); } }, true);
$('#print').onclick = () => window.print();
$('#export').onclick = () => {
  const page = '<!doctype html><html data-theme="' + (root.dataset.theme || '') + '" data-scheme="' + (root.dataset.scheme || '') + '"><head><meta charset="utf-8"><title>' + document.title.replace(/</g, '&lt;') + '</title><style>' + [...document.querySelectorAll('style')].map((x) => x.textContent).join('\n') + '</style></head><body><main id="viewport" style="margin:auto"><article class="markdown-body">' + doc.innerHTML.replace(/\/asset\?[^"]*/g, '') + '</article></main></body></html>';
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([page], { type: 'text/html' })); a.download = (document.title.split(' — ')[0] || 'document') + '.html'; a.click(); toast('Exported');
};
]==]

local function scheme_file()
  return vim.fn.stdpath("state") .. "/md-peek-scheme"
end

--- The light/dark choice made with the toolbar toggle in an earlier session, if any.
function M.load_scheme()
  local file = io.open(scheme_file(), "r")
  if not file then
    return nil
  end
  local value = vim.trim(file:read("*a") or "")
  file:close()
  return (value == "light" or value == "dark") and value or nil
end

function M.save_scheme(scheme)
  if scheme ~= "light" and scheme ~= "dark" then
    return false
  end
  pcall(vim.fn.mkdir, vim.fn.stdpath("state"), "p")
  local file = io.open(scheme_file(), "w")
  if not file then
    return false
  end
  file:write(scheme)
  file:close()
  return true
end

local function json(value)
  return (
    vim.json
      .encode(value)
      :gsub("<", "\\u003c")
      :gsub("\226\128\168", "\\u2028")
      :gsub("\226\128\169", "\\u2029")
  )
end

local function sanitize_value(value)
  value = tostring(value)
  if value:find("[;{}<>\\]") then
    return nil
  end
  return value
end

local function overrides(preview)
  local rules = {}
  local font = type(preview.font) == "table" and preview.font or {}
  local function add(name, value)
    value = value ~= nil and sanitize_value(value)
    if value and value ~= "" then
      table.insert(rules, "  " .. name .. ": " .. value .. ";")
    end
  end
  add("--md-font-ui", font.ui)
  add("--md-font-mono", font.mono)
  if type(font.size) == "number" then
    add("--md-font-size", font.size .. "px")
  else
    add("--md-font-size", font.size)
  end
  if type(preview.max_width) == "number" then
    add("--content-width", preview.max_width .. "px")
  end
  local colors = type(preview.colors) == "table" and preview.colors or {}
  local names = vim.tbl_keys(colors)
  table.sort(names)
  for _, name in ipairs(names) do
    if tostring(name):match("^[%w-]+$") then
      local key = name:match("^%-%-") and name or ("--md-" .. name)
      add(key, colors[name])
    end
  end
  if #rules == 0 then
    return ""
  end
  -- Doubled selector so these outrank the theme blocks and the light/dark toggle.
  return ":root:root:root {\n" .. table.concat(rules, "\n") .. "\n}\n"
end

--- Returns the viewer page. opts: { token, nonce, preview }.
function M.render(opts)
  opts = opts or {}
  local preview = opts.preview or {}
  local theme = type(preview.theme) == "string" and preview.theme:match("^[%w-]+$") or "dark"
  local css = STYLE:gsub("/%*NVIM_THEME%*/", "")
  css = css .. overrides(preview)
  if type(preview.custom_css) == "string" then
    css = css .. preview.custom_css:gsub("</[sS][tT][yY][lL][eE]", "<\\/style")
  end

  local config = json({
    token = opts.token or "",
    toc = preview.toc ~= false,
    toc_open = preview.toc_open == true,
    raw_toggle = preview.raw_toggle ~= false,
    scroll_sync = preview.scroll_sync ~= false,
    preserve_scroll = preview.preserve_scroll ~= false,
    theme = theme,
    nonce = opts.nonce or "",
    sanitize = preview.sanitize ~= false,
    code_copy = preview.code_copy ~= false,
    mermaid = preview.mermaid ~= false,
  })
  -- A scheme toggled in an earlier session; it would hide the colorscheme of the nvim theme.
  local scheme = (opts.scheme == "light" or opts.scheme == "dark")
      and theme ~= "nvim"
      and opts.scheme
    or nil
  local script = SCRIPT:gsub("__CONFIG__", function()
    return config
  end)

  return table.concat({
    '<!doctype html>\n<html lang="en" data-theme="'
      .. theme
      .. '"'
      .. (scheme and (' data-scheme="' .. scheme .. '"') or "")
      .. ">\n<head>\n",
    '<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n',
    "<title>md-peek</title>\n<style>\n",
    css,
    '\n</style>\n<style id="nvim-theme">\n',
    theme == "nvim" and highlight.nvim_theme_css() or "",
    "</style>\n</head>\n<body>\n",
    BODY,
    '\n<script type="application/json" id="initial">',
    opts.initial and (opts.initial:gsub("<", "\\u003c")) or "",
    '</script>\n<script nonce="' .. (opts.nonce or "") .. '">\n',
    script,
    "</script>\n</body>\n</html>\n",
  })
end

return M
