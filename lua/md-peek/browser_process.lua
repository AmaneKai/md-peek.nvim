local M = {}

local active_process

local function remove_profile(profile_directory)
  if profile_directory and vim.fn.isdirectory(profile_directory) == 1 then
    vim.fn.delete(profile_directory, "rf")
  end
end

local function forget(process)
  remove_profile(process.profile_directory)
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

function M.command(executable, kind, url, profile_directory, window, position)
  local command = { executable }
  local arguments

  if kind == "firefox" then
    arguments = {
      "--new-instance",
      "--profile",
      profile_directory,
      "--window-size",
      string.format("%d,%d", window.width, window.height),
      "--new-window",
      url,
    }
  else
    arguments = {
      "--app=" .. url,
      string.format("--window-size=%d,%d", window.width, window.height),
      string.format("--window-position=%d,%d", position.x, position.y),
      "--user-data-dir=" .. profile_directory,
      "--no-first-run",
      "--no-default-browser-check",
    }
  end

  for _, argument in ipairs(arguments) do
    table.insert(command, argument)
  end
  return command
end

function M.start(command, tag, profile_directory)
  if active_process then
    stop_process(active_process, true)
  end

  local process = {
    job_id = 0,
    profile_directory = profile_directory,
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
