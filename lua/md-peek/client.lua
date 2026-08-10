local M = {}
local uv = vim.uv or vim.loop
local server = require("md-peek.server")

local timers = {}

function M.send(message)
  if server.send(message) then
    return true
  end
  vim.notify("[md-peek] preview server is unavailable", vim.log.levels.WARN)
  return false
end

local function cancel(key)
  local old = timers[key]
  if old then
    if not old.closed then
      old.timer:stop()
      old.timer:close()
    end
    timers[key] = nil
  end
end

function M.debounce(key, delay, callback)
  cancel(key)
  local timer = uv.new_timer()
  local pending = { timer = timer, closed = false }
  timers[key] = pending
  timer:start(delay, 0, function()
    timer:stop()
    timer:close()
    pending.closed = true
    vim.schedule(function()
      if timers[key] ~= pending then
        return
      end
      timers[key] = nil
      callback()
    end)
  end)
end

function M.cancel_debounced()
  local keys = vim.tbl_keys(timers)
  for _, key in ipairs(keys) do
    cancel(key)
  end
end

return M
