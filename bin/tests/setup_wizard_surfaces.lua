-- Run from the repository root with Lua 5.3+: lua bin/tests/setup_wizard_surfaces.lua
-- lib/setup_wizard_surfaces.lua is a port of the configurator's
-- src/tabs/setup_wizard/surfaces.js. These are the surface cases of the
-- configurator's scripts/tests/setup-wizard-surfaces.test.mjs, with the same
-- inputs and expected values, so a change on either side that the other lacks
-- shows up here. The style and mode-range cases of that file come with the
-- steps that use them.

local ROOT = "src/wfsuite/"

local failures, checks = 0, 0
local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    print("  ok    " .. label)
  else
    failures = failures + 1
    print("  FAIL  " .. label)
    if detail then print("        " .. tostring(detail)) end
  end
end

local S = assert(loadfile(ROOT .. "lib/setup_wizard_surfaces.lua"))()

local SET, ADD = 1, 2
-- rule(oper, src, dst, weight, weightNeg) as in the JS test; dst is the mixer
-- output (servo + 1).
local function rule(oper, src, dst, weight, weightNeg)
  return {oper = oper, input = src, output = dst, weight = weight, weightNeg = weightNeg or weight}
end
local function servo(overrides)
  local s = {mid = 1520, min = -500, max = 500, rneg = 500, rpos = 500, flags = 0}
  for k, v in pairs(overrides or {}) do s[k] = v end
  return s
end
local gains = {roll = 1, pitch = 1, yaw = 1}
local function near(a, b) return math.abs(a - b) < 1e-9 end

-- conventional layout names each surface from its axes
do
  local surfaces = S.surfacesFromRules({
    rule(SET, 1, 1, 1000), rule(SET, 1, 2, -1000),
    rule(SET, 2, 3, 1000), rule(SET, 3, 4, 1000),
    rule(SET, 4, 27, 1000), -- throttle to a motor, not a servo
  }, 8)
  local got = {}
  for i, s in ipairs(surfaces) do got[i] = s.servo .. ":" .. s.kind end
  got = table.concat(got, " ")
  check("conventional layout: kinds", got == "0:aileron 1:aileron 2:elevator 3:rudder", got)
  check("conventional layout: aileron primary axis is roll", S.primaryAxis(surfaces[1]) == "roll")
  check("conventional layout: rudder primary axis is yaw", S.primaryAxis(surfaces[4]) == "yaw")
end

-- elevon sums pitch and roll and clips at full deflection on both
do
  local elevon = S.surfacesFromRules({rule(SET, 2, 1, 1000), rule(ADD, 1, 1, 1000)}, 8)[1]
  check("elevon: kind", elevon.kind == "elevon", elevon.kind)
  check("elevon: primary axis is pitch", S.primaryAxis(elevon) == "pitch")
  local reach = S.travelReach(elevon, servo({max = 450, min = -450}), gains)
  check("elevon: pos reach 1000 us", near(reach.pos.us, 1000), reach.pos.us)
  check("elevon: pos fraction 1000/450", near(reach.pos.fraction, 1000 / 450), reach.pos.fraction)
  check("elevon: neg fraction > 2", reach.neg.fraction > 2, reach.neg.fraction)
end

-- a later SET replaces earlier rules on the same output and axis
do
  local surface = S.surfacesFromRules({rule(SET, 2, 1, 1000), rule(SET, 2, 1, 600)}, 8)[1]
  check("later SET replaces", near(surface.axes.pitch.pos, 0.6), surface.axes.pitch.pos)
end

-- differential weights give different reach per side
do
  local aileron = S.surfacesFromRules({rule(SET, 1, 1, 1000, 500)}, 8)[1]
  check("differential: +1 stick", near(S.outputForAxis(aileron, "roll", 1, gains), 1))
  check("differential: -1 stick", near(S.outputForAxis(aileron, "roll", -1, gains), -0.5))
  local reach = S.travelReach(aileron, servo(), gains)
  check("differential: pos 500 us", near(reach.pos.us, 500), reach.pos.us)
  check("differential: neg 250 us", near(reach.neg.us, 250), reach.neg.us)
end

-- servo reverse moves the output to the other side
do
  check("servoSide: not reversed", S.servoSide(0.8, false) == "pos")
  check("servoSide: reversed", S.servoSide(0.8, true) == "neg")
  local aileron = S.surfacesFromRules({rule(SET, 1, 1, 1000, 500)}, 8)[1]
  local reach = S.travelReach(aileron, servo({flags = 1}), gains)
  check("reversed: pos 250 us", near(reach.pos.us, 250), reach.pos.us)
  check("reversed: neg 500 us", near(reach.neg.us, 500), reach.neg.us)
end

-- axis gain scales the reach
do
  local elevator = S.surfacesFromRules({rule(SET, 2, 1, 1000)}, 8)[1]
  local reach = S.travelReach(elevator, servo(), {roll = 1, pitch = 0.5, yaw = 1})
  check("axis gain scales reach", near(reach.pos.fraction, 0.5), reach.pos.fraction)
end

-- largest scale that keeps full stick inside the binding limit
do
  check("maxScale(1, 700)", S.maxScale(1, 700) == 700)
  check("maxScale(0.83, 700): larger with axis gain 83%", S.maxScale(0.83, 700) == 843, S.maxScale(0.83, 700))
  check("maxScale(-0.83, 700): either side", S.maxScale(-0.83, 700) == 843)
  check("maxScale(0.5, 700): never past the travel limit", S.maxScale(0.5, 700) == 1000)
  check("maxScale(1, 20): never below the minimum", S.maxScale(1, 20) == 50)
  check("maxScale(0, 700): axis gain 0 limits nothing", S.maxScale(0, 700) == 1000)
end

-- Lua-only: the rule shape and orderings the port has to get right itself.
do
  local surfaces = S.surfacesFromRules({
    rule(SET, 3, 2, 1000), rule(ADD, 1, 2, 500), -- roll+yaw, yaw rule first
    rule(SET, 13, 1, 1000), rule(ADD, 1, 1, 300), -- flap that follows the ailerons
    rule(3, 1, 3, 1000),                       -- MUL: ignored
    rule(SET, 2, 9, 1000),                     -- past the board's 4 servos
  }, 4)
  check("sorted by servo", surfaces[1].servo == 0 and surfaces[2].servo == 1)
  check("flap following roll is a flap", surfaces[1].kind == "flap", surfaces[1].kind)
  check("mixed surface falls back to its first axis", surfaces[2].kind == "mixed"
    and S.primaryAxis(surfaces[2]) == "yaw", S.primaryAxis(surfaces[2]))
  check("MUL rule makes no surface", #surfaces == 2, #surfaces)
  local past = S.servosPastCount({rule(SET, 2, 9, 1000), rule(SET, 2, 6, 1000), rule(SET, 2, 6, 0)}, 4, 8)
  check("servosPastCount: in slots only, once each", table.concat(past, ",") == "6", table.concat(past, ","))
  local g = S.axisGainsFromRates({roll = 830, pitch = -1000})
  check("axis gains from rates", near(g.roll, 0.83) and near(g.pitch, -1) and near(g.yaw, 1))
end

print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
