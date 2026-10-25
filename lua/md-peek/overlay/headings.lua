local ui = require("md-peek.overlay.ui")

local M = {}

local heading_cache = {}

-- Entries are keyed by buffer, so drop them when a buffer goes away instead of growing forever.
vim.api.nvim_create_autocmd("BufWipeout", {
  group = vim.api.nvim_create_augroup("MdPeekHeadingCache", { clear = true }),
  callback = function(args)
    heading_cache[args.buf] = nil
  end,
})

function M.headings(bufnr)
  if not ui.valid_buf(bufnr) then
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

return M
