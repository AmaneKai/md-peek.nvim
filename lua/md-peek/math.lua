--- LaTeX math to native MathML, in plain Lua: browsers draw <math> themselves, so no script or
--- font bundle is needed. Anything unknown degrades to visible text instead of failing.
local M = {}

local MAX_INPUT, MAX_DEPTH = 20000, 40
local ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }

local function esc(text)
  return (text:gsub('[&<>"]', ESCAPES))
end
local function el(tag, body, attrs)
  return "<" .. tag .. (attrs or "") .. ">" .. body .. "</" .. tag .. ">"
end
local function mi(text, attrs)
  return el("mi", esc(text), attrs)
end
local function mo(text, attrs)
  return el("mo", esc(text), attrs)
end
local function row(parts)
  return #parts == 1 and parts[1] or el("mrow", table.concat(parts))
end

--- "name value name value ..." to a lookup table.
local function words(spec)
  local set = {}
  for key, value in spec:gmatch("(%S+)%s+(%S+)") do
    set[key] = value
  end
  return set
end

local GREEK =
  words([[alpha α beta β gamma γ delta δ epsilon ϵ varepsilon ε zeta ζ eta η theta θ
  vartheta ϑ iota ι kappa κ lambda λ mu μ nu ν xi ξ omicron ο pi π varpi ϖ rho ρ varrho ϱ sigma σ
  varsigma ς tau τ upsilon υ phi ϕ varphi φ chi χ psi ψ omega ω]])
local GREEK_UPPER =
  words([[Gamma Γ Delta Δ Theta Θ Lambda Λ Xi Ξ Pi Π Sigma Σ Upsilon Υ Phi Φ
  Psi Ψ Omega Ω]])
local OPERATORS =
  words([[times × cdot ⋅ pm ± mp ∓ div ÷ ast ∗ star ⋆ circ ∘ bullet ∙ oplus ⊕
  ominus ⊖ otimes ⊗ oslash ⊘ odot ⊙ cup ∪ cap ∩ setminus ∖ wedge ∧ land ∧ vee ∨ lor ∨ neg ¬ lnot ¬
  leq ≤ le ≤ geq ≥ ge ≥ neq ≠ ne ≠ approx ≈ equiv ≡ sim ∼ simeq ≃ cong ≅ propto ∝ ll ≪ gg ≫ prec ≺
  succ ≻ in ∈ notin ∉ ni ∋ subset ⊂ supset ⊃ subseteq ⊆ supseteq ⊇ nsubseteq ⊈ emptyset ∅
  varnothing ∅ forall ∀ exists ∃ nexists ∄ nabla ∇ partial ∂ infty ∞ to → rightarrow → leftarrow ←
  gets ← Rightarrow ⇒ Leftarrow ⇐ leftrightarrow ↔ Leftrightarrow ⇔ iff ⟺ implies ⟹ impliedby ⟸
  mapsto ↦ uparrow ↑ downarrow ↓ longrightarrow ⟶ longleftarrow ⟵ dots … ldots … cdots ⋯ vdots ⋮
  ddots ⋱ angle ∠ perp ⊥ parallel ∥ mid ∣ top ⊤ bot ⊥ prime ′ degree ° hbar ℏ ell ℓ Re ℜ Im ℑ
  aleph ℵ wp ℘ langle ⟨ rangle ⟩ lfloor ⌊ rfloor ⌋ lceil ⌈ rceil ⌉ lbrace { rbrace } vert |
  Vert ‖ colon : triangle △ square □ checkmark ✓ therefore ∴ because ∵]])
local LIMIT_OPERATORS = words(
  "sum ∑ prod ∏ coprod ∐ bigcup ⋃ bigcap ⋂ bigoplus ⨁ bigotimes ⨂ bigvee ⋁ bigwedge ⋀"
)
local SIDE_OPERATORS = words("int ∫ iint ∬ iiint ∭ oint ∮")
local LIMIT_WORDS =
  words("lim lim limsup limsup liminf liminf min min max max sup sup inf inf det det gcd gcd Pr Pr")
local ACCENTS =
  words([[hat ^ widehat ^ bar ¯ overline ‾ vec → tilde ˜ widetilde ˜ dot ˙ ddot ¨
  acute ´ grave ` check ˇ breve ˘ overrightarrow →]])
-- stylua: ignore
local SPACES = {
  [","] = "0.1667em", [":"] = "0.2222em", [";"] = "0.2778em", ["!"] = "-0.1667em",
  [" "] = "0.25em", quad = "1em", qquad = "2em",
}
local CANCELS = {
  cancel = "updiagonalstrike",
  bcancel = "downdiagonalstrike",
  xcancel = "updiagonalstrike downdiagonalstrike",
}
local FUNCTIONS = {}
for name in
  ("sin cos tan cot sec csc arcsin arccos arctan sinh cosh tanh coth log ln lg exp deg dim ker hom arg"):gmatch(
    "%S+"
  )
do
  FUNCTIONS[name] = true
end

-- Environments: fences { left, right, column alignment }.
-- stylua: ignore
local ENVIRONMENTS = {
  matrix = { "", "" }, pmatrix = { "(", ")" }, bmatrix = { "[", "]" }, Bmatrix = { "{", "}" },
  vmatrix = { "|", "|" }, Vmatrix = { "‖", "‖" }, array = { "", "" },
  cases = { "{", "", "left" },
  aligned = { "", "", "right left" }, align = { "", "", "right left" },
  ["align*"] = { "", "", "right left" }, split = { "", "", "right left" },
  gather = { "", "" }, ["gather*"] = { "", "" }, gathered = { "", "" },
}

-- Unicode mathematical alphanumerics for \mathbf, \mathbb, \mathcal and \mathfrak: the code
-- points of A, a and 0, and the letters that live elsewhere.
-- stylua: ignore
local STYLES = {
  bf = { 0x1D400, 0x1D41A, 0x1D7CE },
  bb = { 0x1D538, 0x1D552, 0x1D7D8, words("C ℂ H ℍ N ℕ P ℙ Q ℚ R ℝ Z ℤ") },
  cal = { 0x1D49C, 0x1D4B6, nil, words("B ℬ E ℰ F ℱ H ℋ I ℐ L ℒ M ℳ R ℛ e ℯ g ℊ o ℴ") },
  frak = { 0x1D504, 0x1D51E, nil, words("C ℭ H ℌ I ℑ R ℜ Z ℨ") },
}
-- stylua: ignore
local FONTS = {
  mathbf = "bf", boldsymbol = "bf", bm = "bf", textbf = "bf", mathbb = "bb", Bbb = "bb",
  mathcal = "cal", mathscr = "cal", mathfrak = "frak",
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
  local upper, lower, digit, holes = unpack(STYLES[style], 1, 4)
  local byte = char:byte()
  if holes and holes[char] then
    return holes[char]
  elseif char:match("%u") then
    return utf8_char(upper + byte - 65)
  elseif char:match("%l") then
    return utf8_char(lower + byte - 97)
  elseif char:match("%d") and digit then
    return utf8_char(digit + byte - 48)
  end
  return char
end

local function tokenize(tex)
  local tokens, position = {}, 1
  local function push(kind, value)
    table.insert(tokens, { kind = kind, value = value, pos = position })
  end
  while position <= #tex do
    local char = tex:sub(position, position)
    if char:match("%s") then
      position = position + 1
    elseif char == "\\" then
      local name = tex:match("^%a+", position + 1) or tex:sub(position + 1, position + 1)
      push("cmd", name == "" and "\\" or name)
      position = position + 1 + math.max(#name, 1)
    elseif char:match("%d") or tex:match("^%.%d", position) then
      local number = tex:match("^%d*%.?%d+", position) or tex:match("^%d+", position)
      push("num", number)
      position = position + #number
    elseif char:match("%a") then
      push("ident", char)
      position = position + 1
    else
      local byte = char:byte()
      local size = byte >= 240 and 4 or byte >= 224 and 3 or byte >= 192 and 2 or 1
      push("sym", tex:sub(position, position + size - 1))
      position = position + size
    end
  end
  return tokens
end

local function new_parser(tex, tokens)
  local index, depth = 1, 0
  local function peek()
    return tokens[index]
  end
  local function advance()
    index = index + 1
    return tokens[index - 1]
  end
  local function is(token, kind, value)
    return token ~= nil and token.kind == kind and token.value == value
  end
  local parse_sequence, parse_atom, group_or_atom, command

  --- Source text of the next `{...}` group (or token), spaces included: the argument of \text.
  local function raw_group()
    local open = peek()
    if not is(open, "sym", "{") then
      local token = advance()
      return token and token.value or ""
    end
    local level, position, close = 0, open.pos, #tex + 1
    while position <= #tex do
      local char = tex:sub(position, position)
      if char == "\\" then
        position = position + 1
      elseif char == "{" then
        level = level + 1
      elseif char == "}" then
        level = level - 1
        if level == 0 then
          close = position
          break
        end
      end
      position = position + 1
    end
    while peek() and peek().pos <= close do
      advance()
    end
    return tex:sub(open.pos + 1, close - 1)
  end

  local function until_token(kind, value)
    local parts = parse_sequence(function(token)
      return is(token, kind, value)
    end)
    if is(peek(), kind, value) then
      advance()
    end
    return row(#parts == 0 and { "<mrow></mrow>" } or parts)
  end

  function group_or_atom()
    if is(peek(), "sym", "{") then
      advance()
      return until_token("sym", "}")
    end
    return peek() and parse_atom() or "<mrow></mrow>"
  end

  local function environment(name)
    local fences = ENVIRONMENTS[name]
    local rows, cells, current = {}, {}, {}
    local function cell()
      table.insert(cells, el("mtd", row(#current == 0 and { "<mrow></mrow>" } or current)))
      current = {}
    end
    local function finish_row()
      cell()
      table.insert(rows, el("mtr", table.concat(cells)))
      cells = {}
    end
    if name == "array" and is(peek(), "sym", "{") then
      raw_group() -- the column specification
    end
    local function stop(token)
      return is(token, "sym", "&") or is(token, "cmd", "\\") or is(token, "cmd", "end")
    end
    while peek() do
      local token = peek()
      if is(token, "cmd", "end") then
        advance()
        raw_group()
        break
      elseif is(token, "sym", "&") then
        advance()
        cell()
      elseif is(token, "cmd", "\\") then
        advance()
        finish_row()
      else
        vim.list_extend(current, parse_sequence(stop))
      end
    end
    if #current > 0 or #cells > 0 then
      finish_row()
    end
    local align = fences[3] and (' columnalign="' .. fences[3] .. '"') or ""
    local body = el("mtable", table.concat(rows), align)
    if fences[1] == "" and fences[2] == "" then
      return body
    end
    local function fence(char)
      return char ~= "" and mo(char, ' stretchy="true"') or ""
    end
    return el("mrow", fence(fences[1]) .. body .. fence(fences[2]))
  end

  --- One \command. Returns its MathML and whether scripts go above/below it.
  function command(name)
    if GREEK[name] then
      return mi(GREEK[name])
    elseif GREEK_UPPER[name] then
      return mi(GREEK_UPPER[name], ' mathvariant="normal"')
    elseif LIMIT_OPERATORS[name] then
      return mo(LIMIT_OPERATORS[name], ' largeop="true"'), true
    elseif SIDE_OPERATORS[name] then
      return mo(SIDE_OPERATORS[name], ' largeop="true"')
    elseif LIMIT_WORDS[name] then
      return mi(name == "limsup" and "lim sup" or name == "liminf" and "lim inf" or name), true
    elseif FUNCTIONS[name] then
      return mi(name)
    elseif OPERATORS[name] then
      return mo(OPERATORS[name])
    elseif SPACES[name] then
      return '<mspace width="' .. SPACES[name] .. '"></mspace>'
    elseif name == "frac" or name == "dfrac" or name == "tfrac" or name == "cfrac" then
      local fraction = el("mfrac", group_or_atom() .. group_or_atom())
      return name == "dfrac" and el("mstyle", fraction, ' displaystyle="true"') or fraction
    elseif name == "binom" then
      local fraction = el("mfrac", group_or_atom() .. group_or_atom(), ' linethickness="0"')
      return el("mrow", mo("(", ' stretchy="true"') .. fraction .. mo(")", ' stretchy="true"'))
    elseif name == "sqrt" then
      local root
      if is(peek(), "sym", "[") then
        advance()
        root = until_token("sym", "]")
      end
      local body = group_or_atom()
      return root and el("mroot", body .. root) or el("msqrt", body)
    elseif ACCENTS[name] then
      return el("mover", group_or_atom() .. mo(ACCENTS[name]), ' accent="true"')
    elseif name == "underline" then
      return el("munder", group_or_atom() .. mo("_"))
    elseif name == "underbrace" then
      return el("munder", group_or_atom() .. mo("⏟")), true
    elseif name == "overbrace" then
      return el("mover", group_or_atom() .. mo("⏞")), true
    elseif CANCELS[name] then
      return el("menclose", group_or_atom(), ' notation="' .. CANCELS[name] .. '"')
    elseif name:match("^text") or name == "mbox" then
      return el("mtext", esc(raw_group()))
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
      return mi(text, #text == 1 and ' mathvariant="normal"' or nil)
    elseif FONTS[name] then
      return mi((raw_group():gsub(".", function(char)
        return style_char(FONTS[name], char)
      end)))
    elseif name:match("^[bB]ig") or name == "left" or name == "right" then
      local token = advance()
      local value = token and token.value or "."
      if token and token.kind == "cmd" then
        value = OPERATORS[value] or (value == "|" and "‖" or value)
      end
      return value == "." and "" or mo(value, ' stretchy="true"')
    elseif name == "begin" then
      local env = raw_group()
      return ENVIRONMENTS[env] and environment(env) or el("mtext", esc("\\begin{" .. env .. "}"))
    elseif
      name == "limits"
      or name == "nolimits"
      or name == "displaystyle"
      or name == "textstyle"
    then
      return ""
    elseif name:match("^[{}%%&_#$]$") then
      return mo(name)
    elseif name == "|" then
      return mo("‖")
    elseif name == "\\" then
      return '<mspace linebreak="newline"></mspace>'
    end
    return el("mtext", esc("\\" .. name)) -- unknown: show it rather than fail
  end

  function parse_atom()
    local token = advance()
    if not token then
      return ""
    elseif token.kind == "ident" then
      return mi(token.value)
    elseif token.kind == "num" then
      return el("mn", esc(token.value))
    elseif token.kind == "cmd" then
      return (command(token.value))
    elseif token.value == "{" then
      index = index - 1
      return group_or_atom()
    end
    return mo(({ ["'"] = "′", ["-"] = "−", ["*"] = "∗" })[token.value] or token.value)
  end

  local function with_scripts(atom, limits)
    while is(peek(), "cmd", "limits") or is(peek(), "cmd", "nolimits") do
      advance()
    end
    local sub, sup = nil, {}
    while is(peek(), "sym", "_") or is(peek(), "sym", "^") or is(peek(), "sym", "'") do
      local marker = advance().value
      if marker == "_" then
        sub = group_or_atom()
      else
        table.insert(sup, marker == "'" and mo("′") or group_or_atom())
      end
    end
    sup = #sup > 0 and row(sup) or nil
    if not sub and not sup then
      return atom
    end
    local tag = limits and ((sub and sup) and "munderover" or (sub and "munder" or "mover"))
      or ((sub and sup) and "msubsup" or (sub and "msub" or "msup"))
    return el(tag, atom .. (sub or "") .. (sup or ""))
  end

  --- Atoms with their scripts, until `stop(token)` or the end of input.
  function parse_sequence(stop)
    depth = depth + 1
    if depth > MAX_DEPTH then
      error("math nesting is too deep")
    end
    local parts = {}
    while peek() and not (stop and stop(peek())) do
      local token = peek()
      if is(token, "sym", "}") then
        advance() -- a stray closing brace
      elseif is(token, "sym", "^") or is(token, "sym", "_") then
        table.insert(parts, with_scripts("<mrow></mrow>", false)) -- scripts with no base
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
    depth = depth - 1
    return parts
  end

  return function()
    return table.concat(parse_sequence(nil))
  end
end

--- Translates `tex` to a <math> element; `display` selects block layout. Never raises: a source
--- that cannot be translated comes back as escaped code.
function M.to_mathml(tex, display)
  if type(tex) ~= "string" or #tex > MAX_INPUT then
    return '<code class="math-error">' .. esc(tostring(tex):sub(1, 200)) .. "</code>"
  end
  local ok, body = pcall(function()
    return new_parser(tex, tokenize(tex))()
  end)
  if not ok then
    return '<code class="math-error">' .. esc(tex) .. "</code>"
  end
  return '<math xmlns="http://www.w3.org/1998/Math/MathML"'
    .. (display and ' display="block"' or "")
    .. ">"
    .. (body == "" and "<mrow></mrow>" or body)
    .. "</math>"
end

return M
