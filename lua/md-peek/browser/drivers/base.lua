--- The contract every browser driver fulfils. `detect.lua` asks a driver where its browser is;
--- `init.lua` asks it how to launch one. Everything browser-specific lives in the driver, so
--- adding a browser means adding a file here, not editing the launcher.
---
--- A driver is a table with:
---   kind                  "chromium" | "firefox" | ...
---   persistent_profile    reuse one profile directory between runs (faster to start)
---   candidates(os_name)   list of installs to look for (see detect.lua for the shape)
---   command(executable, url, profile_directory, size, position)  -> argv
---   after_launch(found, tag, size, position)   optional; runs once the process has started
local M = {}

local REQUIRED = { "kind", "candidates", "command" }

--- Validates a driver and fills in the optional parts.
function M.define(driver)
  for _, field in ipairs(REQUIRED) do
    assert(driver[field] ~= nil, "browser driver is missing `" .. field .. "`")
  end
  driver.persistent_profile = driver.persistent_profile == true
  driver.after_launch = driver.after_launch or function() end
  return driver
end

return M
