-- Servo names a mixer setup gives the servos it assigns, and servo labels
-- with the name. A port of wingflight-configurator's src/js/ServoNames.js
-- (namesFromRules(), assignServoNames(), withServoName()); the names are the
-- same so a model set up from either side reads the same in both. When one
-- changes, change the other, and bin/tests/servo_names.lua with them.
--
-- Each servo the mix drives is named after the surface it moves
-- (lib/setup_wizard_surfaces.lua's surfaceKind()): a pair of one kind is left
-- and right, in servo order (the wizards give the left surface the lower
-- servo), one alone has no side, and more are numbered. Thrust-vector servos
-- are named after their axis.

if package.loaded["wfsuite.lib.servo_names"] then
  return package.loaded["wfsuite.lib.servo_names"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local surfacesLib = requireModule("lib/setup_wizard_surfaces.lua")

local M = {}

-- Every servo the firmware has a name for (MAX_SUPPORTED_SERVOS)
M.SERVO_COUNT = 24

local ABBREVIATIONS = {
  aileron = "AIL",
  flaperon = "FLPRN",
  elevon = "ELEVON",
  ruddervator = "VTAIL",
  elevator = "ELEV",
  rudder = "RUDDER",
  flap = "FLAP",
  mixed = "MIX",
}

-- Mixer inputs MIXER_IN_STABILIZED_TV_ROLL/PITCH/YAW
local TV_NAMES = {[27] = "TV ROLL", [28] = "TV PITCH", [29] = "TV YAW"}

-- Names for the servos `rules` drives: names[servo] (0-based).
function M.namesFromRules(rules)
  local names = {}
  local byKind, kinds = {}, {}
  for _, surface in ipairs(surfacesLib.surfacesFromRules(rules, M.SERVO_COUNT)) do
    local list = byKind[surface.kind]
    if not list then
      list = {}
      byKind[surface.kind] = list
      kinds[#kinds + 1] = surface.kind
    end
    list[#list + 1] = surface.servo
  end
  for _, kind in ipairs(kinds) do
    local servos = byKind[kind]
    local abbr = ABBREVIATIONS[kind] or ABBREVIATIONS.mixed
    for i, servo in ipairs(servos) do
      if #servos == 1 then
        names[servo] = abbr
      elseif #servos == 2 then
        names[servo] = (i == 1 and "L " or "R ") .. abbr
      else
        names[servo] = abbr .. " " .. i
      end
    end
  end

  for i = 1, #rules do
    local rule = rules[i]
    local servo = (rule.output or 0) - 1
    local tv = TV_NAMES[rule.input]
    if tv and servo >= 0 and servo < M.SERVO_COUNT and not names[servo] then
      names[servo] = tv
    end
  end
  return names
end

-- True for a name namesFromRules() could have given, so one left on a servo
-- a new mix no longer drives can be told from a name the pilot typed.
function M.isGenerated(name)
  if not name or name == "" then return false end
  for _, tv in pairs(TV_NAMES) do
    if name == tv then return true end
  end
  local body = name:gsub("^[LR] ", ""):gsub(" %d+$", "")
  for _, abbr in pairs(ABBREVIATIONS) do
    if body == abbr then return true end
  end
  return false
end

-- After a mixer setup has replaced the mix: names every servo `rules` drives
-- in `names` (0-based, "" for none), and clears a generated name from a
-- servo it no longer drives; a typed name there is kept. Returns the list of
-- servos whose name changed, for the caller to send.
function M.assign(names, rules)
  local wanted = M.namesFromRules(rules)
  local changed = {}
  for servo = 0, M.SERVO_COUNT - 1 do
    local current = names[servo] or ""
    local nextName = wanted[servo]
    if not nextName then
      nextName = M.isGenerated(current) and "" or current
    end
    if nextName ~= current then
      names[servo] = nextName
      changed[#changed + 1] = servo
    end
  end
  return changed
end

-- `label` with servo `servo`'s (0-based) name after it, e.g.
-- "Servo 1 (L AIL)". names may be nil (firmware without names).
function M.withName(label, names, servo)
  local name = names and names[servo]
  if name and name ~= "" then
    return label .. " (" .. name .. ")"
  end
  return label
end

package.loaded["wfsuite.lib.servo_names"] = M
return M
