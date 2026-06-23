--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()
local themeLib = assert(loadfile("widgets/dashboard/lib/themes.lua"))()
local themesBasePath = "SCRIPTS:/" .. wfsuite.config.baseDir .. "/widgets/dashboard/themes/"
local themesUserPath = "SCRIPTS:/" .. wfsuite.config.preferences .. "/dashboard/"
local lcd = lcd

local function loadMask(path)
    local ui = wfsuite.app and wfsuite.app.ui
    if ui and ui.loadMask then return ui.loadMask(path) end
    return lcd.loadMask(path)
end

local enableWakeup = false
local prevConnectedState = nil
local onNavMenu

local function openPage(opts)

    local pidx = opts.idx
    local title = opts.title
    local script = opts.script

    local themeList = themeLib.listThemes()

    wfsuite.session.dashboardEditingTheme = nil
    enableWakeup = true
    wfsuite.app.triggers.closeProgressLoader = true
    form.clear()

    for i in pairs(wfsuite.app.gfx_buttons) do if i ~= "settings_dashboard_themes" then wfsuite.app.gfx_buttons[i] = nil end end

    wfsuite.app.lastIdx = pageIdx
    wfsuite.app.lastTitle = title
    wfsuite.app.lastScript = script

    wfsuite.app.ui.fieldHeader("@i18n(app.modules.settings.name)@" .. " / " .. "@i18n(app.modules.settings.dashboard)@" .. " / " .. "@i18n(app.modules.settings.dashboard_settings)@")

    local buttonW, buttonH, padding, numPerRow
    if wfsuite.preferences.general.iconsize == 0 then
        padding = wfsuite.app.radio.buttonPaddingSmall
        buttonW = (wfsuite.app.lcdWidth - padding) / wfsuite.app.radio.buttonsPerRow - padding
        buttonH = wfsuite.app.radio.navbuttonHeight
        numPerRow = wfsuite.app.radio.buttonsPerRow
    elseif wfsuite.preferences.general.iconsize == 1 then
        padding = wfsuite.app.radio.buttonPaddingSmall
        buttonW = wfsuite.app.radio.buttonWidthSmall
        buttonH = wfsuite.app.radio.buttonHeightSmall
        numPerRow = wfsuite.app.radio.buttonsPerRowSmall
    else
        padding = wfsuite.app.radio.buttonPadding
        buttonW = wfsuite.app.radio.buttonWidth
        buttonH = wfsuite.app.radio.buttonHeight
        numPerRow = wfsuite.app.radio.buttonsPerRow
    end

    if wfsuite.app.gfx_buttons["settings_dashboard_themes"] == nil then wfsuite.app.gfx_buttons["settings_dashboard_themes"] = {} end
    if wfsuite.preferences.menulastselected["settings_dashboard_themes"] == nil then wfsuite.preferences.menulastselected["settings_dashboard_themes"] = 1 end

    local lc, bx, y = 0, 0, 0

    local n = 0

    for idx, theme in ipairs(themeList) do

        if theme.configure then

            if lc == 0 then
                if wfsuite.preferences.general.iconsize == 0 then y = form.height() + wfsuite.app.radio.buttonPaddingSmall end
                if wfsuite.preferences.general.iconsize == 1 then y = form.height() + wfsuite.app.radio.buttonPaddingSmall end
                if wfsuite.preferences.general.iconsize == 2 then y = form.height() + wfsuite.app.radio.buttonPadding end
            end
            if lc >= 0 then bx = (buttonW + padding) * lc end

            if wfsuite.app.gfx_buttons["settings_dashboard_themes"][idx] == nil then

                local icon
                if theme.source == "system" then
                    icon = themesBasePath .. theme.folder .. "/icon.png"
                else
                    icon = themesUserPath .. theme.folder .. "/icon.png"
                end
                wfsuite.app.gfx_buttons["settings_dashboard_themes"][idx] = loadMask(icon)
            end

            wfsuite.app.formFields[idx] = form.addButton(nil, {x = bx, y = y, w = buttonW, h = buttonH}, {
                text = theme.name,
                icon = wfsuite.app.gfx_buttons["settings_dashboard_themes"][idx],
                options = FONT_S,
                paint = function() end,
                press = function()

                    wfsuite.preferences.menulastselected["settings_dashboard_themes"] = idx
                    wfsuite.app.ui.progressDisplay(nil, nil, wfsuite.app.loaderSpeed.FAST)
                    local configure = theme.configure
                    local source = theme.source
                    local folder = theme.folder

                    local themeScript
                    if theme.source == "system" then
                        themeScript = themesBasePath .. folder .. "/" .. configure
                    else
                        themeScript = themesUserPath .. folder .. "/" .. configure
                    end

                    local wrapperScript = "settings/tools/dashboard_settings_theme.lua"

                    wfsuite.app.ui.openPage({idx = idx, title = theme.name, script = wrapperScript, source = source, folder = folder, themeScript = themeScript})
                end
            })

            if not theme.configure then wfsuite.app.formFields[idx]:enable(false) end

            if wfsuite.preferences.menulastselected["settings_dashboard_themes"] == idx then wfsuite.app.formFields[idx]:focus() end

            lc = lc + 1
            n = lc + 1
            if lc == numPerRow then lc = 0 end
        end
    end

    if n == 0 then
        local w, h = lcd.getWindowSize()
        local msg = "@i18n(app.modules.settings.no_themes_available_to_configure)@"
        local tw, th = lcd.getTextSize(msg)
        local x = w / 2 - tw / 2
        local y = h / 2 - th / 2
        local btnH = wfsuite.app.radio.navbuttonHeight
        form.addStaticText(nil, {x = x, y = y, w = tw, h = btnH}, msg)
    end

    wfsuite.app.triggers.closeProgressLoader = true

    enableWakeup = true
    return
end

wfsuite.app.uiState = wfsuite.app.uiStatus.pages

local function event(widget, category, value, x, y)
    return pageRuntime.handleCloseEvent(category, value, {onClose = onNavMenu})
end

onNavMenu = function()
    pageRuntime.openMenuContext()
    return true
end

local function wakeup()
    if not enableWakeup then return end

    local currState = (wfsuite.session.isConnected and wfsuite.session.mcu_id) and true or false

    if currState ~= prevConnectedState then

        if currState == false then onNavMenu() end

        prevConnectedState = currState
    end
end

return {pages = pages, openPage = openPage, API = {}, navButtons = {menu = true, save = false, reload = false, tool = false, help = false}, event = event, onNavMenu = onNavMenu, wakeup = wakeup}
