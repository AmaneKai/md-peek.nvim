local M = {}

local status_bufnr
local status_win
local outline_bufnr
local outline_win
local ns = vim.api.nvim_create_namespace("md-peek-overlay")
local heading_cache = {}

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function close(win)
  if valid_win(win) then
    vim.api.nvim_win_close(win, true)
  end
end

local function truncate(text, max_width)
  if vim.fn.strdisplaywidth(text) <= max_width then
    return text
  end
  local result = ""
  for char in text:gmatch("[\1-\127\194-\244][\128-\191]*") do
    if vim.fn.strdisplaywidth(result .. char .. "…") > max_width then
      break
    end
    result = result .. char
  end
  return result .. "…"
end

function M.headings(bufnr)
  if not valid_buf(bufnr) then
    return {}
  end
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cached = heading_cache[bufnr]
  if cached and cached.changedtick == changedtick then
    return cached.headings
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local headings = {}
  local fence_char, fence_length
  local in_frontmatter = lines[1] and lines[1]:match("^%s*---%s*$") ~= nil

  for index, line in ipairs(lines) do
    local handled = false
    if in_frontmatter then
      if index > 1 and line:match("^%s*---%s*$") then
        in_frontmatter = false
      end
      handled = true
    end

    if not handled then
      local marker = line:match("^%s*(`+)") or line:match("^%s*(~+)")
      if marker and #marker >= 3 then
        local char = marker:sub(1, 1)
        if not fence_char then
          fence_char, fence_length = char, #marker
        elseif char == fence_char and #marker >= fence_length then
          fence_char, fence_length = nil, nil
        end
        handled = true
      end
    end

    if not handled and not fence_char then
      local hashes, title = line:match("^%s*(#+)%s+(.+)$")
      if hashes and #hashes <= 6 then
        title = vim.trim(title:gsub("%s+#+%s*$", ""))
        if title ~= "" then
          table.insert(headings, { line = index, level = #hashes, title = title })
        end
      elseif index > 1 then
        local underline = line:match("^%s*(=+)%s*$") or line:match("^%s*(-+)%s*$")
        local previous = vim.trim(lines[index - 1] or "")
        if underline and previous ~= "" and not previous:match("^#+%s") then
          table.insert(headings, {
            line = index - 1,
            level = underline:sub(1, 1) == "=" and 1 or 2,
            title = previous,
          })
        end
      end
    end
  end
  heading_cache[bufnr] = { changedtick = changedtick, headings = headings }
  return headings
end

local function heading_at(headings, line)
  local current
  for _, heading in ipairs(headings) do
    if heading.line > line then
      break
    end
    current = heading
  end
  return current
end

function M.close_status()
  close(status_win)
  status_win, status_bufnr = nil, nil
end

function M.update_status(bufnr, opts)
  opts = opts or {}
  if opts.enabled == false or not valid_buf(bufnr) then
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
  local current = heading_at(M.headings(bufnr), line)
  local section = current and ("H" .. current.level .. "  " .. current.title)
    or "Before first heading"

  if not valid_buf(status_bufnr) then
    status_bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[status_bufnr].bufhidden = "wipe"
    vim.bo[status_bufnr].filetype = "md-peek-status"
  end
  vim.bo[status_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(status_bufnr, 0, -1, false, {
    "●  md-peek live",
    truncate(section, width - 9),
  })
  vim.bo[status_bufnr].modifiable = false
  vim.api.nvim_buf_clear_namespace(status_bufnr, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(status_bufnr, ns, "DiagnosticOk", 0, 0, 1)
  vim.api.nvim_buf_add_highlight(status_bufnr, ns, "Title", 0, 3, -1)
  vim.api.nvim_buf_add_highlight(status_bufnr, ns, "Comment", 1, 0, -1)
  vim.api.nvim_buf_set_extmark(status_bufnr, ns, 1, 0, {
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
  if valid_win(status_win) then
    vim.api.nvim_win_set_config(status_win, config)
  else
    status_win = vim.api.nvim_open_win(status_bufnr, false, config)
    vim.wo[status_win].winblend = opts.winblend or 8
    vim.wo[status_win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
  end
end

function M.close_outline()
  close(outline_win)
  outline_win, outline_bufnr = nil, nil
end

function M.open_outline(bufnr, opts, on_jump)
  opts = opts or {}
  M.close_outline()
  local headings = M.headings(bufnr)
  local width = math.max(40, math.min(opts.width or 76, vim.o.columns - 8))
  local height = math.max(1, math.min(math.max(1, #headings), opts.height or 20, vim.o.lines - 7))
  local lines = {}
  for _, heading in ipairs(headings) do
    local icon = heading.level == 1 and "◆" or "›"
    local prefix = string.rep("  ", heading.level - 1) .. icon .. " "
    table.insert(
      lines,
      prefix .. truncate(heading.title, width - vim.fn.strdisplaywidth(prefix) - 3)
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
      ns,
      heading.level <= 2 and "Title" or "Comment",
      row - 1,
      0,
      prefix_end
    )
    vim.api.nvim_buf_set_extmark(outline_bufnr, ns, row - 1, 0, {
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

function M.close_all()
  M.close_status()
  M.close_outline()
end

return M
