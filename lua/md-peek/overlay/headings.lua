local markdown = require("md-peek.markdown")
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
  local headings = markdown.scan(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)).headings
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
