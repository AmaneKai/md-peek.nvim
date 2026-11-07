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

--- The one pass over a document's lines that finds what is prose and what is not: front matter
--- and fenced code are skipped, and ATX and Setext headings are collected. The heading list and
--- the link diagnostics both read from it, so they can never disagree about where a fence ends.
---
--- Returns `{ headings = { {line, level, title}, ... }, skip = { [line] = true } }`; `skip` marks
--- every line inside front matter or a fence, delimiters included.
function M.scan(lines)
  local headings, skip = {}, {}
  local fence_char, fence_length
  local in_frontmatter = lines[1] ~= nil and lines[1]:match("^%s*%-%-%-%s*$") ~= nil

  for index, line in ipairs(lines) do
    local handled = false
    if in_frontmatter then
      if index > 1 and line:match("^%s*%-%-%-%s*$") then
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
      elseif fence_char then
        handled = true
      end
    end

    if handled then
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
          table.insert(headings, {
            line = index - 1,
            level = underline:sub(1, 1) == "=" and 1 or 2,
            title = previous,
          })
        end
      end
    end
  end
  return { headings = headings, skip = skip }
end

return M
