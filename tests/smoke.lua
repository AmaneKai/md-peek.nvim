local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:append(root)

local started = 0
package.loaded["md-peek.server"] = {
  ready = false,
  start = function()
    started = started + 1
    return true
  end,
  stop = function() end,
}
package.loaded["md-peek.client"] = {
  request = function() end,
  debounced_request = function() end,
  cancel_debounced = function() end,
}
package.loaded["md-peek.browser"] = {
  open = function() end,
  close = function() end,
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

print("md-peek Lua smoke tests passed")
