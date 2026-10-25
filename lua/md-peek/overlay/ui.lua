local M = {}

M.ns = vim.api.nvim_create_namespace("md-peek-overlay")

function M.valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

function M.valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

function M.close(win)
  if M.valid_win(win) then
    vim.api.nvim_win_close(win, true)
  end
end

function M.truncate(text, max_width)
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

return M
