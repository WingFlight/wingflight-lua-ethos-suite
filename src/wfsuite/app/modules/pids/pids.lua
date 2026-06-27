--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local activateWakeup = false

local apidata = {
    api = {
        {id = 1, name = "PID_TUNING", enableDeltaCache = false, rebuildOnWrite = true},
    },
    formdata = {
        labels = {},
        rows = {
            "@i18n(app.modules.pids.roll)@",
            "@i18n(app.modules.pids.pitch)@",
            "@i18n(app.modules.pids.yaw)@"
        },
        cols = {
            "@i18n(app.modules.pids.p)@",
            "@i18n(app.modules.pids.i)@",
            "@i18n(app.modules.pids.d)@",
            "@i18n(app.modules.pids.f)@",
            "@i18n(app.modules.pids.b)@"
        },
        fields = {
            {row = 1, col = 1, mspapi = 1, apikey = "pid_0_P"},
            {row = 2, col = 1, mspapi = 1, apikey = "pid_1_P"},
            {row = 3, col = 1, mspapi = 1, apikey = "pid_2_P"},
            {row = 1, col = 2, mspapi = 1, apikey = "pid_0_I"},
            {row = 2, col = 2, mspapi = 1, apikey = "pid_1_I"},
            {row = 3, col = 2, mspapi = 1, apikey = "pid_2_I"},
            {row = 1, col = 3, mspapi = 1, apikey = "pid_0_D"},
            {row = 2, col = 3, mspapi = 1, apikey = "pid_1_D"},
            {row = 3, col = 3, mspapi = 1, apikey = "pid_2_D"},
            {row = 1, col = 4, mspapi = 1, apikey = "pid_0_F"},
            {row = 2, col = 4, mspapi = 1, apikey = "pid_1_F"},
            {row = 3, col = 4, mspapi = 1, apikey = "pid_2_F"},
            {row = 1, col = 5, mspapi = 1, apikey = "pid_0_B"},
            {row = 2, col = 5, mspapi = 1, apikey = "pid_1_B"},
            {row = 3, col = 5, mspapi = 1, apikey = "pid_2_B"}
        }
    }
}

local function postLoad(self)
    wfsuite.app.triggers.closeProgressLoader = true
    activateWakeup = true
end

local function openPage(opts)

    local idx = opts.idx
    local title = opts.title
    local script = opts.script

    wfsuite.app.uiState = wfsuite.app.uiStatus.pages
    wfsuite.app.triggers.isReady = false

    local relativeScript = script
    if type(relativeScript) == "string" and relativeScript:sub(1, 12) == "app/modules/" then
        relativeScript = relativeScript:sub(13)
    end

    wfsuite.app.lastIdx = idx
    wfsuite.app.lastTitle = title
    wfsuite.app.lastScript = relativeScript or script
    wfsuite.session.lastPage = relativeScript or script

    wfsuite.app.uiState = wfsuite.app.uiStatus.pages

    form.clear()

    wfsuite.app.ui.fieldHeader(title)
    local numCols
    if wfsuite.app.Page.apidata.formdata.cols ~= nil then
        numCols = #wfsuite.app.Page.apidata.formdata.cols
    else
        numCols = 6
    end
    local screenWidth = wfsuite.app.lcdWidth - 10
    local padding = 10
    local paddingTop = wfsuite.app.radio.linePaddingTop
    local h = wfsuite.app.radio.navbuttonHeight
    local w = ((screenWidth * 70 / 100) / numCols)
    local paddingRight = 20
    local positions = {}
    local pos

    local line = form.addLine("")

    local loc = numCols
    local posX = screenWidth - paddingRight
    local posY = paddingTop

    while loc > 0 do
        local colLabel = wfsuite.app.Page.apidata.formdata.cols[loc]
        pos = {x = posX, y = posY, w = w, h = h}
        form.addStaticText(line, pos, colLabel)
        positions[loc] = posX - w + paddingRight
        posX = math.floor(posX - w)
        loc = loc - 1
    end

    local fields = wfsuite.app.Page.apidata.formdata.fields
    local pidRows = {}
    for ri, rv in ipairs(wfsuite.app.Page.apidata.formdata.rows) do pidRows[ri] = form.addLine(rv) end

    for i = 1, #fields do
        local f = fields[i]
        posX = positions[f.col]

        pos = {x = posX + padding, y = posY, w = w - padding, h = h}

        wfsuite.app.formFields[i] = form.addNumberField(pidRows[f.row], pos, 0, 0, function()
            if not fields or not fields[i] then
                if wfsuite.app.ui then
                    wfsuite.app.ui.disableAllFields()
                    wfsuite.app.ui.disableAllNavigationFields()
                    wfsuite.app.ui.enableNavigationField('menu')
                end
                return nil
            end
            return wfsuite.app.utils.getFieldValue(fields[i])
        end, function(value)
            if not fields or not fields[i] then return end
            wfsuite.app.ui.markPageDirty()
            if f.postEdit then f.postEdit(wfsuite.app.Page) end
            if f.onChange then f.onChange(wfsuite.app.Page) end

            f.value = wfsuite.app.utils.saveFieldValue(fields[i], value)
        end)
    end

    wfsuite.app.ui.setPageDirty(false)
end

local function canSave()
    local pref = wfsuite.preferences and wfsuite.preferences.general and wfsuite.preferences.general.save_dirty_only
    if pref == false or pref == "false" then return true end
    return wfsuite.app.pageDirty == true
end

local function wakeup()
    if activateWakeup == true and wfsuite.tasks.msp.mspQueue:isProcessed() then
        if wfsuite.session.activeProfile ~= nil then
            local titleField = wfsuite.app.formFields['title']
            if titleField then
                wfsuite.app.ui.setHeaderTitle(wfsuite.app.Page.title .. " #" .. wfsuite.session.activeProfile)
            end
        end
    end
end

return {apidata = apidata, title = "@i18n(app.modules.pids.name)@", reboot = false, eepromWrite = true, refreshOnProfileChange = true, postLoad = postLoad, openPage = openPage, wakeup = wakeup, canSave = canSave, API = {}}
