local M = {}
local uv = vim.uv or vim.loop
local server = require("md-peek.server")
local client = require("md-peek.client")
local browser = require("md-peek.browser")
local overlay = require("md-peek.overlay")
local events = require("md-peek.events")
local diagnostics = require("md-peek.diagnostics")
local session = require("md-peek.session")
local is_markdown = require("md-peek.markdown").is_markdown

M.config = require("md-peek.config")

local aug = vim.api.nvim_create_augroup("MdPeek", { clear = true })

local function document(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local path = vim.api.nvim_buf_get_name(bufnr)
  local win = vim.fn.bufwinid(bufnr)
  if path == "" then
    path = vim.fs.joinpath(vim.fn.getcwd(), "untitled.md")
  end
  return {
    content = table.concat(lines, "\n"),
    path = vim.fn.fnamemodify(path, ":p"),
    line = win ~= -1 and vim.api.nvim_win_get_cursor(win)[1] or 1,
  }
end

--- Epoch milliseconds, comparable with the browser's Date.now().
local function now_ms()
  local time = uv.clock_gettime("realtime")
  return math.floor(time.sec * 1000 + time.nsec / 1e6)
end

local function render(bufnr, immediate)
  if not session.is_active(bufnr) or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local function send()
    if session.is_active(bufnr) and vim.api.nvim_buf_is_valid(bufnr) then
      local doc = document(bufnr)
      local last = session.last_sent()
      -- TextChanged, BufWritePost and FileChangedShellPost often fire for identical content.
      if not immediate and last and last.content == doc.content and last.path == doc.path then
        return
      end
      session.set_last_sent({ content = doc.content, path = doc.path })
      client.send({ type = "render", document = doc, sent_at = now_ms() })
    end
  end

  if immediate then
    send()
    return
  end
  client.debounce("render", M.config.debounce_ms, send)
end

local function overlay_options()
  return {
    enabled = M.config.nvim.status_overlay,
    width = M.config.nvim.status_width,
    border = M.config.nvim.border,
    winblend = M.config.nvim.winblend,
  }
end

--- Checks links and images. Kept out of the render path: it touches the filesystem once per
--- local target, which would stutter typing in a long document.
local function audit(bufnr, force)
  if M.config.diagnostics and session.is_active(bufnr) then
    diagnostics.update(bufnr, force)
  end
end

local function sync_cursor(bufnr)
  if not session.is_active(bufnr) then
    return
  end
  overlay.update_status(bufnr, overlay_options())
  client.debounce("cursor", M.config.cursor_debounce_ms, function()
    if not session.is_active(bufnr) or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 then
      client.send({ type = "cursor", line = vim.api.nvim_win_get_cursor(win)[1] })
    end
  end)
end

local function trace(message)
  if M.config.debug then
    vim.notify("[md-peek] " .. message)
  end
end

local function trace_since_open(stage)
  local opened = session.opened_at()
  if opened then
    trace(string.format("%s after %.0f ms", stage, (uv.hrtime() - opened) / 1e6))
  end
end

local function handle_event(event)
  local bufnr = session.bufnr()
  if not bufnr then
    return
  end
  events.handle(bufnr, event, {
    is_active = function()
      return session.is_active(bufnr)
    end,
    has_preview = function()
      return session.state() ~= "idle"
    end,
    is_markdown = is_markdown,
    trace = trace,
    opened_ms = function()
      local opened = session.opened_at()
      return opened and (uv.hrtime() - opened) / 1e6 or nil
    end,
    render = function(immediate)
      render(bufnr, immediate == true)
    end,
    follow = function(target)
      return M.follow(target)
    end,
    open = M.open,
    close = M.close,
  })
end

local function install_buffer_autocmds(bufnr)
  vim.api.nvim_clear_autocmds({ group = aug, buffer = bufnr })
  vim.api.nvim_create_autocmd(
    { "TextChanged", "TextChangedI", "BufWritePost", "FileChangedShellPost" },
    {
      group = aug,
      buffer = bufnr,
      callback = function()
        render(bufnr, false)
      end,
    }
  )
  -- Link checking waits for a save (the files on disk may have changed) or for the cursor to rest.
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = aug,
    buffer = bufnr,
    callback = function()
      audit(bufnr, true)
    end,
  })
  vim.api.nvim_create_autocmd("CursorHold", {
    group = aug,
    buffer = bufnr,
    callback = function()
      audit(bufnr, false)
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = aug,
    buffer = bufnr,
    callback = function()
      sync_cursor(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    group = aug,
    buffer = bufnr,
    callback = overlay.close_status,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = aug,
    buffer = bufnr,
    callback = function()
      sync_cursor(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = aug,
    buffer = bufnr,
    once = true,
    callback = function()
      if session.owns(bufnr) then
        M.close()
      end
    end,
  })
end

--- Stops everything a session started, whatever state it was in.
local function teardown(wait_for_browser)
  local bufnr = session.bufnr()
  client.cancel_debounced()
  overlay.close_all()
  if server.port then
    browser.close(
      "md-peek:" .. server.port,
      M.config.browser,
      { wait_for_completion = wait_for_browser }
    )
  end
  if bufnr then
    diagnostics.clear(bufnr)
    vim.api.nvim_clear_autocmds({ group = aug, buffer = bufnr })
  end
  server.stop()
end

local function close_preview(wait_for_browser)
  if session.state() == "idle" then
    return
  end
  session.stop()
  teardown(wait_for_browser)
  session.finish()
end

local function copy_to_clipboard(text)
  -- Without a clipboard provider (typical over SSH) "+" fails; fall back to the unnamed register.
  if not pcall(vim.fn.setreg, "+", text) then
    pcall(vim.fn.setreg, '"', text)
  end
end

--- The server is listening: attach to the buffer, render, and open the browser.
local function on_server_ready(bufnr, info)
  session.activate()
  trace_since_open("server ready")
  install_buffer_autocmds(bufnr)
  render(bufnr, true)
  audit(bufnr, true)
  overlay.update_status(bufnr, overlay_options())

  local url = info.url .. "?token=" .. server.token
  local reason = browser.unavailable_reason(M.config.browser)
  if reason then
    -- Nothing to launch (SSH, no display, or browser = "none"): hand over the URL instead.
    copy_to_clipboard(url)
    vim.notify(
      string.format("[md-peek] not opening a browser (%s). Preview URL (copied): %s", reason, url)
    )
    return
  end
  browser.open(url, M.config.window, M.config.position, M.config.browser)
  trace_since_open("browser launched")
end

local function on_server_error(message)
  session.fail(message)
  teardown(false)
  vim.notify("[md-peek] " .. message, vim.log.levels.ERROR)
end

function M.open()
  local bufnr = vim.api.nvim_get_current_buf()
  if not is_markdown(bufnr) then
    vim.notify("[md-peek] current buffer is not Markdown", vim.log.levels.WARN)
    return
  end
  if session.is_active(bufnr) then
    render(bufnr, true)
    return
  end
  local state = session.state()
  if state == "active" then
    M.follow(bufnr) -- the preview moves to this document; nothing restarts
    return
  end
  if state == "starting" or state == "stopping" then
    if not session.owns(bufnr) then
      vim.notify(
        "[md-peek] the preview is still starting; try again in a moment",
        vim.log.levels.WARN
      )
    end
    return
  end
  if state == "error" then
    close_preview(false) -- clear the failed session before starting a new one
  end

  local id = session.begin(bufnr, uv.hrtime())
  events.first_render_seen = false
  local started = server.start({
    server_dir = M.config.server_dir,
    preview = M.config.preview,
    startup_timeout_ms = M.config.startup_timeout_ms,
    port = M.config.port,
    on_ready = function(info)
      if session.is_current(id) then
        on_server_ready(bufnr, info)
      end
    end,
    on_event = function(event)
      if session.is_current(id) then
        handle_event(event)
      end
    end,
    on_error = function(message)
      if session.is_current(id) then
        on_server_error(message)
      end
    end,
  })
  if not started then
    on_server_error(server.error or "could not start preview server")
  end
end

--- Moves the running preview to `bufnr` (a Markdown buffer): same server, same browser window,
--- the new document is rendered at once. Returns true when the preview now shows `bufnr`.
function M.follow(bufnr)
  if session.owns(bufnr) then
    return true
  end
  if session.state() ~= "active" or not is_markdown(bufnr) then
    return false
  end

  local previous = session.bufnr()
  client.cancel_debounced()
  overlay.close_status()
  diagnostics.clear(previous)
  vim.api.nvim_clear_autocmds({ group = aug, buffer = previous })
  session.retarget(bufnr)
  install_buffer_autocmds(bufnr)
  render(bufnr, true)
  audit(bufnr, true)
  overlay.update_status(bufnr, overlay_options())
  trace("now previewing " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t"))
  return true
end

--- The address of the running preview, with its session token; nil if none is running.
function M.preview_url()
  if server.url and server.token then
    return server.url .. "?token=" .. server.token
  end
end

--- Copies the preview address to the clipboard and shows it, for browsers on another machine.
function M.url()
  local url = M.preview_url()
  if not url then
    vim.notify("[md-peek] no preview is running", vim.log.levels.WARN)
    return
  end
  copy_to_clipboard(url)
  vim.notify("[md-peek] preview URL (copied): " .. url)
end

function M.close()
  close_preview(false)
end

function M.shutdown()
  close_preview(true)
end

function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  if session.state() == "idle" or (session.state() == "active" and not session.owns(bufnr)) then
    M.open()
  else
    M.close()
  end
end

function M.refresh()
  local bufnr = vim.api.nvim_get_current_buf()
  if not session.is_active(bufnr) then
    vim.notify("[md-peek] this buffer does not own the active preview", vim.log.levels.WARN)
    return
  end
  render(bufnr, true)
  audit(bufnr, true)
end

function M.outline()
  local bufnr = vim.api.nvim_get_current_buf()
  if not is_markdown(bufnr) then
    vim.notify("[md-peek] current buffer is not Markdown", vim.log.levels.WARN)
    return
  end
  overlay.open_outline(bufnr, {
    width = M.config.nvim.outline_width,
    height = M.config.nvim.outline_height,
    border = M.config.nvim.border,
    winblend = M.config.nvim.winblend,
  }, function()
    sync_cursor(bufnr)
  end)
end

local function configure_buffer(bufnr)
  for name, lhs in pairs(M.config.keymaps) do
    if lhs and lhs ~= "" and M[name] then
      vim.keymap.set(
        "n",
        lhs,
        M[name],
        { buffer = bufnr, silent = true, desc = "md-peek: " .. name }
      )
    end
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  vim.api.nvim_clear_autocmds({ group = aug, event = "FileType" })
  vim.api.nvim_create_autocmd("FileType", {
    group = aug,
    pattern = { "markdown", "mdx" },
    callback = function(args)
      configure_buffer(args.buf)
      if M.config.auto_open then
        vim.schedule(M.open)
      end
    end,
  })
  local current = vim.api.nvim_get_current_buf()
  if is_markdown(current) then
    configure_buffer(current)
    if M.config.auto_open then
      vim.schedule(M.open)
    end
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", { group = aug, callback = M.shutdown })

-- Follow mode: entering another Markdown buffer moves the preview there.
vim.api.nvim_create_autocmd("BufEnter", {
  group = aug,
  callback = function(args)
    if
      M.config.follow
      and session.state() == "active"
      and vim.bo[args.buf].buftype == ""
      and not session.owns(args.buf)
    then
      M.follow(args.buf)
    end
  end,
})

vim.api.nvim_create_user_command("MdPeekOpen", M.open, {})
vim.api.nvim_create_user_command("MdPeekClose", M.close, {})
vim.api.nvim_create_user_command("MdPeekToggle", M.toggle, {})
vim.api.nvim_create_user_command("MdPeekRefresh", M.refresh, {})
vim.api.nvim_create_user_command("MdPeekOutline", M.outline, {})
vim.api.nvim_create_user_command("MdPeekUrl", M.url, {})

return M
