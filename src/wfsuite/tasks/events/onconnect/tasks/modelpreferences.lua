--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local modelpreferences = {}

local modelpref_defaults = {dashboard = {theme_preflight = "nil", theme_inflight = "nil", theme_postflight = "nil"}, general = {flightcount = 0, totalflighttime = 0, lastflighttime = 0, batterylocalcalculation = 1}, battery = {smartfuel_model_type = 0, smartfuel_source = 0, stabilize_delay = 1500, stable_window = 15, voltage_fall_limit = 5, fuel_drop_rate = 10, sag_multiplier_percent = 70, sag_multiplier = 0.7, calc_local = 0, alert_type = 0, becalertvalue = 6.5, rxalertvalue = 7.5, flighttime = 300}}

function modelpreferences.wakeup()

    if wfsuite.session.apiVersion == nil then
        wfsuite.session.modelPreferences = nil
        return
    end

    if wfsuite.session.mspBusy then return end

    if not wfsuite.session.mcu_id then
        wfsuite.session.modelPreferences = nil
        return
    end

    if (wfsuite.session.modelPreferences == nil) then

        if wfsuite.config.preferences and wfsuite.session.mcu_id then

            local modelpref_file = "SCRIPTS:/" .. wfsuite.config.preferences .. "/models/" .. wfsuite.session.mcu_id .. ".ini"
            wfsuite.utils.log("Preferences file: " .. modelpref_file, "info")

            os.mkdir("SCRIPTS:/" .. wfsuite.config.preferences)
            os.mkdir("SCRIPTS:/" .. wfsuite.config.preferences .. "/models")

            local slave_ini = modelpref_defaults
            local master_ini = wfsuite.ini.load_ini_file(modelpref_file) or {}

            local updated_ini = wfsuite.ini.merge_ini_tables(master_ini, slave_ini)
            wfsuite.session.modelPreferences = updated_ini
            wfsuite.session.modelPreferencesFile = modelpref_file

            if not wfsuite.ini.ini_tables_equal(master_ini, slave_ini) then wfsuite.ini.save_ini_file(modelpref_file, updated_ini) end

        end
    end

end

function modelpreferences.reset()
    wfsuite.session.modelPreferences = nil
    wfsuite.session.modelPreferencesFile = nil
end

function modelpreferences.isComplete() if wfsuite.session.modelPreferences ~= nil then return true end end

return modelpreferences
