--- Window control with wmctrl, for X11 setups without xdotool.
local M = { name = "wmctrl" }

function M.available()
  return vim.fn.executable("wmctrl") == 1
end

function M.resize(_, tag, size, position, on_done)
  local geometry = string.format("0,%d,%d,%d,%d", position.x, position.y, size.width, size.height)
  vim.system({ "wmctrl", "-r", tag, "-e", geometry }, { text = true }, function(result)
    if on_done then
      vim.schedule(function()
        on_done(result.code == 0 and 1 or 0)
      end)
    end
  end)
end

function M.close(_, tag, wait)
  local function close_matches(output)
    for line in (output or ""):gmatch("[^\n]+") do
      if line:find(tag, 1, true) then
        local id = line:match("^(%S+)")
        if id then
          local command = { "wmctrl", "-ic", id }
          if wait then
            vim.system(command, { text = true }):wait(2000)
          else
            vim.fn.jobstart(command, { detach = true })
          end
        end
      end
    end
  end

  if wait then
    local result = vim.system({ "wmctrl", "-l" }, { text = true }):wait(2000)
    if result.code == 0 then
      close_matches(result.stdout)
    end
    return
  end

  vim.system({ "wmctrl", "-l" }, { text = true }, function(result)
    if result.code == 0 then
      close_matches(result.stdout)
    end
  end)
end

return M
