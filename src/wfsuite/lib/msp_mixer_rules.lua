-- Schema + message-builders for the MSP_MIXER_RULES / MSP_SET_MIXER_RULE
-- command pair (cmd 172 read / 173 write) -- the 32-slot mixer rule table
-- (app/pages/mixer_rules.lua), distinct from both app/pages/mixer_config.lua's
-- MSP_MIXER_INPUT (per-axis Roll/Pitch/Yaw gain scaling) and
-- lib/msp_mixer_curves.lua's MSP_MIXER_CURVES (the curve *shapes* a rule's
-- `curve` field can reference).
--
-- **Wire layout below is derived from wingflight-configurator's own
-- src/js/msp/MSPHelper.js (MIXER_RULES parser / sendMixerRule encoder),
-- cross-checked against wingflight-firmware's actual
-- src/main/msp/msp.c serializer (the MSP_MIXER_RULES/MSP_SET_MIXER_RULE
-- cases) -- unlike lib/msp_mixer_curves.lua/lib/msp_gain_curves.lua's own
-- headers, this one WAS checked directly against firmware source, not just
-- the ground station's implementation.**
--
-- Same asymmetric GET-whole-pool/SET-one-rule shape as the curve pools:
-- GET returns all MIXER_RULE_COUNT rules back to back, no index/count
-- prefix; SET writes exactly one rule, index-prefixed. Unlike a curve, a
-- rule has no point-array substructure -- it's 9 flat scalar fields, so
-- (unlike lib/msp_mixer_curves.lua's page-local flatten/unflatten) this
-- codec's decoded rule shape is already what app/field_layout.lua's flat
-- runtime.data[key] indexing needs, and forSlot() can hand it over as-is.
--
-- Per rule, in wire order: oper:U8, input:U8, output:U8, offset:S16,
-- weight:S16, weightNeg:S16, speed:U16, curve:U8, condition:U8 -- 13 bytes.
-- `oper` 0 means the slot is unused (matches wingflight-firmware's own
-- runtime evaluator, which gates purely on `if (rule->oper)` -- see
-- flight/mixer.c); an active rule always has oper 1(Set)/2(Add)/3(Mul).

if package.loaded["wfsuite.lib.msp_mixer_rules"] then
  return package.loaded["wfsuite.lib.msp_mixer_rules"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 172
local WRITE_COMMAND = 173
local RULE_COUNT = 32

-- Ranges sourced from wingflight-firmware: flight/mixer.h's
-- MIXER_INPUT_MIN/MAX (offset), MIXER_WEIGHT_MIN/MAX (weight/weightNeg,
-- the real wire range -- wingflight-configurator's own GUI caps its
-- derived "Weight" display at 0..5000 because it decomposes weight/
-- weightNeg into a Weight+Differential%+Reverse presentation this page
-- deliberately doesn't replicate, see app/pages/mixer_rules.lua's header);
-- pg/mixer.h's MIXER_RULE_COUNT; pg/logic_condition.h's
-- LOGIC_CONDITION_COUNT=16 (condition: 0=always active, 1-16 = that
-- logic condition, gates this rule -- Logic Conditions has no port in
-- this suite, so condition is exposed as a bare index, see
-- app/pages/mixer_rules.lua). `input`/`output` min/max are enum bounds
-- (27 and 31 entries respectively, 0-based) -- see that page's own
-- INPUT_OPTIONS/OUTPUT_OPTIONS for the human-readable choice tables.
local FIELD_META = {
  oper = {min = 0, max = 3, default = 0},
  input = {min = 0, max = 26, default = 0},
  output = {min = 0, max = 30, default = 0},
  offset = {min = -2500, max = 2500, default = 0},
  weight = {min = -10000, max = 10000, default = 0},
  weightNeg = {min = -10000, max = 10000, default = 0},
  speed = {min = 0, max = 60000, default = 0},
  curve = {min = 0, max = 8, default = 0},
  condition = {min = 0, max = 16, default = 0},
}

local function defaultRule()
  return {
    oper = 0, input = 0, output = 0, offset = 0,
    weight = 0, weightNeg = 0, speed = 0, curve = 0, condition = 0,
  }
end

-- All RULE_COUNT slots unused (all-zero, matching defaultRule()) -- the
-- simulator's whole-pool fixture, 32 * 13 = 416 zero bytes.
local SIMULATOR_RESPONSE_POOL = {}
for _ = 1, RULE_COUNT * 13 do
  SIMULATOR_RESPONSE_POOL[#SIMULATOR_RESPONSE_POOL + 1] = 0
end

local msp_mixer_rules = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  RULE_COUNT = RULE_COUNT,
  FIELD_META = FIELD_META,
  SIMULATOR_RESPONSE_POOL = SIMULATOR_RESPONSE_POOL,
  defaultRule = defaultRule,
}

-- A rule slot is unused when oper == 0 -- matches wingflight-firmware's
-- own runtime gate (flight/mixer.c's evaluator: `if (rule->oper)`),
-- simpler than wingflight-configurator's own stricter "all nine fields
-- zero" check (Mixer.js's isNullRule()), which exists there mainly to
-- decide which rows to render, not to mirror firmware behavior.
function msp_mixer_rules.isEmpty(rule)
  return not rule or (rule.oper or 0) == 0
end

-- Decodes the whole 32-rule pool from one GET reply.
function msp_mixer_rules.decodePool(buf)
  buf.offset = 1
  local pool = {}
  for i = 1, RULE_COUNT do
    pool[i] = {
      oper = mspcodec.readU8(buf),
      input = mspcodec.readU8(buf),
      output = mspcodec.readU8(buf),
      offset = mspcodec.readS16(buf),
      weight = mspcodec.readS16(buf),
      weightNeg = mspcodec.readS16(buf),
      speed = mspcodec.readU16(buf),
      curve = mspcodec.readU8(buf),
      condition = mspcodec.readU8(buf),
    }
  end
  return pool
end

-- Encodes ONE rule for MSP_SET_MIXER_RULE: index:U8 then the 13-byte body.
function msp_mixer_rules.encodeRule(index, rule)
  rule = rule or defaultRule()
  local payload = {}
  mspcodec.writeU8(payload, index)
  mspcodec.writeU8(payload, rule.oper or 0)
  mspcodec.writeU8(payload, rule.input or 0)
  mspcodec.writeU8(payload, rule.output or 0)
  mspcodec.writeS16(payload, rule.offset or 0)
  mspcodec.writeS16(payload, rule.weight or 0)
  mspcodec.writeS16(payload, rule.weightNeg or 0)
  mspcodec.writeU16(payload, rule.speed or 0)
  mspcodec.writeU8(payload, rule.curve or 0)
  mspcodec.writeU8(payload, rule.condition or 0)
  return payload
end

-- Whole-pool GET. Parameterless -- see lib/msp_mixer_curves.lua's own
-- comment on this shape (no per-rule read on the wire, only a per-rule
-- write).
function msp_mixer_rules.buildReadPoolMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_mixer_rules.decodePool(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE_POOL,
  }
end

-- Single-rule SET.
function msp_mixer_rules.buildWriteMessage(index, rule, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_mixer_rules.encodeRule(index, rule),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

-- PageRuntime-compatible adapter for ONE rule slot -- mirrors
-- lib/msp_servo_config.lua's forIndex(). Read always re-fetches the whole
-- pool (the wire GET has no index argument) and returns just that slot;
-- write still only touches the one rule being edited. Unlike the curve
-- codecs' own per-page flatten/unflatten glue, a rule's decoded shape is
-- already flat, so it can be handed straight to/from field_layout.lua.
function msp_mixer_rules.forSlot(index)
  return {
    FIELD_META = FIELD_META,
    buildReadMessage = function(onData, onError)
      return {
        command = READ_COMMAND,
        processReply = function(_, buf)
          onData(msp_mixer_rules.decodePool(buf)[index + 1])
        end,
        errorHandler = onError,
        simulatorResponse = SIMULATOR_RESPONSE_POOL,
      }
    end,
    buildWriteMessage = function(rule, onWritten, onError)
      return msp_mixer_rules.buildWriteMessage(index, rule, onWritten, onError)
    end,
  }
end

package.loaded["wfsuite.lib.msp_mixer_rules"] = msp_mixer_rules
return msp_mixer_rules
