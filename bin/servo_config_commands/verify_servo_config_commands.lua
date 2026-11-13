-- Behaviour check for the servo command numbers (#2444).
--
-- Run it:
--     lua5.4 bin/servo_config_commands/verify_servo_config_commands.lua
--     lua5.4 bin/servo_config_commands/verify_servo_config_commands.lua --self-test
--
-- What it drives:
--   * lib/msp_servo_config.lua: the read message (125) and the write (212), with
--     their payloads.
--   * lib/msp_servo_center.lua (213) and lib/msp_servo_override.lua (193).
--   * lib/msp_mixer_config.lua (42 / 43), which carries the one PWM update rate
--     that replaced the per-servo rate.
--
-- The numbers are the firmware's, from wingflight-firmware
-- src/main/msp/msp_protocol.h: MSP_GET_SERVO_CONFIG 125,
-- MSP_SET_SERVO_CONFIGURATION 212, MSP_SET_SERVO_CENTER 213,
-- MSP_SET_SERVO_OVERRIDE 193. From MSP API 22.16 a servo index is the same in
-- every one of them (index N is servo S(N+1)), and the servo record is seven
-- 16-bit fields with no rate, so the write is 1 + 14 bytes; the firmware refuses
-- any other length (msp.c, MSP_SET_SERVO_CONFIGURATION).
-- The check reads them off the messages the modules build, so a renamed constant
-- that still holds the wrong number is caught as well as a wrong constant name.
--
-- --self-test first requires the unmodified modules to pass, then swaps one
-- command number in a copy of a module, once per entry in MUTATIONS, and requires
-- the check to go red each time. A green run without a red control proves nothing.

local SELF_TEST = arg and arg[1] == "--self-test"

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local ROOT = scriptDir() .. "/../.."
local LIB = ROOT .. "/src/wfsuite/lib/"

-- Modules resolve their requires through lib/require.lua relative to the working
-- directory. Load the memoizer and the codec from the repo root, so the harness
-- works from any directory.
local requireModule = assert(loadfile(LIB .. "require.lua"))()
package.loaded["wfsuite.lib.require"] = requireModule
package.loaded["wfsuite.lib.mspcodec"] = assert(loadfile(LIB .. "mspcodec.lua"))()
package.loaded["wfsuite.lib.bus"] = assert(loadfile(LIB .. "bus.lua"))()
package.loaded["wfsuite.lib.override_keepalive"] = assert(loadfile(LIB .. "override_keepalive.lua"))()

local failures = 0
local checks = 0

local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    print(string.format("  ok    %s", label))
  else
    failures = failures + 1
    print(string.format("  FAIL  %s", label))
    if detail then print("        " .. tostring(detail)) end
  end
end

-- Loads one module fresh: from its file, or from mutated source text.
local function loadModule(name, text)
  package.loaded["wfsuite.lib." .. name] = nil
  local chunk, err
  if text then
    chunk, err = load(text, "@" .. name .. ".lua")
  else
    chunk, err = loadfile(LIB .. name .. ".lua")
  end
  assert(chunk, err)
  return chunk()
end

local function readSource(name)
  local f = assert(io.open(LIB .. name .. ".lua", "r"))
  local text = f:read("a")
  f:close()
  return text
end

-- The payload as a comma-separated string, so a mismatch prints what was sent.
local function bytes(payload)
  return table.concat(payload, ",")
end

-- Pins the command numbers and the payload layout. Returns how many checks failed.
local function pinCommands(cfg, center, override, mixer)
  local before = failures
  -- rate is not a field any more: a caller that still passes one must not see it
  -- on the wire.
  local data = {mid = 1301, min = -600, max = 600, rneg = 500, rpos = 450,
    rate = 333, speed = 120, flags = 1}

  print("Command numbers")
  check("read is MSP_GET_SERVO_CONFIG (125)", cfg.READ_COMMAND == 125,
    "got " .. tostring(cfg.READ_COMMAND))
  check("write is MSP_SET_SERVO_CONFIGURATION (212)", cfg.WRITE_COMMAND == 212,
    "got " .. tostring(cfg.WRITE_COMMAND))
  check("centre is MSP_SET_SERVO_CENTER (213)", center.WRITE_COMMAND == 213,
    "got " .. tostring(center.WRITE_COMMAND))
  check("override is MSP_SET_SERVO_OVERRIDE (193)", override.WRITE_COMMAND == 193,
    "got " .. tostring(override.WRITE_COMMAND))

  print("Messages")
  local read = cfg.buildReadMessage(12, function() end, function() end)
  check("the read message sends 125 with servo index 12",
    read.command == 125 and bytes(read.payload) == "12",
    string.format("command %s, payload %s", tostring(read.command), bytes(read.payload)))

  local write = cfg.buildWriteMessage(12, data, nil, nil)
  check("the write sends 212 and passes its index through unchanged",
    write.command == 212 and write.payload[1] == 12,
    string.format("command %s, index %s", tostring(write.command), tostring(write.payload[1])))
  -- index, mid 1301, min -600, max 600, rneg 500, rpos 450, speed 120, flags 1
  check("the write carries 15 bytes: index + mid, min, max, rneg, rpos, speed, flags",
    bytes(write.payload) == "12,21,5,168,253,88,2,244,1,194,1,120,0,1,0",
    bytes(write.payload))
  check("mid 1301 is little-endian at payload bytes 2-3 (21, 5)",
    write.payload[2] == 21 and write.payload[3] == 5,
    string.format("got %s, %s", tostring(write.payload[2]), tostring(write.payload[3])))

  -- The read reply is the same seven fields, 14 bytes.
  local decoded = cfg.decode({21, 5, 168, 253, 88, 2, 244, 1, 194, 1, 120, 0, 1, 0})
  check("a 14-byte reply decodes to mid, min, max, rneg, rpos, speed, flags",
    decoded.mid == 1301 and decoded.min == -600 and decoded.max == 600 and decoded.rneg == 500
      and decoded.rpos == 450 and decoded.speed == 120 and decoded.flags == 1 and decoded.rate == nil,
    string.format("mid %s min %s max %s rneg %s rpos %s speed %s flags %s rate %s",
      tostring(decoded.mid), tostring(decoded.min), tostring(decoded.max), tostring(decoded.rneg),
      tostring(decoded.rpos), tostring(decoded.speed), tostring(decoded.flags), tostring(decoded.rate)))
  check("the simulator reply is 14 bytes", #read.simulatorResponse == 14,
    "got " .. tostring(#read.simulatorResponse))

  local c = center.buildWriteMessage(12, 1301)
  check("the centre message sends 213 with index 12 and mid 1301",
    c.command == 213 and bytes(c.payload) == "12,21,5",
    string.format("command %s, payload %s", tostring(c.command), bytes(c.payload)))

  local o = override.buildWriteMessage(12, 1500)
  check("the override message sends 193 with index 12 and value 1500",
    o.command == 193 and bytes(o.payload) == "12,220,5",
    string.format("command %s, payload %s", tostring(o.command), bytes(o.payload)))

  print("Factory forIndex")
  local inst = cfg.forIndex(12)
  local fiRead = inst.buildReadMessage(function() end, function() end)
  check("forIndex buildReadMessage delegates to 125 with bound index 12",
    fiRead.command == 125 and bytes(fiRead.payload) == "12",
    string.format("command %s, payload %s", tostring(fiRead.command), bytes(fiRead.payload)))

  local fiWrite = inst.buildWriteMessage(data, nil, nil)
  check("forIndex buildWriteMessage delegates to 212 with bound index 12",
    fiWrite.command == 212 and fiWrite.payload[1] == 12,
    string.format("command %s, index %s", tostring(fiWrite.command), tostring(fiWrite.payload[1])))

  -- The PWM update rate moved out of the servo record (wingflight-firmware
  -- msp.c, MSP_MIXER_CONFIG / MSP_SET_MIXER_CONFIG, MSP API 22.16).
  print("Mixer config")
  check("mixer config is read with 42 and written with 43",
    mixer.READ_COMMAND == 42 and mixer.WRITE_COMMAND == 43,
    string.format("read %s, write %s", tostring(mixer.READ_COMMAND), tostring(mixer.WRITE_COMMAND)))
  -- model type 1, reserved 0, SBUS 16, F.Bus 24, bus output count 24, rate 333
  local mix = mixer.decode({1, 0, 16, 24, 24, 77, 1})
  check("a 7-byte reply decodes to model type, bus channel counts, bus output count and PWM rate",
    mix.model_type == 1 and mix.sbus_out_channels == 16 and mix.fbus_master_channels == 24
      and mix.bus_servo_output_count == 24 and mix.servo_pwm_rate == 333
      and mix.bus_servo_clone_pwm == nil,
    string.format("type %s sbus %s fbus %s count %s rate %s", tostring(mix.model_type),
      tostring(mix.sbus_out_channels), tostring(mix.fbus_master_channels),
      tostring(mix.bus_servo_output_count), tostring(mix.servo_pwm_rate)))
  mix.servo_pwm_rate = 50
  check("what was read goes back as the long form: type, reserved 0, both channel counts, rate",
    bytes(mixer.buildWriteMessage(mix).payload) == "1,0,16,24,50,0",
    bytes(mixer.buildWriteMessage(mix).payload))
  check("a model type on its own goes out as the two-byte short form",
    bytes(mixer.buildWriteMessage({model_type = 3}).payload) == "3,0",
    bytes(mixer.buildWriteMessage({model_type = 3}).payload))
  check("a reply without the rate never writes a rate of 0",
    bytes(mixer.buildWriteMessage(mixer.decode({1, 0, 16, 24, 24})).payload) == "1,0",
    bytes(mixer.buildWriteMessage(mixer.decode({1, 0, 16, 24, 24})).payload))
  check("the mixer config simulator reply is 7 bytes at 50 Hz",
    #mixer.buildReadMessage(function() end).simulatorResponse == 7
      and mixer.decode({table.unpack(mixer.buildReadMessage(function() end).simulatorResponse)}).servo_pwm_rate == 50)

  return failures - before
end

-- Each entry swaps one command number in one module. Every swap must be caught.
local MUTATIONS = {
  {file = "msp_servo_config", from = "local WRITE_COMMAND = 212",
    to = "local WRITE_COMMAND = 213", what = "the write sent as the centre command"},
  {file = "msp_servo_config", from = "local READ_COMMAND = 125",
    to = "local READ_COMMAND = 124", what = "the read sent as a write"},
  {file = "msp_servo_config", from = "  mspcodec.writeU16(payload, data.speed or 0)",
    to = "  mspcodec.writeU16(payload, data.rate or 0)\n  mspcodec.writeU16(payload, data.speed or 0)",
    what = "the removed rate field written back before speed"},
  {file = "msp_servo_center", from = "local WRITE_COMMAND = 213",
    to = "local WRITE_COMMAND = 212", what = "the centre sent as the bulk command"},
  {file = "msp_servo_override", from = "local WRITE_COMMAND = 193",
    to = "local WRITE_COMMAND = 196", what = "the override sent as the all-servos command"},
  {file = "msp_mixer_config", from = "mspcodec.readU8(buf) -- reserved, was bus_servo_clone_pwm",
    to = "-- the reserved byte is not skipped", what = "the reserved byte read as the SBUS channel count"},
  {file = "msp_mixer_config", from = "    mspcodec.writeU16(payload, data.servo_pwm_rate)",
    to = "    mspcodec.writeU8(payload, data.servo_pwm_rate)", what = "the PWM rate written as one byte"},
}

-- Source text of one module with exactly one plain-text replacement.
local function mutatedSource(mutation)
  local text = readSource(mutation.file)
  local s, e = text:find(mutation.from, 1, true)
  assert(s and not text:find(mutation.from, e + 1, true),
    "self-test could not find exactly one '" .. mutation.from .. "'")
  return text:sub(1, s - 1) .. mutation.to .. text:sub(e + 1)
end

-- Loads the modules, with one of them replaced by its mutated copy if given,
-- and runs the pin. Returns the number of failed checks.
local function runWith(mutation)
  local texts = {}
  if mutation then texts[mutation.file] = mutatedSource(mutation) end
  local cfg = loadModule("msp_servo_config", texts.msp_servo_config)
  local center = loadModule("msp_servo_center", texts.msp_servo_center)
  local override = loadModule("msp_servo_override", texts.msp_servo_override)
  local mixer = loadModule("msp_mixer_config", texts.msp_mixer_config)
  return pinCommands(cfg, center, override, mixer)
end

if not SELF_TEST then
  local failed = runWith(nil)
  print(string.format("\n%d checks, %d failed", checks, failures))
  os.exit(failed == 0 and 0 or 1)
end

print("self-test: the unmodified modules must pass first")
local baseline = runWith(nil)
print(string.format("baseline: %s", baseline == 0 and "green" or "RED"))

local caughtCount = 0
for _, mutation in ipairs(MUTATIONS) do
  print(string.format("\nself-test: %s (%s -> %s)", mutation.what, mutation.from, mutation.to))
  local failed = runWith(mutation)
  if failed > 0 then
    caughtCount = caughtCount + 1
    print("self-test: caught")
  else
    print("self-test: NOT caught")
  end
end

print(string.format("\nself-test: baseline %s, %d of %d mutations caught",
  baseline == 0 and "green" or "RED", caughtCount, #MUTATIONS))
os.exit((baseline == 0 and caughtCount == #MUTATIONS) and 0 or 1)
