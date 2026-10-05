-- Setup -> ESC & Motors -> Throttle page.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local pageRuntime = requireModule("app/page_runtime.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local motorConfig = requireModule("lib/msp_motor_config.lua")

local PAGE_TITLE = "@i18n(app.modules.esc_motors.throttle)@"

local PWM_RATE = "motor_pwm_rate"
local MINCOMMAND = "mincommand"
local MINTHROTTLE = "minthrottle"
local MAXTHROTTLE = "maxthrottle"
local UNSYNCED = "use_unsynced_pwm"

-- The Throttle Protocol values are named, not inlined: "no protocol known" used
-- to be a bare 10 here and in esc_motors_rpm.lua, and 10 is SRXL2 (see the enum in
-- lib/msp_motor_config.lua).
local DISABLED = motorConfig.DISABLED_PROTOCOL
local CASTLE = motorConfig.CASTLE_PROTOCOL
local SRXL2 = motorConfig.SRXL2_PROTOCOL

local function protocolOf(runtime)
  return tonumber(runtime.data.motor_pwm_protocol) or DISABLED
end

-- Whether the PWM-rate and throttle-window rows apply: 0..4, and the two
-- protocols the firmware drives as standard 1 ms PWM -- CASTLE and SRXL2
-- (pwmMotorConfig() in wingflight-firmware drivers/pwm_output.c). SRXL2 was
-- missing here. 4 is PWM_TYPE_RESERVED, only reachable when the FC already
-- reports it.
local function pwmFieldsEnabled(protocol)
  return protocol <= 4 or protocol == CASTLE or protocol == SRXL2
end

local function unsyncedEnabled(protocol)
  return protocol >= 1 and protocol <= 4
end

local function refreshProtocolFields(runtime)
  local protocol = protocolOf(runtime)
  local pwmEnabled = runtime.loaded and pwmFieldsEnabled(protocol) and not runtime.activeDialog
  local unsynced = runtime.loaded and unsyncedEnabled(protocol) and not runtime.activeDialog
  if runtime.data.use_unsynced_pwm == nil then runtime.data.use_unsynced_pwm = 0 end
  if runtime.fields[PWM_RATE] then runtime.fields[PWM_RATE]:enable(pwmEnabled) end
  if runtime.fields[MINCOMMAND] then runtime.fields[MINCOMMAND]:enable(pwmEnabled) end
  if runtime.fields[MINTHROTTLE] then runtime.fields[MINTHROTTLE]:enable(pwmEnabled) end
  if runtime.fields[MAXTHROTTLE] then runtime.fields[MAXTHROTTLE]:enable(pwmEnabled) end
  if runtime.fields[UNSYNCED] then runtime.fields[UNSYNCED]:enable(unsynced) end
end

local function open(opts)
  local lastProtocol = nil

  local runtime
  runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE,
    logTag = "esc_throttle",
    mspModule = motorConfig,
    opts = opts,
    profileField = "none",
    rebootAfterSave = true,
    unloadPackageKeys = {"wfsuite.lib.msp_motor_config"},
    onLoaded = function()
      lastProtocol = nil
      refreshProtocolFields(runtime)
    end,
    onWakeup = function(rt)
      local protocol = protocolOf(rt)
      if protocol ~= lastProtocol then
        lastProtocol = protocol
        refreshProtocolFields(rt)
      end
    end,
  })

  form.clear()
  runtime:buildChrome()

  fieldLayout.buildSingle(runtime, "@i18n(app.modules.esc_motors.throttle_protocol)@", {
    key = "motor_pwm_protocol",
    choices = motorConfig.PROTOCOL_CHOICES,
  })
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.esc_motors.motor_pwm_rate)@", {key = PWM_RATE})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.esc_motors.mincommand)@", {key = MINCOMMAND})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.esc_motors.min_throttle)@", {key = MINTHROTTLE})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.esc_motors.max_throttle)@", {key = MAXTHROTTLE})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.esc_motors.unsynced)@", {
    key = UNSYNCED,
    choices = motorConfig.ON_OFF_CHOICES,
  })

  runtime:loadInitial()
end

return {open = open}
