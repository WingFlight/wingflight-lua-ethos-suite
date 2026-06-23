--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --
 
return {
  [1] = {
    name = "WingFlight Dashboard",
    script = "dashboard.lua",
    varname = "dashboard",
    key = "wfsdh",
    folder = "dashboard",
    type = "widget",
  },
  [2] = {
    name = "WingFlight Toolbox",
    script = "toolbox.lua",
    varname = "wftlbx",
    key = "wftlbx",
    folder = "toolbox",
    type = "widget",    
  },
  [3] = {
    name = "WingFlight` ActiveLook",
    script = "activelook.lua",
    varname = "wfactivelook",
    key = "wfalk",
    folder = "activelook",
    type = "glasses",    
  },
}
