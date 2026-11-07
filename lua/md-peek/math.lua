--- LaTeX math to native MathML, in plain Lua. Browsers render <math> themselves, so no script or
--- font bundle is needed. Anything unknown degrades to visible text instead of failing.
local M = {}

local NAMESPACE = "http://www.w3.org/1998/Math/MathML"
local MAX_INPUT = 20000
local MAX_DEPTH = 40

local function escape(text)
  return (
    text:gsub('[&<>"]', { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" })
  )
end

local function mi(text, attrs)
  return "<mi" .. (attrs or "") .. ">" .. escape(text) .. "</mi>"
end
local function mo(text, attrs)
  return "<mo" .. (attrs or "") .. ">" .. escape(text) .. "</mo>"
end
local function mn(text)
  return "<mn>" .. escape(text) .. "</mn>"
end

---------------------------------------------------------------------------------------------
-- Symbol tables

local GREEK = {
  alpha = "α",
  beta = "β",
  gamma = "γ",
  delta = "δ",
  epsilon = "ϵ",
  varepsilon = "ε",
  zeta = "ζ",
  eta = "η",
  theta = "θ",
  vartheta = "ϑ",
  iota = "ι",
  kappa = "κ",
  lambda = "λ",
  mu = "μ",
  nu = "ν",
  xi = "ξ",
  omicron = "ο",
  pi = "π",
  varpi = "ϖ",
  rho = "ρ",
  varrho = "ϱ",
  sigma = "σ",
  varsigma = "ς",
  tau = "τ",
  upsilon = "υ",
  phi = "ϕ",
  varphi = "φ",
  chi = "χ",
  psi = "ψ",
  omega = "ω",
}
local GREEK_UPPER = {
  Gamma = "Γ",
  Delta = "Δ",
  Theta = "Θ",
  Lambda = "Λ",
  Xi = "Ξ",
  Pi = "Π",
  Sigma = "Σ",
  Upsilon = "Υ",
  Phi = "Φ",
  Psi = "Ψ",
  Omega = "Ω",
}

local OPERATORS = {
  times = "×",
  cdot = "⋅",
  pm = "±",
  mp = "∓",
  div = "÷",
  ast = "∗",
  star = "⋆",
  circ = "∘",
  bullet = "∙",
  oplus = "⊕",
  ominus = "⊖",
  otimes = "⊗",
  oslash = "⊘",
  odot = "⊙",
  cup = "∪",
  cap = "∩",
  setminus = "∖",
  wedge = "∧",
  land = "∧",
  vee = "∨",
  lor = "∨",
  neg = "¬",
  lnot = "¬",
  leq = "≤",
  le = "≤",
  geq = "≥",
  ge = "≥",
  neq = "≠",
  ne = "≠",
  approx = "≈",
  equiv = "≡",
  sim = "∼",
  simeq = "≃",
  cong = "≅",
  propto = "∝",
  ll = "≪",
  gg = "≫",
  prec = "≺",
  succ = "≻",
  ["in"] = "∈",
  notin = "∉",
  ni = "∋",
  subset = "⊂",
  supset = "⊃",
  subseteq = "⊆",
  supseteq = "⊇",
  nsubseteq = "⊈",
  emptyset = "∅",
  varnothing = "∅",
  forall = "∀",
  exists = "∃",
  nexists = "∄",
  nabla = "∇",
  partial = "∂",
  infty = "∞",
  ["to"] = "→",
  rightarrow = "→",
  leftarrow = "←",
  gets = "←",
  Rightarrow = "⇒",
  Leftarrow = "⇐",
  leftrightarrow = "↔",
  Leftrightarrow = "⇔",
  iff = "⟺",
  implies = "⟹",
  impliedby = "⟸",
  mapsto = "↦",
  uparrow = "↑",
  downarrow = "↓",
  longrightarrow = "⟶",
  longleftarrow = "⟵",
  dots = "…",
  ldots = "…",
  cdots = "⋯",
  vdots = "⋮",
  ddots = "⋱",
  angle = "∠",
  perp = "⊥",
  parallel = "∥",
  mid = "∣",
  top = "⊤",
  bot = "⊥",
  prime = "′",
  degree = "°",
  hbar = "ℏ",
  ell = "ℓ",
  Re = "ℜ",
  Im = "ℑ",
  aleph = "ℵ",
  wp = "℘",
  langle = "⟨",
  rangle = "⟩",
  lfloor = "⌊",
  rfloor = "⌋",
  lceil = "⌈",
  rceil = "⌉",
  lbrace = "{",
  rbrace = "}",
  vert = "|",
  Vert = "‖",
  backslash = "\\",
  colon = ":",
  triangle = "△",
  square = "□",
  checkmark = "✓",
  therefore = "∴",
  because = "∵",
}

-- Operators drawn with limits above and below; ∫ takes its scripts at the side.
local LIMIT_OPERATORS = {
  sum = "∑",
  prod = "∏",
  coprod = "∐",
  bigcup = "⋃",
  bigcap = "⋂",
  bigoplus = "⨁",
  bigotimes = "⨂",
  bigvee = "⋁",
  bigwedge = "⋀",
}
local SIDE_OPERATORS = { int = "∫", iint = "∬", iiint = "∭", oint = "∮" }
local LIMIT_WORDS = {
  lim = "lim",
  limsup = "lim sup",
  liminf = "lim inf",
  min = "min",
  max = "max",
  sup = "sup",
  inf = "inf",
  det = "det",
  gcd = "gcd",
  Pr = "Pr",
}
local FUNCTION_NAMES = {}
for name in
  ([[sin cos tan cot sec csc arcsin arccos arctan sinh cosh tanh coth log ln lg exp deg dim ker
  hom arg Pr]]):gmatch("%S+")
do
  FUNCTION_NAMES[name] = true
end

local ACCENTS = {
  hat = "^",
  widehat = "^",
  bar = "¯",
  overline = "‾",
  vec = "→",
  tilde = "˜",
  widetilde = "˜",
  dot = "˙",
  ddot = "¨",
  acute = "´",
  grave = "`",
  check = "ˇ",
  breve = "˘",
  overrightarrow = "→",
}
local UNDER_ACCENTS = { underline = "_", underbrace = "⏟" }
local OVER_ACCENTS = { overbrace = "⏞" }

local SPACES = {
  [","] = "0.1667em",
  [":"] = "0.2222em",
  [";"] = "0.2778em",
  ["!"] = "-0.1667em",
  [" "] = "0.25em",
  quad = "1em",
  qquad = "2em",
  thinspace = "0.1667em",
}

local ENVIRONMENTS = {
  matrix = { "", "" },
  pmatrix = { "(", ")" },
  bmatrix = { "[", "]" },
  Bmatrix = { "{", "}" },
  vmatrix = { "|", "|" },
  Vmatrix = { "‖", "‖" },
  cases = { "{", "" },
  array = { "", "" },
  aligned = { "", "" },
  align = { "", "" },
  ["align*"] = { "", "" },
  gathered = { "", "" },
}

-- Unicode mathematical alphanumerics for \mathbf, \mathbb, \mathcal and \mathfrak.
local STYLES = {
  bf = { upper = 0x1D400, lower = 0x1D41A, digit = 0x1D7CE },
  bb = {
    upper = 0x1D538,
    lower = 0x1D552,
    digit = 0x1D7D8,
    holes = { C = "ℂ", H = "ℍ", N = "ℕ", P = "ℙ", Q = "ℚ", R = "ℝ", Z = "ℤ" },
  },
  cal = {
    upper = 0x1D49C,
    lower = 0x1D4B6,
    holes = {
      B = "ℬ",
      E = "ℰ",
      F = "ℱ",
      H = "ℋ",
      I = "ℐ",
      L = "ℒ",
      M = "ℳ",
      R = "ℛ",
      e = "ℯ",
      g = "ℊ",
      o = "ℴ",
    },
  },
  frak = {
    upper = 0x1D504,
    lower = 0x1D51E,
    holes = { C = "ℭ", H = "ℌ", I = "ℑ", R = "ℜ", Z = "ℨ" },
  },
}
local FONT_COMMANDS = {
  mathbf = "bf",
  boldsymbol = "bf",
  bm = "bf",
  textbf = "bf",
  mathbb = "bb",
  Bbb = "bb",
  mathcal = "cal",
  mathscr = "cal",
  mathfrak = "frak",
}

--- UTF-8 for a code point (LuaJIT has no utf8 library).
local function utf8_char(code)
  if code < 0x80 then
    return string.char(code)
  elseif code < 0x800 then
    return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
  elseif code < 0x10000 then
    return string.char(
      0xE0 + math.floor(code / 0x1000),
      0x80 + math.floor(code / 0x40) % 0x40,
      0x80 + code % 0x40
    )
  end
  return string.char(
    0xF0 + math.floor(code / 0x40000),
    0x80 + math.floor(code / 0x1000) % 0x40,
    0x80 + math.floor(code / 0x40) % 0x40,
    0x80 + code % 0x40
  )
end

local function style_char(style, char)
  local spec = STYLES[style]
  if spec.holes and spec.holes[char] then
    return spec.holes[char]
  end
  local byte = char:byte()
  if char:match("%u") then
    return utf8_char(spec.upper + byte - 65)
  elseif char:match("%l") then
    return utf8_char(spec.lower + byte - 97)
  elseif char:match("%d") and spec.digit then
    return utf8_char(spec.digit + byte - 48)
  end
  return char
end

---------------------------------------------------------------------------------------------
-- Tokenizer

local function tokenize(tex)
  local tokens, position, length = {}, 1, #tex
  while position <= length do
    local char = tex:sub(position, position)
    if char:match("%s") then
      position = position + 1
    elseif char == "\\" then
      local name = tex:match("^%a+", position + 1)
      if name then
        table.insert(tokens, { kind = "cmd", value = name, pos = position })
        position = position + 1 + #name
      else
        local symbol = tex:sub(position + 1, position + 1)
        table.insert(
          tokens,
          { kind = "cmd", value = symbol == "" and "\\" or symbol, pos = position }
        )
        position = position + 2
      end
    elseif char:match("%d") or (char == "." and tex:match("^%.%d", position)) then
      local number = tex:match("^%d*%.?%d+", position) or tex:match("^%d+", position)
      table.insert(tokens, { kind = "num", value = number, pos = position })
      position = position + #number
    elseif char:match("%a") then
      table.insert(tokens, { kind = "ident", value = char, pos = position })
      position = position + 1
    else
      -- One UTF-8 character at a time.
      local byte = char:byte()
      local size = byte >= 240 and 4 or byte >= 224 and 3 or byte >= 192 and 2 or 1
      local symbol = tex:sub(position, position + size - 1)
      table.insert(tokens, { kind = "sym", value = symbol, pos = position })
      position = position + size
    end
  end
  return tokens
end

---------------------------------------------------------------------------------------------
-- Parser. Every parse_* function returns a MathML string.

local function row(parts)
  if #parts == 1 then
    return parts[1]
  end
  return "<mrow>" .. table.concat(parts) .. "</mrow>"
end

local function new_parser(tex, tokens)
  local state = { tokens = tokens, index = 1, depth = 0 }

  local function peek()
    return state.tokens[state.index]
  end
  local function advance()
    local token = state.tokens[state.index]
    state.index = state.index + 1
    return token
  end
  local function is_sym(token, value)
    return token ~= nil and token.kind == "sym" and token.value == value
  end
  local function is_cmd(token, value)
    return token ~= nil and token.kind == "cmd" and token.value == value
  end

  local parse_sequence, parse_atom, parse_group_or_atom

  --- The source text of the next `{...}` group (or the next token), spaces included. Used by
  --- \text, \mathbf and friends, whose argument is not math.
  local function raw_group()
    local open = peek()
    if not is_sym(open, "{") then
      local token = advance()
      return token and token.value or ""
    end
    local depth, position, close = 0, open.pos, nil
    while position <= #tex do
      local char = tex:sub(position, position)
      if char == "\\" then
        position = position + 1
      elseif char == "{" then
        depth = depth + 1
      elseif char == "}" then
        depth = depth - 1
        if depth == 0 then
          close = position
          break
        end
      end
      position = position + 1
    end
    close = close or (#tex + 1)
    while peek() and peek().pos <= close do
      advance()
    end
    return tex:sub(open.pos + 1, close - 1)
  end

  --- A braced group as one element, or the next single atom.
  function parse_group_or_atom()
    local token = peek()
    if is_sym(token, "{") then
      advance()
      local parts = parse_sequence(function(t)
        return is_sym(t, "}")
      end)
      if is_sym(peek(), "}") then
        advance()
      end
      return row(#parts == 0 and { "<mrow></mrow>" } or parts)
    end
    if token == nil then
      return "<mrow></mrow>"
    end
    return (parse_atom())
  end

  local function parse_matrix(name)
    local rows, cells, current = {}, {}, {}
    local function flush_cell()
      table.insert(
        cells,
        "<mtd>" .. row(#current == 0 and { "<mrow></mrow>" } or current) .. "</mtd>"
      )
      current = {}
    end
    local function flush_row()
      flush_cell()
      table.insert(rows, "<mtr>" .. table.concat(cells) .. "</mtr>")
      cells = {}
    end
    if name == "array" and is_sym(peek(), "{") then
      raw_group() -- the column specification
    end
    while peek() do
      local token = peek()
      if is_cmd(token, "end") then
        advance()
        raw_group()
        break
      elseif is_sym(token, "&") then
        advance()
        flush_cell()
      elseif is_cmd(token, "\\") then
        advance()
        flush_row()
      else
        local parts = parse_sequence(function(t)
          return is_sym(t, "&") or is_cmd(t, "\\") or is_cmd(t, "end")
        end)
        for _, part in ipairs(parts) do
          table.insert(current, part)
        end
      end
    end
    if #current > 0 or #cells > 0 then
      flush_row()
    end
    local align = (name == "cases" or name == "aligned" or name == "align" or name == "align*")
        and ' columnalign="left"'
      or ""
    local table_html = "<mtable" .. align .. ">" .. table.concat(rows) .. "</mtable>"
    local fences = ENVIRONMENTS[name]
    if fences[1] ~= "" or fences[2] ~= "" then
      return "<mrow>"
        .. (fences[1] ~= "" and mo(fences[1], ' stretchy="true"') or "")
        .. table_html
        .. (fences[2] ~= "" and mo(fences[2], ' stretchy="true"') or "")
        .. "</mrow>"
    end
    return table_html
  end

  local function command(name)
    if GREEK[name] then
      return mi(GREEK[name])
    elseif GREEK_UPPER[name] then
      return mi(GREEK_UPPER[name], ' mathvariant="normal"')
    elseif LIMIT_OPERATORS[name] then
      return mo(LIMIT_OPERATORS[name], ' largeop="true"'), "limits"
    elseif SIDE_OPERATORS[name] then
      return mo(SIDE_OPERATORS[name], ' largeop="true"')
    elseif LIMIT_WORDS[name] then
      return mi(LIMIT_WORDS[name]), "limits"
    elseif FUNCTION_NAMES[name] then
      return mi(name)
    elseif OPERATORS[name] then
      return mo(OPERATORS[name])
    elseif SPACES[name] then
      return '<mspace width="' .. SPACES[name] .. '"></mspace>'
    elseif name == "frac" or name == "dfrac" or name == "tfrac" or name == "cfrac" then
      local numerator, denominator = parse_group_or_atom(), parse_group_or_atom()
      local fraction = "<mfrac>" .. numerator .. denominator .. "</mfrac>"
      return name == "dfrac" and ('<mstyle displaystyle="true">' .. fraction .. "</mstyle>")
        or fraction
    elseif name == "binom" then
      local top, bottom = parse_group_or_atom(), parse_group_or_atom()
      return "<mrow>"
        .. mo("(", ' stretchy="true"')
        .. '<mfrac linethickness="0">'
        .. top
        .. bottom
        .. "</mfrac>"
        .. mo(")", ' stretchy="true"')
        .. "</mrow>"
    elseif name == "sqrt" then
      local index
      if is_sym(peek(), "[") then
        advance()
        local parts = parse_sequence(function(t)
          return is_sym(t, "]")
        end)
        if is_sym(peek(), "]") then
          advance()
        end
        index = row(#parts == 0 and { "<mrow></mrow>" } or parts)
      end
      local body = parse_group_or_atom()
      if index then
        return "<mroot>" .. body .. index .. "</mroot>"
      end
      return "<msqrt>" .. body .. "</msqrt>"
    elseif ACCENTS[name] then
      return '<mover accent="true">' .. parse_group_or_atom() .. mo(ACCENTS[name]) .. "</mover>"
    elseif UNDER_ACCENTS[name] then
      return "<munder>" .. parse_group_or_atom() .. mo(UNDER_ACCENTS[name]) .. "</munder>"
    elseif OVER_ACCENTS[name] then
      return "<mover>" .. parse_group_or_atom() .. mo(OVER_ACCENTS[name]) .. "</mover>"
    elseif
      name == "text"
      or name == "textrm"
      or name == "mbox"
      or name == "textit"
      or name == "textsf"
    then
      return "<mtext>" .. escape(raw_group()) .. "</mtext>"
    elseif name == "operatorname" then
      return mi(raw_group())
    elseif
      name == "mathrm"
      or name == "rm"
      or name == "mathsf"
      or name == "mathit"
      or name == "mathtt"
    then
      local text = raw_group()
      if #text == 1 then
        return mi(text, ' mathvariant="normal"')
      end
      return mi(text)
    elseif FONT_COMMANDS[name] then
      local style = FONT_COMMANDS[name]
      local text = raw_group()
      return mi((text:gsub(".", function(char)
        return style_char(style, char)
      end)))
    elseif
      name == "left"
      or name == "right"
      or name == "big"
      or name == "Big"
      or name == "bigg"
      or name == "Bigg"
      or name == "bigl"
      or name == "bigr"
      or name == "Bigl"
      or name == "Bigr"
    then
      local token = advance()
      local value = token and token.value or "."
      if token and token.kind == "cmd" then
        value = OPERATORS[value]
          or (value == "{" and "{" or value == "}" and "}" or value == "|" and "‖" or value)
      end
      if value == "." then
        return ""
      end
      return mo(value, ' stretchy="true"')
    elseif name == "begin" then
      local environment = raw_group()
      if ENVIRONMENTS[environment] then
        return parse_matrix(environment)
      end
      return "<mtext>" .. escape("\\begin{" .. environment .. "}") .. "</mtext>"
    elseif
      name == "limits"
      or name == "nolimits"
      or name == "displaystyle"
      or name == "textstyle"
    then
      return ""
    elseif
      name == "{"
      or name == "}"
      or name == "%"
      or name == "&"
      or name == "_"
      or name == "#"
      or name == "$"
    then
      return mo(name)
    elseif name == "|" then
      return mo("‖")
    elseif name == "\\" then
      return '<mspace linebreak="newline"></mspace>'
    end
    -- Unknown command: show it rather than fail.
    return "<mtext>" .. escape("\\" .. name) .. "</mtext>"
  end

  function parse_atom()
    local token = advance()
    if not token then
      return ""
    end
    local kind, value = token.kind, token.value
    if kind == "ident" then
      return mi(value)
    elseif kind == "num" then
      return mn(value)
    elseif kind == "cmd" then
      return command(value)
    elseif value == "{" then
      state.index = state.index - 1
      return parse_group_or_atom()
    elseif value == "'" then
      return mo("′")
    elseif value == "-" then
      return mo("−")
    elseif value == "*" then
      return mo("∗")
    end
    return mo(value)
  end

  local function with_scripts(atom, limits)
    while is_cmd(peek(), "limits") or is_cmd(peek(), "nolimits") do
      advance()
    end
    local sub, sup_parts = nil, {}
    while is_sym(peek(), "_") or is_sym(peek(), "^") or is_sym(peek(), "'") do
      local marker = advance().value
      if marker == "'" then
        table.insert(sup_parts, mo("′"))
      elseif marker == "_" then
        sub = parse_group_or_atom()
      else
        table.insert(sup_parts, parse_group_or_atom())
      end
    end
    local sup = #sup_parts > 0 and row(sup_parts) or nil
    if not sub and not sup then
      return atom
    end
    local tag
    if limits then
      tag = (sub and sup) and "munderover" or (sub and "munder" or "mover")
    else
      tag = (sub and sup) and "msubsup" or (sub and "msub" or "msup")
    end
    return "<" .. tag .. ">" .. atom .. (sub or "") .. (sup or "") .. "</" .. tag .. ">"
  end

  --- Atoms with their sub- and superscripts, until `stop(token)` or the end of input.
  function parse_sequence(stop)
    state.depth = state.depth + 1
    if state.depth > MAX_DEPTH then
      error("math nesting is too deep")
    end
    local parts = {}
    while peek() and not (stop and stop(peek())) do
      local token = peek()
      if is_sym(token, "}") then
        advance() -- a stray closing brace
      elseif is_sym(token, "^") or is_sym(token, "_") then
        table.insert(parts, with_scripts("<mrow></mrow>", false)) -- scripts on an empty base
      else
        local atom, limits
        if token.kind == "cmd" then
          advance()
          atom, limits = command(token.value)
        else
          atom = parse_atom()
        end
        if atom ~= "" then
          table.insert(parts, with_scripts(atom, limits))
        end
      end
    end
    state.depth = state.depth - 1
    return parts
  end

  return {
    parse = function()
      local parts = parse_sequence(nil)
      return table.concat(parts)
    end,
  }
end

--- Translates `tex` to a <math> element. `display` selects block layout. Never raises: a source
--- that cannot be translated comes back as escaped code.
function M.to_mathml(tex, display)
  if type(tex) ~= "string" or #tex > MAX_INPUT then
    return '<code class="math-error">' .. escape(tostring(tex):sub(1, 200)) .. "</code>"
  end
  local ok, body = pcall(function()
    return new_parser(tex, tokenize(tex)).parse()
  end)
  if not ok then
    return '<code class="math-error">' .. escape(tex) .. "</code>"
  end
  return '<math xmlns="'
    .. NAMESPACE
    .. '"'
    .. (display and ' display="block"' or "")
    .. ">"
    .. (body == "" and "<mrow></mrow>" or body)
    .. "</math>"
end

return M
