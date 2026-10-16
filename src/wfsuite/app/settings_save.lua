-- Reports a local settings save that the store refused (issue #2500).
--
-- settingsStore.save() and modelPreferences.save() return false when the INI
-- file cannot be written. Every local settings page calls this when that happens,
-- so no page can drop the failure again: the page keeps its dirty state (the
-- Save button stays lit), publishes nothing, and the pilot sees a dialog.
--
-- Two texts, because one page writes both halves in one press: the dashboard
-- theme page saves the global settings and then the model's dashboard override.
-- If only the model's half is refused, the global one is already on disk, so
-- "settings were not saved to the radio" would claim more was lost than
-- actually was. That page calls reportModelFailure() and names the half.

local settingsSave = {}

local MSG_TITLE = "@i18n(app.msg_save_failed_title)@"
local MSG_BODY = "@i18n(app.msg_save_failed_local_body)@"
local MSG_MODEL_BODY = "@i18n(app.msg_save_failed_model_body)@"
local BTN_OK = "@i18n(app.btn_ok)@"

-- focusFn returns focus to the Save button once the dialog is closed.
local function report(message, focusFn)
  if not (form and type(form.openDialog) == "function") then return end
  form.openDialog({
    title = MSG_TITLE,
    message = message,
    buttons = {
      {
        label = BTN_OK,
        action = function()
          if focusFn then focusFn() end
          return true
        end,
      },
    },
    wakeup = function() end,
    paint = function() end,
  })
end

function settingsSave.reportFailure(focusFn)
  report(MSG_BODY, focusFn)
end

-- The model's INI was refused while the global settings did save. See the file
-- header: the dialog must not read as if nothing was written.
function settingsSave.reportModelFailure(focusFn)
  report(MSG_MODEL_BODY, focusFn)
end

return settingsSave
