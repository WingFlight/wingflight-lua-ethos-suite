-- Behaviour check for the WingFlight Ports page labels (#2359, ported from Rotorflight).
--
-- Run it:
--     lua5.4 bin/port_labels/verify_port_labels.lua
--
-- What it drives:
--   * lib/port_labels.lua: the Wingflight Configurator's connector names per board design
--     (the Setup Wizard's Servo bus step finds the SBUS connector by them), and the lookup
--     logic itself with test entries injected into the same tables.
--   * lib/msp_board_info.lua: parse() of MSP_BOARD_INFO replies, including truncated and
--     generic-board cases, and the read message's error path.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local ROOT = scriptDir() .. "/../.."
local LIB = ROOT .. "/src/wfsuite/lib/"

-- Modules resolve their own requires through lib/require.lua relative to the working
-- directory. Load the memoizer and the codec from the repo root, so the harness works
-- from any directory.
assert(loadfile(LIB .. "require.lua"))()
package.loaded["wfsuite.lib.mspcodec"] = assert(loadfile(LIB .. "mspcodec.lua"))()

local port_labels = assert(loadfile(LIB .. "port_labels.lua"))()
local msp_board_info = assert(loadfile(LIB .. "msp_board_info.lua"))()

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

local function bytesOf(str)
  local out = {}
  for i = 1, #str do out[i] = str:byte(i) end
  return out
end

-- Builds an MSP_BOARD_INFO reply payload. Strings are length-prefixed as in the firmware
-- (msp.c) and the Configurator parser.
local function boardInfoReply(opts)
  local buf = {}
  for _, b in ipairs(bytesOf(opts.identifier or "WGFL")) do buf[#buf + 1] = b end
  local version = opts.version or 0
  buf[#buf + 1] = version % 256
  buf[#buf + 1] = math.floor(version / 256)
  buf[#buf + 1] = opts.boardType or 1
  buf[#buf + 1] = opts.caps or 0
  for _, field in ipairs({opts.targetName or "", opts.boardName or "", opts.boardDesign or ""}) do
    buf[#buf + 1] = #field
    for _, b in ipairs(bytesOf(field)) do buf[#buf + 1] = b end
  end
  return buf
end

local function truncate(buf, n)
  local out = {}
  for i = 1, n do out[i] = buf[i] end
  return out
end

-- ---------------------------------------------------------------------------
print("labels: the Wingflight Configurator's names per board design")
-- ---------------------------------------------------------------------------

check("RF007 (F7B5): UART1 is S.BUS", port_labels.lookup("F7B5", 0) == "S.BUS", port_labels.lookup("F7B5", 0))
check("RF007 (F7B5): UART4 is Port A", port_labels.lookup("F7B5", 3) == "Port A", port_labels.lookup("F7B5", 3))
check("Nexus X (F7C5): UART1 is S.BUS", port_labels.lookup("F7C5", 0) == "S.BUS")
check("Nexus F7 (F7A1): UART2 is S.BUS", port_labels.lookup("F7A1", 1) == "S.BUS")
check("RF007 V3 (F7B5M): UART1 is the FBUS mux, not S.BUS", port_labels.lookup("F7B5M", 0) == "FBUS Mux")
check("a UART the design does not name gives nil", port_labels.lookup("F7B5", 8) == nil)
check("an unknown design gives nil", port_labels.lookup("RTFL", 3) == nil)
check("an unlisted board_name falls through to the design", port_labels.lookup("F7B5", 0, "VANTAC_RF007") == "S.BUS")
check("nil arguments give nil", port_labels.lookup(nil, nil, nil) == nil)

-- ---------------------------------------------------------------------------
print("lookup logic, with test entries injected into the same tables")
-- ---------------------------------------------------------------------------

port_labels.DESIGNS["TEST_DESIGN"] = {[2] = "Port X"}
port_labels.BY_NAME["TEST_BOARD"] = {[2] = "NAME LABEL"}

check("design lookup returns its label", port_labels.lookup("TEST_DESIGN", 2) == "Port X")
check("design lookup for an unlisted UART gives nil", port_labels.lookup("TEST_DESIGN", 4) == nil)
check("name entry beats design entry", port_labels.lookup("TEST_DESIGN", 2, "TEST_BOARD") == "NAME LABEL")
check("unlisted name falls through to design", port_labels.lookup("TEST_DESIGN", 2, "OTHER") == "Port X")
check("generic design without name gives nil", port_labels.lookup("RTFL", 2) == nil)

-- Remove the injected entries again.
port_labels.DESIGNS["TEST_DESIGN"] = nil
port_labels.BY_NAME["TEST_BOARD"] = nil

-- ---------------------------------------------------------------------------
print("parse: MSP_BOARD_INFO replies")
-- ---------------------------------------------------------------------------

check("READ_COMMAND is 4", msp_board_info.READ_COMMAND == 4)

local sample = boardInfoReply({targetName = "", boardName = "SAMPLE_BOARD", boardDesign = "RTFL", version = 258})
local info = msp_board_info.parse(sample)
check("parses boardDesign RTFL", info ~= nil and info.boardDesign == "RTFL", info and info.boardDesign or "nil")
check("parses boardName", info ~= nil and info.boardName == "SAMPLE_BOARD", info and info.boardName or "nil")

local generic = msp_board_info.parse(boardInfoReply({boardDesign = ""}))
check("empty design is a valid reply with boardDesign ''", generic ~= nil and generic.boardDesign == "")

check("truncated inside boardDesign gives nil",
  msp_board_info.parse(truncate(sample, #sample - 1)) == nil)
check("truncated inside the header gives nil",
  msp_board_info.parse(truncate(sample, 5)) == nil)
check("empty reply gives nil", msp_board_info.parse({}) == nil)

local dataCalls, errorCalls = 0, 0
local msg = msp_board_info.buildReadMessage(
  function() dataCalls = dataCalls + 1 end,
  function() errorCalls = errorCalls + 1 end)
msg.processReply(nil, {offset = 1, table.unpack(truncate(sample, 6))})
check("truncated reply calls onError", errorCalls == 1 and dataCalls == 0,
  string.format("data=%d error=%d", dataCalls, errorCalls))

local simFixture = msp_board_info.buildReadMessage(function() end, function() end).simulatorResponse
local simInfo = msp_board_info.parse({table.unpack(simFixture)})
check("simulator fixture is a generic board", simInfo ~= nil and simInfo.boardDesign == "")

-- ---------------------------------------------------------------------------
print("")
print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
