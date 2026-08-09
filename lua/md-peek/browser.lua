local M = {}

local MAC_CHROMIUM = {
  { name = "Google Chrome", path = "/Applications/Google Chrome.app" },
  { name = "Brave Browser", path = "/Applications/Brave Browser.app" },
  { name = "Microsoft Edge", path = "/Applications/Microsoft Edge.app" },
  { name = "Chromium", path = "/Applications/Chromium.app" },
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
      local script = string.format(
        'tell application "%s" to repeat with w in every window\ntry\nif (name of w) contains "%s" then set bounds of w to {%d, %d, %d, %d}\nend try\nend repeat',
        found.name,
        tag,
        position.x,
        position.y,
        position.x + window.width,
        position.y + window.height
      )
      vim.fn.jobstart({ "osascript", "-e", script }, { detach = true })
    end, 1200)
  elseif found.os == "linux" and vim.fn.executable("xdotool") == 1 then
    vim.fn.jobstart({
      "xdotool",
      "search",
      "--sync",
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
    }, { detach = true })
  elseif found.os == "linux" and vim.fn.executable("wmctrl") == 1 then
    vim.defer_fn(function()
      local geometry =
        string.format("0,%d,%d,%d,%d", position.x, position.y, window.width, window.height)
      vim.fn.jobstart({ "wmctrl", "-r", tag, "-e", geometry }, { detach = true })
    end, 1200)
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

  if found.kind == "firefox" then
    local executable = found.binary or found.path
    vim.fn.jobstart({ executable, "--new-window", url }, { detach = true })
    local port = url:match(":(%d+)/")
    if port then
      resize_firefox(found, "md-peek:" .. port, window, position)
    end
    return
  end

  local args = {
    "--app=" .. url,
    string.format("--window-size=%d,%d", window.width, window.height),
    string.format("--window-position=%d,%d", position.x, position.y),
  }
  if found.os == "mac" then
    vim.fn.jobstart({ "open", "-na", found.name, "--args", unpack(args) }, { detach = true })
  else
    vim.fn.jobstart({ found.binary or found.path, unpack(args) }, { detach = true })
  end
end

function M.close(tag, preference)
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
    vim.fn.jobstart({ "osascript", "-e", script }, { detach = true })
  elseif found.os == "linux" and vim.fn.executable("xdotool") == 1 then
    vim.fn.jobstart({ "xdotool", "search", "--name", tag, "windowclose" }, { detach = true })
  elseif found.os == "linux" and vim.fn.executable("wmctrl") == 1 then
    vim.system({ "wmctrl", "-l" }, { text = true }, function(result)
      if result.code ~= 0 then
        return
      end
      for line in (result.stdout or ""):gmatch("[^\n]+") do
        if line:find(tag, 1, true) then
          local id = line:match("^(%S+)")
          if id then
            vim.fn.jobstart({ "wmctrl", "-ic", id }, { detach = true })
          end
        end
      end
    end)
  end
end

return M
