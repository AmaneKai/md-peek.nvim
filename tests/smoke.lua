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
  vim.env.PATH = bin -- only the fake, so a real Chrome on the machine cannot be found first
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
local sent = {}
mock_server = {
  ready = false,
  send = function(message)
    table.insert(sent, message)
    return true
  end,
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
peek.debounce = function(_, _, callback)
  callback() -- run debounced work at once so the assertions below stay synchronous
end
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
-- A running session follows :colorscheme so the `nvim` theme stays current.
local before_theme = #sent
vim.api.nvim_exec_autocmds("ColorScheme", {})
assert(#sent == before_theme + 1 and sent[#sent].type == "theme", "ColorScheme sends the theme")
assert(sent[#sent].css:find("data-theme='nvim'", 1, true))
table.remove(sent)
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

-- highlight.lua: Tree-sitter highlighting with HTML-safe output.
local highlight = dofile(root .. "/lua/md-peek/highlight.lua")
local lua_html = highlight.highlight('local s = "<script>" -- note', "lua")
assert(lua_html:find('<span class="hl-keyword">local</span>', 1, true), lua_html)
assert(lua_html:find('class="hl-string"', 1, true) and lua_html:find('class="hl-comment"', 1, true))
assert(not lua_html:find("<script>", 1, true), "code must be escaped")
assert(lua_html:find("&lt;script&gt;", 1, true))
local c_html = highlight.highlight("int main(void) { return 0; }", "c")
assert(c_html:find('class="hl-type"', 1, true) and c_html:find('class="hl-keyword"', 1, true))
assert(highlight.highlight("# Title\n\ntext", "md"):find("<", 1, true), "md aliases markdown")
assert(highlight.highlight("a <b> & 'c'", "no-such-language") == "a &lt;b&gt; &amp; &#39;c&#39;")
assert(highlight.highlight("x < y", nil) == "x &lt; y")
assert(highlight.highlight("local a", "lua") == highlight.highlight("local a", "lua"), "cached")
assert(highlight.resolve_lang("sh") == "bash" and highlight.resolve_lang("py") == "python")
local nvim_css = highlight.nvim_theme_css()
assert(nvim_css:find("data-theme='nvim'", 1, true) and nvim_css:find("--md-fg:", 1, true))

-- compiler.lua: GFM to HTML with source lines.
local compiler = dofile(root .. "/lua/md-peek/compiler.lua")
local function compile(source, config)
  return compiler.compile(source, config or {}, "/tmp/notes/doc.md", "TOK")
end

local framed = compile("---\ntitle: x\n---\n\n# Heading\n\nText")
assert(framed.html:find('<details class="frontmatter" data-source-line="1">', 1, true))
assert(framed.html:find('<h1 id="heading" data-source-line="5">Heading</h1>', 1, true), framed.html)
assert(framed.html:find('<p data-source-line="7">Text</p>', 1, true))
assert(framed.title == "Heading")
assert(compile("text").title == "doc", "title falls back to the file name")

local headings = compile("Setext\n======\n\n## Same\n\n## Same\n\n### `Code` & <b>x</b>")
assert(#headings.toc == 4)
assert(headings.toc[1].level == 1 and headings.toc[1].id == "setext" and headings.toc[1].line == 1)
assert(headings.toc[2].id == "same" and headings.toc[3].id == "same-1", "duplicate slugs")
assert(headings.toc[3].line == 6)
assert(compile("# !!!").toc[1].id == "section")

local code = compile("```lua\nlocal x = 1\n```\n\n~~~mermaid\ngraph TD\n~~~\n")
assert(code.html:find('class="code-block" data-source-line="1"', 1, true))
assert(code.html:find('class="copy-code"', 1, true) and code.html:find("language-lua", 1, true))
assert(code.html:find('<pre class="mermaid" data-source-line="5">graph TD</pre>', 1, true))
assert(not compile("```\nx\n```", { code_copy = false }).html:find("copy-code", 1, true))
assert(compile("````\n```\nnested\n```\n````").html:find("nested", 1, true))

local grid = compile("| a | b |\n|:--|--:|\n| 1 | 2 |\n| 3 | 4 |")
assert(grid.html:find('<table data-source-line="1">', 1, true))
assert(
  grid.html:find('<tr data-source-line="3">', 1, true)
    and grid.html:find('<tr data-source-line="4">', 1, true)
)
assert(grid.html:find('<th style="text-align:left">a</th>', 1, true))
assert(grid.html:find('<td style="text-align:right">4</td>', 1, true))

local tasks = compile("- [ ] one\n- [x] two\n  - nested\n1. first\n")
assert(tasks.html:find('<li class="task-list-item" data-source-line="1">', 1, true))
assert(tasks.html:find('class="task-list-item-checkbox" data-line="2" checked', 1, true))
assert(tasks.html:find('<li data-source-line="3">nested</li>', 1, true), tasks.html)
assert(tasks.html:find("<ol", 1, true))

local alert = compile("> [!WARNING]\n> careful\n\n> plain quote")
assert(alert.html:find('<div class="alert alert-warning" data-source-line="1">', 1, true))
assert(alert.html:find('<p class="alert-title">Warning</p>', 1, true))
assert(alert.html:find('<blockquote data-source-line="4">', 1, true))

local notes = compile("Claim[^a] and more.\n\n[^a]: The note.\n\n[^unused]: x")
assert(
  notes.html:find('class="footnote-ref"', 1, true) and notes.html:find('class="footnotes"', 1, true)
)
assert(notes.html:find("The note.", 1, true))
assert(compile("a\n\n---\n\nb").html:find('<hr data-source-line="3">', 1, true))

local media = compile(
  "![pic](img/a b.png) ![rem](https://x.test/a.png)\n\n[doc](other.md#top) [site](https://x.test)"
)
assert(
  media.html:find('src="/asset?path=img/a%20b.png&amp;token=TOK"', 1, true) == nil,
  "space is not a url"
)
media = compile(
  "![pic](img/a.png) ![rem](https://x.test/a.png)\n\n[doc](other.md#top) [site](https://x.test)"
)
assert(media.html:find('src="/asset?path=img/a.png&amp;token=TOK"', 1, true), media.html)
assert(media.html:find('src="https://x.test/a.png"', 1, true))
assert(media.html:find('data-md-link="other.md#top"', 1, true))
assert(not media.html:match('href="https://x.test"[^>]*data%-md%-link'))

local hostile = compile(
  '<script>alert(1)</script>\n\n<img src="a.png" onerror="alert(1)">\n\n'
    .. "[x](javascript:alert(1)) [y](JaVa&#115;cript:alert(1)) ![z](data:text/html,hi)\n\n"
    .. "text <iframe src=x></iframe> <b onclick='x()'>b</b>"
)
assert(not hostile.html:find("<script", 1, true) and not hostile.html:find("alert(1)</", 1, true))
assert(
  not hostile.html:lower():find("onerror", 1, true)
    and not hostile.html:lower():find("onclick", 1, true)
)
assert(
  not hostile.html:lower():find("javascript:", 1, true)
    and not hostile.html:find("<iframe", 1, true)
)
assert(not hostile.html:find("data:text/html", 1, true))
assert(compile("<b>x</b>", { allow_html = false }).html:find("&lt;b&gt;x&lt;/b&gt;", 1, true))
assert(compile("`<b>` **x**").html:find("<code>&lt;b&gt;</code>", 1, true))

local inline =
  compile("***both*** **bold** *it* _it_ snake_case_word ~~gone~~ :rocket: https://a.test/x.")
assert(
  inline.html:find("<strong><em>both</em></strong>", 1, true)
    and inline.html:find("<del>gone</del>", 1, true)
)
assert(inline.html:find("snake_case_word", 1, true) and inline.html:find("🚀", 1, true))
assert(inline.html:find('href="https://a.test/x"', 1, true))
assert(not compile("x :rocket:", { emoji = false }).html:find("🚀", 1, true))
assert(compile("a\nb", { breaks = true }).html:find("a<br>\nb", 1, true))
assert(compile("a -- b...", { typographer = true }).html:find("a – b…", 1, true))

-- Raw HTML goes through a strict allowlist.
local attack = compile(
  "<svg onload=alert(1)>x</svg>\n\n"
    .. "<img src=x onerror=alert(1)> <a href=\"javascript:alert(1)\">click</a> <a href=' JaVa&#x73;cript:1'>j</a>\n\n"
    .. '<div class="box" style="color:red" onclick="steal()" data-x="1">kept</div> <custom-tag>t</custom-tag> '
    .. '<script src="//evil.test/x.js"></script> <iframe src="x"></iframe> <form action="x"><input></form>'
)
assert(
  not attack.html:find("<svg", 1, true) and attack.html:find("&lt;svg onload=alert(1)&gt;", 1, true)
)
assert(not attack.html:find("<script", 1, true) and not attack.html:find("<iframe", 1, true))
assert(not attack.html:find("<form", 1, true) and not attack.html:find("<input", 1, true))
assert(
  not attack.html:find("<custom-tag", 1, true) and attack.html:find("&lt;custom-tag&gt;", 1, true)
)
assert(not attack.html:find("onerror", 1, true) and not attack.html:find("onclick", 1, true))
assert(
  not attack.html:lower():find("javascript:", 1, true) and not attack.html:find('href=" ', 1, true)
)
assert(
  attack.html:find('<img src="/asset?path=x&amp;token=TOK" loading="lazy">', 1, true),
  attack.html
)
assert(
  attack.html:find('<div class="box">kept</div>', 1, true),
  "class survives; style, onclick, data-* do not"
)
assert(compile('<a href="javascript:alert(1)">x</a>').html:find("<a>x</a>", 1, true))
local data_images = compile(
  '<img src="data:image/png;base64,AAAA"> <img src="data:image/svg+xml;base64,AAAA"> <img src="data:text/html;base64,AAAA">'
)
assert(data_images.html:find('src="data:image/png;base64,AAAA"', 1, true))
assert(
  not data_images.html:find("svg+xml", 1, true) and not data_images.html:find("text/html", 1, true)
)
local relative = compile(
  '<a href="other.md#x">o</a> <a href="https://x.test">e</a> <ol type="a" start="3"><li type="i">x</li></ol> <a name="n" type="x">a</a>'
)
assert(relative.html:find('data-md-link="other.md#x"', 1, true))
assert(relative.html:find('target="_blank" rel="noopener noreferrer"', 1, true))
assert(relative.html:find('<ol type="a" start="3"><li type="i">x</li></ol>', 1, true))
assert(relative.html:find('<a name="n">a</a>', 1, true), "type is only kept on ol and li")
assert(
  not compile('<div id="toolbar">x</div>').html:find("id=", 1, true),
  "reserved ids are dropped"
)

-- Markdown inside <details>.
local details = compile(
  "<details>\n<summary>Title *here*</summary>\n\n- **item**\n- [x] done\n\n```lua\nlocal a = 1\n```\n\n"
    .. "| a | b |\n|---|---|\n| 1 | 2 |\n\n</details>\n\nafter"
)
assert(
  details.html:find('<details data-source-line="1"><summary>Title <em>here</em></summary>', 1, true),
  details.html
)
assert(
  details.html:find("<strong>item</strong>", 1, true)
    and details.html:find("task-list-item-checkbox", 1, true)
)
assert(
  details.html:find('class="code-block" data-source-line="7"', 1, true)
    and details.html:find("<table", 1, true)
)
assert(details.html:find('</details>\n<p data-source-line="17">after</p>', 1, true), details.html)
local inline_details = compile("<details open><summary>T</summary>some *text*\n\nmore\n</details>")
assert(
  inline_details.html:find('<details open data-source-line="1"><summary>T</summary>', 1, true),
  inline_details.html
)
assert(
  inline_details.html:find("some <em>text</em>", 1, true)
    and inline_details.html:find('<p data-source-line="3">more</p>', 1, true)
)
local nested = compile(
  "<details>\n<summary>a</summary>\n<details>\n<summary>b</summary>\n\ninner\n\n</details>\n\nouter\n</details>\n\nend"
)
assert(
  select(2, nested.html:gsub("<details", "")) == 2
    and select(2, nested.html:gsub("</details>", "")) == 2,
  nested.html
)
assert(
  nested.html:find("outer", 1, true)
    < nested.html:find('</details>\n<p data-source-line="13">end', 1, true)
)
assert(compile("<details>\n<summary>unclosed</summary>\n\nbody").html:find("body", 1, true))

-- Links and images with brackets and parentheses.
local brackets = compile(
  "[[RFC 2119]](https://x.test/rfc) [fn(x)](https://x.test/a_(b)) ![alt [x]](a.png) [a\\]b](c)"
)
assert(
  brackets.html:find('<a href="https://x.test/rfc"', 1, true)
    and brackets.html:find("[RFC 2119]</a>", 1, true)
)
assert(
  brackets.html:find('href="https://x.test/a_(b)"', 1, true)
    and brackets.html:find(">fn(x)</a>", 1, true)
)
assert(brackets.html:find('alt="alt [x]"', 1, true))

-- Emphasis next to punctuation.
local emphasis = compile('(*it*), **bold**. "_q_" **"quoted"** snake_case_ok a * b * c _x_.')
assert(
  emphasis.html:find("(<em>it</em>),", 1, true)
    and emphasis.html:find("<strong>bold</strong>.", 1, true)
)
assert(
  emphasis.html:find('"<em>q</em>"', 1, true)
    and emphasis.html:find('<strong>"quoted"</strong>', 1, true)
)
assert(emphasis.html:find("snake_case_ok", 1, true) and emphasis.html:find("a * b * c", 1, true))
assert(emphasis.html:find("<em>x</em>.", 1, true))

-- Nested lists at several indents, and tabs.
local lists = compile("- a\n    - b\n        - c\n- d\n\n1. one\n  - two\n    - three\n")
assert(
  lists.html:find('<li data-source-line="1">a\n<ul data-source-line="2">', 1, true),
  lists.html
)
assert(
  lists.html:find('<li data-source-line="3">c</li>', 1, true)
    and lists.html:find('<li data-source-line="4">d</li>', 1, true)
)
assert(
  lists.html:find('<li data-source-line="6">one\n<ul data-source-line="7">', 1, true),
  lists.html
)
assert(lists.html:find('<li data-source-line="8">three</li>', 1, true))
local tabbed = compile("- a\n\t- b\n\t\t- c\n\n```\n\tkeep\ttabs\n```")
assert(
  tabbed.html:find('<li data-source-line="2">b\n<ul', 1, true)
    and tabbed.html:find('<li data-source-line="3">c</li>', 1, true),
  tabbed.html
)
assert(tabbed.html:find("\tkeep\ttabs", 1, true), "tabs inside fenced code are left alone")
assert(compile("a\tb\n\tc").html:find("a\tb", 1, true) == nil, "tabs outside code are expanded")

-- Heading anchors: one slug for the preview and for #anchor diagnostics.
local guide = compile("## See [Guide](guide.md)\n\n## `code` and *em* <b>bold</b>")
assert(guide.toc[1].id == "see-guide", guide.toc[1].id)
assert(guide.toc[2].id == "code-and-em-bold", guide.toc[2].id)
assert(compiler.slug("See [Guide](guide.md)") == "see-guide")
assert(compiler.slug("`code` and *em* <b>bold</b>") == "code-and-em-bold")
local diagnostics = require("md-peek.diagnostics")
local doc_dir = vim.fn.tempname()
vim.fn.mkdir(doc_dir, "p")
vim.fn.writefile({ "# guide" }, doc_dir .. "/guide.md")
local diag_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(diag_buffer, doc_dir .. "/anchors.md")
vim.api.nvim_buf_set_lines(diag_buffer, 0, -1, false, {
  "## See [Guide](guide.md)",
  "",
  "[ok](#see-guide) [bad](#see-guideguidemd) [ok2](#code-and-em-bold)",
  "",
  "## `code` and *em* <b>bold</b>",
})
local reported = diagnostics.compute(diag_buffer)
assert(#reported == 1 and reported[1].message:find("see%-guideguidemd"), vim.inspect(reported))
vim.api.nvim_buf_delete(diag_buffer, { force = true })
vim.fn.delete(doc_dir, "rf")

-- The folded-away client module is really gone.
assert(not pcall(require, "md-peek.client"), "client.lua was folded into init.lua")

-- One scanner finds headings and the lines that are not prose.
local scanned = require("md-peek.markdown").scan({
  "---",
  "title: x",
  "---",
  "# Real",
  "```sh",
  "# not a heading",
  "```",
  "Setext",
  "======",
})
assert(
  #scanned.headings == 2 and scanned.headings[1].title == "Real",
  vim.inspect(scanned.headings)
)
assert(scanned.headings[2].title == "Setext" and scanned.headings[2].line == 8)
for _, index in ipairs({ 1, 2, 3, 5, 6, 7 }) do
  assert(scanned.skip[index], "line " .. index .. " is front matter or fenced")
end
assert(not scanned.skip[4] and not scanned.skip[8])

-- LaTeX math becomes native MathML.
local mathml = compile("Euler: $e^{i\\pi} + 1 = 0$ is neat.")
assert(mathml.html:find('<math xmlns="http://www.w3.org/1998/Math/MathML">', 1, true), mathml.html)
assert(mathml.html:find("<msup><mi>e</mi><mrow><mi>i</mi><mi>π</mi></mrow></msup>", 1, true))
assert(mathml.html:find("<mo>+</mo><mn>1</mn><mo>=</mo><mn>0</mn>", 1, true))
local display = compile("$$\\frac{a}{b}$$\n\ntext")
assert(
  display.html:find(
    '<div class="math-display" data-source-line="1"><math xmlns="http://www.w3.org/1998/Math/MathML" display="block"><mfrac><mi>a</mi><mi>b</mi></mfrac></math></div>',
    1,
    true
  ),
  display.html
)
local multiline = compile("$$\n\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}\n$$\n\nafter")
assert(
  multiline.html:find('display="block"', 1, true) and multiline.html:find("<mtable>", 1, true),
  multiline.html
)
assert(
  multiline.html:find(
    "<mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>c</mi></mtd><mtd><mi>d</mi></mtd></mtr>",
    1,
    true
  )
)
assert(
  multiline.html:find('<mo stretchy="true">(</mo>', 1, true)
    and multiline.html:find('<p data-source-line="5">after</p>', 1, true)
)
assert(compile("\\[ x^2 \\]").html:find('display="block"', 1, true))
assert(compile("inline \\(x_1\\) here").html:find("<msub><mi>x</mi><mn>1</mn></msub>", 1, true))
local prices = compile("It costs $5 to start and $10 to finish; also $5.")
assert(
  not prices.html:find("<math", 1, true)
    and prices.html:find("costs $5 to start and $10 to finish; also $5.", 1, true),
  prices.html
)
local mixed = compile("A $5 fee, a \\$7 fee, and $a_b$ math.")
assert(
  select(2, mixed.html:gsub("<math", "")) == 1 and mixed.html:find("A $5 fee, a $7 fee", 1, true),
  mixed.html
)
assert(not compile("a $x_i$ b", { math = false }).html:find("<math", 1, true))
assert(not compile("`$x$` and\n\n```\n$y$\n```").html:find("<math", 1, true), "code is never math")
assert(compile("snake_case and $x_i$ and _it_").html:find("<em>it</em>", 1, true))

local latex = require("md-peek.math")
local function tex(source, block)
  return latex.to_mathml(source, block)
end
assert(
  tex("x_{i+1}^{2n}"):find(
    "<msubsup><mi>x</mi><mrow><mi>i</mi><mo>+</mo><mn>1</mn></mrow><mrow><mn>2</mn><mi>n</mi></mrow></msubsup>",
    1,
    true
  )
)
assert(
  tex("x_i"):find("<msub><mi>x</mi><mi>i</mi></msub>", 1, true)
    and tex("x^2"):find("<msup>", 1, true)
)
assert(
  tex("\\dfrac{a}{b}"):find("<mfrac>", 1, true)
    and tex("\\sqrt{x}"):find("<msqrt><mi>x</mi></msqrt>", 1, true)
)
assert(tex("\\sqrt[3]{x}"):find("<mroot><mi>x</mi><mn>3</mn></mroot>", 1, true))
assert(tex("\\sum_{i=1}^n i"):find('<munderover><mo largeop="true">∑</mo>', 1, true))
assert(
  tex("\\lim_{x\\to 0} f"):find("<munder><mi>lim</mi>", 1, true)
    and tex("\\max_x"):find("<munder><mi>max</mi>", 1, true)
)
assert(tex("\\prod^n"):find('<mover><mo largeop="true">∏</mo>', 1, true))
assert(
  tex("\\int_0^1 x\\,dx"):find(
    '<msubsup><mo largeop="true">∫</mo><mn>0</mn><mn>1</mn></msubsup>',
    1,
    true
  )
)
assert(tex("\\hat{x}"):find('<mover accent="true"><mi>x</mi><mo>^</mo></mover>', 1, true))
assert(tex("\\vec v \\bar{y} \\tilde z \\dot a \\overline{AB}"):find("<mo>→</mo>", 1, true))
assert(tex("\\text{if } x"):find("<mtext>if </mtext>", 1, true))
assert(
  tex("\\mathbb{R} \\mathbf{v} \\mathcal{L} \\mathrm{d}"):find("ℝ", 1, true)
    and tex("\\mathbf{v}"):find("𝐯", 1, true)
)
assert(
  tex("\\mathcal{L}"):find("ℒ", 1, true)
    and tex("\\mathrm{d}"):find('<mi mathvariant="normal">d</mi>', 1, true)
)
assert(
  tex("\\alpha \\omega \\Gamma \\Omega"):find(
    '<mi>α</mi><mi>ω</mi><mi mathvariant="normal">Γ</mi><mi mathvariant="normal">Ω</mi>',
    1,
    true
  )
)
for _, name in ipairs({
  "times",
  "cdot",
  "pm",
  "mp",
  "leq",
  "geq",
  "neq",
  "approx",
  "equiv",
  "sim",
  "in",
  "notin",
  "subset",
  "subseteq",
  "cup",
  "cap",
  "forall",
  "exists",
  "nabla",
  "partial",
  "infty",
  "to",
  "rightarrow",
  "Rightarrow",
  "leftrightarrow",
  "iff",
  "dots",
  "ldots",
  "cdots",
}) do
  assert(tex("\\" .. name):find("<mo>", 1, true), name .. " is an operator")
  assert(not tex("\\" .. name):find("<mtext>", 1, true), name .. " is known")
end
local unknown = tex("\\frobnicate{x} + y")
assert(
  unknown:find("<mtext>\\frobnicate</mtext>", 1, true) and unknown:find("<mi>y</mi>", 1, true),
  "unknown commands degrade to text"
)
assert(
  tex("\\frac{a"):find("<math", 1, true)
    and tex("}{"):find("<math", 1, true)
    and tex(""):find("<math", 1, true),
  "malformed input never raises"
)
assert(
  tex("a < b & c"):find("&lt;", 1, true) and tex("a < b & c"):find("&amp;", 1, true),
  "text is escaped"
)
assert(
  tex(string.rep("{", 200) .. "x"):find("math%-error")
    or tex(string.rep("{", 200) .. "x"):find("<math"),
  "deep nesting is bounded"
)
assert(tex("\\begin{bmatrix}1&2\\\\3&4\\end{bmatrix}"):find('<mo stretchy="true">[</mo>', 1, true))
assert(tex("\\begin{vmatrix}a&b\\\\c&d\\end{vmatrix}"):find('<mo stretchy="true">|</mo>', 1, true))
assert(
  tex("\\begin{matrix}a\\end{matrix}"):find(
    "<mtable><mtr><mtd><mi>a</mi></mtd></mtr></mtable>",
    1,
    true
  )
)
assert(
  tex("\\left( x \\right)"):find(
    '<mo stretchy="true">(</mo><mi>x</mi><mo stretchy="true">)</mo>',
    1,
    true
  )
)
assert(
  tex("x", true):find('display="block"', 1, true) and not tex("x", false):find("display", 1, true)
)

-- Page assembly: the theme style element and the remembered scheme.
local page = require("md-peek.page")
local nvim_page =
  page.render({ token = "t", nonce = "n", preview = { theme = "nvim" }, scheme = "light" })
assert(
  nvim_page:find('<style id="nvim-theme">', 1, true)
    and nvim_page:find("data-theme='nvim'", 1, true)
)
assert(
  not nvim_page:match("<html[^>]*>"):find("data-scheme", 1, true),
  "a remembered scheme must not hide the nvim colorscheme"
)
local dark_page =
  page.render({ token = "t", nonce = "n", preview = { theme = "github" }, scheme = "dark" })
assert(
  dark_page:find('<html lang="en" data-theme="github" data-scheme="dark">', 1, true),
  dark_page:sub(1, 120)
)
assert(
  not page
    .render({ token = "t", nonce = "n", preview = {}, scheme = "neon" })
    :match("<html[^>]*>")
    :find("data-scheme", 1, true)
)

-- Block memoisation gives byte-identical output, wherever a cached chunk sits in the file.
local sample = table.concat({
  "# Title",
  "",
  "para with [ref][r] and [^n]",
  "",
  "- loose one",
  "",
  "- loose two",
  "",
  "  continued",
  "",
  "[r]: https://r.test",
  "",
  "<!-- a comment",
  "",
  "still comment -->",
  "",
  "<details>",
  "",
  "inside",
  "",
  "</details>",
  "",
  "[^n]: Note",
  "",
  "    more note",
  "",
  "```",
  "",
  "blank inside fence",
  "```",
}, "\n")
compiler.clear_cache()
local fresh = compile(sample, { memoize = false })
local cached_cold = compile(sample)
local cached_warm = compile(sample)
local shifted_sample = "intro\n\n" .. sample
local shifted_warm = compile(shifted_sample)
assert(
  cached_cold.html == fresh.html and cached_warm.html == fresh.html,
  "cold and warm output match"
)
assert(
  shifted_warm.html == compile(shifted_sample, { memoize = false }).html,
  "shifted chunks are renumbered"
)
assert(vim.deep_equal(shifted_warm.toc, compile(shifted_sample, { memoize = false }).toc))
assert(
  fresh.html:find('<li data-source-line="5">loose one</li>', 1, true)
    or fresh.html:find('<p data-source-line="5">loose one</p>', 1, true)
)
assert(fresh.html:find("blank inside fence", 1, true) and fresh.html:find("<details", 1, true))

-- Benchmark: a 5,000 line document with code, tables, lists, quotes and links.
local function big_document()
  local parts, count, code_blocks, section = {}, 0, 0, 0
  local function add(block)
    for line in (block .. "\n"):gmatch("(.-)\n") do
      count = count + 1
      parts[count] = line
    end
  end
  while count < 5000 do
    section = section + 1
    add("## Section " .. section .. "\n")
    add(
      "Paragraph with **bold**, *italic*, `code`, a [link](https://example.com/"
        .. section
        .. ") and :rocket:\nsecond line ![img](pic"
        .. section
        .. ".png).\n"
    )
    add("- item one\n- item **two**\n  - nested [x](y.md)\n- [ ] task\n")
    add("| a | b | c |\n|---|:-:|--:|\n| 1 | two | `3` |\n| 4 | five | 6 |\n")
    add("> [!NOTE]\n> quoted *text* here\n")
    if section % 3 == 1 and code_blocks < 50 then
      code_blocks = code_blocks + 1
      add(
        "```lua\nlocal function f(x)\n  return x + " .. section .. '\nend\nprint(f(1), "s")\n```\n'
      )
    end
    add("1. first\n2. second\n3. third\n")
  end
  return parts
end
local function milliseconds(fn)
  local clock = (vim.uv or vim.loop).hrtime
  local started = clock()
  local result = fn()
  return (clock() - started) / 1e6, result
end
local big = big_document()
local big_text = table.concat(big, "\n")
assert(#big >= 5000 and select(2, big_text:gsub("```lua", "")) == 50)
compiler.clear_cache()
local cold_ms = milliseconds(function()
  return compile(big_text)
end)
local warm_times = {}
for round = 1, 7 do
  local edited = vim.deepcopy(big)
  edited[100 + round * 400] = "edited line " .. round
  local text = table.concat(edited, "\n")
  local elapsed, result = milliseconds(function()
    return compile(text)
  end)
  table.insert(warm_times, elapsed)
  if round == 1 then
    assert(
      result.html == compile(text, { memoize = false }).html,
      "an edited document still matches"
    )
  end
end
table.sort(warm_times)
local warm_ms = warm_times[4]
local shifted_ms = milliseconds(function()
  return compile("one more line\n\n" .. big_text)
end)
print(
  string.format(
    "compile benchmark, %d lines: cold %.1f ms, warm (1 line edited, median of 7) %.1f ms, warm (block inserted above) %.1f ms",
    #big,
    cold_ms,
    warm_ms,
    shifted_ms
  )
)
assert(warm_ms < 15, string.format("warm recompile took %.1f ms, expected < 15 ms", warm_ms))

-- server.lua: a real loopback HTTP and SSE server.
local uv = vim.uv or vim.loop
local function request(port, text, until_done)
  local socket, data, closed, connect_error = uv.new_tcp(), "", false, nil
  socket:connect("127.0.0.1", port, function(err)
    if err then
      connect_error = err
      return
    end
    socket:read_start(function(_, chunk)
      if chunk then
        data = data .. chunk
      else
        closed = true
      end
    end)
    socket:write(text)
  end)
  vim.wait(5000, function()
    return closed or connect_error ~= nil or (until_done ~= nil and until_done(data))
  end, 10)
  assert(not connect_error, connect_error)
  return data, socket
end

local function get(port, target, extra)
  local text = "GET "
    .. target
    .. " HTTP/1.1\r\nHost: 127.0.0.1:"
    .. port
    .. "\r\n"
    .. (extra or "")
  return request(port, text .. "\r\n")
end

local function post(port, target, body, extra)
  local text = "POST " .. target .. " HTTP/1.1\r\nHost: 127.0.0.1:" .. port .. "\r\n"
  text = text .. (extra or "") .. "Content-Length: " .. #body .. "\r\n\r\n" .. body
  return request(port, text)
end

local state_home = vim.fn.tempname()
vim.fn.mkdir(state_home, "p")
local saved_state_home = vim.env.XDG_STATE_HOME
vim.env.XDG_STATE_HOME = state_home -- scheme choices are written here, not to the real state dir
local real = dofile(root .. "/lua/md-peek/server.lua")
local ready, seen = nil, {}
assert(real.start({
  preview = { asset_root = "document" },
  port = 0,
  on_ready = function(info)
    ready = info
  end,
  on_event = function(event)
    table.insert(seen, event)
  end,
}))
vim.wait(5000, function()
  return ready ~= nil
end)
assert(ready and ready.port > 0 and ready.url == "http://127.0.0.1:" .. ready.port .. "/")
assert(real.ready and real.port == ready.port and #real.token == 64)
local port, token = real.port, real.token

assert(get(port, "/"):match("^HTTP/1.1 401"), "no token, no page")
assert(get(port, "/?token=wrong"):match("^HTTP/1.1 401"))
assert(get(port, "/events"):match("^HTTP/1.1 401"))
assert(get(port, "/asset?path=x.png"):match("^HTTP/1.1 401"))
assert(post(port, "/act", '{"type":"jump","line":1}'):match("^HTTP/1.1 401"))
local foreign = request(port, "GET /?token=" .. token .. " HTTP/1.1\r\nHost: evil.test\r\n\r\n")
assert(foreign:match("^HTTP/1.1 403"), "a foreign Host header is refused")

local index = get(port, "/?token=" .. token)
assert(index:match("^HTTP/1.1 200"), index:sub(1, 80))
assert(index:find("md-peek", 1, true) and index:find("<!doctype html>", 1, true))
local nonce = index:match("script%-src 'nonce%-(%x+)'")
assert(
  nonce and index:find('<script nonce="' .. nonce .. '">', 1, true),
  "CSP nonce matches the script"
)
assert(index:find("default-src 'none'", 1, true) and index:find("frame-ancestors 'none'", 1, true))
assert(index:find('"token":"' .. token .. '"', 1, true))
assert(get(port, "/?token=" .. token, "X-Md-Peek-Token: nope\r\n"):match("^HTTP/1.1 200"))
assert(get(port, "/nothing?token=" .. token):match("^HTTP/1.1 404"))

-- The light/dark toggle is remembered across sessions.
local scheme_file = vim.fn.stdpath("state") .. "/md-peek-scheme"
assert(
  scheme_file:sub(1, #state_home) == state_home,
  "tests must not touch the real state directory"
)
assert(
  not index:match("<html[^>]*>"):find("data-scheme", 1, true)
    and vim.fn.filereadable(scheme_file) == 0
)
local origin_header = "Origin: http://127.0.0.1:" .. port .. "\r\n"
assert(
  post(port, "/act?token=" .. token, '{"type":"set_scheme","scheme":"light"}', origin_header):match(
    "^HTTP/1.1 204"
  )
)
assert(table.concat(vim.fn.readfile(scheme_file)) == "light")
assert(
  get(port, "/?token=" .. token):find(
    '<html lang="en" data-theme="dark" data-scheme="light">',
    1,
    true
  )
)
assert(
  post(port, "/act?token=" .. token, '{"type":"set_scheme","scheme":"neon"}'):match("^HTTP/1.1 400")
)
assert(table.concat(vim.fn.readfile(scheme_file)) == "light", "a bad scheme is not stored")
assert(
  post(
    port,
    "/act?token=" .. token,
    '{"type":"set_scheme","scheme":"light"}',
    "Origin: http://evil.test\r\n"
  ):match("^HTTP/1.1 403")
)
assert(
  post(port, "/act?token=" .. token, '{"type":"set_scheme","scheme":"dark"}'):match("^HTTP/1.1 204")
)
assert(get(port, "/?token=" .. token):match("<html[^>]*>"):find('data-scheme="dark"', 1, true))
assert(#seen == 0, "a scheme change is not an editor event")

local workdir = vim.fn.resolve(vim.fn.tempname())
local outside = workdir .. "/outside"
local docs = workdir .. "/docs"
vim.fn.mkdir(outside, "p")
vim.fn.mkdir(docs .. "/img", "p")
local png = "\137PNG\r\n\26\n" .. string.rep("x", 40)
local function write_file(path, data)
  local file = assert(io.open(path, "wb"))
  file:write(data)
  file:close()
end
write_file(docs .. "/img/ok.png", png)
write_file(docs .. "/.secret", "secret")
write_file(docs .. "/code.lua", "return 1")
write_file(outside .. "/leak.png", png)
local linked = pcall(function()
  assert(uv.fs_symlink(outside .. "/leak.png", docs .. "/img/link.png"))
end)

-- SSE: a render reaches connected clients, and a late joiner is caught up.
local events_text = "GET /events?token="
  .. token
  .. " HTTP/1.1\r\nHost: 127.0.0.1:"
  .. port
  .. "\r\n\r\n"
local _, sse = request(port, events_text, function(data)
  return data:find("\r\n\r\n", 1, true) ~= nil
end)
local stream = ""
sse:read_stop()
sse:read_start(function(_, chunk)
  stream = stream .. (chunk or "")
end)
assert(real.send({
  type = "render",
  document = { content = "# Hello\n\n- [ ] task", path = docs .. "/doc.md", line = 3 },
  sent_at = 123,
}))
vim.wait(5000, function()
  return stream:find("task%-list%-item%-checkbox") ~= nil
end, 10)
local payload = vim.json.decode(stream:match("data: (%b{})"))
assert(payload.type == "render" and payload.html:find("<h1", 1, true) and payload.title == "Hello")
assert(
  payload.html:find("task-list-item-checkbox", 1, true)
    and payload.line == 3
    and payload.sent_at == 123
)
assert(payload.raw == "# Hello\n\n- [ ] task" and payload.path == docs .. "/doc.md")
assert(payload.toc[1].id == "hello")
assert(real.send({ type = "cursor", line = 3 }))
vim.wait(5000, function()
  return stream:find('"type":"cursor"', 1, true) ~= nil
end, 10)
assert(
  stream:find('"type":"cursor","line":3', 1, true)
    or stream:find('"line":3,"type":"cursor"', 1, true)
)
assert(real.send({ type = "theme", css = ":root{--md-bg:#123456}" }))
vim.wait(5000, function()
  return stream:find('"type":"theme"', 1, true) ~= nil
end, 10)
assert(
  stream:find('"type":"theme"', 1, true) and stream:find("#123456", 1, true),
  "theme updates reach the browser"
)
sse:close()
local late = request(port, events_text, function(data)
  return data:find("task%-list%-item%-checkbox") ~= nil
end)
assert(
  late:find("Content%-Type: text/event%-stream") and late:find("task-list-item-checkbox", 1, true)
)
assert(not real.send("nope") and real.send({ type = "bogus" }))
vim.wait(5000, function()
  return #seen > 0
end)
assert(seen[1].type == "error", "a bad editor message comes back as an error")
seen = {}

-- Browser actions become validated events.
local origin = "Origin: http://127.0.0.1:" .. port .. "\r\n"
local acted = post(port, "/act?token=" .. token, '{"type":"jump","line":2}', origin)
assert(acted:match("^HTTP/1.1 204"), acted)
vim.wait(5000, function()
  return #seen > 0
end)
assert(seen[1].type == "jump" and seen[1].line == 2)
post(port, "/act?token=" .. token, '{"type":"toggle_task","line":"3"}')
post(port, "/act?token=" .. token, '{"type":"rendered","latency_ms":12}')
post(port, "/act?token=" .. token, '{"type":"open_file","href":"../notes/Other%20File.md#top"}')
vim.wait(5000, function()
  return #seen >= 4
end)
assert(seen[2].type == "toggle_task" and seen[2].line == 3)
assert(seen[3].type == "rendered" and seen[3].latency_ms == 12)
assert(
  seen[4].type == "open_file"
    and seen[4].path:gsub("\\", "/") == (workdir .. "/notes/Other File.md"):gsub("\\", "/"),
  seen[4].path
)
assert(
  post(port, "/act?token=" .. token, '{"type":"open_file","href":"secret.txt"}'):match(
    "^HTTP/1.1 400"
  )
)
assert(post(port, "/act?token=" .. token, '{"type":"nope"}'):match("^HTTP/1.1 400"))
assert(post(port, "/act?token=" .. token, "not json"):match("^HTTP/1.1 400"))
assert(
  post(port, "/act?token=" .. token, '{"type":"jump","line":1}', "Origin: http://evil.test\r\n"):match(
    "^HTTP/1.1 403"
  )
)
assert(
  post(port, "/act?token=" .. token, '{"type":"jump","line":1}', "Sec-Fetch-Site: cross-site\r\n"):match(
    "^HTTP/1.1 403"
  )
)
assert(post(port, "/act?token=" .. token, string.rep("x", 70000)):match("^HTTP/1.1 413"))
assert(#seen == 4, "refused requests must not produce events")

-- /asset serves media inside the sandbox and nothing else.
local function asset(path)
  return get(port, "/asset?token=" .. token .. "&path=" .. path:gsub("[^%w/.%-_]", function(char)
    return string.format("%%%02X", char:byte())
  end))
end
local served = asset("img/ok.png")
assert(
  served:match("^HTTP/1.1 200") and served:find("Content%-Type: image/png"),
  served:sub(1, 120)
)
assert(served:find("X%-Content%-Type%-Options: nosniff") and served:sub(-#png) == png)
assert(asset("../outside/leak.png"):match("^HTTP/1.1 403"), "parent traversal")
assert(asset(outside .. "/leak.png"):match("^HTTP/1.1 403"), "absolute path outside the root")
assert(asset("missing.png"):match("^HTTP/1.1 404"))
assert(asset(".secret"):match("^HTTP/1.1 403"), "non-media file")
assert(asset("code.lua"):match("^HTTP/1.1 403"), "non-media file")
if linked then
  assert(asset("img/link.png"):match("^HTTP/1.1 403"), "a symlink out of the root")
end

-- Asset responses carry their own CSP so a directly opened SVG can never run script.
assert(
  served:find(
    "Content%-Security%-Policy: default%-src 'none'; style%-src 'unsafe%-inline'; sandbox"
  ),
  served:sub(1, 300)
)
assert(served:find("Accept%-Ranges: bytes"))

-- Validators: unchanged files answer 304, changed files a fresh 200.
local etag = served:match('ETag: ("[^\r]+")')
assert(
  etag and served:find("Cache%-Control: no%-cache"),
  "assets are revalidated, not blindly cached"
)
local revalidated =
  get(port, "/asset?token=" .. token .. "&path=img/ok.png", "If-None-Match: " .. etag .. "\r\n")
assert(revalidated:match("^HTTP/1.1 304 Not Modified"), revalidated:sub(1, 60))
assert(
  revalidated:find("ETag: " .. etag, 1, true)
    and revalidated:find("Content%-Security%-Policy: default%-src 'none'")
)
assert(#revalidated:match("\r\n\r\n(.*)$") == 0, "a 304 has no body")
assert(
  get(port, "/asset?token=" .. token .. "&path=img/ok.png", 'If-None-Match: "stale"\r\n'):match(
    "^HTTP/1.1 200"
  )
)
write_file(docs .. "/img/edit.png", png)
local first_edit = asset("img/edit.png")
local first_etag = first_edit:match('ETag: ("[^\r]+")')
write_file(docs .. "/img/edit.png", png .. "changed")
local second_edit = asset("img/edit.png")
local second_etag = second_edit:match('ETag: ("[^\r]+")')
assert(first_etag and second_etag and first_etag ~= second_etag, "an edited file gets a new ETag")
assert(
  get(
    port,
    "/asset?token=" .. token .. "&path=img/edit.png",
    "If-None-Match: " .. first_etag .. "\r\n"
  ):match("^HTTP/1.1 200")
)
assert(asset("missing.png"):find("Content%-Security%-Policy: default%-src 'none'", 1))
assert(asset(".secret"):find("sandbox", 1, true))

-- Range requests answer with exactly the requested slice.
local function ranged(range)
  return get(
    port,
    "/asset?token=" .. token .. "&path=img/ok.png",
    "Range: bytes=" .. range .. "\r\n"
  )
end
local partial = ranged("0-3")
assert(partial:match("^HTTP/1.1 206 Partial Content"), partial:sub(1, 80))
assert(
  partial:find("Content%-Range: bytes 0%-3/" .. #png) and partial:find("Content%-Length: 4\r\n")
)
assert(partial:sub(-4) == png:sub(1, 4) and #partial:match("\r\n\r\n(.*)$") == 4)
local tail = ranged("-4")
assert(
  tail:match("^HTTP/1.1 206")
    and tail:sub(-4) == png:sub(-4)
    and tail:find("Content%-Range: bytes " .. (#png - 4) .. "%-" .. (#png - 1) .. "/" .. #png)
)
local open_ended = ranged("40-")
assert(open_ended:match("^HTTP/1.1 206") and open_ended:sub(-(#png - 40)) == png:sub(41))
local clipped = ranged("44-9999")
assert(clipped:match("^HTTP/1.1 206") and clipped:find("bytes 44%-" .. (#png - 1) .. "/" .. #png))
local unsatisfiable = ranged("9999-10000")
assert(
  unsatisfiable:match("^HTTP/1.1 416") and unsatisfiable:find("Content%-Range: bytes %*/" .. #png)
)
assert(ranged("5-2"):match("^HTTP/1.1 416"))
assert(
  get(port, "/asset?token=" .. token .. "&path=img/ok.png", "Range: nonsense\r\n"):match(
    "^HTTP/1.1 200"
  )
)

-- A file larger than one chunk is streamed whole, and in slices.
local big_png = string.rep("0123456789abcdef", 48 * 1024) -- 768 KiB, three read chunks
write_file(docs .. "/img/big.png", big_png)
local streamed = request(
  port,
  "GET /asset?token="
    .. token
    .. "&path=img/big.png HTTP/1.1\r\nHost: 127.0.0.1:"
    .. port
    .. "\r\n\r\n"
)
local streamed_body = streamed:match("\r\n\r\n(.*)$")
assert(streamed:match("^HTTP/1.1 200") and #streamed_body == #big_png and streamed_body == big_png)
local middle =
  get(port, "/asset?token=" .. token .. "&path=img/big.png", "Range: bytes=262140-262151\r\n")
assert(middle:match("^HTTP/1.1 206") and middle:sub(-12) == big_png:sub(262141, 262152))

real.stop()
assert(not real.ready and real.port == nil and real.token == nil)

-- A client that never finishes its request is dropped, but an event stream is not.
local patient = dofile(root .. "/lua/md-peek/server.lua")
local patient_ready
assert(patient.start({
  preview = {},
  request_timeout_ms = 250,
  on_ready = function(info)
    patient_ready = info
  end,
}))
vim.wait(5000, function()
  return patient_ready ~= nil
end)
local stalled =
  request(patient_ready.port, "GET /?token=" .. patient.token .. " HTTP/1.1\r\nHost: 127.0.0.1\r\n")
assert(stalled:match("^HTTP/1.1 408"), "an unfinished request times out: " .. stalled:sub(1, 40))
local patient_events = "GET /events?token="
  .. patient.token
  .. " HTTP/1.1\r\nHost: 127.0.0.1:"
  .. patient_ready.port
  .. "\r\n\r\n"
local _, patient_stream = request(patient_ready.port, patient_events, function(data)
  return data:find("\r\n\r\n", 1, true) ~= nil
end)
local patient_data = ""
patient_stream:read_stop()
patient_stream:read_start(function(_, chunk)
  patient_data = patient_data .. (chunk or "")
end)
vim.wait(600, function()
  return false
end)
patient.send({
  type = "render",
  document = { content = "# Still here", path = workdir .. "/x.md", line = 1 },
})
vim.wait(5000, function()
  return patient_data:find("Still here", 1, true) ~= nil
end, 10)
assert(
  patient_data:find("Still here", 1, true) and not patient_data:find("408", 1, true),
  "SSE connections are not timed out"
)
patient_stream:close()
patient.stop()

-- Nothing is compiled until a browser is connected; only the newest document is ever compiled.
local counted_compiler = require("md-peek.compiler")
local original_compile = counted_compiler.compile
local compile_calls = 0
counted_compiler.compile = function(...)
  compile_calls = compile_calls + 1
  return original_compile(...)
end
local lazy = dofile(root .. "/lua/md-peek/server.lua")
local lazy_ready
assert(lazy.start({
  preview = {},
  on_ready = function(info)
    lazy_ready = info
  end,
}))
vim.wait(5000, function()
  return lazy_ready ~= nil
end)
local lazy_dir = workdir .. "/lazy"
vim.fn.mkdir(lazy_dir, "p")
local function open_stream(server_port, server_token)
  local initial, socket = request(
    server_port,
    "GET /events?token="
      .. server_token
      .. " HTTP/1.1\r\nHost: 127.0.0.1:"
      .. server_port
      .. "\r\n\r\n",
    function(data)
      return data:find("\r\n\r\n", 1, true) ~= nil
    end
  )
  local state = { data = initial, socket = socket } -- keep what arrived with the headers
  socket:read_stop()
  socket:read_start(function(_, chunk)
    state.data = state.data .. (chunk or "")
  end)
  return state
end
assert(lazy.send({
  type = "render",
  document = { content = "# First", path = lazy_dir .. "/a.md", line = 1 },
}))
assert(lazy.send({
  type = "render",
  document = { content = "# Second", path = lazy_dir .. "/a.md", line = 1 },
}))
assert(compile_calls == 0, "no browser is listening, so nothing may be compiled")
local lazy_stream = open_stream(lazy_ready.port, lazy.token)
vim.wait(5000, function()
  return lazy_stream.data:find("Second", 1, true) ~= nil
end, 10)
assert(
  lazy_stream.data:find("Second", 1, true) and not lazy_stream.data:find("First", 1, true),
  "only the newest document is sent"
)
assert(compile_calls == 1, "the first browser triggers exactly one compile, got " .. compile_calls)
assert(lazy.send({
  type = "render",
  document = { content = "# Third", path = lazy_dir .. "/a.md", line = 1 },
}))
vim.wait(5000, function()
  return lazy_stream.data:find("Third", 1, true) ~= nil
end, 10)
assert(
  compile_calls == 2 and lazy_stream.data:find("Third", 1, true),
  "a connected browser gets an immediate compile"
)
lazy_stream.socket:close()
vim.wait(300, function()
  return false
end)
assert(lazy.send({
  type = "render",
  document = { content = "# Fourth", path = lazy_dir .. "/a.md", line = 1 },
}))
assert(compile_calls == 2, "after the browser leaves, compiling stops again")
local lazy_again = open_stream(lazy_ready.port, lazy.token)
vim.wait(5000, function()
  return lazy_again.data:find("Fourth", 1, true) ~= nil
end, 10)
assert(lazy_again.data:find("Fourth", 1, true) and compile_calls == 3)

-- A changed image gets a new URL on the next render, so the browser reloads it.
write_file(lazy_dir .. "/pic.png", png)
local function latest_html(stream)
  local last
  for json_text in stream.data:gmatch("data: (%b{})") do
    last = vim.json.decode(json_text).html
  end
  return last
end
assert(lazy.send({
  type = "render",
  document = { content = "![pic](pic.png)", path = lazy_dir .. "/a.md", line = 1 },
}))
vim.wait(5000, function()
  return (latest_html(lazy_again) or ""):find("pic.png", 1, true) ~= nil
end, 10)
local before_edit = latest_html(lazy_again):match('src="([^"]+)"')
assert(before_edit:find("&amp;v=%d+%-%d+&amp;token=" .. lazy.token), before_edit)
write_file(lazy_dir .. "/pic.png", png .. "more bytes")
assert(lazy.send({
  type = "render",
  document = { content = "![pic](pic.png)", path = lazy_dir .. "/a.md", line = 1 },
}))
vim.wait(5000, function()
  local html = latest_html(lazy_again) or ""
  return html:match('src="([^"]+)"') ~= before_edit
end, 10)
local after_edit = latest_html(lazy_again):match('src="([^"]+)"')
assert(
  after_edit ~= before_edit and after_edit:find("pic.png", 1, true),
  "an edited image must change its URL"
)
lazy_again.socket:close()
counted_compiler.compile = original_compile
lazy.stop()
vim.env.XDG_STATE_HOME = saved_state_home

-- A port that is taken is reported, not raised.
local holder = uv.new_tcp()
assert(holder:bind("127.0.0.1", 0))
local busy = dofile(root .. "/lua/md-peek/server.lua")
assert(busy.start({ preview = {}, port = holder:getsockname().port }) == false)
assert(busy.error and busy.error:match("could not"), tostring(busy.error))
holder:close()

-- The git asset root reaches files outside the document folder.
local repo = workdir .. "/repo"
vim.fn.mkdir(repo .. "/.git", "p")
vim.fn.mkdir(repo .. "/docs", "p")
write_file(repo .. "/shared.png", png)
local git_server = dofile(root .. "/lua/md-peek/server.lua")
local git_ready
assert(git_server.start({
  preview = { asset_root = "git" },
  on_ready = function(info)
    git_ready = info
  end,
}))
vim.wait(5000, function()
  return git_ready ~= nil
end)
git_server.send({
  type = "render",
  document = { content = "x", path = repo .. "/docs/a.md", line = 1 },
})
local shared = get(git_ready.port, "/asset?token=" .. git_server.token .. "&path=../shared.png")
assert(shared:match("^HTTP/1.1 200"), shared:sub(1, 80))
git_server.stop()

-- With no setting at all the repository is the root; "document" keeps to the document's folder.
for _, case in ipairs({
  { preview = {}, expected = "^HTTP/1.1 200", label = "default" },
  { preview = { asset_root = "document" }, expected = "^HTTP/1.1 403", label = "document" },
}) do
  local instance = dofile(root .. "/lua/md-peek/server.lua")
  local instance_ready
  assert(instance.start({
    preview = case.preview,
    on_ready = function(info)
      instance_ready = info
    end,
  }))
  vim.wait(5000, function()
    return instance_ready ~= nil
  end)
  instance.send({
    type = "render",
    document = { content = "x", path = repo .. "/docs/a.md", line = 1 },
  })
  local reached =
    get(instance_ready.port, "/asset?token=" .. instance.token .. "&path=../shared.png")
  assert(reached:match(case.expected), case.label .. ": " .. reached:sub(1, 40))
  instance.stop()
end
-- Outside any repository the default falls back to the document's own folder.
local lone = dofile(root .. "/lua/md-peek/server.lua")
local lone_ready
assert(lone.start({
  preview = {},
  on_ready = function(info)
    lone_ready = info
  end,
}))
vim.wait(5000, function()
  return lone_ready ~= nil
end)
lone.send({ type = "render", document = { content = "x", path = docs .. "/doc.md", line = 1 } })
assert(
  get(lone_ready.port, "/asset?token=" .. lone.token .. "&path=img/ok.png"):match("^HTTP/1.1 200")
)
assert(
  get(lone_ready.port, "/asset?token=" .. lone.token .. "&path=../outside/leak.png"):match(
    "^HTTP/1.1 403"
  )
)
lone.stop()

-- A list of roots: the base (repository with "git", else the document's folder) plus each extra
-- directory, with ~ and $VAR expanded and missing directories skipped.
local extra_dir = workdir .. "/extra"
vim.fn.mkdir(extra_dir, "p")
write_file(extra_dir .. "/pic.png", png)
vim.env.MD_PEEK_TEST_EXTRA = extra_dir
for _, case in ipairs({
  {
    name = "git plus extras",
    roots = { "git", "$MD_PEEK_TEST_EXTRA", "~/md-peek-missing-dir-xyz", "relative/ignored" },
    shared = "^HTTP/1.1 200",
    extra = "^HTTP/1.1 200",
  },
  {
    name = "braced variable, no git",
    roots = { "${MD_PEEK_TEST_EXTRA}" },
    shared = "^HTTP/1.1 403",
    extra = "^HTTP/1.1 200",
  },
  {
    name = "document keyword plus extras",
    roots = { "document", "$MD_PEEK_TEST_EXTRA" },
    shared = "^HTTP/1.1 403",
    extra = "^HTTP/1.1 200",
  },
  { name = "git alone", roots = { "git" }, shared = "^HTTP/1.1 200", extra = "^HTTP/1.1 403" },
}) do
  local multi = dofile(root .. "/lua/md-peek/server.lua")
  local multi_ready
  assert(multi.start({
    preview = { asset_root = case.roots },
    on_ready = function(info)
      multi_ready = info
    end,
  }))
  vim.wait(5000, function()
    return multi_ready ~= nil
  end)
  multi.send({
    type = "render",
    document = { content = "x", path = repo .. "/docs/a.md", line = 1 },
  })
  local base = "/asset?token=" .. multi.token .. "&path="
  assert(
    get(multi_ready.port, base .. "../shared.png"):match(case.shared),
    case.name .. ": repository file"
  )
  assert(
    get(multi_ready.port, base .. extra_dir .. "/pic.png"):match(case.extra),
    case.name .. ": extra directory"
  )
  assert(
    get(multi_ready.port, base .. outside .. "/leak.png"):match("^HTTP/1.1 403"),
    case.name .. ": other places stay closed"
  )
  multi.stop()
end
-- A string root expands too.
vim.env.MD_PEEK_TEST_EXTRA = extra_dir
local single = dofile(root .. "/lua/md-peek/server.lua")
local single_ready
assert(single.start({
  preview = { asset_root = "$MD_PEEK_TEST_EXTRA" },
  on_ready = function(info)
    single_ready = info
  end,
}))
vim.wait(5000, function()
  return single_ready ~= nil
end)
single.send({ type = "render", document = { content = "x", path = repo .. "/docs/a.md", line = 1 } })
assert(
  get(single_ready.port, "/asset?token=" .. single.token .. "&path=" .. extra_dir .. "/pic.png"):match(
    "^HTTP/1.1 200"
  )
)
single.stop()
vim.env.MD_PEEK_TEST_EXTRA = nil
vim.fn.delete(workdir, "rf")

print("md-peek Lua smoke tests passed")
