--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()
local lcd = lcd

local function loadMask(path)
    local ui = wfsuite.app and wfsuite.app.ui
    if ui and ui.loadMask then return ui.loadMask(path) end
    return lcd.loadMask(path)
end

local mspSignature
local mspBytes
local escDetails = {}
local foundESC = false
local foundESCupdateTag = false
local showPowerCycleLoader = false
local showPowerCycleLoaderInProgress = false
local ESC
local powercycleLoader
local powercycleLoaderCounter = 0
local powercycleLoaderRateLimit = 2
local showPowerCycleLoaderFinished = false
local powercycleLoaderBaseMessage
local findTimeoutClock = os.clock()
local findTimeout = math.floor(wfsuite.tasks.msp.protocol.pageReqTimeout * 0.5)
local escDetailsNextReadAt = 0
local escDetailsApiName
local escDetailsApi
local escDetailsHandlersApi

local modelLine
local modelText
local modelTextPos = {x = 0, y = wfsuite.app.radio.linePaddingTop, w = wfsuite.app.lcdWidth, h = wfsuite.app.radio.navbuttonHeight}
local function noop() end
local toolButtonMeta = {}
local toolButtonHandlers = {}

local function openProgressDialog(...)
    if wfsuite.utils.ethosVersionAtLeast({26, 1, 0}) and form.openWaitDialog then
        local arg1 = select(1, ...)
        if type(arg1) == "table" then
            arg1.progress = true
            return form.openWaitDialog(arg1)
        end
        local title = arg1
        local message = select(2, ...)
        return form.openWaitDialog({title = title, message = message, progress = true})
    end
    return form.openProgressDialog(...)
end


-- Update the model/version header without creating overlapping widgets.
-- Ethos keeps old widgets; re-adding at the same position can overlay text (e.g. "UNKNOWN" over the real value).
local function setModelHeaderText(text)
    if not modelLine then return end
    if not modelText then
        modelText = form.addStaticText(modelLine, modelTextPos, text or "")
        return
    end
    local ok = pcall(function() modelText:value(text or "") end)
    if not ok then
        -- Fallback for older widget types: recreate once
        modelText = form.addStaticText(modelLine, modelTextPos, text or "")
    end
end

local mspBusy = false

local function getEscDetailsPollInterval()
    local interval = tonumber(ESC and ESC.escDetailsPollInterval)
    if interval == nil then interval = 0.35 end
    if interval < 0 then interval = 0 end
    return interval
end

local function getEscDetailsRetryInterval()
    local interval = tonumber(ESC and ESC.escDetailsRetryInterval)
    if interval == nil then interval = 0.9 end
    if interval < 0 then interval = 0 end
    return interval
end

local function scheduleEscDetailsReadAt(delaySeconds)
    local delay = tonumber(delaySeconds) or 0
    if delay < 0 then delay = 0 end
    local nextAt = os.clock() + delay
    if nextAt > escDetailsNextReadAt then
        escDetailsNextReadAt = nextAt
    end
end

local function getEscDetailsAPI()
    if not ESC or not ESC.mspapi then return nil end
    if escDetailsApi and escDetailsApiName == ESC.mspapi then
        return escDetailsApi
    end
    escDetailsApi = wfsuite.tasks.msp.api.loadPage(ESC.mspapi)
    if escDetailsApi then
        escDetailsApiName = ESC.mspapi
    else
        escDetailsApiName = nil
    end
    return escDetailsApi
end

local function detachEscApiHandlers(api)
    if not api then return end
    if api.setCompleteHandler then pcall(api.setCompleteHandler, noop) end
    if api.setErrorHandler then pcall(api.setErrorHandler, noop) end
end

local function onEscDetailsReadComplete(_, buf)
    local API = escDetailsApi
    if not API then
        mspBusy = false
        scheduleEscDetailsReadAt(getEscDetailsRetryInterval())
        return
    end
    if not ESC then
        mspBusy = false
        return
    end

    local signature = API.readValue("esc_signature")

    if signature == mspSignature and #buf >= mspBytes then
        escDetails.model = ESC.getEscModel(buf)
        escDetails.version = ESC.getEscVersion(buf)
        escDetails.firmware = ESC.getEscFirmware(buf)

        wfsuite.session.escDetails = escDetails

        if ESC.mspBufferCache == true then wfsuite.session.escBuffer = buf end

        if escDetails.model ~= nil then
            foundESC = true
        end
    else
        scheduleEscDetailsReadAt(getEscDetailsRetryInterval())
    end
    mspBusy = false
end

local function onEscDetailsReadError()
    scheduleEscDetailsReadAt(getEscDetailsRetryInterval())
    mspBusy = false
end

local function installEscDetailsHandlers(api)
    if not api or escDetailsHandlersApi == api then return end
    api.setCompleteHandler(onEscDetailsReadComplete)
    api.setErrorHandler(onEscDetailsReadError)
    escDetailsHandlersApi = api
end

local function clearButtonMeta(meta)
    for k in pairs(meta) do
        meta[k] = nil
    end
end

local function clearButtonCache(meta, handlers)
    clearButtonMeta(meta)
    for k in pairs(handlers) do
        handlers[k] = nil
    end
end

local function pressToolButton(childIdx)
    local meta = toolButtonMeta[childIdx]
    if not meta then return end

    wfsuite.preferences.menulastselected["esctool"] = childIdx
    if wfsuite.session then
        wfsuite.session.escToolKeepSessionOnce = true
    end
    wfsuite.app.ui.progressDisplay(nil, nil, wfsuite.app.loaderSpeed.DEFAULT)

    wfsuite.app.ui.openPage({
        idx = childIdx,
        title = meta.childTitle,
        script = meta.script,
        returnContext = {
            idx = meta.parentIdx,
            title = meta.title,
            folder = meta.folder,
            script = "esc_tools/tools/esc_tool.lua"
        }
    })
end

local function getToolButtonHandler(childIdx)
    local handler = toolButtonHandlers[childIdx]
    if handler then return handler end
    handler = function()
        pressToolButton(childIdx)
    end
    toolButtonHandlers[childIdx] = handler
    return handler
end

local function clearEscQueueEntries(apiName)
    if type(apiName) ~= "string" or apiName == "" then return end
    local queue = wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.mspQueue
    if queue and type(queue.removeQueuedBy) == "function" then
        queue:removeQueuedBy(function(msg)
            return msg and msg.apiname == apiName
        end)
    end
end

local function clearEscApiCache()
    local apiName = ESC and ESC.mspapi
    if type(apiName) ~= "string" or apiName == "" then return end
    local api = wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.api
    if api and type(api.clearEntry) == "function" then
        api.clearEntry(apiName)
        return
    end

    local apidata = api and api.apidata
    if type(apidata) ~= "table" then return end
    if apidata.values then apidata.values[apiName] = nil end
    if apidata.structure then apidata.structure[apiName] = nil end
    if apidata.receivedBytes then apidata.receivedBytes[apiName] = nil end
    if apidata.receivedBytesCount then apidata.receivedBytesCount[apiName] = nil end
    if apidata.positionmap then apidata.positionmap[apiName] = nil end
    if apidata.other then apidata.other[apiName] = nil end
    if apidata._lastReadMode then apidata._lastReadMode[apiName] = nil end
    if apidata._lastWriteMode then apidata._lastWriteMode[apiName] = nil end
end

local function clearEscMaskCache()
    local ui = wfsuite.app and wfsuite.app.ui
    local cache = ui and ui._maskCache
    local order = ui and ui._maskCacheOrder
    if type(cache) ~= "table" then return end

    local prefix = "app/modules/esc_tools/tools/escmfg/"
    local removed = false
    for path in pairs(cache) do
        if type(path) == "string" and path:sub(1, #prefix) == prefix then
            cache[path] = nil
            removed = true
        end
    end
    if not removed or type(order) ~= "table" then return end

    local writeIdx = 1
    for i = 1, #order do
        local path = order[i]
        if cache[path] ~= nil then
            order[writeIdx] = path
            writeIdx = writeIdx + 1
        end
    end
    for i = writeIdx, #order do
        order[i] = nil
    end
end

local function getESCDetails()
    if not ESC then return end
    if not ESC.mspapi then return end
    if not mspSignature then return end
    if not mspBytes then return end
    if os.clock() < escDetailsNextReadAt then return end
    if mspBusy == true then
       if wfsuite.tasks.msp.mspQueue:isProcessed() then
           mspBusy = false
       end
       return
    end
    if not wfsuite.tasks.msp.mspQueue:isProcessed() then return end

    if wfsuite.session.escDetails ~= nil then
        escDetails = wfsuite.session.escDetails
        foundESC = true
        return
    end

    if foundESC == true then return end

    mspBusy = true

    local API = getEscDetailsAPI()
    if not API then
        mspBusy = false
        scheduleEscDetailsReadAt(getEscDetailsRetryInterval())
        return
    end
    installEscDetailsHandlers(API)

    API.setUUID(wfsuite.utils and wfsuite.utils.uuid and wfsuite.utils.uuid() or tostring(os.clock()))
    local ok, reason = API.read()
    if ok then
        if reason == "queued_busy" then
            scheduleEscDetailsReadAt(getEscDetailsRetryInterval())
        else
            scheduleEscDetailsReadAt(getEscDetailsPollInterval())
        end
    else
        mspBusy = false
        scheduleEscDetailsReadAt(getEscDetailsRetryInterval())
    end

end

local function updatePowercycleLoaderMessage()
    if not powercycleLoader or not powercycleLoaderBaseMessage then return end
    if wfsuite.app and wfsuite.app.ui and wfsuite.app.ui.updateProgressDialogMessage then
        wfsuite.app.ui.updateProgressDialogMessage()
    end
end

local function clearPowercycleLoader()
    if powercycleLoader then
        pcall(function() powercycleLoader:close() end)
        if wfsuite.app and wfsuite.app.ui and wfsuite.app.ui.clearProgressDialog then
            wfsuite.app.ui.clearProgressDialog(powercycleLoader)
        end
    end
    powercycleLoader = nil
    powercycleLoaderBaseMessage = nil
    showPowerCycleLoader = false
    showPowerCycleLoaderInProgress = false
    showPowerCycleLoaderFinished = false
end

local function clearEscSessionCache()
    if wfsuite.session then
        wfsuite.session.escDetails = nil
        wfsuite.session.escBuffer = nil
    end
    escDetails = {}
end

local function openPage(opts)

    local parentIdx = opts.idx
    local title = opts.title
    local folder = opts.folder
    local script = opts.script

    if type(folder) ~= "string" or folder == "" then
        folder = title
    end

    local keepEscSessionHot = (wfsuite.session and wfsuite.session.escToolKeepSessionOnce == true) or (type(opts.returnStack) == "table")
    if wfsuite.session then
        wfsuite.session.escToolKeepSessionOnce = nil
    end
    if not keepEscSessionHot then
        clearEscSessionCache()
    end

    foundESC = false
    foundESCupdateTag = false
    mspBusy = false
    showPowerCycleLoader = false
    showPowerCycleLoaderInProgress = false
    showPowerCycleLoaderFinished = false
    powercycleLoader = nil
    powercycleLoaderBaseMessage = nil
    powercycleLoaderCounter = 0
    powercycleLoaderRateLimit = 2
    escDetailsNextReadAt = 0
    findTimeoutClock = os.clock()
    mspSignature = nil
    mspBytes = nil
    escDetailsApi = nil
    escDetailsApiName = nil

    ESC = assert(loadfile("app/modules/esc_tools/tools/escmfg/" .. folder .. "/init.lua"))()

    if wfsuite.app and wfsuite.app.Page and ESC and ESC.mspapi then
        wfsuite.app.Page.apidata = wfsuite.app.Page.apidata or {}
        wfsuite.app.Page.apidata.api = {ESC.mspapi}
    end

    if ESC.mspapi ~= nil then

        local API = getEscDetailsAPI()
        if API then
            mspSignature = API.mspSignature
            local expectedResponse = API.simulatorResponse or {0}
            mspBytes = #expectedResponse
        end
    else

        mspSignature = ESC.mspSignature
        local expectedResponse = ESC.simulatorResponse or {0}
        mspBytes = ESC.mspBytes or #expectedResponse
    end

    local app = wfsuite.app
    if app.formFields then for k in pairs(app.formFields) do app.formFields[k] = nil end end
    if app.formLines then for k in pairs(app.formLines) do app.formLines[k] = nil end end

    local y = wfsuite.app.radio.linePaddingTop

    form.clear()

    local headerTitle = title
    if type(headerTitle) ~= "string" or headerTitle == "" then
        headerTitle = "@i18n(app.modules.esc_tools.name)@" .. " / " .. ESC.toolName
    end
    wfsuite.app.ui.fieldHeader(headerTitle)

    ESC.pages = assert(loadfile("app/modules/esc_tools/tools/escmfg/" .. folder .. "/pages.lua"))()

    modelLine = form.addLine("")
    modelText = form.addStaticText(modelLine, modelTextPos, "")
    clearButtonMeta(toolButtonMeta)

    local buttonW
    local buttonH
    local padding
    local numPerRow

    if wfsuite.preferences.general.iconsize == nil or wfsuite.preferences.general.iconsize == "" then
        wfsuite.preferences.general.iconsize = 1
    else
        wfsuite.preferences.general.iconsize = tonumber(wfsuite.preferences.general.iconsize)
    end

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

    if wfsuite.app.gfx_buttons["esctool"] == nil then wfsuite.app.gfx_buttons["esctool"] = {} end
    if wfsuite.preferences.menulastselected["esctool"] == nil then wfsuite.preferences.menulastselected["esctool"] = 1 end

    for childIdx, pvalue in ipairs(ESC.pages) do

        local section = pvalue
        local hideSection = (section.ethosversion and wfsuite.session.ethosRunningVersion < section.ethosversion) or (section.mspversion and wfsuite.utils.apiVersionCompare("<", section.mspversion))

        if not pvalue.disablebutton or (pvalue and pvalue.disablebutton(mspBytes) == false) or not hideSection then

            if lc == 0 then
                if wfsuite.preferences.general.iconsize == 0 then y = form.height() + wfsuite.app.radio.buttonPaddingSmall end
                if wfsuite.preferences.general.iconsize == 1 then y = form.height() + wfsuite.app.radio.buttonPaddingSmall end
                if wfsuite.preferences.general.iconsize == 2 then y = form.height() + wfsuite.app.radio.buttonPadding end
            end

            if lc >= 0 then bx = (buttonW + padding) * lc end

            if wfsuite.preferences.general.iconsize ~= 0 then
                if wfsuite.app.gfx_buttons["esctool"][pvalue.image] == nil then wfsuite.app.gfx_buttons["esctool"][pvalue.image] = loadMask("app/modules/esc_tools/tools/escmfg/" .. folder .. "/gfx/" .. pvalue.image) end
            else
                wfsuite.app.gfx_buttons["esctool"][pvalue.image] = nil
            end

            toolButtonMeta[childIdx] = {
                parentIdx = parentIdx,
                title = title,
                folder = folder,
                childTitle = title .. " / " .. pvalue.title,
                script = "esc_tools/tools/escmfg/" .. folder .. "/pages/" .. pvalue.script
            }

            wfsuite.app.formFields[childIdx] = form.addButton(nil, {x = bx, y = y, w = buttonW, h = buttonH}, {
                text = pvalue.title,
                icon = wfsuite.app.gfx_buttons["esctool"][pvalue.image],
                options = FONT_S,
                paint = noop,
                press = getToolButtonHandler(childIdx)
            })

            if wfsuite.preferences.menulastselected["esctool"] == childIdx then wfsuite.app.formFields[childIdx]:focus() end

            if wfsuite.app.triggers.escToolEnableButtons == true then
                wfsuite.app.formFields[childIdx]:enable(true)
            else
                wfsuite.app.formFields[childIdx]:enable(false)
            end

            lc = lc + 1

            if lc == numPerRow then lc = 0 end
        end

    end

    wfsuite.app.triggers.escToolEnableButtons = false

end

local function closePage()
    local keepEscSessionHot = wfsuite.session and wfsuite.session.escToolKeepSessionOnce == true
    if wfsuite.session then
        wfsuite.session.escToolKeepSessionOnce = nil
    end

    clearPowercycleLoader()

    if wfsuite.app then
        wfsuite.app.escPowerCycleLoader = false
        if wfsuite.app.triggers then
            wfsuite.app.triggers.disableRssiTimeout = false
        end
        if wfsuite.app.gfx_buttons then
            wfsuite.app.gfx_buttons["esctool"] = nil
        end
    end

    if ESC and ESC.mspapi then
        clearEscQueueEntries(ESC.mspapi)
    end
    detachEscApiHandlers(escDetailsApi)
    clearEscApiCache()
    clearEscMaskCache()
    clearButtonCache(toolButtonMeta, toolButtonHandlers)

    if not keepEscSessionHot then
        clearEscSessionCache()
    end

    mspBusy = false
    escDetailsNextReadAt = 0
    escDetailsApi = nil
    escDetailsApiName = nil
    escDetailsHandlersApi = nil
    mspSignature = nil
    mspBytes = nil
    foundESC = false
    foundESCupdateTag = false
    powercycleLoaderCounter = 0
    powercycleLoaderRateLimit = 2
    findTimeoutClock = os.clock()
    modelLine = nil
    modelText = nil
    ESC = nil
end

local function onNavMenu()
    closePage()
    pageRuntime.openMenuContext({defaultSection = "system"})
    return true
end

local function onReloadMenu()
    closePage()
    wfsuite.app.Page = nil
    wfsuite.app.triggers.triggerReloadFull = true
    return true
end

local function wakeup()

    if foundESC == false then
        getESCDetails()
    end

    if foundESC == true and foundESCupdateTag == false then
        foundESCupdateTag = true

        if escDetails.model ~= nil and escDetails.model ~= nil and escDetails.firmware ~= nil then
            local text = escDetails.model .. " " .. escDetails.version .. " " .. escDetails.firmware
            wfsuite.escHeaderLineText = text
            setModelHeaderText(text)
        end

        for i, v in ipairs(wfsuite.app.formFields) do wfsuite.app.formFields[i]:enable(true) end

        detachEscApiHandlers(escDetailsApi)
        if ESC and ESC.mspBufferCache ~= true then
            clearEscApiCache()
        end

        if ESC and ESC.powerCycle == true and showPowerCycleLoader == true then
            powercycleLoader:close()
            wfsuite.app.ui.clearProgressDialog(powercycleLoader)
            powercycleLoaderCounter = 0
            showPowerCycleLoaderInProgress = false
            showPowerCycleLoader = false
            showPowerCycleLoaderFinished = true
            wfsuite.app.triggers.isReady = true
            powercycleLoaderBaseMessage = nil
        end

        wfsuite.app.triggers.closeProgressLoader = true

    end

    if showPowerCycleLoaderFinished == false and foundESCupdateTag == false and showPowerCycleLoader == false and ((findTimeoutClock <= os.clock() - findTimeout) or wfsuite.app.dialogs.progressCounter >= 101) then
        wfsuite.app.dialogs.progress:close()
        wfsuite.app.dialogs.progressDisplay = false
        wfsuite.app.triggers.isReady = true

        if ESC and ESC.powerCycle ~= true then setModelHeaderText("@i18n(app.modules.esc_tools.unknown)@") end

        if ESC and ESC.powerCycle == true then showPowerCycleLoader = true end

    end

    if showPowerCycleLoaderInProgress == true then

        wfsuite.app.escPowerCycleLoader = true

        local now = os.clock()
        if (now - powercycleLoaderRateLimit) >= 2 then

            powercycleLoaderRateLimit = now
            powercycleLoaderCounter = powercycleLoaderCounter + 5
            powercycleLoader:value(powercycleLoaderCounter)
            updatePowercycleLoaderMessage()

            if powercycleLoaderCounter >= 100 then
                powercycleLoader:close()
                wfsuite.app.ui.clearProgressDialog(powercycleLoader)
                setModelHeaderText("@i18n(app.modules.esc_tools.unknown)@")
                showPowerCycleLoaderInProgress = false
                wfsuite.app.triggers.disableRssiTimeout = false
                showPowerCycleLoader = false
                wfsuite.app.audio.playTimeout = true
            showPowerCycleLoaderFinished = true
            wfsuite.app.triggers.isReady = false
            powercycleLoaderBaseMessage = nil
        end

    end
    else
        wfsuite.app.escPowerCycleLoader = false
    end

    if showPowerCycleLoader == true then
        if showPowerCycleLoaderInProgress == false then
            showPowerCycleLoaderInProgress = true
            wfsuite.app.audio.playEscPowerCycle = true
            wfsuite.app.triggers.disableRssiTimeout = true
            powercycleLoader = openProgressDialog("@i18n(app.modules.esc_tools.searching)@", "@i18n(app.modules.esc_tools.please_powercycle)@")
            powercycleLoader:value(0)
            powercycleLoader:closeAllowed(false)
            powercycleLoaderBaseMessage = "@i18n(app.modules.esc_tools.please_powercycle)@"
            updatePowercycleLoaderMessage()
            wfsuite.app.ui.registerProgressDialog(powercycleLoader, powercycleLoaderBaseMessage)
        end
    end

end

local function event(widget, category, value, x, y)
    return pageRuntime.handleCloseEvent(category, value, {onClose = function()
        onNavMenu()
    end})

end

return {
    openPage = openPage,
    wakeup = wakeup,
    event = event,
    close = closePage,
    onNavMenu = onNavMenu,
    onReloadMenu = onReloadMenu,
    navButtons = {menu = true, save = false, reload = true, tool = false, help = false},
    API = {}
}
