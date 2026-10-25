local M = { port = nil, url = nil, ready = false, error = nil, token = nil }

local job_id
local stopping = false
local startup_timer

local uv = vim.uv or vim.loop

local function token()
  local bytes = uv.random(32)
  if type(bytes) ~= "string" or #bytes ~= 32 then
    return nil
  end
  return (bytes:gsub(".", function(char)
    return string.format("%02x", char:byte())
  end))
end

local function cancel_startup_timer()
  if startup_timer then
    startup_timer:stop()
    startup_timer:close()
    startup_timer = nil
  end
end

--- Starts the Node server. Everything it reports is one JSON object per stdout line:
--- `{"type":"ready",...}` once it is listening, then editor events (jump, open_file, ...).
---
--- opts: server_dir, preview, port (0 = any free port), startup_timeout_ms, and the callbacks
---   on_ready(info)   the server is listening (`info.port`, `info.url`)
---   on_event(event)  an event from the preview, already decoded
---   on_error(text)   it failed to start, timed out, or exited unexpectedly
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
    MD_PEEK_PORT = tostring(opts.port or 0),
    MD_PEEK_TOKEN = M.token,
    MD_PEEK_CONFIG = vim.json.encode(opts.preview or {}),
  }
  stopping = false
  local started
  local partial = ""

  local function fail(message)
    M.error = message
    if opts.on_error then
      opts.on_error(message)
    end
  end

  local function handle_line(line)
    local ok, message = pcall(vim.json.decode, line)
    if not ok or type(message) ~= "table" then
      return
    end
    if message.type == "ready" then
      M.port = tonumber(message.port)
      M.url = message.url
      M.ready = M.port ~= nil and type(M.url) == "string"
      if M.ready then
        cancel_startup_timer()
        if opts.on_ready then
          opts.on_ready({ port = M.port, url = M.url })
        end
      end
    elseif opts.on_event then
      opts.on_event(message)
    end
  end

  -- jobstart raises (instead of returning <= 0) for a missing cwd.
  local launched, job = pcall(vim.fn.jobstart, { "node", "dist/index.js" }, {
    cwd = opts.server_dir,
    env = env,
    stdout_buffered = false,
    on_stdout = function(_, data)
      -- Per :h channel-lines, the first element continues the previous chunk's last line.
      data[1] = partial .. data[1]
      partial = table.remove(data)
      for _, line in ipairs(data) do
        if line ~= "" then
          handle_line(line)
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
      cancel_startup_timer()
      job_id, M.url, M.port, M.ready = nil, nil, nil, false
      if not stopping then
        fail(
          (
            was_ready and "preview server exited unexpectedly"
            or "preview server exited before it was ready"
          )
            .. " (exit "
            .. code
            .. ")"
        )
      end
    end,
  })
  started = launched and job or 0
  if started <= 0 then
    M.error = launched and "failed to start Node preview server"
      or ("failed to start Node preview server: " .. tostring(job))
    M.token = nil
    return false
  end
  job_id = started

  local timeout = opts.startup_timeout_ms
  if timeout and timeout > 0 then
    startup_timer = uv.new_timer()
    startup_timer:start(timeout, 0, function()
      vim.schedule(function()
        if job_id == started and not M.ready then
          cancel_startup_timer()
          fail("preview server startup timed out")
        end
      end)
    end)
  end
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
  cancel_startup_timer()
  if job_id then
    vim.fn.jobstop(job_id)
  end
  job_id, M.port, M.url, M.token = nil, nil, nil, nil
  M.ready, M.error = false, nil
end

return M
