local function plugin_root()
  local source = debug.getinfo(1, "S").source
  local file = source:match("^@(.*)$") or source
  return vim.fn.fnamemodify(file, ":h:h:h")
end

return {
  server_dir = plugin_root() .. "/server",
  debounce_ms = 80,
  cursor_debounce_ms = 45,
  startup_timeout_ms = 10000,
  auto_open = false,
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
    math = true,
    mermaid = true,
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
    max_width = 920,
    font = {},
    colors = {},
    custom_css = "",
  },
}
