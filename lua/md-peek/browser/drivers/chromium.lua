local base = require("md-peek.browser.drivers.base")

local MAC = {
  { name = "Google Chrome", path = "/Applications/Google Chrome.app" },
  { name = "Brave Browser", path = "/Applications/Brave Browser.app" },
  { name = "Microsoft Edge", path = "/Applications/Microsoft Edge.app" },
  { name = "Chromium", path = "/Applications/Chromium.app" },
}

local LINUX = {
  "google-chrome-stable",
  "google-chrome",
  "chromium-browser",
  "chromium",
  "brave-browser",
  "microsoft-edge",
}

local function windows()
  local program_files = os.getenv("PROGRAMFILES")
  local program_files_x86 = os.getenv("ProgramFiles(x86)")
  local local_data = os.getenv("LOCALAPPDATA")
  return {
    program_files and (program_files .. "\\Google\\Chrome\\Application\\chrome.exe"),
    program_files_x86 and (program_files_x86 .. "\\Google\\Chrome\\Application\\chrome.exe"),
    local_data and (local_data .. "\\Google\\Chrome\\Application\\chrome.exe"),
    program_files_x86 and (program_files_x86 .. "\\Microsoft\\Edge\\Application\\msedge.exe"),
    local_data and (local_data .. "\\BraveSoftware\\Brave-Browser\\Application\\brave.exe"),
  }
end

return base.define({
  kind = "chromium",
  -- Chromium keeps a lock file in its profile, so one profile can be shared safely between runs.
  persistent_profile = true,

  candidates = function(os_name)
    if os_name == "mac" then
      return vim.tbl_map(function(app)
        return {
          name = app.name,
          path = app.path,
          binary = app.path .. "/Contents/MacOS/" .. app.name,
        }
      end, MAC)
    elseif os_name == "linux" then
      return LINUX
    end
    return windows()
  end,

  --- `--app` gives a window with no tabs or address bar, sized and placed by flags alone.
  command = function(executable, url, profile_directory, size, position)
    return {
      executable,
      "--app=" .. url,
      string.format("--window-size=%d,%d", size.width, size.height),
      string.format("--window-position=%d,%d", position.x, position.y),
      "--user-data-dir=" .. profile_directory,
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-extensions",
      "--disable-sync",
      "--disable-background-networking",
      "--disable-component-update",
    }
  end,
})
