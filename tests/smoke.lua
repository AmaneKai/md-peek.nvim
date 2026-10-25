local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:append(root)

-- Every module must at least load; the tests below stub most of them out.
for _, file in ipairs(vim.fn.globpath(root, "lua/md-peek/**/*.lua", false, true)) do
  local name = file:gsub("\\", "/"):match("lua/(.+)%.lua$"):gsub("/init$", ""):gsub("/", ".")
  local ok, err = pcall(require, name)
  assert(ok, "failed to load " .. name .. ": " .. tostring(err))
end
for name in pairs(package.loaded) do
  if name:match("^md%-peek") then
    package.loaded[name] = nil -- the tests below install stubs before requiring these again
  end
end

local browser_process = require("md-peek.browser.process")
local chromium = require("md-peek.browser.drivers.chromium")
local firefox = require("md-peek.browser.drivers.firefox")
local preview_url = "http://127.0.0.1:4321/?token=test"
local profile_directory = vim.fn.tempname() .. "-md-peek-test"
local window_size = { width = 1100, height = 1000 }
local window_position = { x = 40, y = 50 }

-- Drivers build the launch command for their own browser.
local chromium_command =
  chromium.command("chromium", preview_url, profile_directory, window_size, window_position)
assert(chromium_command[1] == "chromium")
assert(chromium_command[2] == "--app=" .. preview_url)
assert(chromium_command[3] == "--window-size=1100,1000")
assert(chromium_command[4] == "--window-position=40,50")
assert(chromium_command[5] == "--user-data-dir=" .. profile_directory)
assert(vim.tbl_contains(chromium_command, "--disable-extensions"))
assert(chromium.persistent_profile == true and chromium.kind == "chromium")

local firefox_command =
  firefox.command("firefox", preview_url, profile_directory, window_size, window_position)
assert(firefox_command[1] == "firefox")
assert(firefox_command[2] == "--new-instance")
assert(firefox_command[3] == "--profile")
assert(firefox_command[4] == profile_directory)
assert(firefox_command[5] == "--window-size" and firefox_command[6] == "1100,1000")
assert(firefox_command[7] == "--new-window" and firefox_command[8] == preview_url)
assert(firefox.persistent_profile == false and firefox.kind == "firefox")

-- A driver without the required parts is rejected when it is defined, not when it launches.
local base = require("md-peek.browser.drivers.base")
local defined, definition_error = pcall(base.define, { kind = "broken" })
assert(not defined and tostring(definition_error):match("candidates"), tostring(definition_error))
local minimal = base.define({
  kind = "minimal",
  candidates = function()
    return {}
  end,
  command = function()
    return {}
  end,
})
assert(minimal.persistent_profile == false and type(minimal.after_launch) == "function")

assert(vim.fn.mkdir(profile_directory, "p") == 1)
local lifecycle_tag = "md-peek:lifecycle-test"
assert(browser_process.start({
  vim.v.progpath,
  "--headless",
  "--clean",
  "-i",
  "NONE",
  "-c",
  "sleep 10",
}, lifecycle_tag, profile_directory))
assert(browser_process.is_active(lifecycle_tag))

-- Resizing keeps retrying until the window exists (a new browser has none for a moment).
local windows = require("md-peek.browser.windows")
local real_adapter, real_delays = windows.adapter, windows.RETRY_DELAYS
local attempts, finished = 0, nil
windows.RETRY_DELAYS = { 1, 1, 1, 1, 1 }
windows.adapter = function()
  return {
    resize = function(_, _, _, _, report)
      attempts = attempts + 1
      report(attempts >= 3 and 1 or 0)
    end,
  }
end
windows.resize_when_ready(
  { os = "linux" },
  lifecycle_tag,
  window_size,
  window_position,
  function(ok)
    finished = ok
  end
)
vim.wait(2000, function()
  return finished ~= nil
end)
assert(finished == true and attempts == 3, "resize should stop at the first match: " .. attempts)

-- ...gives up after the last delay when no window ever appears...
attempts, finished = 0, nil
windows.adapter = function()
  return {
    resize = function(_, _, _, _, report)
      attempts = attempts + 1
      report(0)
    end,
  }
end
windows.resize_when_ready(
  { os = "linux" },
  lifecycle_tag,
  window_size,
  window_position,
  function(ok)
    finished = ok
  end
)
vim.wait(2000, function()
  return finished ~= nil
end)
assert(finished == false and attempts == 5, "resize should try every delay: " .. attempts)

-- ...and stops at once when the preview has been closed meanwhile.
attempts, finished = 0, nil
windows.resize_when_ready(
  { os = "linux" },
  "md-peek:not-running",
  window_size,
  window_position,
  function(ok)
    finished = ok
  end
)
vim.wait(2000, function()
  return finished ~= nil
end)
assert(finished == false and attempts == 0, "a closed preview must not be resized")

-- Without any adapter (or without a resize hook) there is nothing to do, and nothing breaks.
windows.adapter = function()
  return nil
end
finished = nil
windows.resize_when_ready(
  { os = "linux" },
  lifecycle_tag,
  window_size,
  window_position,
  function(ok)
    finished = ok
  end
)
assert(finished == false)
windows.adapter, windows.RETRY_DELAYS = real_adapter, real_delays

-- Browsers are found through their driver; a fake `chromium` on PATH is enough to test that.
if vim.fn.has("win32") == 0 then
  local detect = require("md-peek.browser.detect")
  local bin = vim.fn.tempname()
  vim.fn.mkdir(bin, "p")
  vim.fn.writefile({ "#!/bin/sh" }, bin .. "/chromium")
  vim.fn.setfperm(bin .. "/chromium", "rwxr-xr-x")
  local original_path = vim.env.PATH
  vim.env.PATH = bin .. ":" .. original_path
  local found = detect.find_kind("chromium", "linux")
  vim.env.PATH = original_path
  assert(found and found.kind == "chromium" and found.binary == "chromium" and found.driver)
  assert(detect.find_kind("chromium", "plan9") == nil)
  assert(detect.find("nonsense") == nil)
end
assert(type(require("md-peek.browser.detect").capabilities()) == "table")

assert(not browser_process.stop("md-peek:another-preview", true))
assert(browser_process.stop(lifecycle_tag, true))
assert(not browser_process.is_active(lifecycle_tag))
assert(vim.fn.isdirectory(profile_directory) == 0)

local started = 0
local mock_server
mock_server = {
  ready = false,
  start = function(opts)
    started = started + 1
    mock_server.opts = opts
    return true
  end,
  stop = function()
    mock_server.ready, mock_server.port = false, nil
  end,
}
package.loaded["md-peek.server"] = mock_server
local sent = {}
package.loaded["md-peek.client"] = {
  send = function(message)
    table.insert(sent, message)
  end,
  debounce = function(_, _, callback)
    callback()
  end,
  cancel_debounced = function() end,
}
local browser_close_options
local browser_opened = 0
local browser_reason -- what the mock reports as the reason no browser can start, if any
package.loaded["md-peek.browser"] = {
  open = function()
    browser_opened = browser_opened + 1
  end,
  unavailable_reason = function()
    return browser_reason
  end,
  close = function(_, _, options)
    browser_close_options = options
  end,
  find = function()
    return nil
  end,
}

local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buffer)
vim.bo[buffer].filetype = "markdown"
vim.api.nvim_buf_set_name(buffer, vim.fn.tempname() .. ".md")
local peek = require("md-peek")
peek.setup({ debounce_ms = 12, keymaps = { open = "]p" } })
assert(peek.config.debounce_ms == 12)
assert(vim.fn.maparg("]p", "n") ~= "")

vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
  "---",
  "title: Not a heading",
  "---",
  "# First heading",
  "",
  "```markdown",
  "## Hidden in a fence",
  "```",
  "## Second heading",
})
local headings = require("md-peek.overlay").headings(buffer)
assert(#headings == 2)
assert(headings[1].title == "First heading" and headings[1].line == 4)
assert(headings[2].title == "Second heading" and headings[2].line == 9)

local events = require("md-peek.events")
local tasks = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(tasks, 0, -1, false, {
  "- [ ] open",
  "  * [x] nested done",
  "1. [X] numbered",
  "- plain item",
  "[ ] not a list",
})
assert(events.toggle_task(tasks, 1))
assert(events.toggle_task(tasks, 2))
assert(events.toggle_task(tasks, 3))
assert(not events.toggle_task(tasks, 4))
assert(not events.toggle_task(tasks, 5))
assert(not events.toggle_task(tasks, 99))
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(tasks, 0, -1, false), {
  "- [x] open",
  "  * [ ] nested done",
  "1. [ ] numbered",
  "- plain item",
  "[ ] not a list",
}))

local diagnostics = require("md-peek.diagnostics")
local notes = vim.fn.tempname()
vim.fn.mkdir(notes, "p")
vim.fn.writefile({ "x" }, notes .. "/there.md")
vim.fn.writefile({ "x" }, notes .. "/pic.png")
local doc = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(doc, notes .. "/index.md")
vim.api.nvim_buf_set_lines(doc, 0, -1, false, {
  "# Top",
  "[ok](there.md) and [gone](missing.md#x) and [web](https://example.com)",
  '![ok](pic.png) ![gone](nope.png) <img src="alt-missing.png">',
  "[good anchor](#top) [bad anchor](#nowhere) [spaced](my%20file.md)",
  "```",
  "[in fence](missing-in-fence.md)",
  "```",
})
local found = diagnostics.compute(doc)
local messages = {}
for _, item in ipairs(found) do
  messages[#messages + 1] = (item.lnum + 1) .. ":" .. item.message
end
assert(
  vim.deep_equal(messages, {
    "2:file not found: missing.md",
    "3:file not found: nope.png",
    "3:file not found: alt-missing.png",
    "4:no heading matches anchor #nowhere",
    "4:file not found: my file.md",
  }),
  vim.inspect(messages)
)

local overlay = require("md-peek.overlay")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
overlay.update_status(buffer, {})
vim.api.nvim_win_set_cursor(0, { 9, 0 })
overlay.update_status(buffer, {})
local status_buffer
for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[candidate].filetype == "md-peek-status" then
    status_buffer = candidate
  end
end
assert(status_buffer, "status overlay buffer was not created")
local found_percentage = false
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(status_buffer, -1, 0, -1, { details = true })) do
  local virtual_text = mark[4].virt_text
  if virtual_text and virtual_text[1] and virtual_text[1][1]:match("100%%") then
    found_percentage = true
  end
end
assert(found_percentage, "status overlay did not reach 100% on the final line")
overlay.close_all()

local session = require("md-peek.session")
local diagnostics = require("md-peek.diagnostics")
local notifications = {}
local original_notify = vim.notify
vim.notify = function(message)
  table.insert(notifications, message)
end

-- The server calls back when it is listening; nothing renders before that.
local function bring_up()
  mock_server.ready, mock_server.port, mock_server.token = true, 4321, "t"
  mock_server.url = "http://127.0.0.1:4321/"
  mock_server.opts.on_ready({ port = 4321, url = "http://127.0.0.1:4321/" })
end

peek.open()
assert(started == 1 and session.state() == "starting")
peek.open() -- a second open while starting does nothing
assert(started == 1)
peek.refresh()
assert(#sent == 0, "nothing may render before the server is ready")

-- Unchanged buffers are not re-rendered, but an explicit refresh always is.
bring_up()
assert(session.state() == "active")
assert(#sent == 1, "becoming ready should send the first render")
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
assert(#sent == 1, "identical content must not be re-sent")
vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "more" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
assert(#sent == 2, "changed content must be sent")
peek.refresh()
assert(#sent == 3, "refresh must always send")
peek.close()
assert(session.state() == "idle")
assert(browser_close_options.wait_for_completion == false)
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
assert(#sent == 3, "a closed session must not render")

-- A startup failure leaves an error session that a later open recovers from.
peek.open()
mock_server.opts.on_error("boom")
assert(session.state() == "error" and session.error() == "boom")
assert(notifications[#notifications]:match("boom"))
local stale = mock_server.opts
peek.open() -- clears the failed session, then starts again
assert(session.state() == "starting" and started == 3)
stale.on_ready({ port = 1, url = "http://127.0.0.1:1/" }) -- callbacks of the old session are ignored
assert(session.state() == "starting")
bring_up()
peek.shutdown()
assert(browser_close_options.wait_for_completion == true)
assert(session.state() == "idle")

-- The configured port reaches the server.
assert(mock_server.opts.port == 0)

-- Diagnostics are audited when the preview comes up and on save, never per render.
local audits = 0
local real_audit = diagnostics.update
diagnostics.update = function(...)
  audits = audits + 1
  return real_audit(...)
end
peek.open()
bring_up()
assert(audits == 1, "becoming ready audits once: " .. audits)
for index = 1, 5 do
  vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "typing " .. index })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
end
assert(audits == 1, "typing must not audit: " .. audits)
vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buffer })
assert(audits == 2, "saving audits: " .. audits)
vim.api.nvim_exec_autocmds("CursorHold", { buffer = buffer })
assert(audits == 3, "an idle cursor audits: " .. audits)

-- A task toggle from the browser renders at once, with no debounce.
local before_toggle = #sent
require("md-peek.events").handle(buffer, { type = "toggle_task", line = 1 }, {
  is_active = function()
    return true
  end,
  render = function(immediate)
    assert(immediate == true, "toggle must render immediately")
    sent[#sent + 1] = "immediate"
  end,
})
vim.wait(200, function()
  return #sent > before_toggle
end)
assert(#sent == before_toggle, "line 1 is not a task, so nothing renders")
vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { "- [ ] a task" })
local asked_immediate
require("md-peek.events").handle(buffer, { type = "toggle_task", line = 1 }, {
  is_active = function()
    return true
  end,
  render = function(immediate)
    asked_immediate = immediate
  end,
})
vim.wait(200, function()
  return asked_immediate ~= nil
end)
assert(asked_immediate == true, "a toggle must ask for an immediate render")
assert(vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] == "- [x] a task")

-- Follow mode: another Markdown buffer takes over the running preview.
local second = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(second, vim.fn.tempname() .. ".md")
vim.api.nvim_buf_set_lines(second, 0, -1, false, { "# Second document" })
vim.bo[second].filetype = "markdown"
local server_starts, renders = started, #sent
vim.api.nvim_set_current_buf(second) -- BufEnter follows
assert(session.state() == "active" and session.bufnr() == second, "the preview should follow")
assert(started == server_starts, "following must not restart the server")
assert(#sent == renders + 1 and sent[#sent].document.content == "# Second document")
vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "old buffer edit" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
assert(#sent == renders + 1, "the buffer left behind must stop rendering")
vim.api.nvim_buf_set_lines(second, -1, -1, false, { "new buffer edit" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = second })
assert(#sent == renders + 2, "the followed buffer renders")
assert(session.is_current(mock_server.opts and session.id()), "the session id survives a follow")

-- Following can be turned off, and a non-Markdown buffer never takes over.
peek.config.follow = false
vim.api.nvim_set_current_buf(buffer)
assert(session.bufnr() == second, "follow = false leaves the preview where it is")
peek.config.follow = true
local plain = vim.api.nvim_create_buf(true, false)
vim.bo[plain].filetype = "lua"
vim.api.nvim_set_current_buf(plain)
assert(session.bufnr() == second, "only Markdown buffers are followed")

-- Opening explicitly also moves the preview, instead of refusing as it used to.
peek.config.follow = false
vim.api.nvim_set_current_buf(buffer)
assert(session.bufnr() == second)
peek.open()
assert(session.bufnr() == buffer, "MdPeekOpen on another document switches to it")
peek.config.follow = true

-- :MdPeekUrl shows and copies the address of the running preview.
notifications = {}
peek.url()
assert(notifications[#notifications]:match("http://127%.0%.0%.1:4321/%?token=t"))
assert(vim.fn.getreg("+") ~= "" or vim.fn.getreg('"'):match("token=t"))
peek.close()
notifications = {}
mock_server.port, mock_server.url, mock_server.token = nil, nil, nil
peek.url()
assert(notifications[#notifications]:match("no preview is running"))

-- With no usable browser (SSH, no display) the URL is handed over instead of launching one.
browser_reason = "this is an SSH session"
local opened_before = browser_opened
notifications = {}
peek.open()
bring_up()
assert(browser_opened == opened_before, "no browser may start when it cannot")
assert(
  notifications[#notifications]:match("SSH session")
    and notifications[#notifications]:match("token=t")
)
peek.close()
browser_reason = nil
peek.open()
bring_up()
assert(browser_opened == opened_before + 1, "a browser starts when it can")
peek.close()
diagnostics.update = real_audit
vim.notify = original_notify

-- The session state machine rejects impossible transitions.
local machine = dofile(root .. "/lua/md-peek/session.lua")
assert(machine.state() == "idle")
assert(not machine.activate(), "idle cannot become active")
assert(not machine.finish(), "idle cannot finish")
local first = assert(machine.begin(7, 0))
assert(machine.state() == "starting" and machine.owns(7) and not machine.is_active(7))
assert(not machine.begin(8, 0), "a running session cannot be restarted")
assert(machine.activate() and machine.is_active(7) and machine.is_active())
assert(machine.stop() and machine.state() == "stopping")
assert(not machine.activate(), "a stopping session cannot become active")
assert(machine.finish() and machine.state() == "idle")
assert(not machine.is_current(first), "ids from finished sessions are stale")
local second = assert(machine.begin(7, 0))
assert(second ~= first and machine.is_current(second))
assert(machine.fail("x") and machine.error() == "x" and not machine.is_active(7))
assert(not machine.activate(), "a failed session cannot become active")
assert(machine.stop() and machine.finish())

-- The real server speaks one JSON object per line and reports readiness itself.
local server_dir = root .. "/server"
local node_ready = vim.fn.executable("node") == 1
  and vim.fn.isdirectory(server_dir .. "/node_modules/ws") == 1
  and vim.fn.filereadable(server_dir .. "/dist/index.js") == 1
if node_ready then
  local real = dofile(root .. "/lua/md-peek/server.lua")
  local ready, seen, failure
  seen = {}
  assert(real.start({
    server_dir = server_dir,
    preview = {},
    startup_timeout_ms = 15000,
    on_ready = function(info)
      ready = info
    end,
    on_event = function(event)
      table.insert(seen, event)
    end,
    on_error = function(message)
      failure = message
    end,
  }))
  vim.wait(15000, function()
    return ready ~= nil or failure ~= nil
  end)
  assert(ready, failure)
  assert(ready.url:match("^http://127%.0%.0%.1:%d+/$") and ready.port > 0)
  assert(real.send({ type = "bogus" }))
  vim.wait(5000, function()
    return #seen > 0
  end)
  assert(seen[1] and seen[1].type == "error", "a bad editor message should come back as an error")
  real.stop()

  -- A missing server directory is reported, not raised.
  local missing = dofile(root .. "/lua/md-peek/server.lua")
  assert(missing.start({ server_dir = vim.fn.tempname(), preview = {} }) == false)
  assert(missing.error:match("failed to start"), tostring(missing.error))

  -- A server that dies before it is listening reports an error instead of hanging.
  local empty_dir = vim.fn.tempname()
  vim.fn.mkdir(empty_dir, "p")
  vim.notify = function() end -- node's "module not found" stderr is expected here
  local broken = dofile(root .. "/lua/md-peek/server.lua")
  local broken_failure
  assert(broken.start({
    server_dir = empty_dir,
    preview = {},
    on_error = function(message)
      broken_failure = message
    end,
  }))
  vim.wait(10000, function()
    return broken_failure ~= nil
  end)
  assert(broken_failure and broken_failure:match("before it was ready"), tostring(broken_failure))
  broken.stop()
  vim.notify = original_notify
end

print("md-peek Lua smoke tests passed")
