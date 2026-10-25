local headings = require("md-peek.overlay.headings")
local ui = require("md-peek.overlay.ui")

local M = {}

local status_bufnr
local status_win

function M.close_status()
  ui.close(status_win)
  status_win, status_bufnr = nil, nil
end

function M.update_status(bufnr, opts)
  opts = opts or {}
  if opts.enabled == false or not ui.valid_buf(bufnr) then
    M.close_status()
    return
  end
  local source_win = vim.fn.bufwinid(bufnr)
  if source_win == -1 then
    M.close_status()
    return
  end
  if vim.api.nvim_win_get_width(source_win) < 32 then
    M.close_status()
    return
  end

  local width = math.max(28, math.min(opts.width or 42, vim.api.nvim_win_get_width(source_win) - 6))
  local line = vim.api.nvim_win_get_cursor(source_win)[1]
  local total = math.max(1, vim.api.nvim_buf_line_count(bufnr))
  local progress = math.floor((line / total) * 100 + 0.5)
  local current = headings.heading_at(headings.headings(bufnr), line)
  local section = current and ("H" .. current.level .. "  " .. current.title)
    or "Before first heading"

  if not ui.valid_buf(status_bufnr) then
    status_bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[status_bufnr].bufhidden = "wipe"
    vim.bo[status_bufnr].filetype = "md-peek-status"
  end
  vim.bo[status_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(status_bufnr, 0, -1, false, {
    "●  md-peek live",
    ui.truncate(section, width - 9),
  })
  vim.bo[status_bufnr].modifiable = false
  vim.api.nvim_buf_clear_namespace(status_bufnr, ui.ns, 0, -1)
  vim.api.nvim_buf_add_highlight(status_bufnr, ui.ns, "DiagnosticOk", 0, 0, 1)
  vim.api.nvim_buf_add_highlight(status_bufnr, ui.ns, "Title", 0, 3, -1)
  vim.api.nvim_buf_add_highlight(status_bufnr, ui.ns, "Comment", 1, 0, -1)
  vim.api.nvim_buf_set_extmark(status_bufnr, ui.ns, 1, 0, {
    virt_text = { { string.format("%3d%%", progress), "Number" } },
    virt_text_pos = "right_align",
  })

  local config = {
    relative = "win",
    win = source_win,
    row = 1,
    col = math.max(0, vim.api.nvim_win_get_width(source_win) - width - 3),
    width = width,
    height = 2,
    style = "minimal",
    border = opts.border or "rounded",
    focusable = false,
    noautocmd = true,
    zindex = 45,
  }
  if ui.valid_win(status_win) then
    vim.api.nvim_win_set_config(status_win, config)
  else
    status_win = vim.api.nvim_open_win(status_bufnr, false, config)
    vim.wo[status_win].winblend = opts.winblend or 8
    vim.wo[status_win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
  end
end

return M
