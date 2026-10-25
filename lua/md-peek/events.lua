local M = {}

local TASK_PATTERNS = {
  "^(%s*[-*+]%s+%[)([ xX])(%].*)$",
  "^(%s*%d+[.)]%s+%[)([ xX])(%].*)$",
}

--- Flips the `[ ]`/`[x]` marker on a Markdown task line. Returns true when the line was a task.
function M.toggle_task(bufnr, line)
  if
    not vim.api.nvim_buf_is_valid(bufnr)
    or line < 1
    or line > vim.api.nvim_buf_line_count(bufnr)
  then
    return false
  end
  local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
  for _, pattern in ipairs(TASK_PATTERNS) do
    local head, mark, tail = text:match(pattern)
    if head then
      local flipped = head .. (mark == " " and "x" or " ") .. tail
      vim.api.nvim_buf_set_lines(bufnr, line - 1, line, false, { flipped })
      return true
    end
  end
  return false
end

--- Handles one decoded event from the preview server.
--- `session` exposes just what is needed from init.lua: is_active(), has_preview(),
--- is_markdown(bufnr), render(immediate), follow(bufnr), trace(message), opened_ms(), open() and
--- close().
function M.handle(bufnr, event, session)
  if type(event) ~= "table" then
    return
  end
  vim.schedule(function()
    if event.type == "error" then
      vim.notify(
        "[md-peek] preview server rejected an editor message: " .. tostring(event.error),
        vim.log.levels.ERROR
      )
    elseif event.type == "jump" and session.is_active() and vim.api.nvim_buf_is_valid(bufnr) then
      local win = vim.fn.bufwinid(bufnr)
      if win ~= -1 then
        local target =
          math.max(1, math.min(tonumber(event.line) or 1, vim.api.nvim_buf_line_count(bufnr)))
        vim.api.nvim_set_current_win(win)
        vim.api.nvim_win_set_cursor(win, { target, 0 })
      end
    elseif event.type == "rendered" then
      -- Only reported in debug mode: the first one is the first paint after :MdPeekOpen.
      if not M.first_render_seen then
        M.first_render_seen = true
        local opened = session.opened_ms()
        if opened then
          session.trace(string.format("first render after %.0f ms", opened))
        end
      elseif tonumber(event.latency_ms) then
        session.trace(string.format("render took %.0f ms from keystroke", event.latency_ms))
      end
    elseif event.type == "toggle_task" and session.is_active() then
      local line = tonumber(event.line)
      if line and M.toggle_task(bufnr, line) then
        session.render(true) -- the user just clicked; do not wait out the typing debounce
      else
        vim.notify("[md-peek] that line is not a task list item", vim.log.levels.WARN)
      end
    elseif event.type == "open_file" and type(event.path) == "string" then
      local reopen = session.has_preview()
      local origin = vim.api.nvim_get_current_buf()
      -- Edit first: a failure (e.g. E37 on a modified buffer) must not cost the user their preview.
      local edited, err = pcall(vim.cmd.edit, vim.fn.fnameescape(event.path))
      if not edited then
        vim.notify("[md-peek] could not open linked file: " .. tostring(err), vim.log.levels.WARN)
        return
      end
      local current = vim.api.nvim_get_current_buf()
      if reopen and current ~= origin then
        if session.is_markdown(current) then
          session.follow(current) -- keep the window and server; just show the new file
        else
          session.close()
        end
      end
    end
  end)
end

return M
