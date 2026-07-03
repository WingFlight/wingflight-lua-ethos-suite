--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()

local FIELDS = {
    MODE = 1,
    RPM = 2,
    GAIN = 3,
    I_GAIN = 4,
    THROTTLE = 5,
    HANDOVER = 6,
    CEILING = 7
}

local apidata = {
    api = {
        [1] = 'IDLE_GOVERNOR_CONFIG'
    },
    formdata = {
        labels = {},
        fields = {
            [FIELDS.MODE] = {t = "@i18n(app.modules.esc_motors.idle_governor_mode)@", api = "IDLE_GOVERNOR_CONFIG:idle_governor_mode"},
            [FIELDS.RPM] = {t = "@i18n(app.modules.esc_motors.idle_governor_rpm)@", api = "IDLE_GOVERNOR_CONFIG:idle_governor_rpm"},
            [FIELDS.GAIN] = {t = "@i18n(app.modules.esc_motors.idle_governor_gain)@", api = "IDLE_GOVERNOR_CONFIG:idle_governor_gain"},
            [FIELDS.I_GAIN] = {t = "@i18n(app.modules.esc_motors.idle_governor_i_gain)@", api = "IDLE_GOVERNOR_CONFIG:idle_governor_i_gain"},
            [FIELDS.THROTTLE] = {t = "@i18n(app.modules.esc_motors.idle_governor_throttle)@", api = "IDLE_GOVERNOR_CONFIG:idle_governor_throttle"},
            [FIELDS.HANDOVER] = {t = "@i18n(app.modules.esc_motors.idle_governor_handover)@", api = "IDLE_GOVERNOR_CONFIG:idle_governor_handover"},
            [FIELDS.CEILING] = {t = "@i18n(app.modules.esc_motors.idle_governor_ceiling)@", api = "IDLE_GOVERNOR_CONFIG:idle_governor_ceiling"},
        }
    }
}

local function onNavMenu(self)
    pageRuntime.openMenuContext({defaultSection = "hardware"})
    return true
end

local function event(_, category, value)
    return pageRuntime.handleCloseEvent(category, value, {onClose = onNavMenu})
end

return {apidata = apidata, reboot = true, eepromWrite = true, event = event, onNavMenu = onNavMenu}
