--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()
local servoApiHelpers = assert(loadfile("app/modules/servos/tools/servo_api_helpers.lua"))()

local triggerOverRide = false
local triggerOverRideAll = false
local currentServoCenter
local lastSetServoCenter
local lastServoChangeTime = os.clock()
local servoIndex = wfsuite.currentServoIndex - 1
local isSaving = false
local enableWakeup = false

local servoTable
local servoCount
local configs = {}
local INDEXED_SERVO_CONFIG_MIN_API = {12, 0, 9}

local function useIndexedServoConfig()
    return wfsuite.utils.apiVersionCompare(">=", INDEXED_SERVO_CONFIG_MIN_API)
end

local function currentServoReadIndex()
    -- PWM servos use the MSP servo namespace directly: Servo 1 -> 0.
    return servoIndex
end

local function currentServoWriteIndex()
    return servoIndex
end

local queueApiWrite = servoApiHelpers.queueApiWrite
local queueServoOverride = servoApiHelpers.queueServoOverride

local function applyServoConfig(index, data)
    return servoApiHelpers.applyServoConfig(configs, servoTable, index, data)
end

local function completeServoLoad()
    servoApiHelpers.completeServoLoad(function() enableWakeup = true end)
end

local function servoCenterFocusAllOn(self)

    wfsuite.app.audio.playServoOverideEnable = true
    local count = servoCount or (servoTable and #servoTable) or 0

    for i = 0, count - 1 do
        queueServoOverride(i, 0, string.format("servo.override.%d.on", i))
    end
    wfsuite.app.triggers.isReady = true
    wfsuite.app.triggers.closeProgressLoader = true
end

local function servoCenterFocusAllOff(self)

    local count = servoCount or (servoTable and #servoTable) or 0

    for i = 0, count - 1 do
        queueServoOverride(i, 2001, string.format("servo.override.%d.off", i))
    end
    wfsuite.app.triggers.isReady = true
    wfsuite.app.triggers.closeProgressLoader = true
end

local function servoCenterFocusOff(self)
    local writeIndex = currentServoWriteIndex()
    queueServoOverride(writeIndex, 2001, string.format("servo.override.%d.off", writeIndex))
    wfsuite.app.triggers.isReady = true
    wfsuite.app.triggers.closeProgressLoader = true
end

local function servoCenterFocusOn(self)
    local writeIndex = currentServoWriteIndex()
    queueServoOverride(writeIndex, 0, string.format("servo.override.%d.on", writeIndex))
    wfsuite.app.triggers.isReady = true
    wfsuite.app.triggers.closeProgressLoader = true
end

local function writeEeprom()
    local ok, reason = queueApiWrite("EEPROM_WRITE", "servo.pwmtool.eeprom")
    if not ok then
        wfsuite.utils.log("Servo PWM EEPROM enqueue rejected: " .. tostring(reason), "info")
    end
    return ok, reason
end

local function saveServoCenter(self)

    local servoCenter = math.floor(configs[servoIndex]['mid'])
    local writeIndex = currentServoWriteIndex()

    return queueApiWrite("SET_SERVO_CENTER", string.format("servo.%d.center", writeIndex), {
        index = writeIndex,
        mid = servoCenter
    })

end

local function saveServoSettings(self)

    local servoCenter = math.floor(configs[servoIndex]['mid'])
    local servoMin = math.floor(configs[servoIndex]['min'])
    local servoMax = math.floor(configs[servoIndex]['max'])
    local servoScaleNeg = math.floor(configs[servoIndex]['scaleNeg'])
    local servoScalePos = math.floor(configs[servoIndex]['scalePos'])
    local servoRate = math.floor(configs[servoIndex]['rate'])
    local servoSpeed = math.floor(configs[servoIndex]['speed'])
    local servoFlags = math.floor(configs[servoIndex]['flags'])
    local servoReverse = math.floor(configs[servoIndex]['reverse'])
    local servoGeometry = math.floor(configs[servoIndex]['geometry'])

    if servoReverse == 0 and servoGeometry == 0 then
        servoFlags = 0
    elseif servoReverse == 1 and servoGeometry == 0 then
        servoFlags = 1
    elseif servoReverse == 0 and servoGeometry == 1 then
        servoFlags = 2
    elseif servoReverse == 1 and servoGeometry == 1 then
        servoFlags = 3
    end

    local writeIndex = currentServoWriteIndex()
    local ok, reason = queueApiWrite("SET_SERVO_CONFIG", string.format("servo.%d.config", writeIndex), {
        index = writeIndex,
        mid = servoCenter,
        min = servoMin,
        max = servoMax,
        scale_neg = servoScaleNeg,
        scale_pos = servoScalePos,
        rate = servoRate,
        speed = servoSpeed,
        flags = servoFlags
    })
    if not ok then return false, reason end

    if wfsuite.session.servoOverride == true then
        writeEeprom()
    end
    return true, "queued"

end

local function onSaveMenuProgress()
    wfsuite.app.ui.progressDisplay()
    local ok = saveServoSettings()
    if ok then
        wfsuite.app.ui.setPageDirty(false)
    end
    wfsuite.app.triggers.isReady = true
    wfsuite.app.triggers.closeProgressLoader = true
end

local function onSaveMenu()

    if wfsuite.preferences.general.save_confirm == false or wfsuite.preferences.general.save_confirm == "false" then
        isSaving = true
        return
    end  

    local buttons = {
        {
            label = "@i18n(app.btn_ok_long)@",
            action = function()
                isSaving = true

                return true
            end
        }, {label = "@i18n(app.btn_cancel)@", action = function() return true end}
    }
    local theTitle = "@i18n(app.msg_save_settings)@"
    local theMsg = "@i18n(app.msg_save_current_page)@"

    form.openDialog({width = nil, title = theTitle, message = theMsg, buttons = buttons, wakeup = function() end, paint = function() end, options = TEXT_LEFT})

    wfsuite.app.triggers.triggerSave = false
end

local function onNavMenu(self)

    wfsuite.app.ui.progressDisplay()
    pageRuntime.openMenuContext({defaultSection = "hardware"})
    return true

end

local function setServoConfigFieldsEnabled(enabled)
    if not wfsuite.app.formFields then return end
    for _, idx in ipairs({3, 4, 5, 6, 7, 8, 9, 10}) do
        local field = wfsuite.app.formFields[idx]
        if field and field.enable then field:enable(enabled) end
    end
    local saveField = wfsuite.app.formNavigationFields and wfsuite.app.formNavigationFields['save']
    if saveField and saveField.enable then
        if enabled then
            wfsuite.app.ui.setPageDirty(wfsuite.app.pageDirty == true)
        else
            saveField:enable(false)
        end
    end
end

local function canSave()
    if wfsuite.session.servoOverride == true then return false end
    local pref = wfsuite.preferences and wfsuite.preferences.general and wfsuite.preferences.general.save_dirty_only
    if pref == false or pref == "false" then return true end
    return wfsuite.app.pageDirty == true
end

local function wakeup(self)

    if enableWakeup == true then

        -- go back to main as this tool is compromised 
        if wfsuite.session.servoCount == nil or wfsuite.session.servoOverride == nil then
            wfsuite.app.ui.openMenuContext()
            return
        end

        if isSaving == true then
            onSaveMenuProgress()
            isSaving = false
        end

        if wfsuite.session.servoOverride == true then

            currentServoCenter = configs[servoIndex]['mid']

            local now = os.clock()
            local indexedServoConfig = useIndexedServoConfig()
            local settleTime
            if indexedServoConfig then
                settleTime = 0.05
            else
                settleTime = 0.85
            end
            if ((now - lastServoChangeTime) >= settleTime) and wfsuite.tasks.msp.mspQueue:isProcessed() then
                if currentServoCenter ~= lastSetServoCenter then
                    local ok, reason
                    if indexedServoConfig then
                        ok, reason = self.saveServoCenter(self)
                    else
                        ok, reason = self.saveServoSettings(self)
                    end
                    if ok then
                        lastSetServoCenter = currentServoCenter
                        lastServoChangeTime = now
                    elseif reason then
                        wfsuite.utils.log("Servo trim enqueue rejected: " .. tostring(reason), "debug")
                    end
                end
            end

        end
    end

    if triggerOverRide == true then
        triggerOverRide = false

        if wfsuite.session.servoOverride == false then
            wfsuite.app.audio.playServoOverideEnable = true
            wfsuite.app.ui.progressDisplay("@i18n(app.modules.servos.servo_override)@", "@i18n(app.modules.servos.enabling_servo_override)@")
            wfsuite.app.Page.servoCenterFocusAllOn(self)
            wfsuite.session.servoOverride = true

            setServoConfigFieldsEnabled(false)

        else

            wfsuite.app.audio.playServoOverideDisable = true
            wfsuite.app.ui.progressDisplay("@i18n(app.modules.servos.servo_override)@", "@i18n(app.modules.servos.disabling_servo_override)@")
            wfsuite.app.Page.servoCenterFocusAllOff(self)
            wfsuite.session.servoOverride = false

            setServoConfigFieldsEnabled(true)
        end
    end

end

local function getServoConfigurations()
    local API = wfsuite.tasks.msp.api.loadPage("SERVO_CONFIGURATIONS")
    if not API then return false, "api_unavailable" end

    API.setUUID("servo.cfg.bulk")
    API.setCompleteHandler(function()
        local data = API.data()
        local parsed = data and data.parsed
        if not parsed then return end

        servoCount = parsed.servo_count
        if wfsuite.session then
            wfsuite.session.servoCount = servoCount
        end

        if wfsuite.utils and wfsuite.utils.log then
            wfsuite.utils.log("Servo count " .. tostring(servoCount), "info")
        end

        for i = 0, (servoCount or 0) - 1 do
            applyServoConfig(i, parsed.servos and parsed.servos[i])
        end

        completeServoLoad()
    end)

    return API.read()
end


local function getServoConfigurationsIndexed()
    local readIndex = currentServoReadIndex()

    local API = wfsuite.tasks.msp.api.loadPage("GET_SERVO_CONFIG")
    if not API then return getServoConfigurations() end

    API.setUUID(string.format("servo.cfg.%d", readIndex))
    API.setCompleteHandler(function()
        local data = API.data()
        local parsed = data and data.parsed
        if parsed then
            servoCount = wfsuite.session and wfsuite.session.servoCount or servoCount
            applyServoConfig(servoIndex, parsed)
            completeServoLoad()
        end
    end)
    API.setErrorHandler(function()
        getServoConfigurations()
    end)

    local ok, reason = API.read(readIndex)
    if not ok then
        return getServoConfigurations()
    end
    return ok, reason
end


local function openPage(opts)

    local app = wfsuite.app

    local idx = opts.idx
    local title = opts.title
    local script = opts.script
    local servoTableIn = opts.servoTable

    if servoTableIn ~= nil then
        servoTable = servoTableIn
        wfsuite.servoTableLast = servoTable
    else
        if wfsuite.servoTableLast ~= nil then servoTable = wfsuite.servoTableLast end
    end

    configs = {}
    configs[servoIndex] = {}
    configs[servoIndex]['name'] = servoTable[servoIndex + 1]['title']
    configs[servoIndex]['mid'] = 0
    configs[servoIndex]['min'] = 0
    configs[servoIndex]['max'] = 0
    configs[servoIndex]['scaleNeg'] = 0
    configs[servoIndex]['scalePos'] = 0
    configs[servoIndex]['rate'] = 0
    configs[servoIndex]['speed'] = 0
    configs[servoIndex]['flags'] = 0
    configs[servoIndex]['geometry'] = 0
    configs[servoIndex]['reverse'] = 0

    if app.formFields then for k in pairs(app.formFields) do app.formFields[k] = nil end end
    if app.formLines then for k in pairs(app.formLines) do app.formLines[k] = nil end end

    wfsuite.app.lastIdx = idx
    wfsuite.app.lastTitle = title
    wfsuite.app.lastScript = script

    form.clear()

    local fieldHelpTxt = wfsuite.app.ui.getFieldHelpTxt()
    local function getFieldHelpText(key)
        if not fieldHelpTxt or not fieldHelpTxt[key] then return nil end
        return fieldHelpTxt[key]['t']
    end


    wfsuite.app.ui.fieldHeader("@i18n(app.modules.servos.pwm)@" .. " / " .. wfsuite.app.utils.titleCase(configs[servoIndex]['name']))
    wfsuite.app.ui.setPageDirty(false)

    if wfsuite.app.Page.headerLine ~= nil then
        local headerLine = form.addLine("")
        local headerLineText = form.addStaticText(headerLine, {x = 0, y = wfsuite.app.radio.linePaddingTop, w = wfsuite.app.lcdWidth, h = wfsuite.app.radio.navbuttonHeight}, wfsuite.app.Page.headerLine)
    end

    if wfsuite.session.servoOverride == true then wfsuite.app.formNavigationFields['save']:enable(false) end

    if configs[servoIndex]['mid'] ~= nil then

        local idx = 2
        local minValue = 50
        local maxValue = 2250
        local defaultValue = 1500
        local suffix = nil
        local helpTxt = getFieldHelpText('servoMid')

        wfsuite.app.formLines[idx] = form.addLine("@i18n(app.modules.servos.center)@")
        wfsuite.app.formFields[idx] = form.addNumberField(wfsuite.app.formLines[idx], nil, minValue, maxValue, function() return configs[servoIndex]['mid'] end, function(value)
            configs[servoIndex]['mid'] = value
            wfsuite.app.ui.markPageDirty()
        end)
        if suffix ~= nil then wfsuite.app.formFields[idx]:suffix(suffix) end
        if defaultValue ~= nil then wfsuite.app.formFields[idx]:default(defaultValue) end
        if helpTxt ~= nil then wfsuite.app.formFields[idx]:help(helpTxt) end
    end

    if configs[servoIndex]['min'] ~= nil then
        local idx = 3
        local minValue = -1000
        local maxValue = 1000
        local defaultValue = -700
        local suffix = nil
        wfsuite.app.formLines[idx] = form.addLine("@i18n(app.modules.servos.minimum)@")
        local helpTxt = getFieldHelpText('servoMin')
        wfsuite.app.formFields[idx] = form.addNumberField(wfsuite.app.formLines[idx], nil, minValue, maxValue, function() return configs[servoIndex]['min'] end, function(value)
            configs[servoIndex]['min'] = value
            wfsuite.app.ui.markPageDirty()
        end)
        if suffix ~= nil then wfsuite.app.formFields[idx]:suffix(suffix) end
        if defaultValue ~= nil then wfsuite.app.formFields[idx]:default(defaultValue) end
        if helpTxt ~= nil then wfsuite.app.formFields[idx]:help(helpTxt) end
        if wfsuite.session.servoOverride == true then wfsuite.app.formFields[idx]:enable(false) end
    end

    if configs[servoIndex]['max'] ~= nil then
        local idx = 4
        local minValue = -1000
        local maxValue = 1000
        local defaultValue = 700
        local suffix = nil
        local helpTxt = getFieldHelpText('servoMax')
        wfsuite.app.formLines[idx] = form.addLine("@i18n(app.modules.servos.maximum)@")
        wfsuite.app.formFields[idx] = form.addNumberField(wfsuite.app.formLines[idx], nil, minValue, maxValue, function() return configs[servoIndex]['max'] end, function(value)
            configs[servoIndex]['max'] = value
            wfsuite.app.ui.markPageDirty()
        end)
        if suffix ~= nil then wfsuite.app.formFields[idx]:suffix(suffix) end
        if defaultValue ~= nil then wfsuite.app.formFields[idx]:default(defaultValue) end
        if helpTxt ~= nil then wfsuite.app.formFields[idx]:help(helpTxt) end
        if wfsuite.session.servoOverride == true then wfsuite.app.formFields[idx]:enable(false) end
    end

    if configs[servoIndex]['scaleNeg'] ~= nil then
        local idx = 5
        local minValue = 100
        local maxValue = 1000
        local defaultValue = 500
        local suffix = nil
        local helpTxt = getFieldHelpText('servoScaleNeg')
        wfsuite.app.formLines[idx] = form.addLine("@i18n(app.modules.servos.scale_negative)@")
        wfsuite.app.formFields[idx] = form.addNumberField(wfsuite.app.formLines[idx], nil, minValue, maxValue, function() return configs[servoIndex]['scaleNeg'] end, function(value)
            configs[servoIndex]['scaleNeg'] = value
            wfsuite.app.ui.markPageDirty()
        end)
        if suffix ~= nil then wfsuite.app.formFields[idx]:suffix(suffix) end
        if defaultValue ~= nil then wfsuite.app.formFields[idx]:default(defaultValue) end
        if helpTxt ~= nil then wfsuite.app.formFields[idx]:help(helpTxt) end
        if wfsuite.session.servoOverride == true then wfsuite.app.formFields[idx]:enable(false) end
    end

    if configs[servoIndex]['scalePos'] ~= nil then
        local idx = 6
        local minValue = 100
        local maxValue = 1000
        local defaultValue = 500
        local suffix = nil
        local helpTxt = getFieldHelpText('servoScalePos')
        wfsuite.app.formLines[idx] = form.addLine("@i18n(app.modules.servos.scale_positive)@")
        wfsuite.app.formFields[idx] = form.addNumberField(wfsuite.app.formLines[idx], nil, minValue, maxValue, function() return configs[servoIndex]['scalePos'] end, function(value)
            configs[servoIndex]['scalePos'] = value
            wfsuite.app.ui.markPageDirty()
        end)
        if suffix ~= nil then wfsuite.app.formFields[idx]:suffix(suffix) end
        if defaultValue ~= nil then wfsuite.app.formFields[idx]:default(defaultValue) end
        if helpTxt ~= nil then wfsuite.app.formFields[idx]:help(helpTxt) end
        if wfsuite.session.servoOverride == true then wfsuite.app.formFields[idx]:enable(false) end
    end

    if configs[servoIndex]['rate'] ~= nil then
        local idx = 7
        local minValue = 50
        local maxValue = 5000
        local defaultValue = 333
        local suffix = "@i18n(app.unit_hertz)@"
        local helpTxt = getFieldHelpText('servoRate')
        wfsuite.app.formLines[idx] = form.addLine("@i18n(app.modules.servos.rate)@")
        wfsuite.app.formFields[idx] = form.addNumberField(wfsuite.app.formLines[idx], nil, minValue, maxValue, function() return configs[servoIndex]['rate'] end, function(value)
            configs[servoIndex]['rate'] = value
            wfsuite.app.ui.markPageDirty()
        end)
        if suffix ~= nil then wfsuite.app.formFields[idx]:suffix(suffix) end
        if defaultValue ~= nil then wfsuite.app.formFields[idx]:default(defaultValue) end
        if helpTxt ~= nil then wfsuite.app.formFields[idx]:help(helpTxt) end
        if wfsuite.session.servoOverride == true then wfsuite.app.formFields[idx]:enable(false) end
    end

    if configs[servoIndex]['speed'] ~= nil then
        local idx = 8
        local minValue = 0
        local maxValue = 60000
        local defaultValue = 0
        local suffix = "ms"
        local helpTxt = getFieldHelpText('servoSpeed')
        wfsuite.app.formLines[idx] = form.addLine("@i18n(app.modules.servos.speed)@")
        wfsuite.app.formFields[idx] = form.addNumberField(wfsuite.app.formLines[idx], nil, minValue, maxValue, function() return configs[servoIndex]['speed'] end, function(value)
            configs[servoIndex]['speed'] = value
            wfsuite.app.ui.markPageDirty()
        end)
        if suffix ~= nil then wfsuite.app.formFields[idx]:suffix(suffix) end
        if defaultValue ~= nil then wfsuite.app.formFields[idx]:default(defaultValue) end
        if helpTxt ~= nil then wfsuite.app.formFields[idx]:help(helpTxt) end
        if wfsuite.session.servoOverride == true then wfsuite.app.formFields[idx]:enable(false) end
    end

    if configs[servoIndex]['flags'] ~= nil then
        local idx = 9
        local minValue = 0
        local maxValue = 1000
        local table = {"@i18n(app.modules.servos.tbl_no)@", "@i18n(app.modules.servos.tbl_yes)@"}
        local tableIdxInc = -1
        local value
        wfsuite.app.formLines[idx] = form.addLine("@i18n(app.modules.servos.reverse)@")
        wfsuite.app.formFields[idx] = form.addChoiceField(wfsuite.app.formLines[idx], nil, wfsuite.app.utils.convertPageValueTable(table, tableIdxInc), function() return configs[servoIndex]['reverse'] end, function(value)
            configs[servoIndex]['reverse'] = value
            wfsuite.app.ui.markPageDirty()
        end)
        if wfsuite.session.servoOverride == true then wfsuite.app.formFields[idx]:enable(false) end
    end

    if configs[servoIndex]['flags'] ~= nil then
        local idx = 10
        local minValue = 0
        local maxValue = 1000
        local table = {"@i18n(app.modules.servos.tbl_no)@", "@i18n(app.modules.servos.tbl_yes)@"}
        local tableIdxInc = -1
        local value
        wfsuite.app.formLines[idx] = form.addLine("@i18n(app.modules.servos.geometry)@")
        wfsuite.app.formFields[idx] = form.addChoiceField(wfsuite.app.formLines[idx], nil, wfsuite.app.utils.convertPageValueTable(table, tableIdxInc), function() return configs[servoIndex]['geometry'] end, function(value)
            configs[servoIndex]['geometry'] = value
            wfsuite.app.ui.markPageDirty()
        end)
        if wfsuite.session.servoOverride == true then wfsuite.app.formFields[idx]:enable(false) end
    end

    if useIndexedServoConfig() then
        getServoConfigurationsIndexed()
    else
        getServoConfigurations()
    end

end

local function event(widget, category, value, x, y)
    return pageRuntime.handleCloseEvent(category, value, {onClose = onNavMenu})

end

local function onToolMenu(self)

    local buttons
    if wfsuite.session.servoOverride == false then
        buttons = {
            {
                label = "@i18n(app.btn_ok_long)@",
                action = function()

                    triggerOverRide = true
                    triggerOverRideAll = true
                    return true
                end
            }, {label = "@i18n(app.btn_cancel)@", action = function() return true end}
        }
    else
        buttons = {
            {
                label = "@i18n(app.btn_ok_long)@",
                action = function()

                    triggerOverRide = true
                    return true
                end
            }, {label = "@i18n(app.btn_cancel)@", action = function() return true end}
        }
    end
    local message
    local title
    if wfsuite.session.servoOverride == false then
        title = "@i18n(app.modules.servos.enable_servo_override)@"
        message = "@i18n(app.modules.servos.enable_servo_override_msg)@"
    else
        title = "@i18n(app.modules.servos.disable_servo_override)@"
        message = "@i18n(app.modules.servos.disable_servo_override_msg)@"
    end

    form.openDialog({width = nil, title = title, message = message, buttons = buttons, wakeup = function() end, paint = function() end, options = TEXT_LEFT})

end

local function onReloadMenu() wfsuite.app.triggers.triggerReloadFull = true end

local function close()
    -- Release Ethos-held form callbacks immediately so the GC can collect
    -- configs, servoTable, and the rest of the module's upvalue environment.
    -- Without this, Ethos retains the getter/setter closures until the next
    -- page calls form.clear(), leaving all servo data pinned in RAM.
    enableWakeup = false
    form.clear()
    configs = {}
    servoTable = nil
    collectgarbage("collect")
end

return {

    reboot = false,
    event = event,
    close = close,
    setValues = setValues,
    servoChanged = servoChanged,
    servoCenterFocusOn = servoCenterFocusOn,
    servoCenterFocusOff = servoCenterFocusOff,
    servoCenterFocusAllOn = servoCenterFocusAllOn,
    servoCenterFocusAllOff = servoCenterFocusAllOff,
    saveServoSettings = saveServoSettings,
    saveServoCenter = saveServoCenter,
    onToolMenu = onToolMenu,
    wakeup = wakeup,
    openPage = openPage,
    onNavMenu = onNavMenu,
    canSave = canSave,
    onSaveMenu = onSaveMenu,
    onReloadMenu = onReloadMenu,
    navButtons = {menu = true, save = true, reload = true, tool = true, help = true},
    API = {}

}
