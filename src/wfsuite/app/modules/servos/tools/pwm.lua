--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()
local servoApiHelpers = assert(loadfile("app/modules/servos/tools/servo_api_helpers.lua"))()
local lcd = lcd

local function loadMask(path)
    local ui = wfsuite.app and wfsuite.app.ui
    if ui and ui.loadMask then return ui.loadMask(path) end
    return lcd.loadMask(path)
end

local servoTable = {}
servoTable = {}
servoTable['sections'] = {}

local triggerOverRide = false
local triggerOverRideAll = false
local lastServoCountTime = os.clock()
local onNavMenu

local pwmServoCount 
local busServoOffset = 18

local queueApiWrite = servoApiHelpers.queueApiWrite
local queueServoOverride = servoApiHelpers.queueServoOverride

local function writeEeprom()
    local ok, reason = queueApiWrite("EEPROM_WRITE", "servo.pwm.eeprom")
    if not ok then
        wfsuite.utils.log("Servo PWM EEPROM enqueue rejected: " .. tostring(reason), "info")
    end
    return ok, reason
end

local function buildServoTable()
    servoTable = {}
    servoTable['sections'] = {}

    local totalServoCount = tonumber(wfsuite.session.servoCount or 0) or 0
    pwmServoCount = totalServoCount

    -- On some targets/API variants servoCount already excludes BUS outputs.
    -- Only subtract BUS offset when the total clearly includes those outputs.
    if wfsuite.session.servoBusEnabled == true and wfsuite.utils.apiVersionCompare(">=", {22, 0, 0}) and not system.getVersion().simulation and totalServoCount > busServoOffset then
        pwmServoCount = totalServoCount - busServoOffset
    end

    if pwmServoCount < 0 then
        pwmServoCount = 0
    end

    for i = 1, pwmServoCount do
        servoTable[i] = {}
        servoTable[i] = {}
        servoTable[i]['title'] = "@i18n(app.modules.servos.servo_prefix)@" .. i
        servoTable[i]['image'] = "servo" .. i .. ".png"
        servoTable[i]['disabled'] = true
    end

    for i = 1, pwmServoCount do

        servoTable[i]['disabled'] = false

        if wfsuite.session.swashMode == 0 then

        elseif wfsuite.session.swashMode == 1 then

            if wfsuite.session.tailMode == 0 then
                servoTable[4]['title'] = "@i18n(app.modules.servos.tail)@"
                servoTable[4]['image'] = "tail.png"
                servoTable[4]['section'] = 1
            end
        elseif wfsuite.session.swashMode == 2 or wfsuite.session.swashMode == 3 or wfsuite.session.swashMode == 4 then

            servoTable[1]['title'] = "@i18n(app.modules.servos.cyc_pitch)@"
            servoTable[1]['image'] = "cpitch.png"

            servoTable[2]['title'] = "@i18n(app.modules.servos.cyc_left)@"
            servoTable[2]['image'] = "cleft.png"

            servoTable[3]['title'] = "@i18n(app.modules.servos.cyc_right)@"
            servoTable[3]['image'] = "cright.png"

            if wfsuite.session.tailMode == 0 then

                if servoTable[4] == nil then servoTable[4] = {} end
                servoTable[4]['title'] = "@i18n(app.modules.servos.tail)@"
                servoTable[4]['image'] = "tail.png"
            else

            end
        elseif wfsuite.session.swashMode == 5 or wfsuite.session.swashMode == 6 then

            if wfsuite.session.tailMode == 0 then
                servoTable[4]['title'] = "@i18n(app.modules.servos.tail)@"
                servoTable[4]['image'] = "tail.png"
            else

            end
        end
    end
end

local function swashMixerType()
    local txt
    if wfsuite.session.swashMode == 0 then
        txt = "NONE"
    elseif wfsuite.session.swashMode == 1 then
        txt = "DIRECT"
    elseif wfsuite.session.swashMode == 2 then
        txt = "CPPM 120°"
    elseif wfsuite.session.swashMode == 3 then
        txt = "CPPM 135°"
    elseif wfsuite.session.swashMode == 4 then
        txt = "CPPM 140°"
    elseif wfsuite.session.swashMode == 5 then
        txt = "FPPM 90° L"
    elseif wfsuite.session.swashMode == 6 then
        txt = "FPPM 90° R"
    else
        txt = "UNKNOWN"
    end

    return txt
end

local function openPage(opts)

    local pidx = opts.idx
    local title = opts.title
    local script = opts.script

    buildServoTable()

    wfsuite.tasks.msp.protocol.mspIntervalOveride = nil

    wfsuite.app.triggers.isReady = false
    wfsuite.app.uiState = wfsuite.app.uiStatus.pages

    form.clear()

    wfsuite.app.lastIdx = pidx
    wfsuite.app.lastTitle = title
    wfsuite.app.lastScript = script

    if wfsuite.preferences.general.iconsize == nil or wfsuite.preferences.general.iconsize == "" then
        wfsuite.preferences.general.iconsize = 1
    else
        wfsuite.preferences.general.iconsize = tonumber(wfsuite.preferences.general.iconsize)
    end

    local w, h = lcd.getWindowSize()
    local windowWidth = w
    local windowHeight = h
    local padding = wfsuite.app.radio.buttonPadding

    local sc
    local panel

    local buttonW = 100
    local x = windowWidth - buttonW - 10

    wfsuite.app.ui.fieldHeader(title or "@i18n(app.modules.servos.name)@ / @i18n(app.modules.servos.pwm)@")

    local buttonW
    local buttonH
    local padding
    local numPerRow

    if wfsuite.preferences.general.iconsize == 0 then
        padding = wfsuite.app.radio.buttonPaddingSmall
        buttonW = (wfsuite.app.lcdWidth - padding) / wfsuite.app.radio.buttonsPerRow - padding
        buttonH = wfsuite.app.radio.navbuttonHeight
        numPerRow = wfsuite.app.radio.buttonsPerRow
    end

    if wfsuite.preferences.general.iconsize == 1 then

        padding = wfsuite.app.radio.buttonPaddingSmall
        buttonW = wfsuite.app.radio.buttonWidthSmall
        buttonH = wfsuite.app.radio.buttonHeightSmall
        numPerRow = wfsuite.app.radio.buttonsPerRowSmall
    end

    if wfsuite.preferences.general.iconsize == 2 then

        padding = wfsuite.app.radio.buttonPadding
        buttonW = wfsuite.app.radio.buttonWidth
        buttonH = wfsuite.app.radio.buttonHeight
        numPerRow = wfsuite.app.radio.buttonsPerRow
    end

    local lc = 0
    local bx = 0
    local y = 0

    if wfsuite.app.gfx_buttons["pwm"] == nil then wfsuite.app.gfx_buttons["pwm"] = {} end
    if wfsuite.preferences.menulastselected["pwm"] == nil then wfsuite.preferences.menulastselected["pwm"] = 1 end

    if wfsuite.app.gfx_buttons["pwm"] == nil then wfsuite.app.gfx_buttons["pwm"] = {} end
    if wfsuite.preferences.menulastselected["pwm"] == nil then wfsuite.preferences.menulastselected["pwm"] = 1 end

    for pidx, pvalue in ipairs(servoTable) do

        if pvalue.disabled ~= true then

            if pvalue.section == "swash" and lc == 0 then
                local headerLine = form.addLine("")
                local headerLineText = form.addStaticText(headerLine, {x = 0, y = wfsuite.app.radio.linePaddingTop, w = wfsuite.app.lcdWidth, h = wfsuite.app.radio.navbuttonHeight}, headerLineText())
            end

            if pvalue.section == "tail" then
                local headerLine = form.addLine("")
                local headerLineText = form.addStaticText(headerLine, {x = 0, y = wfsuite.app.radio.linePaddingTop, w = wfsuite.app.lcdWidth, h = wfsuite.app.radio.navbuttonHeight}, "@i18n(app.modules.servos.tail)@")
            end

            if pvalue.section == "other" then
                local headerLine = form.addLine("")
                local headerLineText = form.addStaticText(headerLine, {x = 0, y = wfsuite.app.radio.linePaddingTop, w = wfsuite.app.lcdWidth, h = wfsuite.app.radio.navbuttonHeight}, "@i18n(app.modules.servos.tail)@")
            end

            if lc == 0 then
                if wfsuite.preferences.general.iconsize == 0 then y = form.height() + wfsuite.app.radio.buttonPaddingSmall end
                if wfsuite.preferences.general.iconsize == 1 then y = form.height() + wfsuite.app.radio.buttonPaddingSmall end
                if wfsuite.preferences.general.iconsize == 2 then y = form.height() + wfsuite.app.radio.buttonPadding end
            end

            if lc >= 0 then bx = (buttonW + padding) * lc end

            if wfsuite.preferences.general.iconsize ~= 0 then
                if wfsuite.app.gfx_buttons["pwm"][pidx] == nil then wfsuite.app.gfx_buttons["pwm"][pidx] = loadMask("app/modules/servos/gfx/" .. pvalue.image) end
            else
                wfsuite.app.gfx_buttons["pwm"][pidx] = nil
            end

            wfsuite.app.formFields[pidx] = form.addButton(nil, {x = bx, y = y, w = buttonW, h = buttonH}, {
                text = pvalue.title,
                icon = wfsuite.app.gfx_buttons["pwm"][pidx],
                options = FONT_S,
                paint = function() end,
                press = function()
                    wfsuite.preferences.menulastselected["pwm"] = pidx
                    wfsuite.currentServoIndex = pidx
                    wfsuite.app.ui.progressDisplay()

                    wfsuite.app.ui.openPage({
                        idx = pidx,
                        title = pvalue.title,
                        script = "servos/tools/pwm_tool.lua",
                        servoTable = servoTable,
                        returnContext = {idx = pidx, title = title, script = script}
                    })
                end
            })

            if wfsuite.preferences.menulastselected["pwm"] == pidx then wfsuite.app.formFields[pidx]:focus() end

            lc = lc + 1

            if lc == numPerRow then lc = 0 end
        end
    end

    -- for a write if we are in over-ride and returning to main page
    if wfsuite.session.servoOverride == false then
        writeEeprom()
    end


    wfsuite.app.triggers.closeProgressLoader = true

    return
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

local function wakeup()

    -- go back to main as this tool is compromised 
    if wfsuite.session.servoCount == nil or wfsuite.session.servoOverride == nil then
        pageRuntime.openMenuContext()
        return
    end

    if triggerOverRide == true then
        triggerOverRide = false

        if wfsuite.session.servoOverride == false then
            wfsuite.app.audio.playServoOverideEnable = true
            wfsuite.app.ui.progressDisplay("@i18n(app.modules.servos.servo_override)@", "@i18n(app.modules.servos.enabling_servo_override)@")
            wfsuite.app.Page.servoCenterFocusAllOn(self)
            wfsuite.session.servoOverride = true
        else
            wfsuite.app.audio.playServoOverideDisable = true
            wfsuite.app.ui.progressDisplay("@i18n(app.modules.servos.servo_override)@", "@i18n(app.modules.servos.disabling_servo_override)@")
            wfsuite.app.Page.servoCenterFocusAllOff(self)
            wfsuite.session.servoOverride = false
            writeEeprom()
        end
    end

end

local function servoCenterFocusAllOn(self)

    wfsuite.app.audio.playServoOverideEnable = true

    if wfsuite.utils.apiVersionCompare(">=", {22, 0, 0}) then
            queueApiWrite("SERVO_OVERRIDE_ALL", "servo.pwm.override.all.on", {value = 0})
    else
        for i = 0, #servoTable do
            queueServoOverride(i, 0, string.format("servo.pwm.override.%d.on", i))
        end
    end    


    wfsuite.app.triggers.isReady = true
    wfsuite.app.triggers.closeProgressLoader = true
end

local function servoCenterFocusAllOff(self)

    if wfsuite.utils.apiVersionCompare(">=", {22, 0, 0}) then
            queueApiWrite("SERVO_OVERRIDE_ALL", "servo.pwm.override.all.off", {value = 2001})
    else
        for i = 0, #servoTable do
            queueServoOverride(i, 2001, string.format("servo.pwm.override.%d.off", i))
        end
    end    
    wfsuite.app.triggers.isReady = true
    wfsuite.app.triggers.closeProgressLoader = true
end

onNavMenu = function(self)

    if wfsuite.session.servoOverride == true or inFocus == true then
        wfsuite.app.audio.playServoOverideDisable = true
        wfsuite.session.servoOverride = false
        inFocus = false
        wfsuite.app.ui.progressDisplay("@i18n(app.modules.servos.servo_override)@", "@i18n(app.modules.servos.disabling_servo_override)@")
        wfsuite.app.Page.servoCenterFocusAllOff(self)
        wfsuite.app.triggers.closeProgressLoader = true
    end

    pageRuntime.openMenuContext({defaultSection = "hardware"})
    return true

end


return {event = event, openPage = openPage, onToolMenu = onToolMenu, onNavMenu = onNavMenu, servoCenterFocusAllOn = servoCenterFocusAllOn, servoCenterFocusAllOff = servoCenterFocusAllOff, wakeup = wakeup, navButtons = {menu = true, save = false, reload = false, tool = true, help = true}, onReloadMenu = onReloadMenu, API = {}}
