local browser_process = require("md-peek.browser.process")

local M = {}

function M.resize_firefox(found, tag, window, position)
  if found.os == "mac" then
    vim.defer_fn(function()
      if not browser_process.is_active(tag) then
        return
      end
      local script = string.format(
        'tell application "%s" to repeat with w in every window\ntry\nif (name of w) contains "%s" then set bounds of w to {%d, %d, %d, %d}\nend try\nend repeat',
        found.name,
        tag,
        position.x,
        position.y,
        position.x + window.width,
        position.y + window.height
      )
      vim.fn.jobstart({ "osascript", "-e", script }, { detach = false })
    end, 1200)
  elseif found.os == "linux" and vim.fn.executable("xdotool") == 1 then
    vim.defer_fn(function()
      if not browser_process.is_active(tag) then
        return
      end
      vim.fn.jobstart({
        "xdotool",
        "search",
        "--name",
        tag,
        "windowsize",
        "%@",
        tostring(window.width),
        tostring(window.height),
        "windowmove",
        "%@",
        tostring(position.x),
        tostring(position.y),
      }, { detach = false })
    end, 1200)
  elseif found.os == "linux" and vim.fn.executable("wmctrl") == 1 then
    vim.defer_fn(function()
      if not browser_process.is_active(tag) then
        return
      end
      local geometry =
        string.format("0,%d,%d,%d,%d", position.x, position.y, window.width, window.height)
      vim.fn.jobstart({ "wmctrl", "-r", tag, "-e", geometry }, { detach = false })
    end, 1200)
  end
end

local function run_close_command(command, wait_for_completion)
  if wait_for_completion then
    return vim.system(command, { text = true }):wait(2000)
  end
  vim.fn.jobstart(command, { detach = true })
end

local function close_wmctrl_windows(tag, wait_for_completion)
  local function close_matches(output)
    for line in (output or ""):gmatch("[^\n]+") do
      if line:find(tag, 1, true) then
        local id = line:match("^(%S+)")
        if id then
          run_close_command({ "wmctrl", "-ic", id }, wait_for_completion)
        end
      end
    end
  end

  if wait_for_completion then
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

local function close_windows_preview(tag, wait_for_completion)
  local escaped_tag = tag:gsub("'", "''")
  local script = string.format(
    "$title = '%s'; Get-Process | Where-Object { $_.MainWindowTitle -like ('*' + $title + '*') } | ForEach-Object { [void]$_.CloseMainWindow() }",
    escaped_tag
  )
  run_close_command({
    "powershell.exe",
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-Command",
    script,
  }, wait_for_completion)
end

--- Closes preview windows by title when the owned browser process is no longer tracked.
function M.close_by_tag(found, tag, wait_for_completion)
  if found.os == "mac" then
    local script = string.format(
      'tell application "%s" to repeat with w in every window\ntry\nif (name of w) contains "%s" then close w\nend try\nend repeat',
      found.name,
      tag
    )
    run_close_command({ "osascript", "-e", script }, wait_for_completion)
  elseif found.os == "linux" and vim.fn.executable("xdotool") == 1 then
    run_close_command({ "xdotool", "search", "--name", tag, "windowclose" }, wait_for_completion)
  elseif found.os == "linux" and vim.fn.executable("wmctrl") == 1 then
    close_wmctrl_windows(tag, wait_for_completion)
  elseif found.os == "win32" then
    close_windows_preview(tag, wait_for_completion)
  end
end

return M
