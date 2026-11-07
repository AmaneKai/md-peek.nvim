--- A GitHub-flavoured Markdown to HTML compiler in plain Lua. Every block carries the 1-based
--- `data-source-line` of the line it starts on, which the preview uses to sync scroll and clicks.
local highlight = require("md-peek.highlight")
local latex = require("md-peek.math")

local M = {}

local ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }

local function escape(text)
  return (text:gsub('[&<>"]', ESCAPES))
end

--- Escapes text but keeps entities such as `&amp;` and `&#169;` as the author wrote them.
local function escape_text(text)
  text = text:gsub("&", function()
    return "&amp;"
  end)
  text = text:gsub("&amp;(#?%w+;)", "&%1")
  return (text:gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local ENTITIES =
  { ["&lt;"] = "<", ["&gt;"] = ">", ["&quot;"] = '"', ["&#39;"] = "'", ["&amp;"] = "&" }

local function unescape(text)
  return (text:gsub("&#?%w+;", ENTITIES))
end

-- stylua: ignore
local EMOJI = {
  rocket = "🚀", warning = "⚠️", check = "✅", white_check_mark = "✅", x = "❌", sparkles = "✨",
  bug = "🐛", fire = "🔥", thumbsup = "👍", ["+1"] = "👍", tada = "🎉", bulb = "💡", memo = "📝",
  heart = "❤️", star = "⭐", eyes = "👀", wave = "👋", thinking = "🤔", ["100"] = "💯",
}

-- stylua: ignore
local ALERTS = {
  NOTE = "Note", TIP = "Tip", IMPORTANT = "Important", WARNING = "Warning", CAUTION = "Caution",
}

local BLOCK_TAGS = {}
for tag in
  ([[address article aside blockquote center details dialog dd div dl dt fieldset figcaption
  figure footer h1 h2 h3 h4 h5 h6 header hr li main nav ol p picture pre section summary table tbody
  td tfoot th thead tr ul]]):gmatch("%S+")
do
  BLOCK_TAGS[tag] = true
end
--- GitHub-style anchor for already-rendered heading HTML.
local function slugify(html)
  local plain = unescape((html:gsub("<[^>]*>", "")))
  local lowered = vim.fn.tolower(plain):gsub("[^%w%s%-_\128-\255]", "")
  return (vim.trim(lowered):gsub("%s", "-"))
end

local function percent_encode(text)
  return (
    text:gsub("[^%w%-._~/]", function(char)
      return string.format("%%%02X", char:byte())
    end)
  )
end

--- Raw HTML is handed to the browser, which parses and sanitizes it (see page.lua); with
--- `allow_html = false` it is shown as text instead.
local function raw_html(ctx, html)
  return ctx.config.allow_html == false and escape(html) or html
end

---------------------------------------------------------------------------------------------
-- Inline

local inline

local function parse_destination(s, pos)
  -- s:sub(pos, pos) is the character right after "(". Returns dest, title, position after ")".
  local _, after_space = s:find("^%s*", pos)
  pos = after_space + 1
  local dest
  if s:sub(pos, pos) == "<" then
    local close = s:find(">", pos + 1, true)
    if not close then
      return nil
    end
    dest = s:sub(pos + 1, close - 1)
    pos = close + 1
  else
    local depth, start = 0, pos
    while pos <= #s do
      local char = s:sub(pos, pos)
      if char:match("%s") then
        break
      elseif char == "(" then
        depth = depth + 1
      elseif char == ")" then
        if depth == 0 then
          break
        end
        depth = depth - 1
      end
      pos = pos + 1
    end
    dest = s:sub(start, pos - 1)
  end
  local _, after = s:find("^%s*", pos)
  pos = after + 1
  local title
  local quote = s:sub(pos, pos)
  if quote == '"' or quote == "'" or quote == "(" then
    local closer = quote == "(" and ")" or quote
    local close = s:find(closer, pos + 1, true)
    if not close then
      return nil
    end
    title = s:sub(pos + 1, close - 1)
    local _, trailing = s:find("^%s*", close + 1)
    pos = trailing + 1
  end
  if s:sub(pos, pos) ~= ")" then
    return nil
  end
  return dest, title, pos + 1
end

local function link_html(_, dest, title, inner_html)
  local title_attr = title and title ~= "" and (' title="' .. escape(title) .. '"') or ""
  return '<a href="' .. escape(dest) .. '"' .. title_attr .. ">" .. inner_html .. "</a>"
end

local function image_html(_, dest, title, alt)
  local title_attr = title and title ~= "" and (' title="' .. escape(title) .. '"') or ""
  return '<img src="' .. escape(dest) .. '" alt="' .. escape(alt) .. '"' .. title_attr .. ">"
end

local function strip_tags(html)
  return unescape((html:gsub("<[^>]*>", "")))
end

local function normalize_label(label)
  return (vim.trim(label):gsub("%s+", " "):lower())
end

--- `[label]: destination "title"` -> label, destination, title (or nil).
local function parse_definition(line)
  local label, rest = line:match("^ ? ? ?%[([^%]^][^%]]*)%]:%s*(.-)%s*$")
  if not label or rest == "" then
    return nil
  end
  local dest, tail = rest:match("^<([^>]*)>%s*(.*)$")
  if not dest then
    dest, tail = rest:match("^(%S+)%s*(.*)$")
  end
  local title = tail:match('^"(.*)"$') or tail:match("^'(.*)'$") or tail:match("^%((.*)%)$")
  return label, unescape(dest), title
end

--- Finds the `$` that closes an inline `$...$` opened at `start`, or nil. Like pandoc, the opener
--- must be followed by non-space and the closer preceded by non-space and not followed by a
--- digit, so prose such as "costs $5 or $10" is left alone.
local function closing_dollar(text, start)
  local after = text:sub(start + 1, start + 1)
  if after == "" or after:match("%s") then
    return nil
  end
  local search = start + 2
  while true do
    local close = text:find("$", search, true)
    if not close then
      return nil
    end
    local before, following = text:sub(close - 1, close - 1), text:sub(close + 1, close + 1)
    if before ~= "\\" then
      if not before:match("%s") and not following:match("%d") then
        return close
      end
      return nil -- a bare `$` inside would end the span; this opener was just a currency sign
    end
    search = close + 1
  end
end

--- Replaces `$..$`, `$$..$$`, `\(..\)` and `\[..\]` with held MathML.
local function extract_math(text, hold)
  local out, position = {}, 1
  while true do
    local start = text:find("[$\\]", position)
    if not start then
      table.insert(out, text:sub(position))
      break
    end
    local char, following = text:sub(start, start), text:sub(start + 1, start + 1)
    local close, tex, display, length
    if char == "\\" then
      if following == "(" or following == "[" then
        local closer = following == "(" and "\\)" or "\\]"
        close = text:find(closer, start + 2, true)
        tex, display, length = close and text:sub(start + 2, close - 1), following == "[", 2
      end
    elseif following == "$" then
      close = text:find("$$", start + 2, true)
      tex, display, length = close and text:sub(start + 2, close - 1), true, 2
    else
      close = closing_dollar(text, start)
      tex, display, length = close and text:sub(start + 1, close - 1), false, 1
    end
    if close and tex and tex:match("%S") then
      table.insert(out, text:sub(position, start - 1))
      table.insert(out, hold(latex.to_mathml(tex, display)))
      position = close + length
    else
      -- Not math: keep the character (and a backslash's partner) as ordinary text.
      local keep = (char == "\\" or following == "$") and 2 or 1
      table.insert(out, text:sub(position, start + keep - 1))
      position = start + keep
    end
  end
  return table.concat(out)
end

function inline(ctx, text, nested_link, store)
  if not store then
    text = text:gsub("[\1\2]", "")
  end
  store = store or {}
  local function hold(html)
    table.insert(store, html)
    return "\1" .. #store .. "\2"
  end

  -- 1. Code spans, whose content is never parsed again.
  local pieces, pos = {}, 1
  while pos <= #text do
    local open_start, open_end = text:find("`+", pos)
    if not open_start then
      table.insert(pieces, text:sub(pos))
      break
    end
    local length = open_end - open_start + 1
    local search = open_end + 1
    local close_start, close_end
    while true do
      local s, e = text:find("`+", search)
      if not s then
        break
      end
      if e - s + 1 == length then
        close_start, close_end = s, e
        break
      end
      search = e + 1
    end
    if close_start then
      table.insert(pieces, text:sub(pos, open_start - 1))
      local code = text:sub(open_end + 1, close_start - 1):gsub("\n", " ")
      if code:match("^ .* $") and code:match("[^ ]") then
        code = code:sub(2, -2)
      end
      table.insert(pieces, hold("<code>" .. escape(code) .. "</code>"))
      pos = close_end + 1
    else
      table.insert(pieces, text:sub(pos, open_end))
      pos = open_end + 1
    end
  end
  text = table.concat(pieces)

  if ctx.config.math ~= false and text:find("[$\\]") then
    text = extract_math(text, hold)
  end

  -- 2. Hard breaks and backslash escapes.
  text = text:gsub("  +\n", function()
    return hold("<br>") .. "\n"
  end)
  text = text:gsub("\\\n", function()
    return hold("<br>") .. "\n"
  end)
  text = text:gsub("\\([!-/:-@%[-`{-~])", function(char)
    return hold(escape(char))
  end)

  -- 3. <autolinks> and raw HTML.
  text = text:gsub("<(%a[%w+.-]*:[^%s<>]*)>", function(url)
    return hold(link_html(ctx, url, nil, escape(url)))
  end)
  text = text:gsub("<([%w._%%+-]+@[%w.-]+%.%a+)>", function(address)
    return hold('<a href="mailto:' .. escape(address) .. '">' .. escape(address) .. "</a>")
  end)
  text = text:gsub("<!%-%-.-%-%->", function()
    return hold("")
  end)
  text = text:gsub("</?[%a][%w:-]*[^<>]*>", function(tag)
    return hold(raw_html(ctx, tag))
  end)

  -- 4. Images, links, footnote references and reference links.
  local out, cursor = {}, 1
  while true do
    local open = text:find("[", cursor, true)
    if not open then
      table.insert(out, text:sub(cursor))
      break
    end
    local is_image = open > cursor and text:sub(open - 1, open - 1) == "!"
    local label = text:match("^%b[]", open)
    local handled = false
    if label then
      local inner = label:sub(2, -2)
      local after = open + #label
      local replacement, resume
      local footnote = inner:match("^%^([^%s%]]+)$")
      if footnote and ctx.footnote_ids[footnote] and not is_image then
        ctx.impure = true
        local index = ctx.footnote_order[footnote]
        if not index then
          table.insert(ctx.footnote_list, footnote)
          index = #ctx.footnote_list
          ctx.footnote_order[footnote] = index
        end
        local id = percent_encode(footnote)
        replacement = hold(
          '<sup class="footnote-ref"><a href="#fn-'
            .. id
            .. '" id="fnref-'
            .. id
            .. '">'
            .. index
            .. "</a></sup>"
        )
        resume = after
      elseif text:sub(after, after) == "(" then
        local dest, title, finish = parse_destination(text, after + 1)
        if dest then
          dest = unescape(dest)
          title = title and unescape(title)
          if is_image then
            replacement =
              hold(image_html(ctx, dest, title, strip_tags(inline(ctx, inner, true, store))))
          elseif not nested_link then
            replacement = hold(link_html(ctx, dest, title, inline(ctx, inner, true, store)))
          end
          resume = finish
        end
      end
      if not replacement then
        local ref_label, ref_end
        local explicit = text:match("^%[([^%]]*)%]", after)
        if explicit then
          ref_label = explicit ~= "" and explicit or inner
          ref_end = after + #explicit + 2
        else
          ref_label, ref_end = inner, after
        end
        local definition = ctx.definitions[normalize_label(ref_label)]
        if definition and not footnote then
          if is_image then
            replacement = hold(
              image_html(
                ctx,
                definition.dest,
                definition.title,
                strip_tags(inline(ctx, inner, true, store))
              )
            )
          elseif not nested_link then
            replacement = hold(
              link_html(ctx, definition.dest, definition.title, inline(ctx, inner, true, store))
            )
          end
          resume = ref_end
        end
      end
      if replacement then
        local start = is_image and open - 1 or open
        table.insert(out, text:sub(cursor, start - 1))
        table.insert(out, replacement)
        cursor = resume
        handled = true
      end
    end
    if not handled then
      table.insert(out, text:sub(cursor, open))
      cursor = open + 1
    end
  end
  text = table.concat(out)

  -- 5. Bare URLs.
  if ctx.config.linkify ~= false and not nested_link then
    text = text:gsub("(%f[%w]https?://[^%s<>\1\2]+)", function(url)
      local trail = ""
      while true do
        local last = url:sub(-1)
        if last:match("[.,;:!?'\"]") then
          trail = last .. trail
          url = url:sub(1, -2)
        elseif last == ")" then
          local _, opens = url:gsub("%(", "")
          local _, closes = url:gsub("%)", "")
          if closes > opens then
            trail = last .. trail
            url = url:sub(1, -2)
          else
            break
          end
        else
          break
        end
      end
      if url:match("^https?://[^/]+") == nil or url:match("^https?://$") then
        return nil
      end
      return hold(link_html(ctx, url, nil, escape(url))) .. trail
    end)
  end

  -- 6. Plain text: escaping, emphasis, strikethrough, emoji, typography.
  text = escape_text(text)
  local function bounded(delimiter_pattern, tag_open, tag_close)
    return function(source)
      return (
        source:gsub(delimiter_pattern, function(content)
          if content:match("^%s") or content:match("%s$") or content == "" then
            return nil
          end
          return tag_open .. content .. tag_close
        end)
      )
    end
  end
  text = bounded("%*%*%*(.-)%*%*%*", "<strong><em>", "</em></strong>")(text)
  text = bounded("%*%*(.-)%*%*", "<strong>", "</strong>")(text)
  text = bounded("~~(.-)~~", "<del>", "</del>")(text)
  text = text:gsub("%f[%w_]___(.-)___%f[^%w_]", function(content)
    return "<strong><em>" .. content .. "</em></strong>"
  end)
  text = text:gsub("%f[%w_]__([^%s_].-)__%f[^%w_]", function(content)
    if content:match("%s$") then
      return nil
    end
    return "<strong>" .. content .. "</strong>"
  end)
  text = bounded("%*([^%s*][^*]-)%*", "<em>", "</em>")(text)
  text = text:gsub("%f[%w_]_([^%s_].-)_%f[^%w_]", function(content)
    if content:match("%s$") then
      return nil
    end
    return "<em>" .. content .. "</em>"
  end)

  if ctx.config.emoji ~= false then
    text = text:gsub(":([%w_+]+):", function(name)
      return EMOJI[name]
    end)
  end
  if ctx.config.typographer == true then
    text = text:gsub("%-%-%-", "—"):gsub("%-%-", "–"):gsub("%.%.%.", "…")
  end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if ctx.config.breaks == true then
    text = text:gsub("\n", "<br>\n")
  end

  for _ = 1, 3 do
    local replaced = false
    text = text:gsub("\1(%d+)\2", function(index)
      replaced = true
      return store[tonumber(index)]
    end)
    if not replaced then
      break
    end
  end
  return text
end

---------------------------------------------------------------------------------------------
-- Blocks. An "entry" is { text, n } where n is the line number in the original document.

local compile_blocks

local function indent_of(line)
  return #line:match("^ *")
end

--- Expands tabs to 4-column tab stops.
local function expand_tabs(line)
  if not line:find("\t", 1, true) then
    return line
  end
  local out, column = {}, 0
  for char in line:gmatch("[\1-\127\194-\244][\128-\191]*") do
    if char == "\t" then
      local width = 4 - column % 4
      table.insert(out, string.rep(" ", width))
      column = column + width
    else
      table.insert(out, char)
      column = column + 1
    end
  end
  return table.concat(out)
end

local function is_blank(line)
  return line:match("^%s*$") ~= nil
end

local function fence_open(line)
  local indent, marker, info = line:match("^( *)(```+)%s*([^`]*)$")
  if not marker then
    indent, marker, info = line:match("^( *)(~~~+)%s*(.*)$")
  end
  if marker and #indent <= 3 then
    return #indent, marker, vim.trim(info)
  end
end

local function is_hr(line)
  if indent_of(line) > 3 then
    return false
  end
  local compact = line:gsub("%s", "")
  return #compact >= 3
    and (compact:match("^%-+$") or compact:match("^%*+$") or compact:match("^_+$")) ~= nil
end

local function atx(line)
  local hashes, rest = line:match("^ ? ? ?(#+)(.*)$")
  if not hashes or #hashes > 6 then
    return nil
  end
  if rest ~= "" and not rest:match("^%s") then
    return nil
  end
  rest = vim.trim(rest):gsub("%s+#+$", ""):gsub("^#+$", "")
  return #hashes, vim.trim(rest)
end

local function list_marker(line)
  local indent, bullet, rest = line:match("^( *)([-*+])(%s.*)$")
  if not bullet then
    indent, bullet = line:match("^( *)([-*+])$")
    rest = ""
  end
  if bullet then
    return { indent = #indent, kind = bullet, width = 1, rest = rest, number = nil }
  end
  local number, delimiter
  indent, number, delimiter, rest = line:match("^( *)(%d%d?%d?%d?%d?%d?%d?%d?%d?)([.)])(%s.*)$")
  if not number then
    indent, number, delimiter = line:match("^( *)(%d%d?%d?%d?%d?%d?%d?%d?%d?)([.)])$")
    rest = ""
  end
  if number then
    return {
      indent = #indent,
      kind = delimiter,
      width = #number + 1,
      rest = rest,
      number = tonumber(number),
    }
  end
end

local function html_block_start(line)
  if indent_of(line) > 3 then
    return nil
  end
  if line:match("^ *<!%-%-") then
    return "comment"
  end
  local closing, name = line:match("^ *<(/?)([%a][%w-]*)")
  if name and BLOCK_TAGS[name:lower()] then
    return "block"
  end
end

--- True when `line` starts a block that may interrupt a paragraph.
local function interrupts_paragraph(line)
  if fence_open(line) or atx(line) or is_hr(line) then
    return true
  end
  if line:match("^ ? ? ?>") then
    return true
  end
  local marker = list_marker(line)
  if marker and marker.rest ~= "" and (marker.number == nil or marker.number == 1) then
    return true
  end
  return html_block_start(line) == "block"
end

local function split_row(line)
  local trimmed = vim.trim(line):gsub("^|", ""):gsub("([^\\])|$", "%1")
  if trimmed == "|" then
    trimmed = ""
  end
  local cells, current, index = {}, {}, 1
  while index <= #trimmed do
    local char = trimmed:sub(index, index)
    if char == "\\" and trimmed:sub(index + 1, index + 1) == "|" then
      table.insert(current, "|")
      index = index + 2
    elseif char == "|" then
      table.insert(cells, vim.trim(table.concat(current)))
      current = {}
      index = index + 1
    else
      table.insert(current, char)
      index = index + 1
    end
  end
  table.insert(cells, vim.trim(table.concat(current)))
  return cells
end

local function table_alignments(line, columns)
  if not line:find("-", 1, true) or not line:match("^[%s|:%-]+$") or indent_of(line) > 3 then
    return nil
  end
  local cells = split_row(line)
  if #cells ~= columns then
    return nil
  end
  local aligns = {}
  for _, cell in ipairs(cells) do
    local left, right = cell:match("^(:?)%-+(:?)$")
    if not left then
      return nil
    end
    table.insert(
      aligns,
      (left == ":" and right == ":") and "center"
        or (left == ":" and "left")
        or (right == ":" and "right")
        or false
    )
  end
  return aligns
end

local function render_paragraph(ctx, lines, line_number, tight)
  local html = inline(ctx, table.concat(lines, "\n"))
  if tight then
    return html
  end
  return '<p data-source-line="' .. line_number .. '">' .. html .. "</p>"
end

local function heading_html(ctx, level, text, line_number)
  local html = inline(ctx, text)
  ctx.impure = true -- slugs are numbered per document, so a heading's output depends on the rest
  local plain = vim.trim(strip_tags(html))
  local base = slugify(html)
  if base == "" then
    base = "section"
  end
  local count = ctx.used_slugs[base] or 0
  ctx.used_slugs[base] = count + 1
  local id = count > 0 and (base .. "-" .. count) or base
  if level == 1 and not ctx.title then
    ctx.title = plain
  end
  return string.format(
    '<h%d id="%s" data-source-line="%d">%s</h%d>',
    level,
    escape(id),
    line_number,
    html,
    level
  )
end

local function code_block_html(_, lang, code_lines, line_number)
  local code = table.concat(code_lines, "\n")
  local name = (lang:match("^[^%s{]+") or ""):lower()
  if name == "mermaid" or name == "mmd" then
    return '<pre class="mermaid" data-source-line="'
      .. line_number
      .. '">'
      .. escape(code)
      .. "</pre>"
  end
  local class = "hljs" .. (name ~= "" and (" language-" .. escape(name)) or "")
  return '<div class="code-block" data-source-line="'
    .. line_number
    .. '"><pre><code class="'
    .. class
    .. '">'
    .. highlight.highlight(code, name)
    .. "</code></pre></div>"
end

local function html_block(ctx, entries, i, kind)
  local lines = {}
  local j = i
  if kind == "comment" then
    while j <= #entries do
      table.insert(lines, entries[j].text)
      if entries[j].text:find("-->", 1, true) then
        j = j + 1
        break
      end
      j = j + 1
    end
    return "", j
  end
  while j <= #entries and not is_blank(entries[j].text) do
    table.insert(lines, entries[j].text)
    j = j + 1
  end
  local raw = table.concat(lines, "\n")
  if ctx.config.allow_html == false then
    return '<p data-source-line="' .. entries[i].n .. '">' .. escape(raw) .. "</p>", j
  end
  return raw_html(ctx, raw), j
end

--- A display-math block (`$$ ... $$` or `\[ ... \]`) that starts at entry `i` and owns its
--- lines. Returns the LaTeX source and the next entry index, or nil.
local function math_extent(entries, i)
  local closer = "$$"
  local opener, rest = entries[i].text:match("^ ? ? ?(%$%$)(.*)$")
  if not opener then
    opener, rest = entries[i].text:match("^ ? ? ?(\\%[)(.*)$")
    closer = "\\]"
  end
  if not opener then
    return nil
  end
  local close = rest:find(closer, 1, true)
  if close then
    if rest:sub(close + #closer):match("%S") or not rest:sub(1, close - 1):match("%S") then
      return nil
    end
    return rest:sub(1, close - 1), i + 1
  end
  local parts = { rest }
  for j = i + 1, #entries do
    local text = entries[j].text
    local found = text:find(closer, 1, true)
    if found then
      if text:sub(found + #closer):match("%S") then
        return nil
      end
      table.insert(parts, text:sub(1, found - 1))
      return table.concat(parts, "\n"), j + 1
    end
    table.insert(parts, text)
  end
  return nil
end

--- The attributes of a `<details ...>` tag that opens `line`, or nil.
local function details_open_tag(line)
  local attrs = line:match("^%s*<[dD][eE][tT][aA][iI][lL][sS]([^>]*)>")
  return attrs
    and { open = attrs:lower():find("%f[%w]open%f[%W]") ~= nil, rest = #line:match("^%s*<[^>]*>") }
end

--- A `<details>` element whose body is Markdown. Returns html and the next entry index, or nil
--- when the line does not open a well-formed `<details>` tag.
local function details_block(ctx, entries, i)
  local first = entries[i].text
  local tag = details_open_tag(first)
  local is_open = tag.open

  local inner, depth = {}, 1
  local fence_char, fence_length
  local function feed(text, n)
    if fence_char then
      local closing = text:match("^ *([`~]+)%s*$")
      if closing and closing:sub(1, 1) == fence_char and #closing >= fence_length then
        fence_char = nil
      end
      table.insert(inner, { text = text, n = n })
      return false
    end
    local _, marker = fence_open(text)
    if marker then
      fence_char, fence_length = marker:sub(1, 1), #marker
      table.insert(inner, { text = text, n = n })
      return false
    end
    local lowered = text:lower()
    local opens, closes, last_close = 0, 0, nil
    for _ in lowered:gmatch("<details[%s>]") do
      opens = opens + 1
    end
    for position in lowered:gmatch("()</details%s*>") do
      closes = closes + 1
      last_close = position
    end
    if depth + opens - closes <= 0 and last_close then
      local before = text:sub(1, last_close - 1)
      if before:match("%S") then
        table.insert(inner, { text = before, n = n })
      end
      depth = 0
      return true
    end
    depth = depth + opens - closes
    table.insert(inner, { text = text, n = n })
    return false
  end

  local j = i
  local closed = feed(first:sub(tag.rest + 1), entries[i].n)
  while not closed and j < #entries do
    j = j + 1
    closed = feed(entries[j].text, entries[j].n)
  end

  -- An optional leading <summary> holds inline Markdown.
  local summary
  for index, entry in ipairs(inner) do
    if entry.text:match("%S") then
      local text = entry.text
      local body, rest = text:match("^%s*<[sS]ummary[^>]*>(.-)</[sS]ummary>%s*(.*)$")
      local consumed = 1
      if not body then
        local start = text:match("^%s*<[sS]ummary[^>]*>(.*)$")
        if start then
          local parts = { start }
          for k = index + 1, #inner do
            local before, after = inner[k].text:match("^(.-)</[sS]ummary>%s*(.*)$")
            if before then
              table.insert(parts, before)
              body, rest = table.concat(parts, " "), after
              consumed = k - index + 1
              break
            end
            table.insert(parts, inner[k].text)
          end
        end
      end
      if body then
        summary = body
        for _ = 1, consumed do
          table.remove(inner, index)
        end
        if rest ~= "" then
          table.insert(inner, index, { text = rest, n = entry.n })
        end
      end
      break
    end
  end

  local html = "<details"
    .. (is_open and " open" or "")
    .. ' data-source-line="'
    .. entries[i].n
    .. '">'
  if summary then
    html = html .. "<summary>" .. inline(ctx, vim.trim(summary)) .. "</summary>"
  end
  html = html .. "\n" .. compile_blocks(ctx, inner, false) .. "\n</details>"
  return html, j + 1
end

local function parse_list(ctx, entries, i, tight_parent)
  local first = list_marker(entries[i].text)
  local items, loose = {}, false
  local j = i
  local ordered = first.number ~= nil
  while j <= #entries do
    local marker = list_marker(entries[j].text)
    if not marker then
      break
    end
    local rest = marker.rest
    local spaces = #rest:match("^%s*")
    if spaces > 4 or rest:match("^%s*$") then
      spaces = 1
    end
    local width = marker.indent + marker.width + spaces
    local content = rest:sub(spaces + 1)
    local item = { { content, entries[j].n } }
    local item_start = j
    j = j + 1
    local blank_before = false
    while j <= #entries do
      local text = entries[j].text
      if is_blank(text) then
        -- A blank line stays in the item only when indented content follows.
        local k = j
        while k <= #entries and is_blank(entries[k].text) do
          k = k + 1
        end
        if k <= #entries and indent_of(entries[k].text) >= width then
          for _ = j, k - 1 do
            table.insert(item, { "", entries[j].n })
          end
          blank_before = true
          j = k
        else
          break
        end
      elseif indent_of(text) >= width then
        table.insert(item, { text:sub(width + 1), entries[j].n })
        j = j + 1
      elseif
        list_marker(text)
        and not blank_before
        and indent_of(text) >= marker.indent + 2
        and not is_hr(text)
      then
        -- Indented under the item but short of its content column (`1. a` / `  - b`): nest it.
        table.insert(item, { (text:gsub("^ +", "")), entries[j].n })
        j = j + 1
      else
        local last = item[#item]
        local lazy = last
          and last[1] ~= ""
          and not list_marker(text)
          and not interrupts_paragraph(text)
          and not blank_before
        if lazy then
          table.insert(item, { vim.trim(text), entries[j].n })
          j = j + 1
        else
          break
        end
      end
    end
    -- trailing blank entries are not part of the item
    while #item > 1 and item[#item][1] == "" do
      table.remove(item)
    end
    local between = false
    local k = j
    while k <= #entries and is_blank(entries[k].text) do
      k = k + 1
      between = true
    end
    local following = k <= #entries and list_marker(entries[k].text)
    local continues = following
      and following.kind == first.kind
      and following.indent < width
      and not is_hr(entries[k].text)
    if blank_before and #item > 1 then
      for index = 2, #item do
        if item[index][1] == "" and index < #item then
          loose = true
        end
      end
    end
    table.insert(items, { entries = item, line = entries[item_start].n })
    if continues then
      if between then
        loose = true
      end
      j = k
    else
      break
    end
  end

  local tight = not loose
  local html = {}
  for _, item in ipairs(items) do
    local checked
    local task = false
    local text = item.entries[1][1]
    local mark, remainder = text:match("^%[([ xX])%]%s+(.*)$")
    if not mark then
      mark = text:match("^%[([ xX])%]$")
      remainder = mark and ""
    end
    if mark then
      task = true
      checked = mark ~= " "
      item.entries[1][1] = remainder
    end
    local ents = {}
    for _, e in ipairs(item.entries) do
      table.insert(ents, { text = e[1], n = e[2] })
    end
    local inner = compile_blocks(ctx, ents, tight)
    local open
    if task then
      open = '<li class="task-list-item" data-source-line="'
        .. item.line
        .. '"><input type="checkbox" class="task-list-item-checkbox" data-line="'
        .. item.line
        .. '"'
        .. (checked and " checked" or "")
        .. "> "
    else
      open = '<li data-source-line="' .. item.line .. '">'
    end
    table.insert(html, open .. inner .. "</li>")
  end
  local tag = ordered and "ol" or "ul"
  local attrs = ' data-source-line="' .. items[1].line .. '"'
  if ordered and first.number ~= 1 then
    attrs = attrs .. ' start="' .. first.number .. '"'
  end
  if not ordered and html[1] and html[1]:find("task-list-item", 1, true) then
    attrs = attrs .. ' class="contains-task-list"'
  end
  return "<" .. tag .. attrs .. ">\n" .. table.concat(html, "\n") .. "\n</" .. tag .. ">", j
end

function compile_blocks(ctx, entries, tight)
  local out = {}
  local i = 1
  local count = #entries
  while i <= count do
    local entry = entries[i]
    local line = entry.text
    local n = entry.n

    if is_blank(line) then
      i = i + 1
    elseif indent_of(line) <= 3 and fence_open(line) then
      local indent, marker, info = fence_open(line)
      local char, length = marker:sub(1, 1), #marker
      local code = {}
      local j = i + 1
      while j <= count do
        local text = entries[j].text
        local closing = text:match("^ ? ? ?(" .. (char == "`" and "`" or "~") .. "+)%s*$")
        if closing and #closing >= length then
          j = j + 1
          break
        end
        local strip = math.min(indent, indent_of(text))
        table.insert(code, text:sub(strip + 1))
        j = j + 1
      end
      table.insert(out, code_block_html(ctx, info, code, n))
      i = j
    elseif atx(line) then
      local level, text = atx(line)
      table.insert(out, heading_html(ctx, level, text, n))
      i = i + 1
    elseif is_hr(line) then
      table.insert(out, '<hr data-source-line="' .. n .. '">')
      i = i + 1
    elseif ctx.config.math ~= false and math_extent(entries, i) then
      local tex, j = math_extent(entries, i)
      table.insert(
        out,
        '<div class="math-display" data-source-line="'
          .. n
          .. '">'
          .. latex.to_mathml(tex, true)
          .. "</div>"
      )
      i = j
    elseif line:match("^ ? ? ?>") then
      local quote, j = {}, i
      while j <= count do
        local text = entries[j].text
        if text:match("^ ? ? ?>") then
          table.insert(quote, { text = text:gsub("^ ? ? ?> ?", "", 1), n = entries[j].n })
        elseif
          not is_blank(text)
          and #quote > 0
          and not is_blank(quote[#quote].text)
          and not interrupts_paragraph(text)
        then
          table.insert(quote, { text = text, n = entries[j].n })
        else
          break
        end
        j = j + 1
      end
      local kind = quote[1].text:match("^%[!(%a+)%]%s*$")
      kind = kind and kind:upper()
      if kind and ALERTS[kind] then
        table.remove(quote, 1)
        table.insert(
          out,
          '<div class="alert alert-'
            .. kind:lower()
            .. '" data-source-line="'
            .. n
            .. '"><p class="alert-title">'
            .. ALERTS[kind]
            .. "</p>\n"
            .. compile_blocks(ctx, quote, false)
            .. "\n</div>"
        )
      else
        table.insert(
          out,
          '<blockquote data-source-line="'
            .. n
            .. '">\n'
            .. compile_blocks(ctx, quote, false)
            .. "\n</blockquote>"
        )
      end
      i = j
    elseif list_marker(line) and not is_hr(line) then
      local html, j = parse_list(ctx, entries, i, tight)
      table.insert(out, html)
      i = j
    elseif details_open_tag(line) then
      local html, j = details_block(ctx, entries, i)
      table.insert(out, html)
      i = j
    elseif html_block_start(line) then
      local html, j = html_block(ctx, entries, i, html_block_start(line))
      if html ~= "" then
        table.insert(out, html)
      end
      i = j
    elseif line:match("^ ? ? ?%[%^[^%]%s]+%]:") then
      local id, rest = line:match("^ ? ? ?%[%^([^%]%s]+)%]:%s*(.*)$")
      local body = { { text = rest, n = n } }
      local j = i + 1
      while j <= count do
        local text = entries[j].text
        if indent_of(text) >= 4 then
          table.insert(body, { text = text:sub(5), n = entries[j].n })
        elseif is_blank(text) and j < count and indent_of(entries[j + 1].text) >= 4 then
          table.insert(body, { text = "", n = entries[j].n })
        elseif
          not is_blank(text)
          and not interrupts_paragraph(text)
          and not text:match("^%[%^")
        then
          table.insert(body, { text = text, n = entries[j].n })
        else
          break
        end
        j = j + 1
      end
      ctx.footnote_bodies[id] = body
      ctx.impure = true
      i = j
    elseif parse_definition(line) then
      local label, dest, title = parse_definition(line)
      ctx.definitions[normalize_label(label)] = { dest = dest, title = title }
      i = i + 1
    else
      local header = i < count and line:find("|", 1, true) and split_row(line)
      local aligns = header and table_alignments(entries[i + 1].text, #header)
      if aligns then
        local head = {}
        for column, cell in ipairs(header) do
          local style = aligns[column] and (' style="text-align:' .. aligns[column] .. '"') or ""
          table.insert(head, "<th" .. style .. ">" .. inline(ctx, cell) .. "</th>")
        end
        local rows = {}
        local j = i + 2
        while j <= count do
          local text = entries[j].text
          if is_blank(text) or interrupts_paragraph(text) then
            break
          end
          local cells = split_row(text)
          local tds = {}
          for column = 1, #header do
            local style = aligns[column] and (' style="text-align:' .. aligns[column] .. '"') or ""
            table.insert(tds, "<td" .. style .. ">" .. inline(ctx, cells[column] or "") .. "</td>")
          end
          table.insert(
            rows,
            '<tr data-source-line="' .. entries[j].n .. '">' .. table.concat(tds) .. "</tr>"
          )
          j = j + 1
        end
        local html = '<table data-source-line="'
          .. n
          .. '"><thead><tr data-source-line="'
          .. n
          .. '">'
          .. table.concat(head)
          .. "</tr></thead>"
        if #rows > 0 then
          html = html .. "<tbody>" .. table.concat(rows) .. "</tbody>"
        end
        table.insert(out, html .. "</table>")
        i = j
      else
        -- Paragraph, or a setext heading when an underline follows.
        local lines = { (line:gsub("^%s+", "")) }
        local j = i + 1
        local heading_level
        while j <= count do
          local text = entries[j].text
          if is_blank(text) then
            break
          end
          if indent_of(text) <= 3 and text:match("^ *=+%s*$") then
            heading_level = 1
            j = j + 1
            break
          elseif indent_of(text) <= 3 and text:match("^ *%-+%s*$") then
            heading_level = 2
            j = j + 1
            break
          elseif interrupts_paragraph(text) then
            break
          end
          table.insert(lines, (text:gsub("^%s+", "")))
          j = j + 1
        end
        if heading_level then
          table.insert(out, heading_html(ctx, heading_level, table.concat(lines, "\n"), n))
        else
          table.insert(out, render_paragraph(ctx, lines, n, tight))
        end
        i = j
      end
    end
  end
  return table.concat(out, "\n")
end

--- Footnotes referenced anywhere in the document, in order of first reference.
local function footnotes_html(ctx)
  if #ctx.footnote_list == 0 then
    return ""
  end
  local items = {}
  local index = 1
  while index <= #ctx.footnote_list do
    local id = ctx.footnote_list[index]
    local body = compile_blocks(ctx, ctx.footnote_bodies[id] or {}, true)
    local encoded = percent_encode(id)
    table.insert(
      items,
      '<li id="fn-'
        .. encoded
        .. '">'
        .. body
        .. ' <a href="#fnref-'
        .. encoded
        .. '" class="footnote-backref">↩</a></li>'
    )
    index = index + 1
  end
  return '\n<section class="footnotes"><hr class="footnotes-sep"><ol class="footnotes-list">\n'
    .. table.concat(items, "\n")
    .. "\n</ol></section>"
end

---------------------------------------------------------------------------------------------
-- Memoisation. The document is cut into chunks at blank lines (merging the pieces that must stay
-- together: list items, <details>, comments, footnote bodies) and each chunk's HTML is cached by
-- its text. Line numbers inside a cached chunk are stored relative to its first line, so a chunk
-- that merely moved down the file is still a hit.

local MAX_CACHED_CHUNKS = 4096
local chunk_cache, chunk_cache_size = {}, 0

function M.clear_cache()
  chunk_cache, chunk_cache_size = {}, 0
end

local function templatize(html, base)
  html = html:gsub('(data%-source%-line=")(%d+)(")', function(head, number, tail)
    return head .. "\3" .. (tonumber(number) - base) .. "\4" .. tail
  end)
  return (
    html:gsub('(data%-line=")(%d+)(")', function(head, number, tail)
      return head .. "\3" .. (tonumber(number) - base) .. "\4" .. tail
    end)
  )
end

--- Splits a template into alternating literal strings and line offsets, so that moving a chunk is
--- a table walk instead of a pattern replacement.
local function split_template(template)
  local parts, position = {}, 1
  for start, offset, finish in template:gmatch("()\3(%-?%d+)\4()") do
    table.insert(parts, template:sub(position, start - 1))
    table.insert(parts, tonumber(offset))
    position = finish
  end
  table.insert(parts, template:sub(position))
  return parts
end

local function instantiate(parts, base)
  local out = {}
  for index = 1, #parts do
    local part = parts[index]
    out[index] = index % 2 == 0 and (base + part) or part
  end
  return table.concat(out)
end

--- Splits entries into independent chunks. Returns a list of { first, last } index pairs.
local function chunk_lines(lines, fenced, first_line)
  local groups = {}
  local current
  for index = first_line, #lines do
    if fenced[index] or lines[index]:find("%S") then
      if current then
        current[2] = index
      else
        current = { index, index }
        table.insert(groups, current)
      end
    else
      current = nil
    end
  end

  local chunks = {}
  local chunk, has_list, depth, comment_open, footnote, math_open
  local function scan(first, last, is_first)
    for index = first, last do
      local text = lines[index]
      if not fenced[index] then
        if not has_list and text:find("^%s*[%-*+%d]") and list_marker(text) then
          has_list = true
        end
        if text:find("$$", 1, true) or text:find("\\[", 1, true) or text:find("\\]", 1, true) then
          local _, dollars = text:gsub("%$%$", "")
          if dollars % 2 == 1 then
            math_open = not math_open
          elseif text:find("\\[", 1, true) and not text:find("\\]", 1, true) then
            math_open = true
          elseif text:find("\\]", 1, true) then
            math_open = false
          end
        end
        if text:find("<", 1, true) then
          local lowered = text:lower()
          if lowered:find("<details", 1, true) or lowered:find("</details", 1, true) then
            for _ in lowered:gmatch("<details[%s>]") do
              depth = depth + 1
            end
            for _ in lowered:gmatch("</details%s*>") do
              depth = depth - 1
            end
          end
          local open = lowered:find("<!--", 1, true)
          local close = lowered:find("-->", 1, true)
          if open and not (close and close > open) then
            comment_open = true
          elseif close and comment_open then
            comment_open = false
          end
        elseif comment_open and text:find("-->", 1, true) then
          comment_open = false
        end
      end
      if is_first and index == first then
        footnote = text:find("^ ? ? ?%[%^[^%]%s]+%]:") ~= nil
      end
    end
  end

  for _, group in ipairs(groups) do
    local first_text = lines[group[1]]
    local merge = chunk
      and (
        depth > 0
        or comment_open
        or math_open
        or (has_list and (first_text:find("^ ") or (list_marker(first_text) and not is_hr(
          first_text
        ))))
        or (footnote and first_text:find("^    "))
      )
    if merge then
      chunk[2] = group[2]
      scan(group[1], group[2], false)
    else
      chunk = { group[1], group[2] }
      table.insert(chunks, chunk)
      has_list, depth, comment_open, footnote, math_open = false, 0, false, false, false
      scan(group[1], group[2], true)
    end
  end
  return chunks
end

local function fingerprint(ctx)
  local config = ctx.config
  local parts = {
    tostring(config.breaks),
    tostring(config.linkify),
    tostring(config.typographer),
    tostring(config.allow_html),
    tostring(config.sanitize),
    tostring(config.emoji),
    tostring(config.math),
    tostring(ctx.token),
  }
  local labels = vim.tbl_keys(ctx.definitions)
  table.sort(labels)
  for _, label in ipairs(labels) do
    local definition = ctx.definitions[label]
    table.insert(parts, label .. "=" .. definition.dest .. "|" .. tostring(definition.title))
  end
  local ids = vim.tbl_keys(ctx.footnote_ids)
  table.sort(ids)
  table.insert(parts, table.concat(ids, ","))
  return table.concat(parts, "\0")
end

--- The anchor id GitHub (and the preview) gives a heading whose Markdown source is `title`.
--- diagnostics.lua uses this too, so `#anchors` are checked against exactly what is rendered.
function M.slug(title, config)
  local ctx = {
    config = config or {},
    used_slugs = {},
    definitions = {},
    footnote_ids = {},
    footnote_order = {},
    footnote_list = {},
  }
  return slugify(inline(ctx, title))
end

--- Compiles Markdown. Returns `{ html = string, title = string }`.
function M.compile(content, config, doc_path, token)
  config = config or {}
  content = content or ""
  if content:find("\r", 1, true) then
    content = content:gsub("\r\n", "\n"):gsub("\r", "\n")
  end
  if content:find("[\3\4]") then
    content = content:gsub("[\3\4]", "")
  end
  local lines = vim.split(content, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end

  local ctx = {
    config = config,
    token = token,
    used_slugs = {},
    definitions = {},
    footnote_ids = {},
    footnote_bodies = {},
    footnote_order = {},
    footnote_list = {},
  }

  local first_line = 1
  local front_html = ""
  if lines[1] and lines[1]:match("^%-%-%-%s*$") then
    for index = 2, #lines do
      if lines[index]:match("^%-%-%-%s*$") or lines[index]:match("^%.%.%.%s*$") then
        local body = table.concat(lines, "\n", 2, index - 1)
        front_html = '<details class="frontmatter" data-source-line="1"><summary>Front matter</summary><pre>'
          .. escape(body)
          .. "</pre></details>"
        first_line = index + 1
        break
      end
    end
  end

  -- One pass: expand tabs (but not inside fenced code), mark fenced lines, and collect footnote
  -- ids and link reference definitions, which can follow their use.
  local fenced = {}
  local fence_char, fence_length
  for index = first_line, #lines do
    local line = lines[index]
    if fence_char then
      fenced[index] = true
      if line:find(fence_char, 1, true) then
        local marker = line:match("^ *([`~]+)%s*$")
        if marker and marker:sub(1, 1) == fence_char and #marker >= fence_length then
          fence_char = nil
        end
      end
    else
      if line:find("\t", 1, true) then
        line = expand_tabs(line)
        lines[index] = line
      end
      local marker
      if line:find("`", 1, true) or line:find("~", 1, true) then
        local _, found = fence_open(line)
        marker = found
      end
      if marker then
        fence_char, fence_length = marker:sub(1, 1), #marker
        fenced[index] = true
      elseif line:find("^ ? ? ?%[") then
        local id = line:match("^ ? ? ?%[%^([^%]%s]+)%]:")
        if id then
          ctx.footnote_ids[id] = true
        else
          local label, dest, title = parse_definition(line)
          if label then
            ctx.definitions[normalize_label(label)] = { dest = dest, title = title }
          end
        end
      end
    end
  end

  local function entries_for(first, last)
    local entries = {}
    for index = first, last do
      table.insert(entries, { text = lines[index], n = index })
    end
    return entries
  end

  local bodies = {}
  if config.memoize == false then
    local html = compile_blocks(ctx, entries_for(first_line, #lines), false)
    if html ~= "" then
      table.insert(bodies, html)
    end
  else
    local fp = fingerprint(ctx)
    for _, span in ipairs(chunk_lines(lines, fenced, first_line)) do
      local base = span[1]
      local key = fp .. "\1" .. table.concat(lines, "\n", span[1], span[2])
      local hit = chunk_cache[key]
      local html
      if hit then
        if hit.base ~= base then
          hit.parts = hit.parts or split_template(templatize(hit.html, hit.base))
          hit.html, hit.base = instantiate(hit.parts, base), base
        end
        html = hit.html
      else
        ctx.impure = false
        html = compile_blocks(ctx, entries_for(span[1], span[2]), false)
        if not ctx.impure then
          if chunk_cache_size >= MAX_CACHED_CHUNKS then
            M.clear_cache()
          end
          chunk_cache[key] = { html = html, base = base }
          chunk_cache_size = chunk_cache_size + 1
        end
      end
      if html ~= "" then
        table.insert(bodies, html)
      end
    end
  end

  local body = table.concat(bodies, "\n")
  local html = front_html
  if html ~= "" and body ~= "" then
    html = html .. "\n"
  end
  html = html .. body .. footnotes_html(ctx)

  local title = ctx.title
  if not title or title == "" then
    local name = type(doc_path) == "string" and doc_path:match("([^/\\]+)$") or nil
    title = name and name:gsub("%.[^.]*$", "") or "Markdown"
    if title == "" then
      title = "Markdown"
    end
  end
  return { html = html, title = title }
end

M.escape = escape
M.slugify = slugify

return M
