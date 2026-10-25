--- The preview lifecycle as an explicit state machine, so the rest of the plugin asks "is the
--- session active?" instead of juggling flags:
---
---   idle -> starting -> active -> stopping -> idle
---               \          \          /
---                +-> error <+--------+     (error -> starting | stopping)
---
--- Every `begin` starts a new session id; callbacks capture it and ignore themselves once it is
--- stale, which replaces the old hand-incremented `generation` counter.
local M = {}

local ALLOWED = {
  idle = { starting = true },
  starting = { active = true, error = true, stopping = true },
  active = { error = true, stopping = true },
  stopping = { idle = true, error = true },
  error = { starting = true, stopping = true },
}

local current = {}
local last_id = 0

local function reset()
  current = { state = "idle", id = last_id }
end
reset()

local function transition(to)
  if not ALLOWED[current.state][to] then
    return false, string.format("invalid session transition %s -> %s", current.state, to)
  end
  current.state = to
  return true
end

function M.state()
  return current.state
end

function M.bufnr()
  return current.bufnr
end

function M.error()
  return current.error
end

function M.id()
  return current.id
end

--- True while `id` still names the running session (it changes on every begin).
function M.is_current(id)
  return id == current.id and current.state ~= "idle"
end

--- True once the server is up and the buffer can be rendered.
function M.is_active(bufnr)
  return current.state == "active" and (bufnr == nil or current.bufnr == bufnr)
end

--- True for any session that owns `bufnr`, whether still starting or already active.
function M.owns(bufnr)
  return (current.state == "starting" or current.state == "active") and current.bufnr == bufnr
end

--- Starts a session for `bufnr`; returns its id, or nil plus the reason.
function M.begin(bufnr, now)
  local ok, err = transition("starting")
  if not ok then
    return nil, err
  end
  last_id = last_id + 1
  current = {
    state = "starting",
    id = last_id,
    bufnr = bufnr,
    opened_at = now,
    last_sent = nil,
  }
  return current.id
end

function M.activate()
  return transition("active")
end

function M.fail(message)
  local ok, err = transition("error")
  if ok then
    current.error = message
  end
  return ok, err
end

function M.stop()
  return transition("stopping")
end

--- Completes a stop: the session is gone and a new one may begin.
function M.finish()
  local ok, err = transition("idle")
  if ok then
    reset()
  end
  return ok, err
end

--- Moves an active session to another buffer without restarting anything. The id stays the same,
--- so the server's callbacks keep working; what was sent before no longer applies.
function M.retarget(bufnr)
  if current.state ~= "active" then
    return false, "only an active session can change buffer"
  end
  current.bufnr = bufnr
  current.last_sent = nil
  return true
end

function M.opened_at()
  return current.opened_at
end

--- The last document sent to the browser, used to skip identical re-renders.
function M.last_sent()
  return current.last_sent
end

function M.set_last_sent(document)
  current.last_sent = document
end

return M
