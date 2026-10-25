--- Picks the window-control adapter for this machine and retries resizes until the window exists.
local process = require("md-peek.browser.process")

local M = {}

-- In order of preference per operating system.
local ADAPTERS = {
  mac = { "osascript" },
  linux = { "xdotool", "wmctrl" },
  win32 = { "powershell" },
}

--- The first adapter for `os_name` whose tool is installed, or nil.
function M.adapter(os_name)
  for _, name in ipairs(ADAPTERS[os_name] or {}) do
    local adapter = require("md-peek.browser.windows." .. name)
    if adapter.available() then
      return adapter
    end
  end
end

--- Which window-control tools exist here, for `:checkhealth` and for choosing an adapter.
function M.capabilities()
  local capabilities = {}
  for _, names in pairs(ADAPTERS) do
    for _, name in ipairs(names) do
      capabilities[name] = require("md-peek.browser.windows." .. name).available()
    end
  end
  return capabilities
end

M.RETRY_DELAYS = { 200, 300, 500, 1000, 2000 }

--- Resizes the window titled `tag`. A freshly started browser has no window yet, so the attempt
--- repeats after each delay in `RETRY_DELAYS` until a window matched, the preview closed, or the
--- delays ran out. Calls `on_done(matched)` once at the end.
function M.resize_when_ready(found, tag, size, position, on_done)
  local adapter = M.adapter(found.os)
  if not adapter or not adapter.resize then
    if on_done then
      on_done(false)
    end
    return
  end

  local attempt = 0
  local function try()
    attempt = attempt + 1
    if not process.is_active(tag) then
      if on_done then
        on_done(false)
      end
      return
    end
    adapter.resize(found, tag, size, position, function(matched)
      if matched and matched > 0 then
        if on_done then
          on_done(true)
        end
      elseif attempt < #M.RETRY_DELAYS then
        vim.defer_fn(try, M.RETRY_DELAYS[attempt + 1])
      elseif on_done then
        on_done(false)
      end
    end)
  end

  vim.defer_fn(try, M.RETRY_DELAYS[1])
end

function M.close(found, tag, wait)
  local adapter = M.adapter(found.os)
  if adapter then
    adapter.close(found, tag, wait)
  end
end

return M
