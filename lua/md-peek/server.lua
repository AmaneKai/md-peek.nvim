local M = { port = nil, url = nil, ready = false, error = nil, token = nil }

local job_id
local stopping = false

local function token()
  local result = vim
    .system({
      "node",
      "-e",
      'process.stdout.write(require("node:crypto").randomBytes(32).toString("hex"))',
    }, { text = true })
    :wait()
  if result.code ~= 0 or not result.stdout or not result.stdout:match("^[0-9a-f]+$") then
    return nil
  end
  return result.stdout
end

function M.start(opts)
  if job_id then
    return true
  end
  opts = opts or {}
  M.port, M.url, M.error = nil, nil, nil
  M.ready = false
  M.token = token()
  if not M.token then
    M.error = "could not generate a secure preview session token"
    return false
  end

  local env = {
    MD_PEEK_PORT = "0",
    MD_PEEK_TOKEN = M.token,
    MD_PEEK_CONFIG = vim.json.encode(opts.preview or {}),
  }
  stopping = false
  local started
  started = vim.fn.jobstart({ "node", "dist/index.js" }, {
    cwd = opts.server_dir,
    env = env,
    stdout_buffered = false,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        local url = line:match("^MD_PEEK_URL=(.+)$")
        if url then
          M.url = url
          M.port = tonumber(url:match(":(%d+)/?$"))
          M.ready = M.port ~= nil
        end
        local event = line:match("^MD_PEEK_EVENT=(.+)$")
        if event and opts.on_event then
          opts.on_event(event)
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          vim.schedule(function()
            vim.notify("[md-peek] " .. line, vim.log.levels.WARN)
          end)
        end
      end
    end,
    on_exit = function(_, code)
      if job_id ~= started then
        return
      end
      local was_ready = M.ready
      job_id, M.url, M.port, M.ready = nil, nil, nil, false
      if not stopping then
        M.error = "preview server exited unexpectedly (exit " .. code .. ")"
        if was_ready then
          vim.schedule(function()
            vim.notify("[md-peek] " .. M.error, vim.log.levels.ERROR)
          end)
        end
      end
    end,
  })
  if started <= 0 then
    M.error = "failed to start Node preview server"
    M.token = nil
    return false
  end
  job_id = started
  return true
end

function M.send(message)
  if not job_id or not M.ready then
    return false
  end
  local ok, payload = pcall(vim.json.encode, message)
  if not ok then
    return false
  end
  return vim.fn.chansend(job_id, payload .. "\n") > 0
end

function M.stop()
  stopping = true
  if job_id then
    vim.fn.jobstop(job_id)
  end
  job_id, M.port, M.url, M.token = nil, nil, nil, nil
  M.ready, M.error = false, nil
end

return M
