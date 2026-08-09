local M = {}
local browser_process = require("md-peek.browser_process")

local MAC_CHROMIUM = {
  {
    name = "Google Chrome",
    path = "/Applications/Google Chrome.app",
    binary = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  },
  {
    name = "Brave Browser",
    path = "/Applications/Brave Browser.app",
    binary = "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
  },
  {
    name = "Microsoft Edge",
    path = "/Applications/Microsoft Edge.app",
    binary = "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  },
  {
    name = "Chromium",
    path = "/Applications/Chromium.app",
    binary = "/Applications/Chromium.app/Contents/MacOS/Chromium",
  },
}
local MAC_FIREFOX = {
  {
    name = "Firefox",
    path = "/Applications/Firefox.app",
    binary = "/Applications/Firefox.app/Contents/MacOS/firefox",
  },
  {
    name = "Firefox Developer Edition",
    path = "/Applications/Firefox Developer Edition.app",
    binary = "/Applications/Firefox Developer Edition.app/Contents/MacOS/firefox",
  },
}
local LINUX_CHROMIUM = {
  "google-chrome-stable",
  "google-chrome",
  "chromium-browser",
  "chromium",
  "brave-browser",
  "microsoft-edge",
}
local LINUX_FIREFOX = { "firefox", "firefox-developer-edition", "firefox-esr" }

local function windows_chromium()
  local pf = os.getenv("PROGRAMFILES")
  local pfx86 = os.getenv("ProgramFiles(x86)")
  local localdata = os.getenv("LOCALAPPDATA")
  return {
    pf and (pf .. "\\Google\\Chrome\\Application\\chrome.exe"),
    pfx86 and (pfx86 .. "\\Google\\Chrome\\Application\\chrome.exe"),
    localdata and (localdata .. "\\Google\\Chrome\\Application\\chrome.exe"),
    pfx86 and (pfx86 .. "\\Microsoft\\Edge\\Application\\msedge.exe"),
    localdata and (localdata .. "\\BraveSoftware\\Brave-Browser\\Application\\brave.exe"),
  }
end

local function windows_firefox()
  local pf = os.getenv("PROGRAMFILES")
  local pfx86 = os.getenv("ProgramFiles(x86)")
  local localdata = os.getenv("LOCALAPPDATA")
  return {
    pf and (pf .. "\\Mozilla Firefox\\firefox.exe"),
    pfx86 and (pfx86 .. "\\Mozilla Firefox\\firefox.exe"),
    localdata and (localdata .. "\\Mozilla Firefox\\firefox.exe"),
  }
end

local function find_mac(candidates, kind)
  for _, app in ipairs(candidates) do
    if vim.fn.isdirectory(app.path) == 1 then
      return { os = "mac", kind = kind, name = app.name, binary = app.binary }
    end
  end
end

local function find_linux(candidates, kind)
  for _, binary in ipairs(candidates) do
    if vim.fn.executable(binary) == 1 then
      return { os = "linux", kind = kind, binary = binary, name = binary }
    end
  end
end

local function find_windows(candidates, kind)
  for _, path in ipairs(candidates) do
    if path and vim.fn.filereadable(path) == 1 then
      return { os = "win32", kind = kind, path = path, name = vim.fn.fnamemodify(path, ":t") }
    end
  end
end

local function find_kind(kind)
  if vim.fn.has("mac") == 1 then
    return find_mac(kind == "firefox" and MAC_FIREFOX or MAC_CHROMIUM, kind)
  elseif vim.fn.has("linux") == 1 then
    return find_linux(kind == "firefox" and LINUX_FIREFOX or LINUX_CHROMIUM, kind)
  elseif vim.fn.has("win32") == 1 then
    return find_windows(kind == "firefox" and windows_firefox() or windows_chromium(), kind)
  end
end

--- Find the configured browser family. `auto` retains the chromeless
--- Chromium experience when available, then falls back to Firefox.
function M.find(preference)
  preference = preference or "auto"
  if preference == "firefox" or preference == "chromium" then
    return find_kind(preference)
  end
  if preference == "auto" then
    return find_kind("chromium") or find_kind("firefox")
  end
end

local function resize_firefox(found, tag, window, position)
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

local function launch_owned_browser(found, url, window, position)
  local profile_directory = vim.fn.tempname() .. "-md-peek"
  if vim.fn.mkdir(profile_directory, "p") == 0 then
    vim.notify("[md-peek] could not create a temporary browser profile", vim.log.levels.ERROR)
    return
  end

  local port = url:match(":(%d+)/")
  local tag = port and ("md-peek:" .. port) or url
  local command = browser_process.command(
    found.binary or found.path,
    found.kind,
    url,
    profile_directory,
    window,
    position
  )
  if not browser_process.start(command, tag, profile_directory) then
    vim.notify("[md-peek] failed to launch the browser preview", vim.log.levels.ERROR)
    return
  end

  if found.kind == "firefox" then
    resize_firefox(found, tag, window, position)
  end
end

function M.open(url, window, position, preference)
  local found = M.find(preference)
  if not found then
    vim.notify(
      "[md-peek] requested browser was not found; opening a normal browser tab",
      vim.log.levels.WARN
    )
    vim.ui.open(url)
    return
  end

  launch_owned_browser(found, url, window, position)
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

function M.close(tag, preference, options)
  options = options or {}
  local wait_for_completion = options.wait_for_completion == true
  if browser_process.stop(tag, wait_for_completion) then
    return
  end

  local found = M.find(preference)
  if not found then
    return
  end
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
