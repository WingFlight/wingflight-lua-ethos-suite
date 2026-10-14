-- Run from the repository root with Lua 5.4: lua5.4 bin/tests/setup_wizard_controls.lua
-- lib/setup_wizard_controls.lua and lib/setup_wizard_styles.lua are ports of
-- the configurator's src/tabs/setup_wizard/receiver.js, modeRanges.js,
-- trimGain.js and styles.js. These are the configurator's own cases, from
-- scripts/tests/setup-wizard-receiver.test.mjs, setup-wizard-trim-gain.test.mjs
-- and the style and mode-range cases of setup-wizard-surfaces.test.mjs, with
-- the same inputs and expected values. Lists are 1-based here; the channel
-- numbers in them are the same 0-based ones.

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

local C = assert(loadfile(ROOT .. "lib/setup_wizard_controls.lua"))()
local St = assert(loadfile(ROOT .. "lib/setup_wizard_styles.lua"))()
local function list(t) return table.concat(t, ",") end
local function range(r) return r.start .. "-" .. r["end"] end

-- receiver.js
check("orderLabel AETR", C.orderLabel({0, 1, 3, 2, 4, 5, 6, 7}) == "AETR1234")
check("orderLabel TAER", C.orderLabel({1, 2, 3, 0, 4, 5, 6, 7}) == "TAER1234")
check("mapFromDetected: TEAR on 0-3", list(C.mapFromDetected({2, 1, 3, 0}, 8)) == "2,1,3,0,4,5,6,7")
check("mapFromDetected: sticks on 4-7, aux fills 0-3", list(C.mapFromDetected({4, 5, 6, 7}, 8)) == "4,5,6,7,0,1,2,3")
check("orderLabel of a detected map", C.orderLabel(C.mapFromDetected({2, 1, 3, 0}, 8)) == "TEAR1234")
check("movedChannel: nothing moved", C.movedChannel({0, 0, 0, 0}) == -1)
check("movedChannel: not far enough yet", C.movedChannel({0, 200, 0, 0}) == -1)
check("movedChannel: a clear winner", C.movedChannel({10, 450, 20, 0}) == 1)
check("movedChannel: two together is not clear", C.movedChannel({400, 450, 0, 0}) == -1)
check("movedChannel ignores channels found", C.movedChannel({500, 30, 420, 0}, {0}) == 2)
check("movedChannel: only the found one moved", C.movedChannel({500, 0, 0, 0}, {0}) == -1)

-- modeRanges.js
check("2-position switch, low to high", range(C.rangeForSwitch(1000, 2000)) == "1500-2100")
check("2-position switch, high to low", range(C.rangeForSwitch(2000, 1000)) == "900-1500")
check("3-position: low to middle", range(C.rangeForSwitch(1000, 1500)) == "1250-1750")
check("3-position: middle to high", range(C.rangeForSwitch(1500, 2000)) == "1750-2100")
check("988-2012 endpoints reach the end stops", range(C.rangeForSwitch(988, 2012)) == "1500-2100")

-- trimGain.js
local function off() return {adjFunction = 0, adjChannel = 0, adjRange1 = {start = 1500, ["end"] = 1500}} end
do
  local r = C.trimRange("roll", 4)
  check("trim range: roll trim, mapped", r.adjFunction == 89 and r.adjStep == 0)
  check("trim range: centred adds nothing, ends +-100", C.mappedValue(r, 1500) == 0
    and C.mappedValue(r, 975) == -100 and C.mappedValue(r, 2025) == 100 and C.mappedValue(r, 2100) == 100)
  local g = C.gainRange("pitch", 2)
  check("gain knob: 0-150%, 75% centred", g.adjFunction == 84 and C.mappedValue(g, 1500) == 75
    and C.mappedValue(g, 975) == 0 and C.mappedValue(g, 2025) == 150)
end
do
  local ranges = {C.gainRange("roll", 1), off(), C.trimRange("yaw", 3), off()}
  check("slotFor reuses the function's own slot", C.slotFor(ranges, 85) == 1 and C.slotFor(ranges, 91) == 3)
  check("slotFor takes the first free one", C.slotFor(ranges, 89) == 2)
  check("slotFor: no room", C.slotFor({C.gainRange("roll", 1)}, 89) == -1)
end
check("gainMode none", C.gainMode({off(), off()}) == "none")
check("gainMode single", C.gainMode({C.gainRange("roll", 2), C.gainRange("pitch", 2), C.gainRange("yaw", 2)}) == "single")
check("gainMode separate", C.gainMode({C.gainRange("roll", 2), C.gainRange("pitch", 3), C.gainRange("yaw", 4)}) == "separate")
for i, b in ipairs(C.TRIM_BUTTONS) do
  local value = C.buttonValue(b.weight)
  local w = C.buttonWindow(i)
  check(b.button .. ": value well inside its window", w.start % 5 == 0 and w["end"] % 5 == 0
    and value - w.start >= 20 and w["end"] - value >= 20 and C.buttonAt(math.floor(value + 0.5)) == b
    and (i == 1 or C.buttonWindow(i - 1)["end"] == w.start))
end
check("no button at 1500, 1000, 2012 or nil", C.buttonAt(1500) == nil and C.buttonAt(1000) == nil
  and C.buttonAt(2012) == nil and C.buttonAt(nil) == nil)
do
  local roll = C.steppedTrimRange("roll", 3)
  check("stepped roll trim", roll.adjFunction == 89 and roll.adjChannel == 3 and roll.adjStep == C.STEPPED_TRIM_STEP
    and range(roll.adjRange1) == "1835-1885" and range(roll.adjRange2) == "1885-1935")
  local pitch = C.steppedTrimRange("pitch", 3)
  check("stepped pitch trim", range(pitch.adjRange1) == "1780-1835" and range(pitch.adjRange2) == "1730-1780")
  local yaw = C.steppedTrimRange("yaw", 3)
  check("stepped yaw trim", range(yaw.adjRange1) == "1630-1680" and range(yaw.adjRange2) == "1680-1730")
end
check("trimMode none", C.trimMode({off(), off()}) == nil)
check("trimMode programmable", C.trimMode({C.trimRange("roll", 4), off()}) == "programmable")
check("trimMode buttons", C.trimMode({C.steppedTrimRange("roll", 3), C.steppedTrimRange("yaw", 3)}) == "buttons")
do
  local r = C.resetToOff(C.trimRange("roll", 4))
  check("resetToOff clears the function and keeps the channel", r.adjFunction == 0 and r.adjMax == 100
    and r.adjChannel == 4)
end

-- styles.js, on the wire values (rate deg/s / 5, expo percent)
do
  local rc, pid = {}, {}
  for n = 1, 3 do rc["rcRates_" .. n] = 50; rc["rcExpo_" .. n] = 0 end
  check("no style matches 250/0", St.matchingStyle(rc, pid) == nil)
  local threeD = St.STYLES[3]
  St.applyStyle(threeD, rc, pid)
  check("3D: roll 500 deg/s", St.rateOf(rc, "roll") == 500 and rc.rcRates_1 == 100)
  check("3D: yaw expo 60%", St.expoOf(rc, "yaw") == 60)
  check("3D: relax 7 on pitch, level 15 on yaw", pid.bounceback_1 == 7 and pid.iterm_relax_level_2 == 15)
  check("3D is recognised afterwards", St.matchingStyle(rc, pid) == threeD)
  rc.rcRates_3 = 70
  check("an edited rate is no longer a preset", St.matchingStyle(rc, pid) == nil)
end

print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
