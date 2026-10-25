local M = {}

local uv = vim.uv or vim.loop

--- Chromium records its owner as a `host-pid` symlink; a lock whose pid is gone is stale.
local function profile_in_use(profile_directory)
  local lock = uv.fs_readlink(profile_directory .. "/SingletonLock")
  if not lock then
    return false
  end
  local pid = tonumber(lock:match("%-(%d+)$"))
  return pid == nil or uv.kill(pid, 0) == 0
end

--- Returns `directory, keep`. A driver that allows it reuses one profile under Neovim's cache, so
--- every open skips first-run setup; it is still separate from the user's own profile. If
--- another Neovim holds it, or the driver wants a fresh one, a throwaway directory is used.
function M.choose(driver)
  if driver.persistent_profile then
    local persistent =
      vim.fs.joinpath(vim.fn.stdpath("cache"), "md-peek", driver.kind .. "-profile")
    if not profile_in_use(persistent) and vim.fn.mkdir(persistent, "p") == 1 then
      return persistent, true
    end
  end
  local temporary = vim.fn.tempname() .. "-md-peek"
  if vim.fn.mkdir(temporary, "p") == 0 then
    return nil
  end
  return temporary, false
end

return M
