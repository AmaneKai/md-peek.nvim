local M = {}

local function executable(name)
  return vim.fn.executable(name) == 1
end

function M.check()
  vim.health.start("md-peek")
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim 0.10+")
  else
    vim.health.error("Neovim 0.10 or newer is required")
  end
  for _, name in ipairs({ "node" }) do
    if executable(name) then
      vim.health.ok(name .. " found")
    else
      vim.health.error(name .. " not found on PATH")
    end
  end
  local dir = require("md-peek").config.server_dir
  if vim.fn.filereadable(dir .. "/dist/index.js") == 1 then
    vim.health.ok("preview bundle found")
  else
    vim.health.error(
      "preview bundle missing",
      { "Run `cd " .. dir .. " && npm install && npm run build`" }
    )
  end
  if vim.fn.isdirectory(dir .. "/node_modules/ws") == 1 then
    vim.health.ok("server dependencies installed")
  else
    vim.health.error(
      "server dependencies missing",
      { "Run the plugin manager build step, or `cd " .. dir .. " && npm install`" }
    )
  end
  local browser_preference = require("md-peek").config.browser
  local found = require("md-peek.browser").find(browser_preference)
  if found then
    vim.health.ok(
      (found.kind == "firefox" and "Firefox" or "Chromium")
        .. " browser found (browser = "
        .. browser_preference
        .. ")"
    )
  else
    vim.health.warn("Configured browser not found; previews will use a normal browser tab")
  end
end

return M
