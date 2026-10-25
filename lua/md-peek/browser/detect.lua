local M = {}

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

return M
