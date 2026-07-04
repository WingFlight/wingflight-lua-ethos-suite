--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 -- https://www.gnu.org/licenses/gpl-3.0.en.html
]] --


local apidata = {
    api = {
        {id = 1, name = "MIXER_INPUT_ROLL"},
        {id = 2, name = "MIXER_INPUT_PITCH"},
        {id = 3, name = "MIXER_INPUT_YAW"},
    },
    formdata = {
        labels = {},
        fields = {
            { t = "@i18n(app.modules.mixer.roll)@ @i18n(app.modules.mixer.gain)@", mspapi = 1, apikey = "gain" },
            { t = "@i18n(app.modules.mixer.roll)@ @i18n(app.modules.mixer.invert)@", mspapi = 1, apikey = "invert", type = 1 },
            { t = "@i18n(app.modules.mixer.pitch)@ @i18n(app.modules.mixer.gain)@", mspapi = 2, apikey = "gain" },
            { t = "@i18n(app.modules.mixer.pitch)@ @i18n(app.modules.mixer.invert)@", mspapi = 2, apikey = "invert", type = 1 },
            { t = "@i18n(app.modules.mixer.yaw)@ @i18n(app.modules.mixer.gain)@", mspapi = 3, apikey = "gain" },
            { t = "@i18n(app.modules.mixer.yaw)@ @i18n(app.modules.mixer.invert)@", mspapi = 3, apikey = "invert", type = 1 },
        }
    }
}

return {apidata = apidata, eepromWrite = true, reboot = false, API = {}}
