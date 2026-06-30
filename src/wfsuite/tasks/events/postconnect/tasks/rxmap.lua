--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local rxmap = {}

local mspCallMade = false
local API_NAME = "RX_MAP"

local function clearApiEntry()
    local api = wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.api
    if api and type(api.clearEntry) == "function" then
        api.clearEntry(API_NAME)
    end
end

function rxmap.wakeup()

    if wfsuite.session.apiVersion == nil then return end

    if wfsuite.session.mspBusy then return end

    if not wfsuite.utils.rxmapReady() and mspCallMade == false then
        mspCallMade = true
        local API = wfsuite.tasks.msp.api.load(API_NAME)
        if API and API.enableDeltaCache then API.enableDeltaCache(false) end
        API.setCompleteHandler(function(self, buf)

            local aileron = API.readValue("aileron")
            local elevator = API.readValue("elevator")
            local rudder = API.readValue("rudder")
            local throttle = API.readValue("throttle")
            local aux1 = API.readValue("aux1")
            local aux2 = API.readValue("aux2")
            local aux3 = API.readValue("aux3")
            local aux4 = API.readValue("aux4")

            wfsuite.session.rx.map.aileron = aileron
            wfsuite.session.rx.map.elevator = elevator
            wfsuite.session.rx.map.rudder = rudder
            wfsuite.session.rx.map.throttle = throttle
            wfsuite.session.rx.map.aux1 = aux1
            wfsuite.session.rx.map.aux2 = aux2
            wfsuite.session.rx.map.aux3 = aux3
            wfsuite.session.rx.map.aux4 = aux4

            wfsuite.utils.log("RX Map: Aileron: " .. aileron .. ", Elevator: " .. elevator .. ", Rudder: " .. rudder .. ", Throttle: " .. throttle .. ", Aux1: " .. aux1 .. ", Aux2: " .. aux2 .. ", Aux3: " .. aux3 .. ", Aux4: " .. aux4, "info")
            wfsuite.utils.log("RX Map: Ail: " .. aileron .. ", Elev: " .. elevator .. ", Rud: " .. rudder .. ", Thr: " .. throttle , "connect")

            clearApiEntry()
        end)
        API.setErrorHandler(function() clearApiEntry() end)
        API.setUUID("postconnect-rxmap-read")
        API.read()
    end

end

function rxmap.reset()
    clearApiEntry()
    if wfsuite.session.rx and wfsuite.session.rx.map then for _, key in ipairs({"aileron", "elevator", "rudder", "throttle", "aux1", "aux2", "aux3", "aux4"}) do wfsuite.session.rx.map[key] = nil end end
    wfsuite.session.rxmap = {}
    wfsuite.session.rxvalues = {}
    mspCallMade = false
end

function rxmap.isComplete() return wfsuite.utils.rxmapReady() end

return rxmap
