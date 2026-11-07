local M = {}

function M.check()
  vim.health.start("md-peek")
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim 0.10+")
  else
    vim.health.error("Neovim 0.10 or newer is required")
  end
  local uv = vim.uv or vim.loop
  if uv and uv.new_tcp then
    local probe = uv.new_tcp()
    local bound = probe:bind("127.0.0.1", 0)
    probe:close()
    if bound then
      vim.health.ok("vim.uv can bind a loopback TCP server")
    else
      vim.health.error("vim.uv could not bind 127.0.0.1; the preview server cannot start")
    end
  else
    vim.health.error("vim.uv TCP support is missing")
  end
  if vim.treesitter and vim.treesitter.get_string_parser then
    local available = {}
    for _, lang in ipairs({ "lua", "vim", "markdown", "c" }) do
      if pcall(vim.treesitter.language.add, lang) then
        table.insert(available, lang)
      end
    end
    if #available > 0 then
      vim.health.ok(
        "Tree-sitter parsers for code blocks: "
          .. table.concat(available, ", ")
          .. " (+ any you install)"
      )
    else
      vim.health.warn(
        "no Tree-sitter parsers found; code blocks will not be highlighted",
        { "Install parsers (for example with nvim-treesitter) for the languages you use" }
      )
    end
  else
    vim.health.error("vim.treesitter is unavailable")
  end
  local browser_preference = require("md-peek").config.browser
  local detect = require("md-peek.browser")
  local found = detect.find(browser_preference)
  if found then
    vim.health.ok(
      (found.kind == "firefox" and "Firefox" or "Chromium")
        .. " browser found: "
        .. found.name
        .. " (browser = "
        .. browser_preference
        .. ")"
    )
  else
    vim.health.warn("Configured browser not found; previews will use a normal browser tab")
  end

  -- Firefox cannot be placed by command-line flags, so it needs a window tool to honour the
  -- configured size and position. Chromium does not.
  local tools = detect.capabilities()
  local available = {}
  for name, present in pairs(tools) do
    if present then
      table.insert(available, name)
    end
  end
  table.sort(available)
  if #available > 0 then
    vim.health.ok("window control available: " .. table.concat(available, ", "))
  elseif found and found.kind == "firefox" and found.os == "linux" then
    vim.health.warn(
      "no window tool found; Firefox will open at its default size and position",
      { "Install xdotool or wmctrl to let md-peek size and place the Firefox window" }
    )
  end
end

return M
