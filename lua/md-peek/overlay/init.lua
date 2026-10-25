local headings = require("md-peek.overlay.headings")
local outline = require("md-peek.overlay.outline")
local status = require("md-peek.overlay.status")

local M = {
  headings = headings.headings,
  update_status = status.update_status,
  close_status = status.close_status,
  open_outline = outline.open_outline,
  close_outline = outline.close_outline,
}

function M.close_all()
  status.close_status()
  outline.close_outline()
end

return M
