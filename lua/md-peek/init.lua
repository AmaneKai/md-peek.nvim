local M = {}
local uv = vim.uv or vim.loop
local server = require("md-peek.server")
local client = require("md-peek.client")
local browser = require("md-peek.browser")
local overlay = require("md-peek.overlay")
local events = require("md-peek.events")

M.config = require("md-peek.config")

local active_bufnr
local generation = 0
local last_sent -- content/path of the last render, so unchanged buffers are not re-sent
local open_started
local aug = vim.api.nvim_create_augroup("MdPeek", { clear = true })

local function is_markdown(bufnr)
  local ft = vim.bo[bufnr].filetype
  local name = vim.api.nvim_buf_get_name(bufnr):lower()
  return ft == "markdown" or ft == "mdx" or name:match("%.md$") or name:match("%.markdown$")
end

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

local function render(bufnr, immediate)
  if active_bufnr ~= bufnr or not server.ready or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local function send()
    if active_bufnr == bufnr and server.ready and vim.api.nvim_buf_is_valid(bufnr) then
      local doc = document(bufnr)
      -- TextChanged, BufWritePost and FileChangedShellPost often fire for identical content.
      if
        not immediate
        and last_sent
        and last_sent.content == doc.content
        and last_sent.path == doc.path
      then
        return
      end
      last_sent = { content = doc.content, path = doc.path }
      client.send({ type = "render", document = doc })
    end
  end

  if immediate then
    send()
    return
  end
  client.debounce("render", M.config.debounce_ms, send)
end

local function sync_cursor(bufnr)
  if active_bufnr ~= bufnr or not server.ready then
    return
  end
  overlay.update_status(bufnr, {
    enabled = M.config.nvim.status_overlay,
    width = M.config.nvim.status_width,
    border = M.config.nvim.border,
    winblend = M.config.nvim.winblend,
  })
  client.debounce("cursor", M.config.cursor_debounce_ms, function()
    if active_bufnr ~= bufnr or not server.ready or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 then
      client.send({ type = "cursor", line = vim.api.nvim_win_get_cursor(win)[1] })
    end
  end)
end

local function handle_event(bufnr, line)
  events.handle(bufnr, line, {
    is_active = function()
      return active_bufnr == bufnr
    end,
    has_preview = function()
      return active_bufnr ~= nil
    end,
    is_markdown = is_markdown,
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
      if active_bufnr == bufnr and server.ready then
        sync_cursor(bufnr)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = aug,
    buffer = bufnr,
    once = true,
    callback = function()
      if active_bufnr == bufnr then
        M.close()
      end
    end,
  })
end

function M.open()
  local bufnr = vim.api.nvim_get_current_buf()
  if not is_markdown(bufnr) then
    vim.notify("[md-peek] current buffer is not Markdown", vim.log.levels.WARN)
    return
  end
  if active_bufnr == bufnr and server.ready then
    render(bufnr, true)
    return
  end
  if active_bufnr and active_bufnr ~= bufnr then
    vim.notify(
      "[md-peek] close the active preview before opening another document",
      vim.log.levels.WARN
    )
    return
  end

  active_bufnr = bufnr
  last_sent = nil
  open_started = uv.hrtime()
  generation = generation + 1
  local mine = generation
  if
    not server.start({
      server_dir = M.config.server_dir,
      preview = M.config.preview,
      on_event = function(line)
        handle_event(bufnr, line)
      end,
    })
  then
    active_bufnr = nil
    vim.notify(
      "[md-peek] " .. (server.error or "could not start preview server"),
      vim.log.levels.ERROR
    )
    return
  end

  local started = uv.hrtime()
  local function trace(stage)
    if M.config.debug then
      vim.notify(
        string.format("[md-peek] %s after %.0f ms", stage, (uv.hrtime() - open_started) / 1e6)
      )
    end
  end
  local function await_ready()
    if mine ~= generation or active_bufnr ~= bufnr then
      return
    end
    if server.ready then
      trace("server ready")
      install_buffer_autocmds(bufnr)
      render(bufnr, true)
      overlay.update_status(bufnr, {
        enabled = M.config.nvim.status_overlay,
        width = M.config.nvim.status_width,
        border = M.config.nvim.border,
        winblend = M.config.nvim.winblend,
      })
      browser.open(
        server.url .. "?token=" .. server.token,
        M.config.window,
        M.config.position,
        M.config.browser
      )
      trace("browser launched")
      return
    end
    if server.error then
      active_bufnr = nil
      vim.notify("[md-peek] " .. server.error, vim.log.levels.ERROR)
      return
    end
    if (uv.hrtime() - started) / 1e6 >= M.config.startup_timeout_ms then
      M.close()
      vim.notify("[md-peek] preview server startup timed out", vim.log.levels.ERROR)
      return
    end
    vim.defer_fn(await_ready, 40)
  end
  await_ready()
end

local function close_preview(wait_for_browser)
  generation = generation + 1
  client.cancel_debounced()
  overlay.close_all()
  if server.port then
    browser.close(
      "md-peek:" .. server.port,
      M.config.browser,
      { wait_for_completion = wait_for_browser }
    )
  end
  server.stop()
  active_bufnr = nil
  last_sent = nil
end

function M.close()
  close_preview(false)
end

function M.shutdown()
  close_preview(true)
end

function M.toggle()
  if active_bufnr then
    M.close()
  else
    M.open()
  end
end

function M.refresh()
  local bufnr = vim.api.nvim_get_current_buf()
  if active_bufnr ~= bufnr then
    vim.notify("[md-peek] this buffer does not own the active preview", vim.log.levels.WARN)
    return
  end
  render(bufnr, true)
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
    if active_bufnr == bufnr and server.ready then
      sync_cursor(bufnr)
    end
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

vim.api.nvim_create_user_command("MdPeekOpen", M.open, {})
vim.api.nvim_create_user_command("MdPeekClose", M.close, {})
vim.api.nvim_create_user_command("MdPeekToggle", M.toggle, {})
vim.api.nvim_create_user_command("MdPeekRefresh", M.refresh, {})
vim.api.nvim_create_user_command("MdPeekOutline", M.outline, {})

return M
