local M = {}
local uv = vim.uv or vim.loop
local server = require("md-peek.server")
local browser = require("md-peek.browser")
local overlay = require("md-peek.overlay")
local diagnostics = require("md-peek.diagnostics")
local highlight = require("md-peek.highlight")

M.config = require("md-peek.config")

local session = (function()
  local M = {}

  local ALLOWED = {
    idle = { starting = true },
    starting = { active = true, error = true, stopping = true },
    active = { error = true, stopping = true },
    stopping = { idle = true, error = true },
    error = { starting = true, stopping = true },
  }

  local current = {}
  local last_id = 0

  local function reset()
    current = { state = "idle", id = last_id }
  end
  reset()

  local function transition(to)
    if not ALLOWED[current.state][to] then
      return false, string.format("invalid session transition %s -> %s", current.state, to)
    end
    current.state = to
    return true
  end

  function M.state()
    return current.state
  end

  function M.bufnr()
    return current.bufnr
  end

  function M.error()
    return current.error
  end

  function M.id()
    return current.id
  end

  --- True while `id` still names the running session (it changes on every begin).
  function M.is_current(id)
    return id == current.id and current.state ~= "idle"
  end

  --- True once the server is up and the buffer can be rendered.
  function M.is_active(bufnr)
    return current.state == "active" and (bufnr == nil or current.bufnr == bufnr)
  end

  --- True for any session that owns `bufnr`, whether still starting or already active.
  function M.owns(bufnr)
    return (current.state == "starting" or current.state == "active") and current.bufnr == bufnr
  end

  --- Starts a session for `bufnr`; returns its id, or nil plus the reason.
  function M.begin(bufnr, now)
    local ok, err = transition("starting")
    if not ok then
      return nil, err
    end
    last_id = last_id + 1
    current = {
      state = "starting",
      id = last_id,
      bufnr = bufnr,
      opened_at = now,
      last_sent = nil,
    }
    return current.id
  end

  function M.activate()
    return transition("active")
  end

  function M.fail(message)
    local ok, err = transition("error")
    if ok then
      current.error = message
    end
    return ok, err
  end

  function M.stop()
    return transition("stopping")
  end

  --- Completes a stop: the session is gone and a new one may begin.
  function M.finish()
    local ok, err = transition("idle")
    if ok then
      reset()
    end
    return ok, err
  end

  --- Moves an active session to another buffer without restarting anything. The id stays the same,
  --- so the server's callbacks keep working; what was sent before no longer applies.
  function M.retarget(bufnr)
    if current.state ~= "active" then
      return false, "only an active session can change buffer"
    end
    current.bufnr = bufnr
    current.last_sent = nil
    return true
  end

  function M.opened_at()
    return current.opened_at
  end

  --- The last document sent to the browser, used to skip identical re-renders.
  function M.last_sent()
    return current.last_sent
  end

  function M.set_last_sent(document)
    current.last_sent = document
  end

  return M
end)()
local events = (function()
  local M = {}

  local TASK_PATTERNS = {
    "^(%s*[-*+]%s+%[)([ xX])(%].*)$",
    "^(%s*%d+[.)]%s+%[)([ xX])(%].*)$",
  }

  --- Flips the `[ ]`/`[x]` marker on a Markdown task line. Returns true when the line was a task.
  function M.toggle_task(bufnr, line)
    if
      not vim.api.nvim_buf_is_valid(bufnr)
      or line < 1
      or line > vim.api.nvim_buf_line_count(bufnr)
    then
      return false
    end
    local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
    for _, pattern in ipairs(TASK_PATTERNS) do
      local head, mark, tail = text:match(pattern)
      if head then
        local flipped = head .. (mark == " " and "x" or " ") .. tail
        vim.api.nvim_buf_set_lines(bufnr, line - 1, line, false, { flipped })
        return true
      end
    end
    return false
  end

  --- Handles one decoded event from the preview server.
  --- `session` exposes just what is needed from init.lua: is_active(), has_preview(),
  --- is_markdown(bufnr), render(immediate), follow(bufnr), trace(message), opened_ms(), open() and
  --- close().
  function M.handle(bufnr, event, session)
    if type(event) ~= "table" then
      return
    end
    vim.schedule(function()
      if event.type == "error" then
        vim.notify(
          "[md-peek] preview server rejected an editor message: " .. tostring(event.error),
          vim.log.levels.ERROR
        )
      elseif event.type == "jump" and session.is_active() and vim.api.nvim_buf_is_valid(bufnr) then
        local win = vim.fn.bufwinid(bufnr)
        if win ~= -1 then
          local target =
            math.max(1, math.min(tonumber(event.line) or 1, vim.api.nvim_buf_line_count(bufnr)))
          vim.api.nvim_set_current_win(win)
          vim.api.nvim_win_set_cursor(win, { target, 0 })
        end
      elseif event.type == "rendered" then
        -- Only reported in debug mode: the first one is the first paint after :MdPeekOpen.
        if not M.first_render_seen then
          M.first_render_seen = true
          local opened = session.opened_ms()
          if opened then
            session.trace(string.format("first render after %.0f ms", opened))
          end
        elseif tonumber(event.latency_ms) then
          session.trace(string.format("render took %.0f ms from keystroke", event.latency_ms))
        end
      elseif event.type == "toggle_task" and session.is_active() then
        local line = tonumber(event.line)
        if line and M.toggle_task(bufnr, line) then
          session.render(true) -- the user just clicked; do not wait out the typing debounce
        else
          vim.notify("[md-peek] that line is not a task list item", vim.log.levels.WARN)
        end
      elseif event.type == "open_file" and type(event.path) == "string" then
        local reopen = session.has_preview()
        local origin = vim.api.nvim_get_current_buf()
        -- Edit first: a failure (e.g. E37 on a modified buffer) must not cost the user their preview.
        local edited, err = pcall(vim.cmd.edit, vim.fn.fnameescape(event.path))
        if not edited then
          vim.notify("[md-peek] could not open linked file: " .. tostring(err), vim.log.levels.WARN)
          return
        end
        local current = vim.api.nvim_get_current_buf()
        if reopen and current ~= origin then
          if session.is_markdown(current) then
            session.follow(current) -- keep the window and server; just show the new file
          else
            session.close()
          end
        end
      end
    end)
  end

  return M
end)()

--- True for buffers md-peek can preview, by filetype or by file name.
local function is_markdown(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local filetype = vim.bo[bufnr].filetype
  if filetype == "markdown" or filetype == "mdx" then
    return true
  end
  local name = vim.api.nvim_buf_get_name(bufnr):lower()
  return name:match("%.md$") ~= nil or name:match("%.markdown$") ~= nil
end

M.session, M.events, M.is_markdown = session, events, is_markdown

local timers = {}

local function cancel_timer(key)
  local old = timers[key]
  if old then
    if not old.closed then
      old.timer:stop()
      old.timer:close()
    end
    timers[key] = nil
  end
end

--- Runs `callback` after `delay` ms unless the same `key` is debounced again first. This is a
--- field of M so tests can run callbacks synchronously.
function M.debounce(key, delay, callback)
  cancel_timer(key)
  local timer = uv.new_timer()
  local pending = { timer = timer, closed = false }
  timers[key] = pending
  timer:start(delay, 0, function()
    timer:stop()
    timer:close()
    pending.closed = true
    vim.schedule(function()
      if timers[key] ~= pending then
        return
      end
      timers[key] = nil
      callback()
    end)
  end)
end

local function cancel_debounced()
  for _, key in ipairs(vim.tbl_keys(timers)) do
    cancel_timer(key)
  end
end

local function deliver(message)
  if server.send(message) then
    return true
  end
  vim.notify("[md-peek] preview server is unavailable", vim.log.levels.WARN)
  return false
end

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
      deliver({ type = "render", document = doc, sent_at = now_ms() })
    end
  end

  if immediate then
    send()
    return
  end
  M.debounce("render", M.config.debounce_ms, send)
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
  M.debounce("cursor", M.config.cursor_debounce_ms, function()
    if not session.is_active(bufnr) or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 then
      deliver({ type = "cursor", line = vim.api.nvim_win_get_cursor(win)[1] })
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

local theme_group = vim.api.nvim_create_augroup("MdPeekTheme", { clear = true })

--- While a session runs, follow `:colorscheme` changes so the `nvim` theme stays current.
local function watch_colorscheme()
  vim.api.nvim_clear_autocmds({ group = theme_group })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = theme_group,
    callback = function()
      if session.is_active() then
        deliver({ type = "theme", css = highlight.nvim_theme_css() })
      end
    end,
  })
end

--- Stops everything a session started, whatever state it was in.
local function teardown(wait_for_browser)
  local bufnr = session.bufnr()
  vim.api.nvim_clear_autocmds({ group = theme_group })
  cancel_debounced()
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
  -- With no provider setreg("+") only warns instead of raising, so check that the text landed.
  local copied = pcall(vim.fn.setreg, "+", text) and vim.fn.getreg("+") == text
  if not copied then
    pcall(vim.fn.setreg, '"', text)
  end
end

--- The server is listening: attach to the buffer, render, and open the browser.
local function on_server_ready(bufnr, info)
  session.activate()
  trace_since_open("server ready")
  install_buffer_autocmds(bufnr)
  watch_colorscheme()
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
    preview = M.config.preview,
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
  cancel_debounced()
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
