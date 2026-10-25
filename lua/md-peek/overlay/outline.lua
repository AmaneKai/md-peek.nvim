local scan = require("md-peek.overlay.headings")
local ui = require("md-peek.overlay.ui")

local M = {}

local outline_bufnr
local outline_win

function M.close_outline()
  ui.close(outline_win)
  outline_win, outline_bufnr = nil, nil
end

function M.open_outline(bufnr, opts, on_jump)
  opts = opts or {}
  M.close_outline()
  local headings = scan.headings(bufnr)
  local width = math.max(40, math.min(opts.width or 76, vim.o.columns - 8))
  local height = math.max(1, math.min(math.max(1, #headings), opts.height or 20, vim.o.lines - 7))
  local lines = {}
  for _, heading in ipairs(headings) do
    local icon = heading.level == 1 and "◆" or "›"
    local prefix = string.rep("  ", heading.level - 1) .. icon .. " "
    table.insert(
      lines,
      prefix .. ui.truncate(heading.title, width - vim.fn.strdisplaywidth(prefix) - 3)
    )
  end
  if #lines == 0 then
    lines = { "  No Markdown headings" }
  end

  outline_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[outline_bufnr].bufhidden = "wipe"
  vim.bo[outline_bufnr].filetype = "md-peek-outline"
  vim.api.nvim_buf_set_lines(outline_bufnr, 0, -1, false, lines)
  vim.bo[outline_bufnr].modifiable = false

  outline_win = vim.api.nvim_open_win(outline_bufnr, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = opts.border or "rounded",
    title = " Markdown outline ",
    title_pos = "center",
    footer = #headings > 0 and " ↵ jump  q close " or " q close ",
    footer_pos = "center",
    zindex = 60,
  })
  vim.wo[outline_win].cursorline = true
  vim.wo[outline_win].winblend = opts.winblend or 4
  vim.wo[outline_win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:Visual"

  for row, heading in ipairs(headings) do
    local prefix_end = (heading.level - 1) * 2 + 3
    vim.api.nvim_buf_add_highlight(
      outline_bufnr,
      ui.ns,
      heading.level <= 2 and "Title" or "Comment",
      row - 1,
      0,
      prefix_end
    )
    vim.api.nvim_buf_set_extmark(outline_bufnr, ui.ns, row - 1, 0, {
      virt_text = { { "L" .. heading.line, "LineNr" } },
      virt_text_pos = "right_align",
    })
  end

  local cursor_line = vim.api.nvim_win_get_cursor(vim.fn.bufwinid(bufnr))[1]
  local selected = 1
  for index, heading in ipairs(headings) do
    if heading.line > cursor_line then
      break
    end
    selected = index
  end
  vim.api.nvim_win_set_cursor(outline_win, { selected, 0 })

  local function dismiss()
    M.close_outline()
  end
  local function jump()
    local selected_heading = headings[vim.api.nvim_win_get_cursor(0)[1]]
    if not selected_heading then
      return
    end
    M.close_outline()
    local source_win = vim.fn.bufwinid(bufnr)
    if source_win == -1 then
      return
    end
    vim.api.nvim_set_current_win(source_win)
    vim.api.nvim_win_set_cursor(source_win, { selected_heading.line, 0 })
    vim.cmd.normal({ "zz", bang = true })
    if on_jump then
      on_jump()
    end
  end
  vim.keymap.set("n", "<CR>", jump, { buffer = outline_bufnr, silent = true })
  vim.keymap.set("n", "q", dismiss, { buffer = outline_bufnr, silent = true })
  vim.keymap.set("n", "<Esc>", dismiss, { buffer = outline_bufnr, silent = true })
end

return M
