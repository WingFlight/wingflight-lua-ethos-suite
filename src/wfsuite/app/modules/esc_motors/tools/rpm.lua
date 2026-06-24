--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()

local enableWakeup = false

local function rpmSensor(field, value)
    --print("RPM Sensor Source changed to: " .. tostring(value))
end

local function dshotSensor(field, value)
    --print("RPM Sensor Source changed to: " .. tostring(value))
end

local formFields = wfsuite.app.formFields

local FIELDS = {
    RPM_SENSOR = 1,
    DSHOT_TELEMETRY = 2,
    MOTOR_POLE_COUNT = 3
}

local apidata = {
    api = {
        [1] = 'MOTOR_CONFIG',
        [2] = 'FEATURE_CONFIG'
    },
    formdata = {
        labels = {},
        fields = {
            [FIELDS.RPM_SENSOR] = {t = "@i18n(app.modules.esc_motors.rpm_sensor_source)@",   api = "FEATURE_CONFIG:enabledFeatures->freq_sensor", type = 1, onChange=rpmSensor},
            [FIELDS.DSHOT_TELEMETRY] = {t = "@i18n(app.modules.esc_motors.use_dshot_telemetry)@", api = "MOTOR_CONFIG:use_dshot_telemetry", type = 1, onChange=dshotSensor},
            [FIELDS.MOTOR_POLE_COUNT] = {t = "@i18n(app.modules.esc_motors.motor_pole_count)@",    api = "MOTOR_CONFIG:motor_pole_count_0"},
        }
    }
}

local function postLoad(self)
    wfsuite.app.triggers.closeProgressLoader = true
    enableWakeup = true
end

local function wakeup() 
    if enableWakeup == true then
        local values = wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.api and wfsuite.tasks.msp.api.apidata and wfsuite.tasks.msp.api.apidata.values
        local motorConfig = values and values["MOTOR_CONFIG"] or nil
        local protocol = motorConfig and motorConfig.motor_pwm_protocol or nil
        local dshotField = formFields and formFields[FIELDS.DSHOT_TELEMETRY] or nil

        if protocol == nil or not (dshotField and dshotField.enable) then
            return
        end

        if protocol >= 5 and protocol <= 8 then
            -- dshot compatable
            dshotField:enable(true)
        else
            -- not dshot
            dshotField:enable(false)
        end

        -- No additional processing for motor protocol here.
    end 
end

local function onNavMenu(self)
    pageRuntime.openMenuContext({defaultSection = "hardware"})
    return true
end

local function event(_, category, value)
    return pageRuntime.handleCloseEvent(category, value, {onClose = onNavMenu})
end

return {apidata = apidata, reboot = true, eepromWrite = true, event = event, wakeup = wakeup, postLoad = postLoad, onNavMenu = onNavMenu}
