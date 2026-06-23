--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()
local lcd = lcd
local navHandlers = pageRuntime.createMenuHandlers()

local utils = assert(loadfile("SCRIPTS:/" .. wfsuite.config.baseDir .. "/app/modules/logs/lib/utils.lua"))()

local function loadMask(path)
    local ui = wfsuite.app and wfsuite.app.ui
    if ui and ui.loadMask then return ui.loadMask(path) end
    return lcd.loadMask(path)
end

local enableWakeup = false

local function openPage(opts)

    local idx = opts.idx
    local title = opts.title
    local script = opts.script
    wfsuite.app.activeLogDir = nil
    if not wfsuite.utils.ethosVersionAtLeast() then return end

    if wfsuite.tasks.msp then wfsuite.tasks.msp.protocol.mspIntervalOveride = nil end

    wfsuite.app.triggers.isReady = false
    wfsuite.app.uiState = wfsuite.app.uiStatus.pages
    form.clear()

    wfsuite.app.lastIdx = idx
    wfsuite.app.lastTitle = title
    wfsuite.app.lastScript = script

    local w, h = lcd.getWindowSize()
    local prefs = wfsuite.preferences.general
    local radio = wfsuite.app.radio
    local icons = prefs.iconsize
    local padding, btnW, btnH, perRow

    if icons == 0 then
        padding = radio.buttonPaddingSmall
        btnW = (wfsuite.app.lcdWidth - padding) / radio.buttonsPerRow - padding
        btnH = radio.navbuttonHeight
        perRow = radio.buttonsPerRow
    elseif icons == 1 then
        padding = radio.buttonPaddingSmall
        btnW, btnH = radio.buttonWidthSmall, radio.buttonHeightSmall
        perRow = radio.buttonsPerRowSmall
    else
        padding = radio.buttonPadding
        btnW, btnH = radio.buttonWidth, radio.buttonHeight
        perRow = radio.buttonsPerRow
    end

    wfsuite.app.ui.fieldHeader("Logs")

    local logDir = utils.getLogPath()
    local folders = utils.getLogsDir(logDir)

    if #folders == 0 then
        local msg = "@i18n(app.modules.logs.msg_no_logs_found)@"
        local tw, th = lcd.getTextSize(msg)
        local x = w / 2 - tw / 2
        local y = h / 2 - th / 2
        form.addStaticText(nil, {x = x, y = y, w = tw, h = btnH}, msg)
    else

        local x, y, col = 0, form.height() + padding, 0
        wfsuite.app.gfx_buttons.logs = wfsuite.app.gfx_buttons.logs or {}

        for i, item in ipairs(folders) do
            if col >= perRow then col, y = 0, y + btnH + padding end

            local modelName = utils.resolveModelName(item.foldername)

            if icons ~= 0 then
                wfsuite.app.gfx_buttons.logs[i] = wfsuite.app.gfx_buttons.logs[i] or loadMask("app/modules/logs/gfx/folder.png")
            else
                wfsuite.app.gfx_buttons.logs[i] = nil
            end

            local btn = form.addButton(nil, {x = col * (btnW + padding), y = y, w = btnW, h = btnH}, {
                text = modelName,
                options = FONT_S,
                icon = wfsuite.app.gfx_buttons.logs[i],
                press = function()
                    wfsuite.preferences.menulastselected.logs_folder = i
                    wfsuite.app.ui.progressDisplay()
                    wfsuite.utils.log("Opening logs for: " .. item.foldername, "info")
                    local logsModelTitle = "Logs / " .. modelName
                    wfsuite.app.ui.openPage({
                        idx = i,
                        title = logsModelTitle,
                        script = "logs/logs_logs.lua",
                        dirname = item.foldername,
                        modelName = modelName,
                        returnContext = {idx = idx, title = title, script = script}
                    })
                end
            })

            btn:enable(true)

            if wfsuite.preferences.menulastselected.logs_folder == i then btn:focus() end

            col = col + 1
        end
    end

    if wfsuite.tasks.msp then wfsuite.app.triggers.closeProgressLoader = true end

    enableWakeup = true
end

local function event(widget, category, value)
    if value == KEY_DOWN_BREAK or category == EVT_CLOSE then
        pageRuntime.openMenuContext()
        return true
    end
    return false
end

local function wakeup() if enableWakeup then end end

local function onNavMenu() return navHandlers.onNavMenu() end
return {event = event, openPage = openPage, wakeup = wakeup, onNavMenu = onNavMenu, navButtons = {menu = true, save = false, reload = false, tool = false, help = true}, API = {}}
