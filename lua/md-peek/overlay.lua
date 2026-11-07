--- Neovim-side extras: the heading scanner, the live status HUD and the outline popup.
local M = {}

local ns = vim.api.nvim_create_namespace("md-peek-overlay")

local function valid(win_or_buf, is_win)
  local check = is_win and vim.api.nvim_win_is_valid or vim.api.nvim_buf_is_valid
  return win_or_buf ~= nil and win_or_buf ~= false and check(win_or_buf)
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

---------------------------------------------------------------------------------------------
-- The scanner: the one pass that says what is prose and what is not. The outline and the link
-- diagnostics both read it, so they can never disagree about where a fence ends.

--- Returns `{ headings = { {line, level, title}, ... }, skip = { [line] = true } }`; `skip` marks
--- every line inside front matter or a fence, delimiters included.
function M.scan(lines)
  local headings, skip = {}, {}
  local fence_char, fence_length
  local in_frontmatter = lines[1] ~= nil and lines[1]:match("^%s*%-%-%-%s*$") ~= nil

  for index, line in ipairs(lines) do
    local fenced = false
    if in_frontmatter then
      fenced = true
      in_frontmatter = not (index > 1 and line:match("^%s*%-%-%-%s*$"))
    else
      local marker = line:match("^%s*(`+)") or line:match("^%s*(~+)")
      if marker and #marker >= 3 then
        local char = marker:sub(1, 1)
        if not fence_char then
          fence_char, fence_length = char, #marker
        elseif char == fence_char and #marker >= fence_length then
          fence_char, fence_length = nil, nil
        end
        fenced = true
      elseif fence_char then
        fenced = true
      end
    end

    if fenced then
      skip[index] = true
    else
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
          local level = underline:sub(1, 1) == "=" and 1 or 2
          table.insert(headings, { line = index - 1, level = level, title = previous })
        end
      end
    end
  end
  return { headings = headings, skip = skip }
end

local heading_cache = {}

-- Entries are keyed by buffer, so drop them when a buffer goes away instead of growing forever.
vim.api.nvim_create_autocmd("BufWipeout", {
  group = vim.api.nvim_create_augroup("MdPeekHeadingCache", { clear = true }),
  callback = function(args)
    heading_cache[args.buf] = nil
  end,
})

--- The headings of a buffer, cached per change.
function M.headings(bufnr)
  if not valid(bufnr) then
    return {}
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cached = heading_cache[bufnr]
  if not (cached and cached.tick == tick) then
    cached =
      { tick = tick, headings = M.scan(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)).headings }
    heading_cache[bufnr] = cached
  end
  return cached.headings
end

--- The last heading at or before `line`.
function M.heading_at(headings, line)
  local current
  for _, heading in ipairs(headings) do
    if heading.line > line then
      break
    end
    current = heading
  end
  return current
end

---------------------------------------------------------------------------------------------
-- A floating window that one function owns: `float` creates or updates it, `close_float` closes.

local floats = {}

local function close_float(name)
  local float = floats[name]
  if float and valid(float.win, true) then
    vim.api.nvim_win_close(float.win, true)
  end
  floats[name] = nil
end

function M.close_status()
  close_float("status")
end

function M.close_outline()
  close_float("outline")
end

function M.close_all()
  M.close_status()
  M.close_outline()
end

--- The two-line HUD with the current section and progress. `opts`: enabled, width, border,
--- winblend.
function M.update_status(bufnr, opts)
  opts = opts or {}
  local source = valid(bufnr) and vim.fn.bufwinid(bufnr) or -1
  if opts.enabled == false or source == -1 or vim.api.nvim_win_get_width(source) < 32 then
    return M.close_status()
  end
  local width = math.max(28, math.min(opts.width or 42, vim.api.nvim_win_get_width(source) - 6))
  local line = vim.api.nvim_win_get_cursor(source)[1]
  local progress = math.floor(line / math.max(1, vim.api.nvim_buf_line_count(bufnr)) * 100 + 0.5)
  local current = M.heading_at(M.headings(bufnr), line)
  local section = current and ("H" .. current.level .. "  " .. current.title)
    or "Before first heading"

  local float = floats.status
  if not (float and valid(float.buf)) then
    float = { buf = vim.api.nvim_create_buf(false, true) }
    vim.bo[float.buf].bufhidden = "wipe"
    vim.bo[float.buf].filetype = "md-peek-status"
    floats.status = float
  end
  vim.bo[float.buf].modifiable = true
  vim.api.nvim_buf_set_lines(
    float.buf,
    0,
    -1,
    false,
    { "●  md-peek live", truncate(section, width - 9) }
  )
  vim.bo[float.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(float.buf, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(float.buf, ns, "DiagnosticOk", 0, 0, 1)
  vim.api.nvim_buf_add_highlight(float.buf, ns, "Title", 0, 3, -1)
  vim.api.nvim_buf_add_highlight(float.buf, ns, "Comment", 1, 0, -1)
  vim.api.nvim_buf_set_extmark(float.buf, ns, 1, 0, {
    virt_text = { { string.format("%3d%%", progress), "Number" } },
    virt_text_pos = "right_align",
  })

  local config = {
    relative = "win",
    win = source,
    row = 1,
    height = 2,
    width = width,
    col = math.max(0, vim.api.nvim_win_get_width(source) - width - 3),
    style = "minimal",
    border = opts.border or "rounded",
    focusable = false,
    noautocmd = true,
    zindex = 45,
  }
  if valid(float.win, true) then
    vim.api.nvim_win_set_config(float.win, config)
  else
    float.win = vim.api.nvim_open_win(float.buf, false, config)
    vim.wo[float.win].winblend = opts.winblend or 8
    vim.wo[float.win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
  end
end

--- The heading picker. `<CR>` jumps to the heading and calls `on_jump`; `q`/`<Esc>` close it.
function M.open_outline(bufnr, opts, on_jump)
  opts = opts or {}
  M.close_outline()
  local headings = M.headings(bufnr)
  local width = math.max(40, math.min(opts.width or 76, vim.o.columns - 8))
  local height = math.max(1, math.min(#headings, opts.height or 20, vim.o.lines - 7))
  local lines = {}
  for _, heading in ipairs(headings) do
    local prefix = string.rep("  ", heading.level - 1)
      .. (heading.level == 1 and "◆" or "›")
      .. " "
    table.insert(
      lines,
      prefix .. truncate(heading.title, width - vim.fn.strdisplaywidth(prefix) - 3)
    )
  end
  if #lines == 0 then
    lines = { "  No Markdown headings" }
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "md-peek-outline"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    style = "minimal",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    border = opts.border or "rounded",
    title = " Markdown outline ",
    title_pos = "center",
    footer = #headings > 0 and " ↵ jump  q close " or " q close ",
    footer_pos = "center",
    zindex = 60,
  })
  floats.outline = { buf = buf, win = win }
  vim.wo[win].cursorline = true
  vim.wo[win].winblend = opts.winblend or 4
  vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:Visual"

  for row, heading in ipairs(headings) do
    local group = heading.level <= 2 and "Title" or "Comment"
    vim.api.nvim_buf_add_highlight(buf, ns, group, row - 1, 0, (heading.level - 1) * 2 + 3)
    vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, {
      virt_text = { { "L" .. heading.line, "LineNr" } },
      virt_text_pos = "right_align",
    })
  end
  local selected = 1
  local cursor_line = vim.api.nvim_win_get_cursor(vim.fn.bufwinid(bufnr))[1]
  for index, heading in ipairs(headings) do
    if heading.line > cursor_line then
      break
    end
    selected = index
  end
  vim.api.nvim_win_set_cursor(win, { selected, 0 })

  local function jump()
    local heading = headings[vim.api.nvim_win_get_cursor(0)[1]]
    local source = vim.fn.bufwinid(bufnr)
    if not heading then
      return
    end
    M.close_outline()
    if source ~= -1 then
      vim.api.nvim_set_current_win(source)
      vim.api.nvim_win_set_cursor(source, { heading.line, 0 })
      vim.cmd.normal({ "zz", bang = true })
      if on_jump then
        on_jump()
      end
    end
  end
  local keys = { buffer = buf, silent = true }
  vim.keymap.set("n", "<CR>", jump, keys)
  vim.keymap.set("n", "q", M.close_outline, keys)
  vim.keymap.set("n", "<Esc>", M.close_outline, keys)
end

return M
