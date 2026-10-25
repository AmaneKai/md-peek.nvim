--- macOS window control through AppleScript. Windows are found by their title, which md-peek tags
--- with the server port (see client/render/pipeline.ts).
local M = { name = "osascript" }

function M.available()
  return vim.fn.executable("osascript") == 1
end

local function run(script, on_done, wait)
  if wait then
    local result = vim.system({ "osascript", "-e", script }, { text = true }):wait(2000)
    if on_done then
      on_done(result.code == 0 and tonumber(vim.trim(result.stdout or "")) or 0)
    end
    return
  end
  vim.system({ "osascript", "-e", script }, { text = true }, function(result)
    if on_done then
      vim.schedule(function()
        on_done(result.code == 0 and tonumber(vim.trim(result.stdout or "")) or 0)
      end)
    end
  end)
end

local function for_each_window(app, tag, action)
  return string.format(
    'tell application "%s"\nset matched to 0\nrepeat with w in every window\ntry\nif (name of w) contains "%s" then\n%s\nset matched to matched + 1\nend if\nend try\nend repeat\nreturn matched\nend tell',
    app,
    tag,
    action
  )
end

--- Moves and sizes the window titled with `tag`; `on_done(count)` reports how many matched.
function M.resize(found, tag, size, position, on_done)
  local action = string.format(
    "set bounds of w to {%d, %d, %d, %d}",
    position.x,
    position.y,
    position.x + size.width,
    position.y + size.height
  )
  run(for_each_window(found.name, tag, action), on_done, false)
end

function M.close(found, tag, wait)
  run(for_each_window(found.name, tag, "close w"), nil, wait)
end

return M
