--- Windows window control. Windows has no position/size hook for a browser we did not create
--- through a shell, so this adapter only closes windows by title.
local M = { name = "powershell" }

function M.available()
  return vim.fn.executable("powershell.exe") == 1
end

function M.close(_, tag, wait)
  local escaped = tag:gsub("'", "''")
  local script = string.format(
    "$title = '%s'; Get-Process | Where-Object { $_.MainWindowTitle -like ('*' + $title + '*') } | ForEach-Object { [void]$_.CloseMainWindow() }",
    escaped
  )
  local command =
    { "powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script }
  if wait then
    vim.system(command, { text = true }):wait(2000)
  else
    vim.fn.jobstart(command, { detach = true })
  end
end

return M
