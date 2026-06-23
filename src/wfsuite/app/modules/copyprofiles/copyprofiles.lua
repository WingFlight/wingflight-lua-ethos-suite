--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local labels = {}
local fields = {}

fields[#fields + 1] = {t = "@i18n(app.modules.copyprofiles.profile_type)@", value = 0, min = 0, max = 1, table = {[0] = "@i18n(app.modules.copyprofiles.profile_type_pid)@", "@i18n(app.modules.copyprofiles.profile_type_rate)@"}}
fields[#fields + 1] = {t = "@i18n(app.modules.copyprofiles.source_profile)@", value = 0, min = 0, max = 5, tableIdxInc = -1, table = {"1", "2", "3", "4", "5", "6"}}
fields[#fields + 1] = {t = "@i18n(app.modules.copyprofiles.dest_profile)@", value = 0, min = 0, max = 5, tableIdxInc = -1, table = {"1", "2", "3", "4", "5", "6"}}

local doSave = false

local function queueCopyProfile(payload, uuid)
    local msp = wfsuite.tasks and wfsuite.tasks.msp
    local bus = wfsuite.bus
    local actions = msp and msp.genericActions
    local contextId = bus and bus.createContext and bus.createContext({}, wfsuite.app and wfsuite.app.lastScript)
    local API = msp and msp.api and msp.api.loadPage("COPY_PROFILE")
    if not API then return false, "api_unavailable" end

    API.setUUID(uuid)
    API.setValue("profile_type", payload[1])
    API.setValue("dest_profile", payload[2])
    API.setValue("source_profile", payload[3])
    if contextId and actions and actions.actions and API.setBusActions then
        API.setBusActions(actions.actions.appCloseProgress, nil, contextId, true)
    end

    local ok, reason = API.write()
    if not ok and contextId and bus and bus.releaseContext then
        bus.releaseContext(contextId)
    end
    return ok, reason
end

local function onSaveMenu()

    if wfsuite.preferences.general.save_confirm == false or wfsuite.preferences.general.save_confirm == "false" then
        doSave = true
        return
    end    

    local buttons = {
        {
            label = "@i18n(app.btn_ok)@",
            action = function()

                doSave = true

                return true
            end
        }, {label = "@i18n(app.btn_cancel)@", action = function() return true end}
    }
    local theTitle = "@i18n(app.modules.copyprofiles.msgbox_save)@"
    local theMsg
    if wfsuite.app.Page.extraMsgOnSave then
        theMsg = "@i18n(app.modules.copyprofiles.msgbox_msg)@" .. "\n\n" .. wfsuite.app.Page.extraMsgOnSave
    else
        theMsg = "@i18n(app.modules.copyprofiles.msgbox_msg)@"
    end

    form.openDialog({width = nil, title = theTitle, message = theMsg, buttons = buttons, wakeup = function() end, paint = function() end, options = TEXT_LEFT})
end

local function getDestinationPidProfile(self)
    local destPidProfile
    if (self.currentPidProfile < self.maxPidProfiles - 1) then
        destPidProfile = self.currentPidProfile + 1
    else
        destPidProfile = self.currentPidProfile - 1
    end
    return destPidProfile
end

local function openPage(opts)

    local idx = opts.idx
    local title = opts.title
    local script = opts.script

    wfsuite.app.uiState = wfsuite.app.uiStatus.pages
    wfsuite.app.triggers.isReady = false

    local app = wfsuite.app
    if app.formFields then for k in pairs(app.formFields) do app.formFields[k] = nil end end
    if app.formLines then for k in pairs(app.formLines) do app.formLines[k] = nil end end

    wfsuite.app.lastIdx = idx
    wfsuite.app.lastTitle = title
    wfsuite.app.lastScript = script

    form.clear()
    wfsuite.session.lastPage = script

    local pageTitle = wfsuite.app.Page.pageTitle or title
    wfsuite.app.ui.fieldHeader(pageTitle)

    if wfsuite.app.Page.headerLine then
        local headerLine = form.addLine("")
        form.addStaticText(headerLine, {x = 0, y = wfsuite.app.radio.linePaddingTop, w = app.lcdWidth, h = wfsuite.app.radio.navbuttonHeight}, wfsuite.app.Page.headerLine)
    end

    wfsuite.app.formLineCnt = 0

    if fields then
        for i, field in ipairs(fields) do
            local label = labels
            local valid = (field.apiversion == nil or wfsuite.utils.apiVersionCompare(">=", field.apiversion)) and
                (field.apiversionlt == nil or wfsuite.utils.apiVersionCompare("<", field.apiversionlt)) and
                (field.apiversiongt == nil or wfsuite.utils.apiVersionCompare(">", field.apiversiongt)) and
                (field.apiversionlte == nil or wfsuite.utils.apiVersionCompare("<=", field.apiversionlte)) and
                (field.apiversiongte == nil or wfsuite.utils.apiVersionCompare(">=", field.apiversiongte)) and
                (field.enablefunction == nil or field.enablefunction())

            if field.hidden ~= true and valid then
                wfsuite.app.ui.fieldLabel(field, i, label)
                if field.type == 0 then
                    wfsuite.app.ui.fieldStaticText(i,fields)
                elseif field.table or field.type == 1 then
                    wfsuite.app.ui.fieldChoice(i,fields)
                elseif field.type == 2 then
                    wfsuite.app.ui.fieldNumber(i,fields)
                elseif field.type == 3 then
                    wfsuite.app.ui.fieldText(i,fields)
                else
                    wfsuite.app.ui.fieldNumber(i,fields)
                end
            else
                wfsuite.app.formFields[i] = {}
            end
        end
    end

    wfsuite.app.triggers.closeProgressLoader = true
end

local function wakeup()
    if doSave == true then
        wfsuite.app.ui.progressDisplaySave()
        wfsuite.app.triggers.isSavingFake = true

        local payload = {}
        payload[1] = fields[1].value
        payload[2] = fields[3].value
        payload[3] = fields[2].value

        if payload[2] == payload[3] then
            wfsuite.utils.log("Source and destination profiles are the same. No need to copy.", "info")
            wfsuite.app.triggers.closeSaveFake = true
            wfsuite.app.triggers.isSaving = false
            doSave = false
            return
        end

        local ok, reason = queueCopyProfile(payload, string.format("copyprofiles.%d.%d.%d", payload[1], payload[2], payload[3]))
        if not ok then
            wfsuite.utils.log("Copy profiles enqueue rejected: " .. tostring(reason), "info")
            wfsuite.app.triggers.closeSaveFake = true
            wfsuite.app.triggers.isSaving = false
        end

        doSave = false
    end
end

return {reboot = false, eepromWrite = true, title = "Copy", openPage = openPage, wakeup = wakeup, onSaveMenu = onSaveMenu, labels = labels, fields = fields, getDestinationPidProfile = getDestinationPidProfile, API = {}, navButtons = {menu = true, save = true, reload = false, tool = false, help = true}}
