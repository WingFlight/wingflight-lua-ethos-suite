-- Run from the repository root: lua tests/attitude_limits_codec.lua
package.loaded["wfsuite.lib.require"] = function(path)
  return assert(loadfile("src/wfsuite/" .. path))()
end
local codec = assert(loadfile("src/wfsuite/lib/msp_pid_profile.lua"))()
local fixture = codec.buildReadMessage(function() end).simulatorResponse
local function copy(t, n)
  local out = {}
  for i = 1, n or #t do out[i] = t[i] end
  return out
end
local function same(a, b)
  assert(#a == #b, "payload length changed")
  for i = 1, #a do assert(a[i] == b[i], "byte mismatch at " .. i) end
end
local current = codec.decode(copy(fixture))
assert(current.has_axis_limits)
assert(current.angle_roll_limit == current.angle_level_limit)
assert(current.trainer_pitch_limit == current.trainer_angle_limit)
same(codec.encode(current), fixture)
current.trainer_roll_limit = 60
local expected = copy(fixture)
expected[#expected - 1] = 60
same(codec.encode(current), expected)
for tail = 0, 3 do
  local old = copy(fixture, #fixture - 4 + tail)
  local decoded = codec.decode(old)
  assert(not decoded.has_axis_limits)
  decoded.trainer_roll_limit = 70 -- unsupported edits cannot corrupt old writes
  same(codec.encode(decoded), copy(fixture, #fixture - 4))
end
local bounded = copy(fixture)
bounded[#bounded - 3] = 255
bounded[#bounded - 2] = 255
bounded[#bounded - 1] = 1
bounded[#bounded] = 1
local decoded = codec.decode(bounded)
assert(decoded.angle_roll_limit == 90 and decoded.angle_pitch_limit == 75)
assert(decoded.trainer_roll_limit == 10 and decoded.trainer_pitch_limit == 10)
same(codec.encode(decoded), bounded)
print("PASS: new/old/truncated replies, inheritance, independent edits and firmware bounds")
