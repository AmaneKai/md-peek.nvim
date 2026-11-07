--- The preview server: HTTP/1.1 plus Server-Sent Events on 127.0.0.1, running inside Neovim on
--- vim.uv. Requests are parsed in libuv callbacks and handled on the main loop.
local compiler = require("md-peek.compiler")
local page = require("md-peek.page")

local uv = vim.uv or vim.loop

local M = { port = nil, url = nil, ready = false, error = nil, token = nil }

local MAX_BODY = 64 * 1024
local MAX_HEADER = 16 * 1024
local CHUNK = 256 * 1024
local DEFAULT_REQUEST_TIMEOUT_MS = 15000
local request_timeout_ms = DEFAULT_REQUEST_TIMEOUT_MS
local IS_WINDOWS = (jit and jit.os == "Windows") or false
local KEEPALIVE_MS = 15000

local MIME = {
  png = "image/png",
  jpg = "image/jpeg",
  jpeg = "image/jpeg",
  gif = "image/gif",
  webp = "image/webp",
  svg = "image/svg+xml",
  avif = "image/avif",
  bmp = "image/bmp",
  ico = "image/x-icon",
  mp4 = "video/mp4",
  webm = "video/webm",
  ogg = "audio/ogg",
  mp3 = "audio/mpeg",
  wav = "audio/wav",
  pdf = "application/pdf",
}

local REASONS = {
  [200] = "OK",
  [204] = "No Content",
  [304] = "Not Modified",
  [400] = "Bad Request",
  [401] = "Unauthorized",
  [403] = "Forbidden",
  [404] = "Not Found",
  [206] = "Partial Content",
  [405] = "Method Not Allowed",
  [408] = "Request Timeout",
  [416] = "Range Not Satisfiable",
  [413] = "Payload Too Large",
  [431] = "Request Header Fields Too Large",
  [500] = "Internal Server Error",
  [503] = "Service Unavailable",
}

local tcp_server
local sse_clients = {}
local connections = {}
local last_render_payload
local pending_document
local current_doc_path
local preview_config = {}
local on_event
local keepalive

local function hex(bytes)
  return (bytes:gsub(".", function(char)
    return string.format("%02x", char:byte())
  end))
end

local function random_hex(count)
  local bytes = uv.random(count)
  if type(bytes) ~= "string" or #bytes ~= count then
    return nil
  end
  return hex(bytes)
end

--- Constant-time string comparison.
local function equal(a, b)
  if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then
    return false
  end
  local diff = 0
  for index = 1, #a do
    diff = bit.bor(diff, bit.bxor(a:byte(index), b:byte(index)))
  end
  return diff == 0
end

local function percent_decode(text)
  return (
    text:gsub("%+", " "):gsub("%%(%x%x)", function(code)
      return string.char(tonumber(code, 16))
    end)
  )
end

local function parse_query(query)
  local params = {}
  for pair in (query or ""):gmatch("[^&]+") do
    local key, value = pair:match("^([^=]*)=?(.*)$")
    params[percent_decode(key)] = percent_decode(value)
  end
  return params
end

--- The parent directory of `path`. A filesystem root ("/", "C:/") is its own parent, which is what
--- ends a walk up the tree; a bare relative name gives ".".
local function dirname(path)
  if path == "/" or path:match("^%a:[/\\]?$") then
    return path
  end
  local directory = path:gsub("[/\\][^/\\]*$", "")
  if directory == path then
    return "."
  elseif directory == "" then
    return "/"
  elseif directory:match("^%a:$") then
    return directory .. "/"
  end
  return directory
end

local function is_absolute(path)
  return path:sub(1, 1) == "/" or path:sub(1, 1) == "\\" or path:match("^%a:[/\\]") ~= nil
end

--- Resolves `.` and `..` lexically.
local function normalize(path)
  path = path:gsub("\\", "/")
  local prefix = path:match("^%a:/") or (path:sub(1, 1) == "/" and "/" or "")
  local parts = {}
  for part in path:sub(#prefix + 1):gmatch("[^/]+") do
    if part == ".." then
      table.remove(parts)
    elseif part ~= "." then
      table.insert(parts, part)
    end
  end
  return prefix .. table.concat(parts, "/")
end

--- Slash-normalised form for prefix checks; Windows drive letters (and, there, the whole path)
--- compare case-insensitively.
local function canonical(path)
  path = path:gsub("\\", "/")
  if IS_WINDOWS then
    path = path:lower()
  end
  return path
end

local function inside(root, path)
  root, path = canonical(root), canonical(path)
  if root:sub(-1) ~= "/" then
    root = root .. "/"
  end
  return path == root:sub(1, -2) or path:sub(1, #root) == root
end

local function extension(path)
  return (path:match("%.([%w]+)$") or ""):lower()
end

---------------------------------------------------------------------------------------------
-- Responses

local function send_raw(client, data, close)
  if client:is_closing() then
    return
  end
  client:write(data, function()
    if close and not client:is_closing() then
      client:close()
    end
  end)
end

local function respond(client, status, headers, body)
  body = body or ""
  local lines = { "HTTP/1.1 " .. status .. " " .. (REASONS[status] or "OK") }
  local merged = {
    ["Content-Length"] = tostring(#body),
    ["Connection"] = "close",
    ["Cache-Control"] = "no-store",
    ["X-Content-Type-Options"] = "nosniff",
    ["Referrer-Policy"] = "no-referrer",
  }
  for key, value in pairs(headers or {}) do
    merged[key] = value
  end
  local bodiless = status == 204 or status == 304
  if bodiless then
    merged["Content-Length"] = nil
  end
  for key, value in pairs(merged) do
    table.insert(lines, key .. ": " .. value)
  end
  table.insert(lines, "")
  table.insert(lines, "")
  send_raw(client, table.concat(lines, "\r\n") .. (bodiless and "" or body), true)
end

local function text(client, status, message)
  respond(
    client,
    status,
    { ["Content-Type"] = "text/plain; charset=utf-8" },
    message or REASONS[status]
  )
end

local function csp(nonce)
  local images = "'self' data:"
  if preview_config.remote_images ~= false then
    images = images .. " https: http:"
  end
  return table.concat({
    "default-src 'none'",
    "script-src 'nonce-" .. nonce .. "'",
    "style-src 'unsafe-inline'",
    "img-src " .. images,
    "media-src 'self'",
    "connect-src 'self'",
    "font-src 'self' data:",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  }, "; ")
end

---------------------------------------------------------------------------------------------
-- Request handling

local function authorized(request)
  return M.token ~= nil
    and (
      equal(request.query.token or "", M.token)
      or equal(request.headers["x-md-peek-token"] or "", M.token)
    )
end

local function loopback_host(host)
  if not host then
    return false
  end
  host = host:lower()
  local name = host:match("^%[(.-)%]") or host:match("^([^:]+)")
  return name == "127.0.0.1" or name == "localhost" or name == "::1"
end

local function same_origin(request)
  local fetch_site = request.headers["sec-fetch-site"]
  if fetch_site and fetch_site ~= "same-origin" and fetch_site ~= "none" then
    return false
  end
  local origin = request.headers["origin"]
  if origin then
    local host = origin:match("^https?://([^/]+)$")
    if not host or host:lower() ~= (request.headers["host"] or ""):lower() then
      return false
    end
  end
  return true
end

local function broadcast(payload)
  local frame = "data: " .. payload .. "\n\n"
  for client in pairs(sse_clients) do
    if client:is_closing() then
      sse_clients[client] = nil
    else
      client:write(frame)
    end
  end
end

--- Expands a leading `~` and `$VAR` / `${VAR}` so one config works on every machine.
local function expand_path(path)
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
  if path == "~" or path:match("^~[/\\]") then
    path = home .. path:sub(2)
  end
  return (
    path
      :gsub("%$(%b{})", function(braced)
        return os.getenv(braced:sub(2, -2)) or ""
      end)
      :gsub("%$([%w_]+)", function(name)
        return os.getenv(name) or ""
      end)
  )
end

local function git_root(directory)
  local walk = directory
  while true do
    if uv.fs_stat(walk .. "/.git") then
      return uv.fs_realpath(walk)
    end
    local parent = dirname(walk)
    if parent == walk or parent == "." then
      return uv.fs_realpath(directory)
    end
    walk = parent
  end
end

--- Every directory a document may embed files from: "git" (the default), "document", an absolute
--- directory, or a list of those. In a list the keywords pick the base root (the document's folder
--- unless "git" is listed) and every other entry is an extra directory; directories that are
--- missing on this machine are skipped.
local function asset_roots()
  if not current_doc_path then
    return {}
  end
  local setting = preview_config.asset_root
  local directory = dirname(current_doc_path)
  local roots = {}
  local function add(path)
    local real = path and uv.fs_realpath(path)
    if real then
      table.insert(roots, real)
    end
  end
  if type(setting) == "table" then
    local use_git = false
    local extras = {}
    for _, entry in ipairs(setting) do
      if entry == "git" then
        use_git = true
      elseif entry ~= "document" and type(entry) == "string" and entry ~= "" then
        local expanded = expand_path(entry)
        if is_absolute(expanded) then
          table.insert(extras, expanded)
        end
      end
    end
    add(use_git and git_root(directory) or directory)
    for _, extra in ipairs(extras) do
      add(extra)
    end
  elseif setting == "document" then
    add(directory)
  elseif type(setting) == "string" and setting ~= "git" then
    local expanded = expand_path(setting)
    add(is_absolute(expanded) and expanded or directory)
  else
    add(git_root(directory))
  end
  return roots
end

local function inside_any(roots, path)
  for _, root in ipairs(roots) do
    if inside(root, path) then
      return true
    end
  end
  return false
end

local ASSET_CSP = "default-src 'none'; style-src 'unsafe-inline'; sandbox"

local function asset_response(client, status, headers, body)
  headers = headers or {}
  headers["Content-Security-Policy"] = ASSET_CSP
  headers["Content-Type"] = headers["Content-Type"] or "text/plain; charset=utf-8"
  respond(client, status, headers, body or REASONS[status])
end

--- Parses a single `bytes=a-b` range. Returns first, last (inclusive), or nil for no/unsupported
--- range, or false when the range cannot be satisfied.
local function parse_range(header, total)
  if not header then
    return nil
  end
  local first, last = header:match("^bytes=(%d*)%-(%d*)$")
  if not first or (first == "" and last == "") then
    return nil
  end
  if first == "" then
    local suffix = tonumber(last)
    if suffix == 0 or total == 0 then
      return false
    end
    return math.max(0, total - suffix), total - 1
  end
  first = tonumber(first)
  last = last ~= "" and tonumber(last) or total - 1
  if first >= total or last < first then
    return false
  end
  return first, math.min(last, total - 1)
end

--- Streams a file to the client in chunks without blocking the editor, honouring one Range.
local function stream_file(client, path, mime, range_header, if_none_match)
  uv.fs_open(path, "r", 292, function(open_error, fd)
    if open_error or not fd then
      return asset_response(client, 404)
    end
    uv.fs_fstat(fd, function(stat_error, stat)
      if stat_error or not stat or stat.type ~= "file" then
        uv.fs_close(fd)
        return asset_response(client, 404)
      end
      local total = stat.size
      local etag = string.format('"%d-%d-%d"', stat.mtime.sec, stat.mtime.nsec, total)
      if if_none_match and (if_none_match == etag or if_none_match == "W/" .. etag) then
        uv.fs_close(fd)
        return asset_response(client, 304, { ["ETag"] = etag, ["Cache-Control"] = "no-cache" })
      end
      local first, last = parse_range(range_header, total)
      if first == false then
        uv.fs_close(fd)
        return asset_response(client, 416, { ["Content-Range"] = "bytes */" .. total })
      end
      local status = first and 206 or 200
      first, last = first or 0, last or (total - 1)
      local length = total == 0 and 0 or (last - first + 1)
      local head = {
        "HTTP/1.1 " .. status .. " " .. REASONS[status],
        "Content-Type: " .. mime,
        "Content-Length: " .. length,
        "Accept-Ranges: bytes",
        "ETag: " .. etag,
        "Content-Security-Policy: " .. ASSET_CSP,
        "X-Content-Type-Options: nosniff",
        "Cache-Control: no-cache",
        "Referrer-Policy: no-referrer",
        "Connection: close",
      }
      if status == 206 then
        table.insert(head, "Content-Range: bytes " .. first .. "-" .. last .. "/" .. total)
      end
      table.insert(head, "")
      table.insert(head, "")

      local position = first
      local function finish()
        uv.fs_close(fd)
        if not client:is_closing() then
          client:close()
        end
      end
      local function step()
        if length == 0 or position > last or client:is_closing() then
          return finish()
        end
        local want = math.min(CHUNK, last - position + 1)
        uv.fs_read(fd, want, position, function(read_error, data)
          if read_error or not data or #data == 0 then
            return finish()
          end
          position = position + #data
          client:write(data, function(write_error)
            if write_error then
              return finish()
            end
            step()
          end)
        end)
      end
      client:write(table.concat(head, "\r\n"), function(write_error)
        if write_error then
          return finish()
        end
        step()
      end)
    end)
  end)
end

local function handle_asset(client, request)
  local requested = request.query.path
  local roots = asset_roots()
  if not requested or requested == "" or #roots == 0 or not current_doc_path then
    return asset_response(client, 404)
  end
  local candidate = is_absolute(requested) and requested
    or (dirname(current_doc_path) .. "/" .. requested)
  local real = uv.fs_realpath(candidate)
  if not real then
    return asset_response(client, 404)
  end
  if not inside_any(roots, real) then
    return asset_response(client, 403)
  end
  local mime = MIME[extension(real)]
  if not mime then
    return asset_response(client, 403)
  end
  stream_file(client, real, mime, request.headers["range"], request.headers["if-none-match"])
end

local MERMAID_URL = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"
local mermaid_waiting -- requests queued while the bundle downloads

local function mermaid_path()
  return vim.fn.stdpath("cache") .. "/md-peek/mermaid.min.js"
end

local function serve_mermaid(client, request, path)
  stream_file(
    client,
    path,
    "application/javascript; charset=utf-8",
    request.headers["range"],
    request.headers["if-none-match"]
  )
end

--- Serves the Mermaid bundle from the cache, downloading it with curl the first time it is asked
--- for. Without curl or a network the answer is 503 and the diagrams stay as source.
local function handle_mermaid(client, request)
  local path = mermaid_path()
  if preview_config.mermaid == false then
    return text(client, 404)
  elseif uv.fs_stat(path) then
    return serve_mermaid(client, request, path)
  elseif vim.fn.executable("curl") ~= 1 then
    return text(client, 503, "mermaid is not cached and curl is not available")
  elseif mermaid_waiting then
    return table.insert(mermaid_waiting, { client, request })
  end
  mermaid_waiting = { { client, request } }
  vim.fn.mkdir(dirname(path), "p")
  local partial = path .. ".part" .. (random_hex(4) or "")
  vim.system(
    { "curl", "-fsSL", "--max-time", "20", MERMAID_URL, "-o", partial },
    {},
    function(result)
      vim.schedule(function()
        local waiting = mermaid_waiting
        mermaid_waiting = nil
        local stat = result.code == 0 and uv.fs_stat(partial)
        local ok = stat and stat.size > 1000 and uv.fs_rename(partial, path)
        if not ok then
          uv.fs_unlink(partial)
        end
        for _, pending in ipairs(waiting) do
          if ok then
            serve_mermaid(pending[1], pending[2], path)
          else
            text(pending[1], 503, "mermaid could not be downloaded")
          end
        end
      end)
    end
  )
end

local function resolve_markdown_link(href)
  if type(href) ~= "string" or not current_doc_path then
    return nil
  end
  local path = percent_decode((href:gsub("[#?].*$", "")))
  if path == "" or path:match("^%a[%w+.-]*:") and not path:match("^%a:[/\\]") then
    return nil
  end
  local ext = extension(path)
  if ext ~= "md" and ext ~= "markdown" then
    return nil
  end
  if is_absolute(path) then
    return normalize(path)
  end
  return normalize(dirname(current_doc_path) .. "/" .. path)
end

local function handle_act(client, request)
  if not same_origin(request) then
    return text(client, 403)
  end
  local ok, body = pcall(vim.json.decode, request.body)
  if not ok or type(body) ~= "table" then
    return text(client, 400, "invalid JSON")
  end
  local event
  local kind = body.type
  if kind == "jump" or kind == "toggle_task" then
    local line = tonumber(body.line)
    if line and line >= 1 then
      event = { type = kind, line = math.floor(line) }
    end
  elseif kind == "rendered" then
    local latency = tonumber(body.latency_ms)
    event = { type = "rendered", latency_ms = latency and latency >= 0 and latency or nil }
  elseif kind == "open_file" then
    local path = resolve_markdown_link(body.href)
    if path then
      event = { type = "open_file", path = path }
    end
  elseif kind == "set_scheme" then
    -- A display preference, remembered for the next preview; the editor has no use for it.
    if body.scheme == "light" or body.scheme == "dark" then
      page.save_scheme(body.scheme)
      return respond(client, 204)
    end
  end
  if not event then
    return text(client, 400, "invalid event")
  end
  respond(client, 204)
  if on_event then
    on_event(event)
  end
end

local function handle_events(client)
  client:write(table.concat({
    "HTTP/1.1 200 OK",
    "Content-Type: text/event-stream",
    "Cache-Control: no-cache",
    "Connection: keep-alive",
    "X-Content-Type-Options: nosniff",
    "",
    "",
  }, "\r\n"))
  sse_clients[client] = true
  M.flush_pending()
  if last_render_payload then
    client:write("data: " .. last_render_payload .. "\n\n")
  end
end

local function handle_request(client, request)
  if client:is_closing() then
    return
  end
  local peer = client:getpeername()
  if peer and peer.ip ~= "127.0.0.1" and peer.ip ~= "::1" then
    return text(client, 403)
  end
  if not loopback_host(request.headers["host"]) then
    return text(client, 403, "unexpected Host header")
  end
  if request.path == "/favicon.ico" then
    return respond(client, 204)
  end

  if request.method == "GET" and request.path == "/" then
    if not authorized(request) then
      return text(client, 401)
    end
    local nonce = random_hex(16) or tostring(uv.hrtime())
    M.flush_pending() -- a browser is here now: compile what is waiting, and paint it at once
    local ok, html = pcall(page.render, {
      initial = last_render_payload,
      token = M.token,
      nonce = nonce,
      preview = preview_config,
      scheme = page.load_scheme(),
    })
    if not ok then
      return text(client, 500, tostring(html))
    end
    return respond(client, 200, {
      ["Content-Type"] = "text/html; charset=utf-8",
      ["Content-Security-Policy"] = csp(nonce),
    }, html)
  elseif request.method == "GET" and request.path == "/events" then
    if not authorized(request) then
      return text(client, 401)
    end
    return handle_events(client)
  elseif request.method == "POST" and request.path == "/act" then
    if not authorized(request) then
      return text(client, 401)
    end
    return handle_act(client, request)
  elseif request.method == "GET" and request.path == "/mermaid.js" then
    if not authorized(request) then
      return text(client, 401)
    end
    return handle_mermaid(client, request)
  elseif request.method == "GET" and request.path == "/asset" then
    if not authorized(request) then
      return text(client, 401)
    end
    return handle_asset(client, request)
  elseif request.method ~= "GET" and request.method ~= "POST" then
    return text(client, 405)
  end
  text(client, 404)
end

--- Parses `data` once it holds a whole request. Returns the request, `false` when more bytes are
--- needed, or nil plus an HTTP status when the request is unacceptable.
local function parse_request(data)
  local header_end = data:find("\r\n\r\n", 1, true)
  if not header_end then
    if #data > MAX_HEADER then
      return nil, 431
    end
    return false
  end
  if header_end > MAX_HEADER then
    return nil, 431
  end
  local head = data:sub(1, header_end - 1)
  local request_line, rest = head:match("^([^\r\n]*)\r?\n?(.*)$")
  local method, target = request_line:match("^(%u+) (%S+) HTTP/1%.[01]$")
  if not method then
    return nil, 400
  end
  local headers = {}
  for line in rest:gmatch("[^\r\n]+") do
    local key, value = line:match("^([^:]+):%s*(.-)%s*$")
    if key then
      headers[key:lower()] = value
    end
  end
  local body = ""
  if method == "POST" then
    local length = tonumber(headers["content-length"] or "0")
    if not length or length < 0 then
      return nil, 400
    end
    if length > MAX_BODY then
      return nil, 413
    end
    body = data:sub(header_end + 4, header_end + 3 + length)
    if #body < length then
      return false
    end
  end
  local path, query = target:match("^([^?]*)%??(.*)$")
  return {
    method = method,
    target = target,
    path = path,
    query = parse_query(query),
    headers = headers,
    body = body,
  }
end

local function on_connection(server)
  local client = uv.new_tcp()
  if not server:accept(client) then
    client:close()
    return
  end
  connections[client] = true
  local buffer, done = "", false
  local idle = uv.new_timer()
  local function stop_idle()
    if idle then
      idle:stop()
      idle:close()
      idle = nil
    end
  end
  idle:start(request_timeout_ms, 0, function()
    stop_idle()
    if not client:is_closing() then
      text(client, 408)
    end
  end)
  client:read_start(function(err, chunk)
    if err or not chunk then
      stop_idle()
      sse_clients[client] = nil
      connections[client] = nil
      if not client:is_closing() then
        client:close()
      end
      return
    end
    if done then
      return
    end
    buffer = buffer .. chunk
    local request, status = parse_request(buffer)
    if request == false then
      return
    end
    done = true
    stop_idle()
    if not request then
      text(client, status)
      return
    end
    vim.schedule(function()
      local ok, failure = pcall(handle_request, client, request)
      if not ok then
        pcall(text, client, 500, tostring(failure))
      end
    end)
  end)
end

---------------------------------------------------------------------------------------------
-- Public interface

local function stop_keepalive()
  if keepalive then
    keepalive:stop()
    keepalive:close()
    keepalive = nil
  end
end

--- Starts listening on 127.0.0.1.
---
--- opts: preview (the preview config), port (0 = any free port), request_timeout_ms (how long a
--- client may take to send a whole request; default 15000), and the callbacks
---   on_ready(info)   the server is listening (`info.port`, `info.url`)
---   on_event(event)  an event from the preview, already validated
---   on_error(text)   it failed after startup
function M.start(opts)
  if tcp_server then
    return true
  end
  opts = opts or {}
  M.port, M.url, M.error = nil, nil, nil
  M.ready = false
  M.token = random_hex(32)
  if not M.token then
    M.error = "could not generate a secure preview session token"
    return false
  end
  preview_config = type(opts.preview) == "table" and opts.preview or {}
  request_timeout_ms = tonumber(opts.request_timeout_ms) or DEFAULT_REQUEST_TIMEOUT_MS
  on_event = opts.on_event
  last_render_payload, pending_document, current_doc_path = nil, nil, nil

  local server = uv.new_tcp()
  local bound, bind_error = server:bind("127.0.0.1", tonumber(opts.port) or 0)
  if not bound then
    server:close()
    M.error = "could not bind preview server: " .. tostring(bind_error)
    M.token = nil
    return false
  end
  local listening, listen_error = server:listen(128, function(err)
    if err then
      return
    end
    on_connection(server)
  end)
  if not listening then
    server:close()
    M.error = "could not listen: " .. tostring(listen_error)
    M.token = nil
    return false
  end
  local address = server:getsockname()
  if not address then
    server:close()
    M.error = "could not read the preview server address"
    M.token = nil
    return false
  end

  tcp_server = server
  M.port = address.port
  M.url = "http://127.0.0.1:" .. address.port .. "/"
  M.ready = true

  keepalive = uv.new_timer()
  keepalive:start(KEEPALIVE_MS, KEEPALIVE_MS, function()
    for client in pairs(sse_clients) do
      if client:is_closing() then
        sse_clients[client] = nil
      else
        client:write(": ping\n\n")
      end
    end
  end)

  vim.schedule(function()
    if tcp_server == server and opts.on_ready then
      opts.on_ready({ port = M.port, url = M.url })
    end
  end)
  return true
end

--- `{ [src] = "mtime-size" }` for the local files an HTML fragment embeds. The page adds it to
--- the asset URL, so an image edited on disk gets a new URL and the browser refetches it.
local function asset_versions(html)
  local versions = {}
  if not current_doc_path then
    return versions
  end
  local directory = dirname(current_doc_path)
  for src in html:gmatch('%ssrc="([^"]+)"') do
    if not versions[src] and not src:match("^%a[%w+.-]*:") and not src:match("^[/#]") then
      local stat = uv.fs_stat(directory .. "/" .. percent_decode((src:gsub("[?#].*$", ""))))
      if stat then
        versions[src] = stat.mtime.sec .. "-" .. stat.size
      end
    end
  end
  return versions
end

--- Compiles a document into the JSON payload sent to the browser.
local function render_payload(document, sent_at)
  local ok, compiled =
    pcall(compiler.compile, document.content or "", preview_config, current_doc_path, M.token)
  if not ok then
    compiled = {
      html = "<pre>md-peek could not render this document:\n" .. compiler.escape(
        tostring(compiled)
      ) .. "</pre>",
      title = "Markdown",
    }
  end
  local encoded, payload = pcall(vim.json.encode, {
    type = "render",
    html = compiled.html,
    assets = asset_versions(compiled.html),
    title = compiled.title,
    raw = document.content,
    path = current_doc_path,
    line = document.line,
    sent_at = sent_at,
  })
  return encoded and payload or nil
end

--- Compiles the document that arrived while no browser was listening. Nothing is compiled until
--- someone is there to read it.
function M.flush_pending()
  local pending = pending_document
  if not pending then
    return
  end
  pending_document = nil
  last_render_payload = render_payload(pending.document, pending.sent_at)
end

--- Sends a message from the editor to every connected preview.
function M.send(message)
  if not M.ready or type(message) ~= "table" then
    return false
  end
  if message.type == "render" and type(message.document) == "table" then
    current_doc_path = message.document.path
    if next(sse_clients) == nil then
      pending_document = { document = message.document, sent_at = message.sent_at }
      last_render_payload = nil
      return true
    end
    pending_document = nil
    local payload = render_payload(message.document, message.sent_at)
    if not payload then
      return false
    end
    last_render_payload = payload
    broadcast(payload)
    return true
  elseif message.type == "cursor" and tonumber(message.line) then
    broadcast(vim.json.encode({ type = "cursor", line = tonumber(message.line) }))
    return true
  elseif message.type == "theme" and type(message.css) == "string" then
    broadcast(vim.json.encode({ type = "theme", css = message.css }))
    return true
  end
  if on_event then
    local handler = on_event
    vim.schedule(function()
      handler({ type = "error", error = "invalid editor message" })
    end)
  end
  return true
end

function M.stop()
  stop_keepalive()
  for client in pairs(connections) do
    if not client:is_closing() then
      client:close()
    end
  end
  connections, sse_clients = {}, {}
  if tcp_server then
    if not tcp_server:is_closing() then
      tcp_server:close()
    end
    tcp_server = nil
  end
  M.port, M.url, M.token = nil, nil, nil
  M.ready, M.error = false, nil
  last_render_payload, pending_document, current_doc_path, on_event = nil, nil, nil, nil
end

return M
