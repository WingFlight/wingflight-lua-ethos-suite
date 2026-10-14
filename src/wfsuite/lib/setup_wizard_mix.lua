-- The Setup Wizard's Airframe step: model types and the mixer rules each
-- one gets.
--
-- A port of wingflight-configurator src/js/Mixer.js (MODEL_TYPES and
-- buildWizardRules()). Keep the two in step; bin/tests/setup_wizard_mix.lua
-- checks the rules for each layout. Rules come out in lib/msp_mixer_rules.lua's
-- shape (input/output, where the JS has src/dst).

if package.loaded["wfsuite.lib.setup_wizard_mix"] then
  return package.loaded["wfsuite.lib.setup_wizard_mix"]
end

local M = {}

M.RULE_COUNT = 32
M.MOTOR_OUTPUT_OFFSET = 27
M.ROLE_FLAP_COMPENSATION = 1
M.ROLE_DIFFERENTIAL_THRUST_YAW = 2
M.MODEL_TYPE_CUSTOM = 5

-- mixerConfig_t.model_type (pg/mixer.h). Each of ailerons/tailControl/wingYaw
-- is omitted (not applicable), {fixed =} or {options =, default =}.
M.MODEL_TYPES = {
  {value = 0, key = "regular", layout = "conventional",
    ailerons = {options = {"none", "single", "independent"}, default = "independent"},
    tailControl = {options = {"elevatorOnly", "elevatorRudder"}, default = "elevatorRudder"}},
  {value = 1, key = "flyingWing", layout = "flyingWing",
    wingYaw = {options = {"none", "rudder"}, default = "rudder"}},
  {value = 2, key = "vTail", layout = "conventional",
    ailerons = {options = {"none", "single", "independent"}, default = "independent"},
    tailControl = {fixed = "vtail"}},
  {value = 3, key = "deltaWing", layout = "flyingWing",
    wingYaw = {options = {"none", "rudder"}, default = "rudder"}},
  {value = 4, key = "trainer", layout = "conventional",
    ailerons = {fixed = "none"},
    tailControl = {fixed = "elevatorRudder"}},
}

function M.typeOf(value)
  for _, t in ipairs(M.MODEL_TYPES) do
    if t.value == value then return t end
  end
  return nil
end

-- Default options for a type, as the Configurator's setup dialog opens with.
function M.defaultOptions(t)
  local function pick(o) return o and (o.default or o.fixed) or nil end
  return {
    layout = t.layout,
    ailerons = pick(t.ailerons) or "none",
    tailControl = pick(t.tailControl),
    wingYaw = pick(t.wingYaw) or "none",
    flaps = false,
    flapServos = 1,
    flapsFollowAilerons = false,
    motors = 1,
    diffThrustYaw = false,
  }
end

local OP_SET, OP_ADD = 1, 2
local ROLL, PITCH, YAW, THROTTLE, RC_AUX1 = 1, 2, 3, 4, 13
local TV_ROLL, TV_PITCH, TV_YAW = 27, 28, 29

local function rule(oper, input, output, weight, reverse, role)
  local w = reverse and -weight or weight
  return {oper = oper, input = input, output = output, offset = 0, weight = w, weightNeg = w,
    speed = 0, curve = 0, condition = 0, role = role or 0}
end

-- Rules for the airframe options, as Mixer.buildWizardRules().
function M.buildRules(options)
  local rules = {}
  local nextServo = 1
  local nextMotor = M.MOTOR_OUTPUT_OFFSET
  local pitchOutputs, aileronOutputs = {}, {}
  local function add(r) rules[#rules + 1] = r end
  local function servo() local s = nextServo; nextServo = nextServo + 1; return s end

  if options.layout == "conventional" then
    if options.ailerons == "single" then
      add(rule(OP_SET, ROLL, servo(), 1000))
    elseif options.ailerons == "independent" then
      local left, right = servo(), servo()
      add(rule(OP_SET, ROLL, left, 1000))
      add(rule(OP_SET, ROLL, right, 1000, true))
      aileronOutputs[#aileronOutputs + 1] = left
      aileronOutputs[#aileronOutputs + 1] = right
    end

    if options.tailControl == "elevatorOnly" then
      local elevator = servo()
      add(rule(OP_SET, PITCH, elevator, 1000))
      pitchOutputs[#pitchOutputs + 1] = elevator
    elseif options.tailControl == "elevatorRudder" then
      local elevator = servo()
      add(rule(OP_SET, PITCH, elevator, 1000))
      pitchOutputs[#pitchOutputs + 1] = elevator
      add(rule(OP_SET, YAW, servo(), 1000))
    elseif options.tailControl == "vtail" then
      local rightTail, leftTail = servo(), servo()
      add(rule(OP_SET, YAW, rightTail, 1000))
      add(rule(OP_ADD, PITCH, rightTail, 1000))
      add(rule(OP_SET, YAW, leftTail, 1000, true))
      add(rule(OP_ADD, PITCH, leftTail, 1000))
      pitchOutputs[#pitchOutputs + 1] = rightTail
      pitchOutputs[#pitchOutputs + 1] = leftTail
    end
  elseif options.layout == "flyingWing" then
    local left, right = servo(), servo()
    add(rule(OP_SET, PITCH, left, 1000))
    add(rule(OP_ADD, ROLL, left, 1000))
    add(rule(OP_SET, PITCH, right, 1000))
    add(rule(OP_ADD, ROLL, right, 1000, true))
    pitchOutputs[#pitchOutputs + 1] = left
    pitchOutputs[#pitchOutputs + 1] = right
    if options.wingYaw == "rudder" then
      add(rule(OP_SET, YAW, servo(), 1000))
    end
  end

  -- flapServos 0 means flaperons, only possible with independent ailerons.
  local flaperons = options.flaps and options.flapServos == 0
  local flaps
  if flaperons then flaps = #aileronOutputs == 2 else flaps = options.flaps end

  if flaps then
    if flaperons then
      for _, output in ipairs(aileronOutputs) do
        add(rule(OP_ADD, RC_AUX1, output, 500))
      end
    elseif (options.flapServos or 1) >= 2 then
      local leftFlap, rightFlap = servo(), servo()
      add(rule(OP_SET, RC_AUX1, leftFlap, 1000))
      add(rule(OP_SET, RC_AUX1, rightFlap, 1000))
      if options.flapsFollowAilerons and #aileronOutputs == 2 then
        add(rule(OP_ADD, ROLL, leftFlap, 500))
        add(rule(OP_ADD, ROLL, rightFlap, 500, true))
      end
    else
      add(rule(OP_SET, RC_AUX1, servo(), 1000))
    end
    -- Flap compensation placeholders, zero weight, to tune in later.
    for _, output in ipairs(pitchOutputs) do
      add(rule(OP_ADD, RC_AUX1, output, 0, false, M.ROLE_FLAP_COMPENSATION))
    end
  end

  local motor1
  if (options.motors or 0) >= 1 then
    motor1 = nextMotor
    nextMotor = nextMotor + 1
    add(rule(OP_SET, THROTTLE, motor1, 1000))
  end
  if (options.motors or 0) >= 2 then
    local motor2 = nextMotor
    add(rule(OP_SET, THROTTLE, motor2, 1000))
    if options.diffThrustYaw then
      add(rule(OP_ADD, YAW, motor1, 500, false, M.ROLE_DIFFERENTIAL_THRUST_YAW))
      add(rule(OP_ADD, YAW, motor2, 500, true, M.ROLE_DIFFERENTIAL_THRUST_YAW))
    end
  end

  if options.thrustVectorRoll then add(rule(OP_SET, TV_ROLL, servo(), 1000)) end
  if options.thrustVectorPitch then add(rule(OP_SET, TV_PITCH, servo(), 1000)) end
  if options.thrustVectorYaw then add(rule(OP_SET, TV_YAW, nextServo, 1000)) end

  return rules
end

-- The full RULE_COUNT table: the generated rules, then unused slots.
function M.ruleTable(options)
  local generated = M.buildRules(options)
  local out = {}
  for i = 1, M.RULE_COUNT do
    out[i] = generated[i] or {oper = 0, input = 0, output = 0, offset = 0, weight = 0, weightNeg = 0,
      speed = 0, curve = 0, condition = 0, role = 0}
  end
  return out
end

-- Highest servo number (1-based) the options use, for the board check.
function M.servosUsed(rules)
  local most = 0
  for _, r in ipairs(rules) do
    if r.oper ~= 0 and r.output >= 1 and r.output < M.MOTOR_OUTPUT_OFFSET and r.output > most then
      most = r.output
    end
  end
  return most
end

package.loaded["wfsuite.lib.setup_wizard_mix"] = M
return M
