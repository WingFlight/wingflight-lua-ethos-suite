--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local lcd = lcd
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()
local navHandlers = pageRuntime.createMenuHandlers({defaultSection = "hardware"})

local activateWakeup = false
local doFullReload = false
local HIDDEN_COLUMNS = {
    [4] = true
}

if wfsuite.session.activeRateTable == nil then wfsuite.session.activeRateTable = wfsuite.config.defaultRateProfile end

local rows
if wfsuite.utils.apiVersionCompare(">=", {22, 0, 0}) then
    rows = {
        "@i18n(app.modules.rates_advanced.response_time)@",
        "@i18n(app.modules.rates_advanced.acc_limit)@",
        "@i18n(app.modules.rates_advanced.setpoint_boost_gain)@",
        "@i18n(app.modules.rates_advanced.setpoint_boost_cutoff)@",
        "@i18n(app.modules.rates_advanced.dyn_ceiling_gain)@",
        "@i18n(app.modules.rates_advanced.dyn_deadband_gain)@",
        "@i18n(app.modules.rates_advanced.dyn_deadband_filter)@"
    }
else
    rows = {
        "@i18n(app.modules.rates_advanced.response_time)@",
        "@i18n(app.modules.rates_advanced.acc_limit)@"
    }
end

local apidata = {
    api = {
        {id = 1, name = "RC_TUNING", enableDeltaCache = false, rebuildOnWrite = true},
    },
    formdata = {
        name = "@i18n(app.modules.rates_advanced.dynamics)@",
        labels = {},
        rows = rows,
        cols = {
            "@i18n(app.modules.rates_advanced.roll)@",
            "@i18n(app.modules.rates_advanced.pitch)@",
            "@i18n(app.modules.rates_advanced.yaw)@",
            "@i18n(app.modules.rates_advanced.col)@"
        },
        fields = {
            {row = 1, col = 1, mspapi = 1, apikey = "response_time_1"},
            {row = 1, col = 2, mspapi = 1, apikey = "response_time_2"},
            {row = 1, col = 3, mspapi = 1, apikey = "response_time_3"},
            {row = 1, col = 4, mspapi = 1, apikey = "response_time_4"},
            {row = 2, col = 1, mspapi = 1, apikey = "accel_limit_1"},
            {row = 2, col = 2, mspapi = 1, apikey = "accel_limit_2"},
            {row = 2, col = 3, mspapi = 1, apikey = "accel_limit_3"},
            {row = 2, col = 4, mspapi = 1, apikey = "accel_limit_4"},
            {row = 3, col = 1, mspapi = 1, apikey = "setpoint_boost_gain_1", apiversiongte = {22, 0, 0}},
            {row = 3, col = 2, mspapi = 1, apikey = "setpoint_boost_gain_2", apiversiongte = {22, 0, 0}},
            {row = 3, col = 3, mspapi = 1, apikey = "setpoint_boost_gain_3", apiversiongte = {22, 0, 0}},
            {row = 3, col = 4, mspapi = 1, apikey = "setpoint_boost_gain_4", apiversiongte = {22, 0, 0}},
            {row = 4, col = 1, mspapi = 1, apikey = "setpoint_boost_cutoff_1", apiversiongte = {22, 0, 0}},
            {row = 4, col = 2, mspapi = 1, apikey = "setpoint_boost_cutoff_2", apiversiongte = {22, 0, 0}},
            {row = 4, col = 3, mspapi = 1, apikey = "setpoint_boost_cutoff_3", apiversiongte = {22, 0, 0}},
            {row = 4, col = 4, mspapi = 1, apikey = "setpoint_boost_cutoff_4", apiversiongte = {22, 0, 0}},
            {row = 5, col = 3, mspapi = 1, apikey = "yaw_dynamic_ceiling_gain", apiversiongte = {22, 0, 0}},
            {row = 6, col = 3, mspapi = 1, apikey = "yaw_dynamic_deadband_gain", apiversiongte = {22, 0, 0}},
            {row = 7, col = 3, mspapi = 1, apikey = "yaw_dynamic_deadband_filter", apiversiongte = {22, 0, 0}}
        }
    }
}

local function buildVisibleColumns(cols)
    local visible = {}

    if cols ~= nil then
        for i = 1, #cols do
            if not HIDDEN_COLUMNS[i] then
                visible[#visible + 1] = i
            end
        end
    else
        for i = 1, 4 do
            if not HIDDEN_COLUMNS[i] then
                visible[#visible + 1] = i
            end
        end
    end

    return visible
end

local function getApiEntryName(entry)
    if type(entry) == "table" then return entry.name end
    return entry
end

local function getRateType()
    local apiName = getApiEntryName(apidata and apidata.api and apidata.api[1])
    local values = wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.api and wfsuite.tasks.msp.api.apidata and wfsuite.tasks.msp.api.apidata.values

    if values and apiName and values[apiName] and values[apiName].rates_type ~= nil then
        return values[apiName].rates_type
    end

    local fields = wfsuite.app and wfsuite.app.Page and wfsuite.app.Page.apidata and wfsuite.app.Page.apidata.formdata and wfsuite.app.Page.apidata.formdata.fields
    if fields then
        for i = 1, #fields do
            if fields[i] and fields[i].apikey == "rates_type" then
                return fields[i].value
            end
        end
    end

    return nil
end

local function rightAlignText(width, text)
    local textWidth, _ = lcd.getTextSize(text)
    local padding = width - textWidth

    if padding > 0 then
        return string.rep(" ", math.floor(padding / lcd.getTextSize(" "))) .. text
    else
        return text
    end
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

    local longPage = false

    form.clear()

    wfsuite.app.ui.fieldHeader(title)
    local cols = wfsuite.app.Page.apidata.formdata.cols
    local visibleCols = buildVisibleColumns(cols)
    local numCols = #visibleCols
    local screenWidth = wfsuite.app.lcdWidth - 10
    local padding = 10
    local paddingTop = wfsuite.app.radio.linePaddingTop
    local h = wfsuite.app.radio.navbuttonHeight
    local w = ((screenWidth * 60 / 100) / numCols)
    local paddingRight = 20
    local positions = {}
    local pos

    local line = form.addLine("")

    local loc = numCols
    local posX = screenWidth - paddingRight
    local posY = paddingTop

    wfsuite.session.colWidth = w - paddingRight

    while loc > 0 do
        local sourceCol = visibleCols[loc]
        local colLabel = (cols and cols[sourceCol]) or tostring(sourceCol)

        positions[sourceCol] = posX - w

        lcd.font(FONT_STD)

        colLabel = rightAlignText(wfsuite.session.colWidth, colLabel)

        local posTxt = positions[sourceCol] + paddingRight

        pos = {x = posTxt, y = posY, w = w, h = h}
        wfsuite.app.formFields['col_' .. tostring(sourceCol)] = form.addStaticText(line, pos, colLabel)

        posX = math.floor(posX - w)

        loc = loc - 1
    end

    local fieldRows = {}
    for ri, rv in ipairs(wfsuite.app.Page.apidata.formdata.rows) do fieldRows[ri] = form.addLine(rv) end

    for i = 1, #wfsuite.app.Page.apidata.formdata.fields do
        local f = wfsuite.app.Page.apidata.formdata.fields[i]

        local valid = (f.apiversion == nil or wfsuite.utils.apiVersionCompare(">=", f.apiversion)) and (f.apiversionlt == nil or wfsuite.utils.apiVersionCompare("<", f.apiversionlt)) and (f.apiversiongt == nil or wfsuite.utils.apiVersionCompare(">", f.apiversiongt)) and (f.apiversionlte == nil or wfsuite.utils.apiVersionCompare("<=", f.apiversionlte)) and (f.apiversiongte == nil or wfsuite.utils.apiVersionCompare(">=", f.apiversiongte)) and (f.enablefunction == nil or f.enablefunction())

        if f.row and f.col and valid and positions[f.col] ~= nil then
            local l = wfsuite.app.Page.apidata.formdata.labels
            local pageIdx = i
            local currentField = i

            posX = positions[f.col]

            pos = {x = posX + padding, y = posY, w = w - padding, h = h}

            wfsuite.app.formFields[i] = form.addNumberField(fieldRows[f.row], pos, 0, 0, function()
                local page = wfsuite.app and wfsuite.app.Page
                if not (page and page.apidata and page.apidata.formdata and page.apidata.formdata.fields and page.apidata.formdata.fields[i]) then
                    if wfsuite.app and wfsuite.app.ui then
                        wfsuite.app.ui.disableAllFields()
                        wfsuite.app.ui.disableAllNavigationFields()
                        wfsuite.app.ui.enableNavigationField('menu')
                    end
                    return nil
                end
                return wfsuite.app.utils.getFieldValue(page.apidata.formdata.fields[i])
            end, function(value)
                local page = wfsuite.app and wfsuite.app.Page
                if not (page and page.apidata and page.apidata.formdata and page.apidata.formdata.fields and page.apidata.formdata.fields[i]) then
                    return
                end
                wfsuite.app.ui.markPageDirty()
                if f.postEdit then f.postEdit(page) end
                if f.onChange then f.onChange(page) end

                f.value = wfsuite.app.utils.saveFieldValue(page.apidata.formdata.fields[i], value)
            end)
        end
    end

    wfsuite.app.ui.setPageDirty(false)
end

local function postLoad(self)

    local v = getRateType()

    if v == nil then
        wfsuite.utils.log("Unable to resolve rates_type from RC_TUNING data", "warning")
        wfsuite.app.triggers.closeProgressLoader = true
        activateWakeup = true
        return
    end

    local activeRateTable = tonumber(wfsuite.session.activeRateTable) or wfsuite.session.activeRateTable
    local requestedRateTable = tonumber(v) or v

    wfsuite.utils.log("Active Rate Table: " .. tostring(activeRateTable), "debug")

    if requestedRateTable ~= activeRateTable then
        wfsuite.utils.log("Switching Rate Table: " .. tostring(requestedRateTable), "info")
        wfsuite.app.triggers.reloadFull = true
        wfsuite.session.activeRateTable = requestedRateTable
        return
    end

    wfsuite.app.triggers.closeProgressLoader = true
    activateWakeup = true
end

local function wakeup()
    if activateWakeup and wfsuite.tasks.msp.mspQueue:isProcessed() then

        local activeRateProfile = wfsuite.session and wfsuite.session.activeRateProfile
        if activeRateProfile ~= nil then
            local baseTitle = wfsuite.app.lastTitle or (wfsuite.app.Page and wfsuite.app.Page.title) or ""
            baseTitle = tostring(baseTitle):gsub("%s+#%d+$", "")
            wfsuite.app.ui.setHeaderTitle(baseTitle .. " #" .. activeRateProfile, nil, wfsuite.app.Page and wfsuite.app.Page.navButtons)
        end

        if doFullReload == true then
            wfsuite.utils.log("Reloading full after rate type change", "info")
            wfsuite.app.triggers.reload = true
            doFullReload = false
        end
    end
end

local function onToolMenu() end

local function canSave()
    local pref = wfsuite.preferences and wfsuite.preferences.general and wfsuite.preferences.general.save_dirty_only
    if pref == false or pref == "false" then return true end
    return wfsuite.app.pageDirty == true
end

return {apidata = apidata, title = "@i18n(app.modules.rates_advanced.name)@", onNavMenu = navHandlers.onNavMenu, event = navHandlers.event, reboot = false, openPage = openPage, eepromWrite = true, refreshOnRateChange = true, rTableName = rTableName, postLoad = postLoad, wakeup = wakeup, API = {}, onToolMenu = onToolMenu, canSave = canSave, navButtons = {menu = true, save = true, reload = true, tool = false, help = true}}
