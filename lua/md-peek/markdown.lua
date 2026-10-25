local M = {}

--- True for buffers md-peek can preview, by filetype or by file name.
function M.is_markdown(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local filetype = vim.bo[bufnr].filetype
  if filetype == "markdown" or filetype == "mdx" then
    return true
  end
  local name = vim.api.nvim_buf_get_name(bufnr):lower()
  return name:match("%.md$") ~= nil or name:match("%.markdown$") ~= nil
end

return M
