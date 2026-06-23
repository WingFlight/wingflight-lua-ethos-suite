--[[
  Toolbar action: launch app
]] --

local wfsuite = require("wfsuite")
local M = {}


function M.launchApp()
    if (system.openPage) and wfsuite.sysIndex['app'] then
        system.openPage({system=wfsuite.sysIndex['app']})
    end
end

function M.wakeup()

end

function M.reset()

end

return M
