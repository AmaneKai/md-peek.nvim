local M = {}

local active_process

local function remove_profile(profile_directory)
  if profile_directory and vim.fn.isdirectory(profile_directory) == 1 then
    vim.fn.delete(profile_directory, "rf")
  end
end

local function forget(process)
  if not process.keep_profile then
    remove_profile(process.profile_directory)
  end
  if active_process == process then
    active_process = nil
  end
end

local function stop_process(process, wait_for_completion)
  vim.fn.jobstop(process.job_id)
  if wait_for_completion then
    vim.fn.jobwait({ process.job_id }, 2000)
    forget(process)
  end
end

--- `keep_profile` marks a profile that outlives the preview (reused to skip first-run setup).
function M.start(command, tag, profile_directory, keep_profile)
  if active_process then
    stop_process(active_process, true)
  end

  local process = {
    job_id = 0,
    profile_directory = profile_directory,
    keep_profile = keep_profile,
    tag = tag,
  }
  active_process = process
  process.job_id = vim.fn.jobstart(command, {
    -- Keep the job attached so Neovim also terminates it after an abrupt exit.
    detach = false,
    on_exit = function()
      forget(process)
    end,
  })

  if process.job_id <= 0 then
    forget(process)
    return false
  end
  return true
end

function M.stop(tag, wait_for_completion)
  local process = active_process
  if not process or process.tag ~= tag then
    return false
  end
  stop_process(process, wait_for_completion)
  return true
end

function M.is_active(tag)
  return active_process ~= nil and active_process.tag == tag
end

return M
