--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 -- https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()
local common = assert(loadfile("app/modules/settings/activelook/common.lua"))()
local system = system

local config = {}

local function switchSourceFromConfig(value)
    if value == nil or value == "" then return nil end
    local scategory, smember = tostring(value):match("([^,]+),([^,]+)")
    scategory = tonumber(scategory)
    smember = tonumber(smember)
    if scategory and smember then
        return system.getSource({category = scategory, member = smember})
    end
    return nil
end

local function openPage(opts)
    local pageIdx = opts.idx
    local title = opts.title
    local script = opts.script

    common.clearPreviewMode()

    if not wfsuite.app.navButtons then wfsuite.app.navButtons = {} end
    wfsuite.app.triggers.closeProgressLoader = true
    form.clear()

    wfsuite.app.lastIdx = pageIdx
    wfsuite.app.lastTitle = title
    wfsuite.app.lastScript = script

    wfsuite.app.ui.fieldHeader("@i18n(app.modules.settings.name)@" .. " / ActiveLook / " .. "@i18n(app.modules.settings.activelook_settings)@")
    wfsuite.app.formLineCnt = 0
    local formFieldCount = 0

    config = {}
    local saved = wfsuite.preferences.activelook or {}
    for k, v in pairs(saved) do config[k] = v end
    config = common.applyDefaults(config)

    local function addLine(label)
        wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
        local line = form.addLine(label)
        wfsuite.app.formLines[wfsuite.app.formLineCnt] = line
        return line
    end

    local function addFieldLine(label)
        local line = addLine(label)
        formFieldCount = formFieldCount + 1
        return line, formFieldCount
    end

    local line, fieldIdx = addFieldLine("@i18n(app.modules.settings.activelook_hide_display)@")
    wfsuite.app.formFields[fieldIdx] = form.addSwitchField(line, nil, function()
        return switchSourceFromConfig(config.display_switch)
    end, function(newValue)
        if newValue then
            config.display_switch = newValue:category() .. "," .. newValue:member()
        else
            config.display_switch = ""
        end
    end)

    line, fieldIdx = addFieldLine("Offset X")
    wfsuite.app.formFields[fieldIdx] = form.addNumberField(line, nil, -20, 20, function()
        return tonumber(config.offset_x) or 0
    end, function(newValue) config.offset_x = common.clampOffset(newValue) end)
    if wfsuite.app.formFields[fieldIdx] and wfsuite.app.formFields[fieldIdx].suffix then
        wfsuite.app.formFields[fieldIdx]:suffix("px")
    end

    line, fieldIdx = addFieldLine("Offset Y")
    wfsuite.app.formFields[fieldIdx] = form.addNumberField(line, nil, -20, 20, function()
        return tonumber(config.offset_y) or 0
    end, function(newValue) config.offset_y = common.clampOffset(newValue) end)
    if wfsuite.app.formFields[fieldIdx] and wfsuite.app.formFields[fieldIdx].suffix then
        wfsuite.app.formFields[fieldIdx]:suffix("px")
    end

    for _, field in ipairs(wfsuite.app.formFields) do
        if field and field.enable then field:enable(true) end
    end
    wfsuite.app.navButtons.save = true
end

local function onNavMenu()
    common.clearPreviewMode()
    pageRuntime.openMenuContext()
    return true
end

local function onSaveMenu()
    return common.confirmedSave(config)
end

local function event(widget, category, value, x, y)
    return pageRuntime.handleCloseEvent(category, value, {onClose = onNavMenu})
end

return {
    event = event,
    openPage = openPage,
    onNavMenu = onNavMenu,
    onSaveMenu = onSaveMenu,
    navButtons = {menu = true, save = true, reload = false, tool = false, help = false},
    API = {}
}
