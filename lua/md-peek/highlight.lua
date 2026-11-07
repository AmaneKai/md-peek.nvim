--- Syntax highlighting for fenced code blocks, done by Neovim's own Tree-sitter parsers.
local M = {}

local ALIASES = {
  sh = "bash",
  zsh = "bash",
  shell = "bash",
  console = "bash",
  js = "javascript",
  jsx = "javascript",
  ts = "typescript",
  py = "python",
  rb = "ruby",
  rs = "rust",
  yml = "yaml",
  cs = "c_sharp",
  csharp = "c_sharp",
  cplusplus = "cpp",
  ["c++"] = "cpp",
  dockerfile = "dockerfile",
  md = "markdown",
  vimscript = "vim",
  viml = "vim",
  golang = "go",
  tex = "latex",
  ps1 = "powershell",
  kt = "kotlin",
  hs = "haskell",
  ex = "elixir",
  exs = "elixir",
}

-- Capture name prefix -> CSS class. The longest matching prefix wins.
local CLASSES = {
  keyword = "hl-keyword",
  conditional = "hl-keyword",
  ["repeat"] = "hl-keyword",
  include = "hl-keyword",
  exception = "hl-keyword",
  ["function"] = "hl-function",
  method = "hl-function",
  string = "hl-string",
  character = "hl-string",
  ["string.escape"] = "hl-constant",
  ["string.special"] = "hl-constant",
  comment = "hl-comment",
  type = "hl-type",
  ["type.builtin"] = "hl-type",
  module = "hl-type",
  namespace = "hl-type",
  constructor = "hl-type",
  number = "hl-number",
  float = "hl-number",
  boolean = "hl-number",
  constant = "hl-constant",
  label = "hl-constant",
  operator = "hl-operator",
  property = "hl-property",
  field = "hl-property",
  attribute = "hl-property",
  ["variable.builtin"] = "hl-builtin",
  ["variable.member"] = "hl-property",
  punctuation = "hl-punctuation",
  tag = "hl-tag",
  ["tag.attribute"] = "hl-property",
  ["tag.delimiter"] = "hl-punctuation",
  ["markup.heading"] = "hl-title",
  ["markup.raw"] = "hl-string",
  ["markup.link"] = "hl-function",
  ["markup.list"] = "hl-keyword",
}

local ESCAPES =
  { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }

function M.escape(text)
  return (text:gsub("[&<>\"']", ESCAPES))
end

local class_cache = {}

local function class_for(name)
  local cached = class_cache[name]
  if cached ~= nil then
    return cached or nil
  end
  local found = false
  local key = name
  while key do
    if CLASSES[key] then
      found = CLASSES[key]
      break
    end
    key = key:match("^(.*)%.[^.]*$")
  end
  class_cache[name] = found
  return found or nil
end

--- The Tree-sitter language for a fence info word, or nil when there is none.
function M.resolve_lang(lang)
  if type(lang) ~= "string" or lang == "" then
    return nil
  end
  lang = lang:lower()
  local alias = ALIASES[lang] or lang
  local ok, resolved = pcall(vim.treesitter.language.get_lang, alias)
  if ok and resolved then
    return resolved
  end
  return alias
end

local cache, cache_size = {}, 0

--- Turns [start, end) byte spans with classes into non-overlapping tagged slices. A narrower span
--- beats a wider one; between equal spans the one captured later wins, as in Neovim itself.
local function render(code, spans)
  local points, seen = {}, {}
  for _, span in ipairs(spans) do
    for _, point in ipairs({ span[1], span[2] }) do
      if not seen[point] then
        seen[point] = true
        table.insert(points, point)
      end
    end
  end
  table.sort(points)
  table.sort(spans, function(a, b)
    if a[1] ~= b[1] then
      return a[1] < b[1]
    end
    return a[4] < b[4]
  end)

  local out, active, next_span = {}, {}, 1
  local function emit(from, to, class)
    if to <= from then
      return
    end
    local text = M.escape(code:sub(from + 1, to))
    table.insert(out, class and ('<span class="' .. class .. '">' .. text .. "</span>") or text)
  end

  if points[1] and points[1] > 0 then
    emit(0, points[1], nil)
  end
  for index = 1, #points - 1 do
    local from, to = points[index], points[index + 1]
    while spans[next_span] and spans[next_span][1] <= from do
      table.insert(active, spans[next_span])
      next_span = next_span + 1
    end
    local best
    local kept = {}
    for _, span in ipairs(active) do
      if span[2] > from then
        table.insert(kept, span)
        local width = span[2] - span[1]
        if
          not best
          or width < best[2] - best[1]
          or (width == best[2] - best[1] and span[4] > best[4])
        then
          best = span
        end
      end
    end
    active = kept
    emit(from, to, best and best[3])
  end
  emit(points[#points] or 0, #code, nil)
  return table.concat(out)
end

--- Highlights `code` as `lang`. Always returns valid HTML: plain escaped text when there is no
--- parser for the language.
function M.highlight(code, lang)
  local key = tostring(lang) .. "\0" .. code
  local hit = cache[key]
  if hit then
    return hit
  end

  local result
  local ts_lang = M.resolve_lang(lang)
  if ts_lang and #code < 200000 then
    local ok, html = pcall(function()
      local parser = vim.treesitter.get_string_parser(code, ts_lang)
      local query = vim.treesitter.query.get(ts_lang, "highlights")
      if not query then
        return nil
      end
      local tree = parser:parse()[1]
      if not tree then
        return nil
      end
      local spans = {}
      for id, node in query:iter_captures(tree:root(), code, 0, -1) do
        local name = query.captures[id]
        local class = name and class_for(name)
        if class then
          local _, _, start_byte, _, _, end_byte = node:range(true)
          if end_byte > start_byte then
            table.insert(spans, { start_byte, end_byte, class, #spans })
          end
        end
      end
      return render(code, spans)
    end)
    if ok then
      result = html
    end
  end
  result = result or M.escape(code)

  if cache_size >= 512 then
    cache, cache_size = {}, 0
  end
  cache[key] = result
  cache_size = cache_size + 1
  return result
end

local function hex(value)
  return value and string.format("#%06x", value) or nil
end

local function color(name, attr)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok and type(hl) == "table" then
    return hex(hl[attr or "fg"])
  end
  return nil
end

--- CSS for `data-theme="nvim"`: the page palette and token colours taken from the colorscheme
--- that is active in Neovim right now.
function M.nvim_theme_css()
  local function first(...)
    for _, candidate in ipairs({ ... }) do
      if candidate then
        return candidate
      end
    end
  end
  local variables = {
    ["--md-bg"] = color("Normal", "bg"),
    ["--md-fg"] = color("Normal"),
    ["--md-surface"] = first(
      color("NormalFloat", "bg"),
      color("CursorLine", "bg"),
      color("Pmenu", "bg"),
      color("Normal", "bg")
    ),
    ["--md-surface-2"] = first(color("CursorLine", "bg"), color("Visual", "bg")),
    ["--md-border"] = first(color("FloatBorder"), color("WinSeparator"), color("Comment")),
    ["--md-muted"] = color("Comment"),
    ["--md-accent"] = first(
      color("Directory"),
      color("Title"),
      color("@function"),
      color("Function")
    ),
    ["--md-heading"] = first(color("Title"), color("Normal")),
    ["--md-code"] = first(
      color("NormalFloat", "bg"),
      color("CursorLine", "bg"),
      color("Normal", "bg")
    ),
    ["--md-danger"] = first(color("DiagnosticError"), color("ErrorMsg")),
    ["--md-success"] = first(color("DiagnosticOk"), color("String")),
    ["--md-warning"] = first(color("DiagnosticWarn"), color("WarningMsg")),
    ["--md-important"] = first(color("@keyword"), color("Keyword")),
    ["--hl-keyword"] = first(color("@keyword"), color("Keyword")),
    ["--hl-string"] = first(color("@string"), color("String")),
    ["--hl-title"] = first(color("@type"), color("Type")),
    ["--hl-number"] = first(color("@number"), color("Number")),
    ["--hl-variable"] = first(color("@variable.builtin"), color("Identifier")),
    ["--hl-function"] = first(color("@function"), color("Function")),
    ["--hl-meta"] = first(color("@punctuation"), color("Delimiter")),
    ["--hl-comment"] = first(color("@comment"), color("Comment")),
    ["--hl-type"] = first(color("@type"), color("Type")),
    ["--hl-constant"] = first(color("@constant"), color("Constant")),
    ["--hl-operator"] = first(color("@operator"), color("Operator")),
    ["--hl-property"] = first(color("@property"), color("Identifier")),
    ["--hl-builtin"] = first(color("@variable.builtin"), color("Special")),
    ["--hl-punctuation"] = first(color("@punctuation"), color("Delimiter")),
    ["--hl-tag"] = first(color("@tag"), color("Tag"), color("Function")),
  }
  local names = vim.tbl_keys(variables)
  table.sort(names)
  local lines = {}
  for _, name in ipairs(names) do
    table.insert(lines, "  " .. name .. ": " .. variables[name] .. ";")
  end
  local scheme = vim.o.background == "light" and "light" or "dark"
  return ":root[data-theme='nvim']:not([data-scheme]) {\n  color-scheme: "
    .. scheme
    .. ";\n"
    .. table.concat(lines, "\n")
    .. "\n}\n"
end

return M
