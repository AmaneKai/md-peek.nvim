local M = {}
local uv = vim.uv or vim.loop
local server = require("md-peek.server")

local timers = {}

function M.request(port, path, body, on_result)
  local args = {
    "curl",
    "-sS",
    "--connect-timeout",
    "2",
    "--max-time",
    "15",
    "-X",
    "POST",
    "-H",
    "Content-Type: application/json",
  }
  if server.token then
    vim.list_extend(args, { "-H", "X-Md-Peek-Token: " .. server.token })
  end
  vim.list_extend(
    args,
    { "--data-binary", "@-", string.format("http://127.0.0.1:%d%s", port, path) }
  )

  vim.system(args, { stdin = body }, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        vim.notify(
          "[md-peek] request to " .. path .. " failed (curl exit " .. result.code .. ")",
          vim.log.levels.WARN
        )
      end)
      return
    end
    if not on_result or not result.stdout or result.stdout == "" then
      return
    end
    local ok, decoded = pcall(vim.json.decode, result.stdout)
    vim.schedule(function()
      if ok then
        on_result(decoded)
      else
        vim.notify("[md-peek] received an invalid response from " .. path, vim.log.levels.WARN)
      end
    end)
  end)
end

function M.debounced_request(key, port, path, body, delay, on_result)
  local old = timers[key]
  if old then
    old:stop()
    old:close()
  end
  local timer = uv.new_timer()
  timers[key] = timer
  timer:start(delay, 0, function()
    timer:stop()
    timer:close()
    timers[key] = nil
    M.request(port, path, body, on_result)
  end)
end

function M.cancel_debounced()
  for key, timer in pairs(timers) do
    timer:stop()
    timer:close()
    timers[key] = nil
  end
end

return M
