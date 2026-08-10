local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:append(root)

local browser_process = require("md-peek.browser_process")
local preview_url = "http://127.0.0.1:4321/?token=test"
local profile_directory = vim.fn.tempname() .. "-md-peek-test"
local chromium_command = browser_process.command(
  "chromium",
  "chromium",
  preview_url,
  profile_directory,
  { width = 1100, height = 1000 },
  { x = 40, y = 50 }
)
assert(chromium_command[2] == "--app=" .. preview_url)
assert(chromium_command[3] == "--window-size=1100,1000")
assert(chromium_command[4] == "--window-position=40,50")
assert(chromium_command[5] == "--user-data-dir=" .. profile_directory)

local firefox_command = browser_process.command(
  "firefox",
  "firefox",
  preview_url,
  profile_directory,
  { width = 1100, height = 1000 },
  { x = 40, y = 50 }
)
assert(firefox_command[2] == "--new-instance")
assert(firefox_command[3] == "--profile")
assert(firefox_command[4] == profile_directory)
assert(firefox_command[5] == "--window-size" and firefox_command[6] == "1100,1000")
assert(firefox_command[7] == "--new-window" and firefox_command[8] == preview_url)

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
assert(not browser_process.stop("md-peek:another-preview", true))
assert(browser_process.stop(lifecycle_tag, true))
assert(not browser_process.is_active(lifecycle_tag))
assert(vim.fn.isdirectory(profile_directory) == 0)

local started = 0
local mock_server = {
  ready = false,
  start = function()
    started = started + 1
    return true
  end,
  stop = function() end,
}
package.loaded["md-peek.server"] = mock_server
package.loaded["md-peek.client"] = {
  send = function() end,
  debounce = function() end,
  cancel_debounced = function() end,
}
local browser_close_options
package.loaded["md-peek.browser"] = {
  open = function() end,
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

peek.open()
assert(started == 1)
peek.close()

mock_server.port = 4321
peek.close()
assert(browser_close_options.wait_for_completion == false)

mock_server.port = 4321
peek.shutdown()
assert(browser_close_options.wait_for_completion == true)

print("md-peek Lua smoke tests passed")
