--[[
  Toolbar action: reset flight mode
]] --

local wfsuite = require("wfsuite")
local M = {}

local function applyReset()
    local tasks = wfsuite and wfsuite.tasks
    if tasks and tasks.events and tasks.events.flightmode and type(tasks.events.flightmode.reset) == "function" then
        tasks.events.flightmode.reset()
    end
    if wfsuite and wfsuite.flightmode then
        wfsuite.flightmode.current = "preflight"
    end
    local dashboard = wfsuite and wfsuite.widgets and wfsuite.widgets.dashboard
    if dashboard then
        dashboard.flightmode = "preflight"
    end
    if model and type(model.resetFlight) == "function" then
        pcall(model.resetFlight)
    end
    if lcd and lcd.invalidate then
        lcd.invalidate()
    end
end

function M.resetFlightModeAsk()
    local buttons = {
        {
            label = "@i18n(app.btn_ok)@",
            action = function()
                applyReset()
                return true
            end
        }, {label = "@i18n(app.btn_cancel)@", action = function() return true end}
    }

    form.openDialog({width = nil, title = "@i18n(widgets.dashboard.reset_flight_ask_title)@", message = "@i18n(widgets.dashboard.reset_flight_ask_text)@", buttons = buttons, wakeup = function() end, paint = function() end, options = TEXT_LEFT})
end

function M.wakeup()
    return
end

function M.reset()
    return
end

return M
