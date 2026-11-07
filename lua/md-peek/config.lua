return {
  debounce_ms = 80,
  cursor_debounce_ms = 45,
  auto_open = false,
  follow = true, -- keep the preview on whichever Markdown buffer you are in
  port = 0, -- 0 picks a free port; set one to forward it over SSH
  diagnostics = true, -- warn about missing link/image files and unknown #anchors while previewing
  debug = false, -- print how long each stage of opening a preview takes
  browser = "auto",
  window = { width = 1100, height = 1000 },
  position = { x = 40, y = 40 },
  nvim = {
    status_overlay = false,
    status_width = 42,
    outline_width = 76,
    outline_height = 20,
    border = "rounded",
    winblend = 6,
  },
  keymaps = {
    open = "<leader>mo",
    close = "<leader>mc",
    toggle = "<leader>mp",
    refresh = "<leader>mr",
    outline = "<leader>mm",
  },
  preview = {
    theme = "dark",
    toc = true,
    toc_open = false,
    mermaid = true, -- diagrams: the Mermaid bundle is downloaded once (curl) into the cache dir
    math = true, -- LaTeX math as native MathML: $..$, $$..$$, \\(..\\), \\[..\\]
    emoji = true,
    raw_toggle = true,
    code_copy = true,
    scroll_sync = true,
    preserve_scroll = true,
    breaks = false,
    linkify = true,
    typographer = false,
    allow_html = true,
    sanitize = true,
    remote_images = true, -- false blocks http(s) images via the CSP
    -- Which local files a document may embed: "git" (the enclosing repository, or the document's
    -- own folder when there is none), "document" (its own folder and below), or an absolute
    -- directory. Only media types are ever served.
    -- A list allows several places at once, e.g. { "git", "~/Pictures", "$XDG_DATA_HOME/img" }:
    -- the document's folder (or the repo, with "git") plus each directory. `~` and `$VAR` are
    -- expanded and directories missing on this machine are skipped, so one config fits every machine.
    asset_root = "git",
    max_width = 920,
    font = {},
    colors = {},
    custom_css = "",
  },
}
