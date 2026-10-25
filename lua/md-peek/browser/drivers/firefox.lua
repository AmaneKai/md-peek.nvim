local base = require("md-peek.browser.drivers.base")
local windows = require("md-peek.browser.windows")

local MAC = {
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

local LINUX = { "firefox", "firefox-developer-edition", "firefox-esr" }

local function windows_paths()
  local program_files = os.getenv("PROGRAMFILES")
  local program_files_x86 = os.getenv("ProgramFiles(x86)")
  local local_data = os.getenv("LOCALAPPDATA")
  return {
    program_files and (program_files .. "\\Mozilla Firefox\\firefox.exe"),
    program_files_x86 and (program_files_x86 .. "\\Mozilla Firefox\\firefox.exe"),
    local_data and (local_data .. "\\Mozilla Firefox\\firefox.exe"),
  }
end

return base.define({
  kind = "firefox",

  candidates = function(os_name)
    if os_name == "mac" then
      return MAC
    elseif os_name == "linux" then
      return LINUX
    end
    return windows_paths()
  end,

  --- Firefox has no app mode, so the window keeps its normal chrome.
  command = function(executable, url, profile_directory, size)
    return {
      executable,
      "--new-instance",
      "--profile",
      profile_directory,
      "--window-size",
      string.format("%d,%d", size.width, size.height),
      "--new-window",
      url,
    }
  end,

  --- Firefox ignores a position flag, so move and size the window once it exists.
  after_launch = function(found, tag, size, position)
    windows.resize_when_ready(found, tag, size, position)
  end,
})
