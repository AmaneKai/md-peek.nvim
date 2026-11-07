--- Finding a browser, launching it as an owned preview window, and moving or closing that window.
--- Browsers and window tools are data: adding one means adding a table entry here.
local M = {}
local uv = vim.uv or vim.loop

---------------------------------------------------------------------------------------------
-- Drivers: where a browser lives and how to start it.

local function env_paths(list)
  local paths = {}
  for _, entry in ipairs(list) do
    local base = os.getenv(entry[1])
    if base then
      table.insert(paths, base .. entry[2])
    end
  end
  return paths
end

-- stylua: ignore
M.drivers = {
  chromium = {
    kind = "chromium",
    persistent_profile = true, -- Chromium locks its profile, so one can be shared between runs
    mac = { { "Google Chrome" }, { "Brave Browser" }, { "Microsoft Edge" }, { "Chromium" } },
    linux = { "google-chrome-stable", "google-chrome", "chromium-browser", "chromium", "brave-browser", "microsoft-edge" },
    win32 = {
      { "PROGRAMFILES", "\\Google\\Chrome\\Application\\chrome.exe" },
      { "ProgramFiles(x86)", "\\Google\\Chrome\\Application\\chrome.exe" },
      { "LOCALAPPDATA", "\\Google\\Chrome\\Application\\chrome.exe" },
      { "ProgramFiles(x86)", "\\Microsoft\\Edge\\Application\\msedge.exe" },
      { "LOCALAPPDATA", "\\BraveSoftware\\Brave-Browser\\Application\\brave.exe" },
    },
    --- `--app` gives a window with no tabs or address bar, sized and placed by flags alone.
    command = function(executable, url, profile, size, position)
      return {
        executable, "--app=" .. url,
        string.format("--window-size=%d,%d", size.width, size.height),
        string.format("--window-position=%d,%d", position.x, position.y),
        "--user-data-dir=" .. profile, "--no-first-run", "--no-default-browser-check",
        "--disable-extensions", "--disable-sync", "--disable-background-networking",
        "--disable-component-update",
      }
    end,
  },
  firefox = {
    kind = "firefox",
    persistent_profile = false,
    mac = { { "Firefox", "firefox" }, { "Firefox Developer Edition", "firefox" } },
    linux = { "firefox", "firefox-developer-edition", "firefox-esr" },
    win32 = {
      { "PROGRAMFILES", "\\Mozilla Firefox\\firefox.exe" },
      { "ProgramFiles(x86)", "\\Mozilla Firefox\\firefox.exe" },
      { "LOCALAPPDATA", "\\Mozilla Firefox\\firefox.exe" },
    },
    --- Firefox has no app mode (the window keeps its chrome) and ignores a position flag, so the
    --- window is moved afterwards (`resize_after_launch`).
    resize_after_launch = true,
    command = function(executable, url, profile, size)
      return {
        executable, "--new-instance", "--profile", profile,
        "--window-size", string.format("%d,%d", size.width, size.height), "--new-window", url,
      }
    end,
  },
}

--- "mac", "linux" or "win32"; nil on anything else.
function M.os_name()
  for _, name in ipairs({ "mac", "linux", "win32" }) do
    if vim.fn.has(name) == 1 then
      return name
    end
  end
end

local function locate(driver, os_name)
  local candidates = driver[os_name]
  if os_name == "win32" then
    for _, path in ipairs(env_paths(candidates or {})) do
      if vim.fn.filereadable(path) == 1 then
        return { name = vim.fn.fnamemodify(path, ":t"), path = path }
      end
    end
  elseif os_name == "mac" then
    for _, app in ipairs(candidates or {}) do
      local path = "/Applications/" .. app[1] .. ".app"
      if vim.fn.isdirectory(path) == 1 then
        return { name = app[1], binary = path .. "/Contents/MacOS/" .. (app[2] or app[1]) }
      end
    end
  else
    for _, binary in ipairs(candidates or {}) do
      if vim.fn.executable(binary) == 1 then
        return { name = binary, binary = binary }
      end
    end
  end
end

--- Finds an install of one browser family: `{ os, kind, name, binary | path, driver }`.
function M.find_kind(kind, os_name)
  os_name = os_name or M.os_name()
  local driver = M.drivers[kind]
  local install = os_name and driver and locate(driver, os_name)
  return install
    and vim.tbl_extend("force", install, { os = os_name, kind = kind, driver = driver })
end

--- Finds the configured browser. `auto` prefers Chromium's chromeless mode, then Firefox.
function M.find(preference)
  preference = preference or "auto"
  if M.drivers[preference] then
    return M.find_kind(preference)
  elseif preference == "auto" then
    return M.find_kind("chromium") or M.find_kind("firefox")
  end
end

--- Why no browser should be started on this machine (so the URL is shown instead), or nil.
function M.unavailable_reason(preference)
  if preference == "none" then
    return 'browser = "none"'
  elseif vim.env.SSH_CONNECTION or vim.env.SSH_TTY then
    return "this is an SSH session"
  elseif M.os_name() == "linux" and not (vim.env.DISPLAY or vim.env.WAYLAND_DISPLAY) then
    return "there is no display server"
  end
end

---------------------------------------------------------------------------------------------
-- The one browser process we own, and its profile directory.

local active

local function forget(process)
  if not process.keep_profile and process.profile and vim.fn.isdirectory(process.profile) == 1 then
    vim.fn.delete(process.profile, "rf")
  end
  if active == process then
    active = nil
  end
end

local function stop_process(process, wait)
  vim.fn.jobstop(process.job_id)
  if wait then
    vim.fn.jobwait({ process.job_id }, 2000)
    forget(process)
  end
end

--- Starts `command` as an attached job tagged `tag`. `keep_profile` marks a profile that outlives
--- the preview (reused to skip first-run setup).
function M.start(command, tag, profile, keep_profile)
  if active then
    stop_process(active, true)
  end
  local process = { job_id = 0, profile = profile, keep_profile = keep_profile, tag = tag }
  active = process
  -- Attached, so Neovim also terminates it after an abrupt exit.
  process.job_id = vim.fn.jobstart(command, {
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

--- Stops the process tagged `tag`; false when it is not ours.
function M.stop(tag, wait)
  if not active or active.tag ~= tag then
    return false
  end
  stop_process(active, wait)
  return true
end

function M.is_active(tag)
  return active ~= nil and active.tag == tag
end

--- Chromium records its owner as a `host-pid` symlink; a lock whose pid is gone is stale.
local function profile_in_use(directory)
  local lock = uv.fs_readlink(directory .. "/SingletonLock")
  if not lock then
    return false
  end
  local pid = tonumber(lock:match("%-(%d+)$"))
  return pid == nil or uv.kill(pid, 0) == 0
end

--- `directory, keep`: a reusable profile under the cache dir when the driver allows it and no
--- other Neovim holds it, otherwise a throwaway directory.
local function choose_profile(driver)
  if driver.persistent_profile then
    local persistent = vim.fn.stdpath("cache") .. "/md-peek/" .. driver.kind .. "-profile"
    if not profile_in_use(persistent) and vim.fn.mkdir(persistent, "p") == 1 then
      return persistent, true
    end
  end
  local temporary = vim.fn.tempname() .. "-md-peek"
  if vim.fn.mkdir(temporary, "p") == 1 then
    return temporary, false
  end
end

---------------------------------------------------------------------------------------------
-- Window control. Windows are found by their title, which the page tags with `md-peek:<port>`.

local function run(argv, wait, callback)
  if wait then
    local result = vim.system(argv, { text = true }):wait(2000)
    return callback and callback(result)
  end
  vim.system(argv, { text = true }, function(result)
    if callback then
      vim.schedule(function()
        callback(result)
      end)
    end
  end)
end

local function found(result)
  return result.code == 0 and 1 or 0
end

local function applescript(app, tag, action)
  return string.format(
    'tell application "%s"\nset matched to 0\nrepeat with w in every window\ntry\nif (name of w) contains "%s" then\n%s\nset matched to matched + 1\nend if\nend try\nend repeat\nreturn matched\nend tell',
    app,
    tag,
    action
  )
end

-- Each adapter: `tool` (the executable), `resize(found, tag, size, position, done)` and
-- `close(found, tag, wait)`. `done(count)` reports how many windows matched.
-- stylua: ignore
M.adapters = {
  osascript = {
    os = "mac", tool = "osascript",
    resize = function(install, tag, size, position, done)
      local bounds = string.format("set bounds of w to {%d, %d, %d, %d}", position.x, position.y,
        position.x + size.width, position.y + size.height)
      run({ "osascript", "-e", applescript(install.name, tag, bounds) }, false, function(result)
        done(result.code == 0 and tonumber(vim.trim(result.stdout or "")) or 0)
      end)
    end,
    close = function(install, tag, wait)
      run({ "osascript", "-e", applescript(install.name, tag, "close w") }, wait)
    end,
  },
  xdotool = {
    os = "linux", tool = "xdotool",
    resize = function(_, tag, size, position, done)
      run({ "xdotool", "search", "--name", tag, "windowsize", "%@", tostring(size.width),
        tostring(size.height), "windowmove", "%@", tostring(position.x), tostring(position.y) },
        false, function(result) done(found(result)) end)
    end,
    close = function(_, tag, wait)
      run({ "xdotool", "search", "--name", tag, "windowclose" }, wait)
    end,
  },
  wmctrl = {
    os = "linux", tool = "wmctrl",
    resize = function(_, tag, size, position, done)
      local geometry = string.format("0,%d,%d,%d,%d", position.x, position.y, size.width, size.height)
      run({ "wmctrl", "-r", tag, "-e", geometry }, false, function(result) done(found(result)) end)
    end,
    close = function(_, tag, wait)
      run({ "wmctrl", "-l" }, wait, function(result)
        for line in (result.code == 0 and result.stdout or ""):gmatch("[^\n]+") do
          local id = line:find(tag, 1, true) and line:match("^(%S+)")
          if id then
            run({ "wmctrl", "-ic", id }, wait)
          end
        end
      end)
    end,
  },
  powershell = { -- Windows can only close windows by title; there is no resize hook
    os = "win32", tool = "powershell.exe",
    close = function(_, tag, wait)
      local script = string.format(
        "$title = '%s'; Get-Process | Where-Object { $_.MainWindowTitle -like ('*' + $title + '*') } | ForEach-Object { [void]$_.CloseMainWindow() }",
        tag:gsub("'", "''")
      )
      run({ "powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script }, wait)
    end,
  },
}

-- In order of preference per operating system.
local ADAPTER_ORDER =
  { mac = { "osascript" }, linux = { "xdotool", "wmctrl" }, win32 = { "powershell" } }

--- The first window tool for `os_name` that is installed, or nil.
function M.adapter(os_name)
  for _, name in ipairs(ADAPTER_ORDER[os_name] or {}) do
    local adapter = M.adapters[name]
    if vim.fn.executable(adapter.tool) == 1 then
      return adapter
    end
  end
end

--- Which window-control tools exist here, for `:checkhealth`.
function M.capabilities()
  local available = {}
  for name, adapter in pairs(M.adapters) do
    available[name] = vim.fn.executable(adapter.tool) == 1
  end
  return available
end

M.RETRY_DELAYS = { 200, 300, 500, 1000, 2000 }

--- Resizes the window titled `tag`. A fresh browser has no window yet, so the attempt repeats
--- after each delay in `RETRY_DELAYS` until a window matched, the preview closed, or the delays
--- ran out. Calls `on_done(matched)` once at the end.
function M.resize_when_ready(install, tag, size, position, on_done)
  on_done = on_done or function() end
  local adapter = M.adapter(install.os)
  if not adapter or not adapter.resize then
    return on_done(false)
  end
  local attempt = 0
  local function try()
    attempt = attempt + 1
    if not M.is_active(tag) then
      return on_done(false)
    end
    adapter.resize(install, tag, size, position, function(matched)
      if matched and matched > 0 then
        on_done(true)
      elseif attempt < #M.RETRY_DELAYS then
        vim.defer_fn(try, M.RETRY_DELAYS[attempt + 1])
      else
        on_done(false)
      end
    end)
  end
  vim.defer_fn(try, M.RETRY_DELAYS[1])
end

---------------------------------------------------------------------------------------------
-- The public pair: open a preview window, close it again.

function M.open(url, size, position, preference)
  local install = M.find(preference)
  if not install then
    vim.notify(
      "[md-peek] requested browser was not found; opening a normal browser tab",
      vim.log.levels.WARN
    )
    return vim.ui.open(url)
  end
  local driver = install.driver
  local profile, keep = choose_profile(driver)
  if not profile then
    return vim.notify("[md-peek] could not create a browser profile", vim.log.levels.ERROR)
  end
  local port = url:match(":(%d+)/")
  local tag = port and ("md-peek:" .. port) or url
  local command = driver.command(install.binary or install.path, url, profile, size, position)
  if not M.start(command, tag, profile, keep) then
    return vim.notify("[md-peek] failed to launch the browser preview", vim.log.levels.ERROR)
  end
  if driver.resize_after_launch then
    M.resize_when_ready(install, tag, size, position)
  end
end

function M.close(tag, preference, options)
  local wait = options and options.wait_for_completion == true
  if M.stop(tag, wait) then
    return
  end
  local install = M.find(preference)
  local adapter = install and M.adapter(install.os)
  if adapter then
    adapter.close(install, tag, wait)
  end
end

return M
