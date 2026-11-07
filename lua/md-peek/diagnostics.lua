local compiler = require("md-peek.compiler")
local overlay = require("md-peek.overlay")

local M = {}

local uv = vim.uv or vim.loop
local ns = vim.api.nvim_create_namespace("md-peek-diagnostics")

local function decode(path)
  return (path:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

--- GitHub-style heading slug. It is the compiler's own, so it always matches the preview's anchors.
local function slug(title)
  local plugin = package.loaded["md-peek"]
  return compiler.slug(title, plugin and plugin.config and plugin.config.preview or {})
end

local function heading_slugs(bufnr)
  local used, slugs = {}, {}
  for _, heading in ipairs(overlay.headings(bufnr)) do
    local base = slug(heading.title)
    if base == "" then
      base = "section"
    end
    local count = used[base] or 0
    used[base] = count + 1
    slugs[count > 0 and (base .. "-" .. count) or base] = true
  end
  return slugs
end

--- Collects every link/image target on a line with its 0-based column span.
local function targets(line)
  local found = {}
  for start, target, finish in line:gmatch("()%b[]%(%s*<?([^%s)>]+)[^)]*%)()") do
    table.insert(found, { target = target, col = start - 1, end_col = finish - 1 })
  end
  for start, target, finish in line:gmatch([[()<img[^>]-src=["']([^"']+)["'][^>]*>()]]) do
    table.insert(found, { target = target, col = start - 1, end_col = finish - 1 })
  end
  -- Reference definitions: `[label]: target "title"`.
  local start, target, finish = line:match("^ ? ? ?%[[^%]^][^%]]*%]:%s*()<?([^%s>]+)>?.-()%s*$")
  if target then
    table.insert(found, { target = target, col = start - 1, end_col = finish - 1 })
  end
  return found
end

--- Finds relative links and images whose file is missing, and `#anchors` with no matching heading.
--- Returns vim.diagnostic items; nothing is reported for URLs or code blocks.
function M.compute(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  local directory = name ~= "" and vim.fs.dirname(vim.fn.fnamemodify(name, ":p")) or vim.fn.getcwd()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local slugs
  local diagnostics = {}
  local scan = overlay.scan(lines)

  for index, line in ipairs(lines) do
    if not scan.skip[index] then
      for _, item in ipairs(targets(line)) do
        local target = item.target
        local report
        if target:match("^#") then
          slugs = slugs or heading_slugs(bufnr)
          local anchor = decode(target:sub(2)):lower()
          if anchor ~= "" and not slugs[anchor] then
            report = "no heading matches anchor " .. target
          end
        elseif not target:match("^%a[%w+.-]*:") and not target:match("^//") then
          local path = decode(target:gsub("[?#].*$", ""))
          if
            path ~= ""
            and not path:match("^/")
            and not uv.fs_stat(vim.fs.joinpath(directory, path))
          then
            report = "file not found: " .. path
          end
        end
        if report then
          table.insert(diagnostics, {
            lnum = index - 1,
            col = item.col,
            end_lnum = index - 1,
            end_col = item.end_col,
            severity = vim.diagnostic.severity.WARN,
            source = "md-peek",
            message = report,
          })
        end
      end
    end
  end
  return diagnostics
end

local audited_tick = {}

--- Audits links and images (a filesystem check per local target, so not on every keystroke).
--- Skips a buffer that has not changed since the last audit unless `force` is set, as it is
--- after a save, when files on disk may have changed.
function M.update(bufnr, force)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  if not force and audited_tick[bufnr] == tick then
    return
  end
  audited_tick[bufnr] = tick
  vim.diagnostic.set(ns, bufnr, M.compute(bufnr))
end

function M.clear(bufnr)
  audited_tick[bufnr or 0] = nil
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.diagnostic.reset(ns, bufnr)
  end
end

return M
