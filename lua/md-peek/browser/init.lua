local detect = require("md-peek.browser.detect")
local process = require("md-peek.browser.process")
local profile = require("md-peek.browser.profile")
local windows = require("md-peek.browser.windows")

local M = {}

M.find = detect.find
M.unavailable_reason = detect.unavailable_reason

local function launch_owned_browser(found, url, size, position)
  local driver = found.driver
  local profile_directory, keep_profile = profile.choose(driver)
  if not profile_directory then
    vim.notify("[md-peek] could not create a browser profile", vim.log.levels.ERROR)
    return
  end

  local port = url:match(":(%d+)/")
  local tag = port and ("md-peek:" .. port) or url
  local command = driver.command(found.binary or found.path, url, profile_directory, size, position)
  if not process.start(command, tag, profile_directory, keep_profile) then
    vim.notify("[md-peek] failed to launch the browser preview", vim.log.levels.ERROR)
    return
  end

  driver.after_launch(found, tag, size, position)
end

function M.open(url, size, position, preference)
  local found = M.find(preference)
  if not found then
    vim.notify(
      "[md-peek] requested browser was not found; opening a normal browser tab",
      vim.log.levels.WARN
    )
    vim.ui.open(url)
    return
  end

  launch_owned_browser(found, url, size, position)
end

function M.close(tag, preference, options)
  options = options or {}
  local wait_for_completion = options.wait_for_completion == true
  if process.stop(tag, wait_for_completion) then
    return
  end

  local found = M.find(preference)
  if found then
    windows.close(found, tag, wait_for_completion)
  end
end

return M
