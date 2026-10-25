local M = {}

--- Handles one NDJSON event line from the preview server.
--- `session` exposes just what is needed from init.lua: is_active(), has_preview(),
--- is_markdown(bufnr), open() and close().
function M.handle(bufnr, line, session)
  if line == "" then
    return
  end
  local ok, event = pcall(vim.json.decode, line)
  if not ok or type(event) ~= "table" then
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
    elseif event.type == "open_file" and type(event.path) == "string" then
      local reopen = session.has_preview()
      local origin = vim.api.nvim_get_current_buf()
      -- Edit first: a failure (e.g. E37 on a modified buffer) must not cost the user their preview.
      local edited, err = pcall(vim.cmd.edit, vim.fn.fnameescape(event.path))
      if not edited then
        vim.notify("[md-peek] could not open linked file: " .. tostring(err), vim.log.levels.WARN)
        return
      end
      if reopen and vim.api.nvim_get_current_buf() ~= origin then
        session.close()
        if session.is_markdown(vim.api.nvim_get_current_buf()) then
          session.open()
        end
      end
    end
  end)
end

return M
