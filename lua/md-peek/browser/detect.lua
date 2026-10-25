local windows = require("md-peek.browser.windows")

local M = {}

local DRIVERS = {
  chromium = require("md-peek.browser.drivers.chromium"),
  firefox = require("md-peek.browser.drivers.firefox"),
}

--- "mac", "linux" or "win32"; nil on anything else.
function M.os_name()
  if vim.fn.has("mac") == 1 then
    return "mac"
  elseif vim.fn.has("linux") == 1 then
    return "linux"
  elseif vim.fn.has("win32") == 1 then
    return "win32"
  end
end

local function locate(driver, os_name)
  for _, candidate in ipairs(driver.candidates(os_name)) do
    if os_name == "mac" then
      if vim.fn.isdirectory(candidate.path) == 1 then
        return { name = candidate.name, binary = candidate.binary }
      end
    elseif os_name == "linux" then
      if vim.fn.executable(candidate) == 1 then
        return { name = candidate, binary = candidate }
      end
    elseif candidate and vim.fn.filereadable(candidate) == 1 then
      return { name = vim.fn.fnamemodify(candidate, ":t"), path = candidate }
    end
  end
end

--- Finds an install of one browser family. Returns `{ os, kind, name, binary | path, driver }`.
function M.find_kind(kind, os_name)
  os_name = os_name or M.os_name()
  local driver = DRIVERS[kind]
  if not os_name or not driver then
    return nil
  end
  local install = locate(driver, os_name)
  if install then
    return vim.tbl_extend("force", install, { os = os_name, kind = kind, driver = driver })
  end
end

--- Finds the configured browser. `auto` keeps the chromeless Chromium experience when it is
--- available and falls back to Firefox.
function M.find(preference)
  preference = preference or "auto"
  if preference == "firefox" or preference == "chromium" then
    return M.find_kind(preference)
  elseif preference == "auto" then
    return M.find_kind("chromium") or M.find_kind("firefox")
  end
end

--- Why no browser should be started on this machine (so the URL is shown instead), or nil.
function M.unavailable_reason(preference)
  if preference == "none" then
    return 'browser = "none"'
  end
  if vim.env.SSH_CONNECTION or vim.env.SSH_TTY then
    return "this is an SSH session"
  end
  if M.os_name() == "linux" and not (vim.env.DISPLAY or vim.env.WAYLAND_DISPLAY) then
    return "there is no display server"
  end
end

--- Which window-control tools this machine has (osascript, xdotool, wmctrl, powershell).
function M.capabilities()
  return windows.capabilities()
end

return M
