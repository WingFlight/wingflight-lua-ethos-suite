--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()

local FIELDS = {
    MODE = 1,
    RPM = 2,
    RPM_MIN = 3,
    RPM_MAX = 4,
    GAIN = 5,
    I_GAIN = 6,
    THROTTLE = 7,
    HANDOVER = 8,
    CEILING = 9
}

local MODE_OFF = 0
local MODE_RPM = 1
local MODE_THROTTLE = 2
local MODE_RPM_RANGE = 3

local apidata
local lastMode

local function currentMode()
    local modeField = apidata.formdata.fields[FIELDS.MODE]
    return modeField and wfsuite.app.utils.getFieldValue(modeField) or MODE_OFF
end

local function setFieldActive(index, active)
    local field = wfsuite.app.formFields and wfsuite.app.formFields[index]
    if not field then return end

    local ok = pcall(function() field:active(active == true) end)
    if not ok and field.enable then field:enable(active == true) end
end

local function applyMode(mode)
    mode = mode or MODE_OFF
    if mode == lastMode then return end
    lastMode = mode

    local rpmMode = mode == MODE_RPM
    local throttleMode = mode == MODE_THROTTLE
    local rpmRangeMode = mode == MODE_RPM_RANGE
    local activeMode = mode ~= MODE_OFF
    local rpmControlMode = rpmMode or rpmRangeMode

    setFieldActive(FIELDS.RPM, rpmMode)
    setFieldActive(FIELDS.RPM_MIN, rpmRangeMode)
    setFieldActive(FIELDS.RPM_MAX, rpmRangeMode)
    setFieldActive(FIELDS.GAIN, rpmControlMode)
    setFieldActive(FIELDS.I_GAIN, rpmControlMode)
    setFieldActive(FIELDS.THROTTLE, throttleMode)
    setFieldActive(FIELDS.HANDOVER, rpmMode or throttleMode)
    setFieldActive(FIELDS.CEILING, activeMode)
end

local function onModeChange(_, value)
    applyMode(value)
end

apidata = {
    api = {
        [1] = 'WING_GOVERNOR_CONFIG'
    },
    formdata = {
        labels = {},
        fields = {
            [FIELDS.MODE] = {
                t = "@i18n(app.modules.esc_motors.governor_mode)@",
                api = "WING_GOVERNOR_CONFIG:governor_mode",
                type = 1,
                table = {
                    "@i18n(api.WING_GOVERNOR_CONFIG.tbl_mode_off)@",
                    "@i18n(api.WING_GOVERNOR_CONFIG.tbl_mode_rpm)@",
                    "@i18n(api.WING_GOVERNOR_CONFIG.tbl_mode_throttle)@",
                    "@i18n(api.WING_GOVERNOR_CONFIG.tbl_mode_rpm_range)@"
                },
                tableIdxInc = -1,
                onChange = onModeChange
            },
            [FIELDS.RPM] = {
                t = "@i18n(app.modules.esc_motors.governor_rpm)@",
                api = "WING_GOVERNOR_CONFIG:governor_rpm"
            },
            [FIELDS.RPM_MIN] = {
                t = "@i18n(app.modules.esc_motors.governor_rpm_min)@",
                api = "WING_GOVERNOR_CONFIG:governor_rpm_min"
            },
            [FIELDS.RPM_MAX] = {
                t = "@i18n(app.modules.esc_motors.governor_rpm_max)@",
                api = "WING_GOVERNOR_CONFIG:governor_rpm_max"
            },
            [FIELDS.GAIN] = {
                t = "@i18n(app.modules.esc_motors.governor_gain)@",
                api = "WING_GOVERNOR_CONFIG:governor_gain"
            },
            [FIELDS.I_GAIN] = {
                t = "@i18n(app.modules.esc_motors.governor_i_gain)@",
                api = "WING_GOVERNOR_CONFIG:governor_i_gain"
            },
            [FIELDS.THROTTLE] = {
                t = "@i18n(app.modules.esc_motors.governor_throttle)@",
                api = "WING_GOVERNOR_CONFIG:governor_throttle"
            },
            [FIELDS.HANDOVER] = {
                t = "@i18n(app.modules.esc_motors.governor_handover)@",
                api = "WING_GOVERNOR_CONFIG:governor_handover"
            },
            [FIELDS.CEILING] = {
                t = "@i18n(app.modules.esc_motors.governor_ceiling)@",
                api = "WING_GOVERNOR_CONFIG:governor_ceiling"
            },
        }
    }
}

local function postLoad()
    wfsuite.app.triggers.closeProgressLoader = true
    lastMode = nil
    applyMode(currentMode())
end

local function onNavMenu(self)
    pageRuntime.openMenuContext({defaultSection = "hardware"})
    return true
end

local function event(_, category, value)
    return pageRuntime.handleCloseEvent(category, value, {onClose = onNavMenu})
end

return {apidata = apidata, reboot = true, eepromWrite = true, event = event, postLoad = postLoad, onNavMenu = onNavMenu}
