local detect = require("md-peek.browser.detect")
local process = require("md-peek.browser.process")
local profile = require("md-peek.browser.profile")
local windows = require("md-peek.browser.window")

local M = {}

M.find = detect.find

local function launch_owned_browser(found, url, size, position)
  local profile_directory, keep_profile = profile.choose(found)
  if not profile_directory then
    vim.notify("[md-peek] could not create a browser profile", vim.log.levels.ERROR)
    return
  end

  local port = url:match(":(%d+)/")
  local tag = port and ("md-peek:" .. port) or url
  local command =
    process.command(found.binary or found.path, found.kind, url, profile_directory, size, position)
  if not process.start(command, tag, profile_directory, keep_profile) then
    vim.notify("[md-peek] failed to launch the browser preview", vim.log.levels.ERROR)
    return
  end

  if found.kind == "firefox" then
    windows.resize_firefox(found, tag, size, position)
  end
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
    windows.close_by_tag(found, tag, wait_for_completion)
  end
end

return M
