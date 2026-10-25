--- X11 window control with xdotool.
local M = { name = "xdotool" }

function M.available()
  return vim.fn.executable("xdotool") == 1
end

function M.resize(_, tag, size, position, on_done)
  vim.system({
    "xdotool",
    "search",
    "--name",
    tag,
    "windowsize",
    "%@",
    tostring(size.width),
    tostring(size.height),
    "windowmove",
    "%@",
    tostring(position.x),
    tostring(position.y),
  }, { text = true }, function(result)
    if on_done then
      -- `search` exits non-zero when no window matched yet.
      vim.schedule(function()
        on_done(result.code == 0 and 1 or 0)
      end)
    end
  end)
end

function M.close(_, tag, wait)
  local command = { "xdotool", "search", "--name", tag, "windowclose" }
  if wait then
    vim.system(command, { text = true }):wait(2000)
  else
    vim.fn.jobstart(command, { detach = true })
  end
end

return M
