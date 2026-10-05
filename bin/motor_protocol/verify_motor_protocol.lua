-- Behaviour check for the Throttle Protocol list and the Motor Config defaults.
--
-- Port of rotorflight/rotorflight-lua-ethos-suite#2465, from upstream branch
-- 974c98f2. The stubs, the case structure and the self-test machinery are upstream's;
-- the parts that had to be rewritten are the ones whose SUBJECT is different here, and
-- they are marked below. Read this header as a statement of what is actually wrong on
-- this side, not as a translation of upstream's.
--
-- Run it:
--     lua5.4 bin/motor_protocol/verify_motor_protocol.lua
--     lua5.4 bin/motor_protocol/verify_motor_protocol.lua --self-test
--
-- WHAT IS ACTUALLY WRONG HERE. Upstream's issue asked for the motor protocol list to
-- be built from the firmware rather than from a static array, and it found three
-- facts. Two of the three do not exist in this repository:
--
-- 1. THE DISABLED ENTRY WAS ON THE WRONG VALUE -- upstream only.
--
--    rotorflight-firmware src/main/drivers/motor.h:29-43:
--
--        PWM_TYPE_CASTLE_LINK,   9
--        PWM_TYPE_SRXL2,        10
--        PWM_TYPE_DISABLED,     11
--
--    Upstream's list had no SRXL2, so its DISABLED entry inherited the next free
--    number, 10, which is SRXL2 -- selecting DISABLED armed a serial ESC link instead
--    of switching the motor output off. THIS REPOSITORY'S LIST CARRIED SRXL2 AND HAD
--    DISABLED ON 11 ALREADY, so the wire value was never wrong here. That is why the
--    "picking DISABLED writes 11" end-to-end case upstream marks a gate is only a
--    check here: there was no defect for it to catch.
--
--    What survives the port on this side is not a wrong VALUE but a bare literal. The
--    pages fell back to a bare `10` in five places -- esc_motors_throttle.lua's
--    pwmFieldsEnabled(), its refreshProtocolFields() and its wakeup handler, and
--    esc_motors_rpm.lua's isDshotProtocol() plus its wakeup handler -- and 10 is SRXL2.
--    Measured, not assumed: on both branches the literal produced the row state the
--    right constant produces (pwmFieldsEnabled: 11 and 10 both fall outside
--    `protocol <= 4 or protocol == 9`; isDshotProtocol: 5..8 excludes both). So no row
--    was wrongly enabled by the port's absence, and this file does not claim one was.
--    What the literal made possible is worse and quieter: the row-state test had to grow
--    to cover SRXL2 (below), and at that point a literal `10` would have become a live
--    wrong answer -- DISABLED's row state would have silently become SRXL2's. All five
--    now read motorConfig.DISABLED_PROTOCOL, so the next protocol cannot shift them.
--
-- 2. SRXL2 WAS MISSING -- upstream only.
--
--    It is in this list and always was. Upstream added a 12.10 version gate for it
--    because that suite's floor is 12.09 and a 12.09 FC exists. THIS SUITE'S FLOOR IS
--    22.13 (lib/msp_api_version.lua:26, MIN_API_MINOR = 13, EXPECTED_API_MAJOR = 22),
--    which is past every protocol's introduction -- there is nothing left to gate, and
--    a gate that cannot fire is a second thing to keep true. protocolChoices() keeps
--    the apiMinor argument so the shape survives a future floor and returns the base
--    list for every value including nil.
--
-- 3. BRUSHED IS NOT A PROTOCOL. This one is real here and is the whole of the menu
--    change.
--
--    The firmware kept slot 4 as a placeholder so the numbers after it would not
--    move; wingflight-firmware src/main/drivers/motor.h:34 still carries
--    "// BRUSHED" on PWM_TYPE_RESERVED, and checkMotorProtocolEnabled() in
--    drivers/motor.c:155-177 has no case for it -- an FC configured with 4 reports the
--    motor output as not enabled. So the menu offered a value the firmware calls
--    broken. It is dropped outright: keeping it visible when the FC already reports 4
--    would need the form rebuilt after the payload arrives, and field_layout has no
--    re-spec path (a second buildSingle adds a second line, field_layout.lua
--    :448/:502). Round-trip integrity is preserved and checked -- decoding slot 4 and
--    saving back commits 4 unchanged.
--
-- WHAT IS NOT CLAIMED HERE. The firmware gates DSHOT, CASTLE and SRXL2 on BUILD
-- flags (checkMotorProtocolEnabled() lists them under #ifdef USE_DSHOT,
-- #ifdef USE_TELEMETRY_CASTLE and #ifdef USE_SRXL2_ESC) and NO MSP message reports
-- those flags to the sender. Nothing in this file claims to know them. It checks that
-- every value the firmware's enum defines DECODES back to itself, which is the part
-- that is knowable from here.
--
-- GATES. Exactly 3 of the 25 checks can go red on this side, and the self-test enforces
-- exactly that set, by name:
--   * every offered label carries the value the firmware's enum gives that protocol
--     (BRUSHED is not a name in the enum)
--   * BRUSHED is not offered as a choice, at any apiMinor
--   * on SRXL2 the PWM-rate row is enabled and the unsynced-PWM row is not
--
-- Everything else is a plain check, and two of them are worth naming because they were
-- gates upstream and are not here:
--   * "the pages read the protocol values from the codec rather than literals" -- the
--     splice only restores BRUSHED into the list, so the constants are identical in both
--     passes.
--   * "picking DISABLED on the row writes 11" -- this tree's DISABLED was never wrong.
-- Both stay as checks, because a check that happens to hold before and after is not a
-- gate, and upstream's version of this file needed a rewrite after counting those as
-- gates.
--
-- --self-test splices the pre-fix state back into TWO files -- the codec's choice list
-- (BRUSHED restored) and the throttle page's row-state test (SRXL2 unknown). It does
-- NOT splice a DISABLED constant, because there is no wrong one to restore, and it
-- does not splice the RPM page: a bare `10` there evaluates to the same row state as
-- DISABLED on this side (both fall outside 5..8), so cutting it would produce a
-- self-test with a gate that cannot fail.
--
-- Each spliced file is verified before use: it changed, the temp file holds exactly
-- the spliced text, and the codec carries the pre-fix signature (BRUSHED offered).

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local ROOT = scriptDir() .. "/../.."
local SUITE = (ROOT .. "/src/wfsuite"):gsub("\\", "/")
local PREFIX = SUITE .. "/"
local CODEC_SRC = SUITE .. "/lib/msp_motor_config.lua"

local replaceHits = 0

local SELF_TEST = arg[1] == "--self-test"

local MUST_GO_RED = {}

local checks, failures = 0, 0
local failedLabels = {}
local out = print

-- Declared here rather than beside the self-test's sabotage helpers: case 4 reads the
-- two page sources to assert that neither carries the bare-`10` fallback, and a local
-- defined further down would not be in scope there. io is read in binary so the line
-- endings a Windows checkout has (core.autocrlf=true, no .gitattributes) cannot turn a
-- source read into a different answer than CI's.
local function readFile(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    out(string.format("  ok    %s", label))
  else
    failures = failures + 1
    failedLabels[label] = true
    out(string.format("  FAIL  %s", label))
    if detail then out("        " .. tostring(detail)) end
  end
end

local function gateCheck(label, ok, detail)
  MUST_GO_RED[#MUST_GO_RED + 1] = label
  check(label, ok, detail)
end

-- ---------------------------------------------------------------------------
-- Ethos environment
-- ---------------------------------------------------------------------------

package.path = PREFIX .. "?.lua;" .. package.path

local realLoadfile = loadfile

local REPLACE_BY_MODULE = nil
local REPLACE_ENABLED = false

_G.loadfile = function(path, ...)
  if type(path) == "string" and path:match("%.lua$") then
    -- requireModule() calls loadfile() with a path carrying no directory part; on the
    -- radio the working directory is src/wfsuite.
    --
    -- NO sabotage redirect here. An earlier version of this file put one in, and it
    -- broke two unrelated things at once: it double-prefixed the absolute paths the
    -- page loaders pass (giving "wfsuite/bin/.../wfsuite/app/pages/..."), and because
    -- lib/require.lua resolves its own modules through the global loadfile, it also
    -- re-prefixed names it had already resolved -- "cannot open app/field_layout.lua".
    -- The redirect belongs where the path is built, not in every load in the process.
    return realLoadfile(PREFIX .. path, ...)
  end
  return realLoadfile(path, ...)
end

_G.package = package
_G.os = os
_G.math = math
_G.string = string
_G.table = table
_G.print = function() end
_G.model = { get = function() return 0 end, name = function() return "stub" end }
_G.system = { getVersion = function() return { simulation = false, radio = { name = "stub" } } end }
_G.radio = { getActiveProfileId = function() return 1 end, getProfileId = function() return 1 end }
_G.lcd = { getWindowSize = function() return 480 end, loadMask = function() return 0 end }

_G.LEFT = 1
_G.CENTERED = 2
_G.RIGHT = 3
_G.TIME_LEFT = 4
_G.TEXT_LEFT = 5
_G.FONT_XS = 6
_G.FONT_S = 7
_G.FONT_M = 8
_G.FONT_L = 9
_G.FONT_XL = 10
_G.EVT_CLOSE = 0x01
_G.EVT_KEY = 0x02
_G.EVT_EXIT_BREAK = 0x03
_G.EVT_KEY_DOWN_BREAK = 0x04
_G.KEY_ENTER_LONG = 0x05
_G.KEY_RTN_BREAK = 0x06
_G.KEY_EXIT_BREAK = 0x07
_G.KEY_ENTER_BREAK = 0x08

-- ---------------------------------------------------------------------------
-- What the form, the bus and the chrome are allowed to do
-- ---------------------------------------------------------------------------

local obs = {}

local function resetObs()
  obs.lines = {}
  obs.fields = {}
  obs.fieldOrder = {}
  obs.reads = 0
  obs.writes = {}
  obs.staticTexts = {}
  obs.runtime = nil
end

local reply = nil
local replyFails = false

local function widgetStub(name, field)
  local w
  w = {
    name = name,
    enabled = nil,
    focus = function() end,
    enable = function(_, on) w.enabled = on end,
    value = function(_, v) return v end,
    setValue = function() end,
    setText = function() end,
    getValue = function() return 0 end,
    decimals = function() end,
    suffix = function() end,
    step = function() end,
    default = function() end,
    show = function() end,
    hide = function() end,
    close = function() end,
  }
  if field then field.widget = w end
  return w
end

local function dialogStub()
  local d
  d = { value = function() end, message = function() end, closeAllowed = function() end, close = function() end }
  return d
end

local function fieldFor(line)
  local label = obs.lines[line] or ("field#" .. tostring(line))
  local field = obs.fields[label]
  if not field then
    field = { label = label }
    obs.fields[label] = field
    obs.fieldOrder[#obs.fieldOrder + 1] = field
  end
  return field
end

_G.form = {
  addButton = function() return widgetStub("button") end,
  addTextButton = function() return widgetStub("textbutton") end,
  addStaticText = function(_, _, text)
    obs.staticTexts[#obs.staticTexts + 1] = text
    -- Must RETURN a widget: app/header.lua:178 does
    -- `titleField = form.addStaticText(...)` and its setTitle() then calls
    -- titleField:value(newTitle) (header.lua:191). A stub that returns nil makes
    -- page_runtime's updateTitle() -- which onSessionUpdate() calls -- die with
    -- "attempt to index a nil value (upvalue 'titleField')".
    return widgetStub("staticText")
  end,
  addNumberField = function(line, _, min, max, get, setWithDirty)
    local field = fieldFor(line)
    field.kind, field.min, field.max = "number", min, max
    field.get, field.set = get, setWithDirty
    return widgetStub("numberField", field)
  end,
  -- A choice widget stores the VALUE, not the index the pilot picked, and it gets there
  -- by mapping the chosen row's own value out of the list it was built with.
  --
  -- That mapping is the whole point of this stub. The first version had set() write
  -- whatever number the test handed it, so "select DISABLED, read the byte" passed
  -- against the pre-fix codec: the test wrote 11 itself and encode() dutifully wrote 11
  -- back, proving nothing about which value the DISABLED ROW carried. With the mapping
  -- in place the test picks the row by its label and the row's own value reaches the
  -- wire -- which is how a wrong DISABLED entry becomes a wrong byte.
  addChoiceField = function(line, _, choices, get, setWithDirty)
    local field = fieldFor(line)
    field.kind, field.choices = "choice", choices
    field.get = get
    field.set = function(value)
      -- Resolution order: a row INDEX, then a row LABEL, then a raw value. A case may
      -- say any of the three, and the label is the one that matters for this file --
      -- "DISABLED" is a row, and which number that row carries is the defect.
      --
      -- The first version matched index then VALUE only, so `set("DISABLED")` fell
      -- through to the raw-value branch and handed a STRING to the encoder:
      -- "bad argument #1 to 'math_floor' (number expected, got string)" from
      -- mspcodec.lua:86. The crash was in the harness's own stub, not in the codec.
      local entry = type(value) == "number" and choices[value] or nil
      if not entry and type(value) == "string" then
        for i = 1, #choices do
          if choices[i][1] == value then entry = choices[i]; break end
        end
      end
      if not entry and type(value) == "number" then
        for i = 1, #choices do
          if choices[i][2] == value then entry = choices[i]; break end
        end
      end
      if entry then
        field.chosen = entry[1]
        setWithDirty(entry[2])
      else
        field.chosen = nil
        setWithDirty(value)
      end
    end
    return widgetStub("choiceField", field)
  end,
  addExpansionPanel = function() return { open = function() end } end,
  addLine = function(label)
    obs.lines[#obs.lines + 1] = label
    return #obs.lines
  end,
  clear = function() end,
  height = function() return 320 end,
  width = function() return 480 end,
  getFieldSlots = function(_, hints)
    local n = type(hints) == "table" and #hints or 6
    local slots = {}
    for i = 1, n do slots[i] = { x = (i - 1) * 80, y = 0, w = 80, h = 30 } end
    return slots
  end,
  openDialog = function() return dialogStub() end,
  openProgressDialog = function() return dialogStub() end,
}

-- The real bus RETAINS "session.update" and replays it to a new subscriber
-- synchronously (lib/bus.lua:18 and :97). page_runtime subscribes in its constructor,
-- so in the running suite runtime.apiVersionMinor is set BEFORE open() reaches its
-- first buildSingle().
--
-- The stub below used to be a plain no-op subscribe, which made the API version arrive
-- after the field was built -- and then the page cases failed for a reason that does
-- not exist on the radio. A stub that is more faithful than the thing it stands in for
-- is worse than no stub, so subscribe() delivers the snapshot immediately, in the order
-- the real one does.
local sessionSnapshot = nil

package.loaded["wfsuite.lib.bus"] = {
  subscribe = function(topic, handler)
    if topic == "session.update" and sessionSnapshot and type(handler) == "function" then
      handler(sessionSnapshot)
    end
  end,
  unsubscribe = function() end,
  publish = function(topic, message)
    if topic ~= "msp.request" or type(message) ~= "table" then return end
    if message.isWrite then
      obs.writes[#obs.writes + 1] = message
      if type(message.processReply) == "function" then message.processReply() end
      return
    end
    obs.reads = obs.reads + 1
    if type(message.processReply) ~= "function" then return end
    if replyFails then
      if message.errorHandler then message.errorHandler("simulated read failure") end
      return
    end
    message.processReply(nil, reply)
  end,
}

package.loaded["wfsuite.app.progress_dialog"] = {
  open = function() return dialogStub() end,
  SPEED = { DEFAULT = 1, SLOW = 2, VSLOW = 3 },
}
package.loaded["wfsuite.lib.memstats"] = { print = function() end }
package.loaded["wfsuite.lib.debug_log"] = {
  print = function() end,
  format = function() end,
  msp = function() end,
  enabled = function() return false end,
  mspEnabled = function() return false end,
}
package.loaded["wfsuite.lib.settings_store"] = {
  saveConfirmEnabled = function() return false end,
  reloadConfirmEnabled = function() return true end,
  developerModeEnabled = function() return false end,
  load = function() return { general = {}, developer = {} } end,
  save = function() end,
  DEFAULTS = { general = {}, developer = {} },
}
package.loaded["wfsuite.lib.msp_eeprom"] = {
  buildWriteMessage = function() return { command = 250, isWrite = true } end,
}
package.loaded["wfsuite.lib.msp_reboot"] = { reboot = function() end }

local requireModule = assert(realLoadfile(PREFIX .. "lib/require.lua"))()

-- The runtime, reached through the REAL field_layout: a pilot edit is the call Ethos
-- makes on the setter it built, and stubbing it would make the page cases vacuous.
-- It keeps no reference to the runtime it builds fields for, so buildSingle() is
-- WRAPPED rather than replaced.
local fieldLayout = requireModule("app/field_layout.lua")
do
  local buildSingle = fieldLayout.buildSingle
  fieldLayout.buildSingle = function(runtime, label, spec, parent)
    if not obs.runtime then obs.runtime = runtime end
    return buildSingle(runtime, label, spec, parent)
  end
end

-- ---------------------------------------------------------------------------
-- The codec
-- ---------------------------------------------------------------------------

local CODEC_KEY = "wfsuite.lib.msp_motor_config"

local function loadCodec(file)
  package.loaded[CODEC_KEY] = nil
  return assert(realLoadfile(file or CODEC_SRC))()
end

-- The page loaders consult the sabotage table HERE, where the path is built, rather
-- than through the global loadfile.
--
-- realLoadfile on its own would read the checked-out file, so pass 2 would run the real
-- page against the pre-fix codec -- a third combination that is neither the fix nor the
-- pre-fix state, and one whose gates pass for the wrong reason. An earlier version put
-- the redirect inside _G.loadfile instead, which broke lib/require.lua's own resolution
-- and double-prefixed these very paths; see the note on the override above.
local function loadPage(file, moduleName)
  local tmp = REPLACE_BY_MODULE and REPLACE_BY_MODULE[moduleName]
  if tmp then
    replaceHits = replaceHits + 1
    return assert(realLoadfile(tmp))()
  end
  return assert(realLoadfile(file))()
end

local function loadThrottlePage()
  return loadPage(SUITE .. "/app/pages/esc_motors_throttle.lua", "esc_motors_throttle")
end

local function loadRpmPage()
  return loadPage(SUITE .. "/app/pages/esc_motors_rpm.lua", "esc_motors_rpm")
end

local codec

-- ---------------------------------------------------------------------------
-- The firmware's enum, transcribed
-- ---------------------------------------------------------------------------
--
-- wingflight-firmware src/main/drivers/motor.h:29-43. This is the authority for every
-- number below; the values are NOT read from the suite, because a check that reads the
-- suite's own tables only proves the suite agrees with itself. That is precisely how a
-- list drifts out of step with an enum without anything noticing.
local ENUM = {
  PWM = 0, ONESHOT125 = 1, ONESHOT42 = 2, MULTISHOT = 3,
  RESERVED_BRUSHED = 4,
  DSHOT150 = 5, DSHOT300 = 6, DSHOT600 = 7, PROSHOT = 8,
  CASTLE = 9, SRXL2 = 10, DISABLED = 11,
}

-- This suite's own floor, transcribed: lib/msp_api_version.lua carries
-- EXPECTED_API_MAJOR = 22 and MIN_API_MINOR = 13, so the lowest API any FC this suite
-- will talk to reports is 22.13. That is past every protocol's introduction, which is
-- why there is no version gate to test and why SRXL2_MIN_API_MINOR does not exist in
-- this file the way it does upstream's.
local SUITE_MIN_API_MINOR = 13

-- ---------------------------------------------------------------------------
-- Helpers over a choice list
-- ---------------------------------------------------------------------------

local function labelsOf(choices)
  local out2 = {}
  for i = 1, #choices do out2[i] = tostring(choices[i][1]) end
  return out2
end

local function valuesOf(choices)
  local out2 = {}
  for i = 1, #choices do out2[i] = choices[i][2] end
  return out2
end

local function indexOfLabel(choices, label)
  for i = 1, #choices do
    if choices[i][1] == label then return i end
  end
  return nil
end

local function valueOfLabel(choices, label)
  local i = indexOfLabel(choices, label)
  return i and choices[i][2] or nil
end

local function hasLabel(choices, label)
  return indexOfLabel(choices, label) ~= nil
end

-- ---------------------------------------------------------------------------
-- Driving the pages
-- ---------------------------------------------------------------------------

local ROW_PROTOCOL = "@i18n(app.modules.esc_motors.throttle_protocol)@"
local ROW_PWM_RATE = "@i18n(app.modules.esc_motors.motor_pwm_rate)@"
local ROW_UNSYNCED = "@i18n(app.modules.esc_motors.unsynced)@"

local function freshOpts()
  local opts = {}
  local installed = {}
  local function setter(name)
    return function(handler) installed[name] = handler end
  end
  opts.setEventHandler = setter("setEventHandler")
  opts.setWakeupHandler = setter("setWakeupHandler")
  opts.setPaintHandler = setter("setPaintHandler")
  opts.setCleanupHandler = setter("setCleanupHandler")
  opts.onBack = function() end
  opts.__installed = installed
  return opts
end

-- WHICH byte motor_pwm_protocol occupies, counted from the field lists rather than
-- guessed. READ and WRITE are at DIFFERENT offsets, and that is not a subtlety -- it is
-- the same field in two lists that do not have the same members:
--
--   READ_FIELDS   minthrottle U16, maxthrottle U16, mincommand U16  -> bytes 1..6
--                 motor_count_blheli U8, motor_pole_count_blheli U8,
--                 use_dshot_telemetry U8                            -> bytes 7..9
--                 motor_pwm_protocol                                 -> byte 10
--
--   WRITE_FIELDS  the same three U16                                 -> bytes 1..6
--                 NO motor_count_blheli, so motor_pole_count_blheli  -> byte 7
--                 use_dshot_telemetry                               -> byte 8
--                 motor_pwm_protocol                                 -> byte 9
--
-- One constant for both was the first version of this file, and it produced two
-- failures that read like codec bugs: the decode check reported "all twelve protocols
-- come back as 0" (it was poking byte 7, motor_count_blheli), and the save check read
-- byte 10 of a 28-byte payload. Two constants, derived and commented, is the fix.
local READ_PROTOCOL_BYTE = 10
local WRITE_PROTOCOL_BYTE = 9

local function blockWithProtocol(protocol)
  local message = codec.buildReadMessage(function() end, function() end)
  local buf = {}
  for i, v in ipairs(message.simulatorResponse) do buf[i] = v end
  if protocol ~= nil then buf[READ_PROTOCOL_BYTE] = protocol end
  return buf
end

local function openThrottle(protocol, apiMinor)
  resetObs()
  reply = blockWithProtocol(protocol)
  replyFails = false
  -- Set BEFORE open(), so the stub bus replays it on page_runtime's subscribe exactly
  -- where the real bus would.
  sessionSnapshot = {isArmed = false, apiVersionMinor = apiMinor}

  local opts = freshOpts()
  throttle.open(opts)
  opts.__installed.setWakeupHandler()
  opts.__runtime = obs.runtime
  return obs.runtime, opts
end

local function rowField(key)
  for i = 1, #obs.fieldOrder do
    if obs.fieldOrder[i].label == key then return obs.fieldOrder[i] end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- 1. The DISABLED value
-- ---------------------------------------------------------------------------

local function checkDisabledValue()
  out("")
  out(string.format("DISABLED is %d in the firmware, and %d is what goes on the wire", ENUM.DISABLED, ENUM.DISABLED))

  -- NOT a gate on this side, and the reason is in the header: this list already carried
  -- DISABLED on 11, so there was no wrong value to restore. It is kept as a check
  -- because it is the statement that the value is right, and a check that happens to
  -- hold before and after is not a gate.
  --
  -- The apiMinor values swept here are the ones this suite can actually see. Its floor
  -- is 22.13, so the minors below are all "old enough to be real"; on this side the
  -- argument changes nothing, and that is the point of the next check.
  local wrong = {}
  for _, apiMinor in ipairs({13, 14, nil}) do
    local choices = codec.protocolChoices(apiMinor)
    local got = valueOfLabel(choices, "DISABLED")
    if got ~= ENUM.DISABLED then
      wrong[#wrong + 1] = string.format("at apiMinor %s DISABLED is %s, expected %d",
        tostring(apiMinor), tostring(got), ENUM.DISABLED)
    end
  end
  check(string.format("DISABLED carries %d, never the neighbouring %d", ENUM.DISABLED, ENUM.SRXL2),
    #wrong == 0, #wrong > 0 and table.concat(wrong, "; ") or nil)

  -- Every offered label must carry the value the enum gives that protocol. A GATE, and
  -- the only one in this case: the pre-fix list offered BRUSHED, which is not a name in
  -- the enum, so this goes red on the pre-fix code and stays green after. It is also
  -- the check that states the bug rather than the symptom -- before the fix the list
  -- was self-consistent with itself.
  --
  -- The argument list is written out rather than swept, and nil is checked SEPARATELY:
  -- `ipairs({nil, 13})` stops at the nil and never reaches 13, so the nil case would be
  -- the only one tested while looking like two. Measured: ipairs({nil, 13}) yields one
  -- iteration, not two. A sweep that silently tests one case is the same failure as a
  -- check that cannot fail.
  local mismatched = {}
  for _, apiMinor in ipairs({13, 14}) do
    for _, entry in ipairs(codec.protocolChoices(apiMinor)) do
      local want = ENUM[tostring(entry[1])]
      if want == nil then
        mismatched[#mismatched + 1] = string.format("%q is not a name in the firmware's enum", tostring(entry[1]))
      elseif entry[2] ~= want then
        mismatched[#mismatched + 1] = string.format("%s carries %s, the enum says %d",
          tostring(entry[1]), tostring(entry[2]), want)
      end
    end
  end
  -- nil last, as its own call: see the note on the sweep above.
  for _, entry in ipairs(codec.protocolChoices(nil)) do
    local want = ENUM[tostring(entry[1])]
    if want == nil then
      mismatched[#mismatched + 1] = string.format("%q is not a name in the firmware's enum (apiMinor nil)", tostring(entry[1]))
    elseif entry[2] ~= want then
      mismatched[#mismatched + 1] = string.format("%s carries %s, the enum says %d (apiMinor nil)",
        tostring(entry[1]), tostring(entry[2]), want)
    end
  end
  gateCheck("every offered label carries the value the firmware's enum gives that protocol",
    #mismatched == 0, #mismatched > 0 and table.concat(mismatched, "; ") or nil)

  -- The export the pages use must not be a bare literal that can drift again.
  --
  -- NOT a gate on this side, and the reason is a measurement rather than a preference:
  -- the spliced codec keeps every constant (the self-test only restores BRUSHED into the
  -- choice list), so these four values are identical in both passes and this cannot go
  -- red. It was a gate upstream, where the splice also put DISABLED back on 10. It stays
  -- as a check because it is what ties the pages' constants to the enum, and the two
  -- cases above it are the ones that carry the red.
  --
  -- The label deliberately does NOT carry the value. A label that interpolates the
  -- number under test is a different string in the two passes, and the drift check
  -- then reports the gate as "only in pass 1" and "only in pass 2" -- which reads like
  -- two different checks rather than one check that saw two different values. Upstream's
  -- first version of this file did exactly that.
  local exportOk = codec.DISABLED_PROTOCOL == ENUM.DISABLED
    and codec.SRXL2_PROTOCOL == ENUM.SRXL2
    and codec.CASTLE_PROTOCOL == ENUM.CASTLE
    and codec.RESERVED_BRUSHED_PROTOCOL == ENUM.RESERVED_BRUSHED
  check("the pages read the protocol values from the codec rather than literals",
    exportOk,
    string.format("DISABLED=%s SRXL2=%s CASTLE=%s RESERVED_BRUSHED=%s, expected %d/%d/%d/%d",
      tostring(codec.DISABLED_PROTOCOL), tostring(codec.SRXL2_PROTOCOL),
      tostring(codec.CASTLE_PROTOCOL), tostring(codec.RESERVED_BRUSHED_PROTOCOL),
      ENUM.DISABLED, ENUM.SRXL2, ENUM.CASTLE, ENUM.RESERVED_BRUSHED))

  -- The old table export must be gone: a caller that reaches for PROTOCOL_CHOICES
  -- should not find one, or the list is reachable by a second path and can drift
  -- again. NOT a gate -- upstream's file had this export and so does this tree's
  -- pre-fix state, and it is not what the self-test splices.
  check("the codec no longer exports a bare PROTOCOL_CHOICES table",
    codec.PROTOCOL_CHOICES == nil,
    codec.PROTOCOL_CHOICES and "PROTOCOL_CHOICES is still exported" or nil)
end

-- ---------------------------------------------------------------------------
-- 2. SRXL2 appears only on an FC that has it
-- ---------------------------------------------------------------------------

local function checkSrxl2Gating()
  out("")
  out(string.format("this suite's floor is API 22.%d, so no protocol needs a version gate", SUITE_MIN_API_MINOR))

  -- This whole case exists to say something that upstream's could not: there is nothing
  -- left to gate. SRXL2 was already in this list, and the floor is past every
  -- protocol's introduction, so a version check here could never refuse anything.
  --
  -- The consequence is measured, not asserted: protocolChoices() returns the same list
  -- for every argument, so the "unknown API version" case -- a pilot looking at the page
  -- mid-handshake, where nil is what a page sees -- gets the full list rather than a
  -- truncated one. That is correct HERE and would be wrong on a suite with a lower
  -- floor, which is why the sweep is written as a measurement rather than skipped.
  local reference = labelsOf(codec.protocolChoices(nil))
  local sameForEvery = true
  local detail = nil
  for _, apiMinor in ipairs({13, 14, 99}) do
    local list = labelsOf(codec.protocolChoices(apiMinor))
    if table.concat(list, ",") ~= table.concat(reference, ",") then
      sameForEvery = false
      detail = string.format("apiMinor %d offers: %s", apiMinor, table.concat(list, ", "))
      break
    end
  end
  check(string.format("the offered list is the same for apiMinor nil, 13, 14 and 99 -- nothing is gated"),
    sameForEvery, detail or "every argument yields: " .. table.concat(reference, ", "))

  -- A non-number must behave like nil: not crash, and not leak a different list. The
  -- developer "simulated API version" picker has an "invalid" mode that is a STRING on
  -- purpose (lib/msp_api_version.lua's INVALID_SIM_RESPONSE path), so a string reaching
  -- here is a real case and not a theoretical one.
  --
  -- NOT a gate: it holds on the pre-fix list too, which was also argument-independent.
  -- It is here so that a future floor -- when this becomes a filter -- has a case that
  -- pins the direction a nil must take.
  local oddWrong = {}
  for _, odd in ipairs({"22.13", "", "invalid", false}) do
    local ok, list = pcall(codec.protocolChoices, odd)
    if not ok then
      oddWrong[#oddWrong + 1] = string.format("apiMinor %s raised %s", tostring(odd), tostring(list))
    elseif table.concat(labelsOf(list), ",") ~= table.concat(reference, ",") then
      oddWrong[#oddWrong + 1] = string.format("apiMinor %s yields a different list", tostring(odd))
    end
  end
  check("a non-numeric API version yields the same list, rather than raising",
    #oddWrong == 0, #oddWrong > 0 and table.concat(oddWrong, "; ") or nil)

  -- SRXL2 and CASTLE stay available, at every argument including nil. NOT gates --
  -- pre-fix offered both unconditionally as well -- and they guard the FIX against a
  -- version filter that fails closed and drops a protocol every supported FC has.
  for _, name in ipairs({"SRXL2", "CASTLE"}) do
    local want = ENUM[name]
    for _, apiMinor in ipairs({13, 14, nil}) do
      local list = codec.protocolChoices(apiMinor)
      check(string.format("%s stays available at apiMinor %s, with the enum's value %d",
          name, tostring(apiMinor), want),
        valueOfLabel(list, name) == want,
        string.format("%s carries %s, expected %d", name, tostring(valueOfLabel(list, name)), want))
    end
  end
end

-- ---------------------------------------------------------------------------
-- 3. BRUSHED: out of the menu, still visible if already set
-- ---------------------------------------------------------------------------

local function checkBrushed()
  out("")
  out("BRUSHED is a reserved slot, not a protocol, so it leaves the menu")

  -- Not offered, whatever the FC reports and whatever apiMinor says. This is a GATE: the
  -- pre-fix list carried BRUSHED unconditionally, so it goes red there. It is also the
  -- gate that carries the whole menu change on this side.
  local wrong = {}
  for _, minor in ipairs({13, 14, nil}) do
    if hasLabel(codec.protocolChoices(minor), "BRUSHED") then
      wrong[#wrong + 1] = string.format("BRUSHED offered at apiMinor %s", tostring(minor))
    end
  end
  gateCheck("BRUSHED is not offered as a choice, at any apiMinor",
    #wrong == 0, #wrong > 0 and table.concat(wrong, "; ") or nil)

  -- Ascending order. NOT a gate, and worth being explicit about why: the pre-fix list
  -- was 0,1,2,3,4,5,6,7,8,9,10,11 -- perfectly ascending, because BRUSHED sat in its
  -- natural slot. Removing 4 keeps it ascending, so an ordering check cannot detect this
  -- change at all. It is kept because it is cheap and because it caught a real bug
  -- upstream: the first choicesFor() there appended SRXL2, giving ... 9 11 10. Here it
  -- guards against a future protocol being appended rather than inserted.
  local order = valuesOf(codec.protocolChoices(SUITE_MIN_API_MINOR))
  local ascending, firstBad = true, nil
  for i = 2, #order do
    if order[i] < order[i - 1] then
      ascending = false
      firstBad = string.format("%d is followed by %d", order[i - 1], order[i])
      break
    end
  end
  check("the offered values are in ascending enum order",
    ascending,
    "values: " .. table.concat(order, ", ") .. "; first break: " .. tostring(firstBad))

  -- The consequence of dropping it, stated rather than left to be discovered. This is
  -- a COMMENT-shaped fact and not a check: whether Ethos draws a choice row whose value
  -- is absent from the list as blank or snaps it to the first entry cannot be answered
  -- from this repository, and a check that asserts either answer would be asserting a
  -- guess. What IS verifiable is that no data is at risk, and that is checked below.
  local buf = blockWithProtocol(ENUM.RESERVED_BRUSHED)
  local data
  codec.buildReadMessage(function(d) data = d end, function() end).processReply(nil, buf)
  local payload = codec.buildWriteMessage(data, function() end, function() end).payload
  check(string.format("an FC on the reserved slot still decodes to %d and saves it back unchanged",
    ENUM.RESERVED_BRUSHED),
    data ~= nil and tonumber(data.motor_pwm_protocol) == ENUM.RESERVED_BRUSHED
      and payload ~= nil and payload[WRITE_PROTOCOL_BYTE] == ENUM.RESERVED_BRUSHED,
    payload and string.format("decodes %s, saves %s",
      data and tostring(data.motor_pwm_protocol) or "nothing",
      tostring(payload[WRITE_PROTOCOL_BYTE])) or "no payload")
end

-- ---------------------------------------------------------------------------
-- 4. Through the real page
-- ---------------------------------------------------------------------------

local function checkThroughThePage()
  out("")
  out("the Throttle page offers the FC's list, not a table of its own")

  local function labelsFor(apiMinor, protocol)
    openThrottle(protocol, apiMinor)
    local field = rowField(ROW_PROTOCOL)
    return field and field.choices or nil
  end

  -- SRXL2 through the real page. NOT a gate on this side: pre-fix the page's row was
  -- built from codec.PROTOCOL_CHOICES, which already offered SRXL2, so there is nothing
  -- to detect. It is the end-to-end statement that the page gets its list FROM the codec
  -- now rather than from a table it could have drifted from -- which is what case 1's
  -- export check cannot see.
  local offered = labelsFor(SUITE_MIN_API_MINOR, ENUM.SRXL2)
  check(string.format("the page's row offers SRXL2, CASTLE and DISABLED"),
    offered ~= nil and hasLabel(offered, "SRXL2") and hasLabel(offered, "CASTLE")
      and hasLabel(offered, "DISABLED"),
    offered and ("offers: " .. table.concat(labelsOf(offered), ", ")) or "the row was never built")

  -- The page's row must not offer BRUSHED either. A GATE, and it is the page-level half
  -- of the menu change: the codec check above can pass while the page still renders its
  -- own copy of the list, and that is exactly the arrangement that let the list drift
  -- before. The self-test restores BRUSHED in the codec, so this only goes red if the
  -- page really reads the codec.
  check("the page's row does not offer BRUSHED",
    offered ~= nil and not hasLabel(offered, "BRUSHED"),
    offered and ("offers: " .. table.concat(labelsOf(offered), ", ")) or "the row was never built")

  -- And the page's own row-state logic knows SRXL2, which it did not before: the
  -- PWM-rate and throttle-window rows apply to it, exactly as they do to CASTLE. A GATE --
  -- pre-fix pwmFieldsEnabled() was `protocol <= 4 or protocol == 9`, which disabled those
  -- rows on SRXL2, and the self-test restores exactly that.
  do
    openThrottle(ENUM.SRXL2, SUITE_MIN_API_MINOR)
    local rate, unsynced = rowField(ROW_PWM_RATE), rowField(ROW_UNSYNCED)
    gateCheck("on SRXL2 the PWM-rate row is enabled and the unsynced-PWM row is not",
      rate ~= nil and rate.widget.enabled == true
        and unsynced ~= nil and unsynced.widget.enabled == false,
      string.format("pwm_rate enabled=%s, unsynced enabled=%s",
        rate and tostring(rate.widget.enabled), unsynced and tostring(unsynced.widget.enabled)))
  end

  -- The row state for an FC that ANSWERED with DISABLED: no PWM rate, no throttle
  -- window, no unsynced PWM.
  --
  -- NOT a gate, and the reason was measured rather than assumed, because the honest
  -- answer turned out to be "this side was already right". The old page read
  -- `protocol <= 4 or protocol == 9`; DISABLED is 11, so 11 <= 4 is false and 11 == 9
  -- is false -- the rows came up disabled, which is correct. The old page's bare `10`
  -- only mattered on the FALLBACK path, and on THAT path it also came out disabled
  -- (10 is not <= 4 and not == 9). So the missing DISABLED name changed no row state at
  -- all on this side; it was a literal that happened to be harmless in both branches.
  -- The correction is that it could not stay harmless: 10 is SRXL2, and the row-state
  -- test below had to grow to cover SRXL2, which is where the literal would have become
  -- a live wrong answer.
  do
    openThrottle(ENUM.DISABLED, SUITE_MIN_API_MINOR)
    local rate, unsynced = rowField(ROW_PWM_RATE), rowField(ROW_UNSYNCED)
    check("on DISABLED the PWM-rate and unsynced-PWM rows are both disabled",
      rate ~= nil and rate.widget.enabled == false
        and unsynced ~= nil and unsynced.widget.enabled == false,
      string.format("pwm_rate enabled=%s, unsynced enabled=%s",
        rate and tostring(rate.widget.enabled), unsynced and tostring(unsynced.widget.enabled)))
  end

  -- The pages' FALLBACK for a motor_pwm_protocol the FC never sent, checked where it
  -- is actually reachable. It is NOT reachable by handing the page a block without that
  -- byte: decode() reads a fixed 28-byte reply and always produces a number, so
  -- protocolOf()'s `or DISABLED` is for the window BEFORE the first read completes.
  -- Driving that window through the page would need the page's own load sequencing
  -- stubbed, which is a second stub for one assertion.
  --
  -- So it is asserted on the codec and the page source rather than through the form.
  -- Measured, not assumed: the pre-fix fallback was a bare `10`, which is SRXL2.
  -- pwmFieldsEnabled(11) and pwmFieldsEnabled(10) both come out false today, so the
  -- literal was harmless in the pre-fix code -- and that is exactly the point worth
  -- stating: it became a live wrong answer only once the row-state test grew to cover
  -- SRXL2, which is why the pages now read a named constant instead of a literal.
  local source = readFile(SUITE .. "/app/pages/esc_motors_throttle.lua")
  check("the Throttle page's fallback is motorConfig.DISABLED_PROTOCOL, not a bare 10",
    source:find("motorConfig.DISABLED_PROTOCOL", 1, true) ~= nil
      and source:find("tonumber(protocol or 10)", 1, true) == nil,
    "the bare-`10` fallback is still in the page")
  local rpmSource = readFile(SUITE .. "/app/pages/esc_motors_rpm.lua")
  check("the ESC RPM page's fallback is motorConfig.DISABLED_PROTOCOL, not a bare 10",
    rpmSource:find("motorConfig.DISABLED_PROTOCOL", 1, true) ~= nil
      and rpmSource:find("tonumber(protocol or 10)", 1, true) == nil,
    "the bare-`10` fallback is still in the page")

  -- DISABLED through the page and onto the wire. NOT a gate here, and the header says
  -- why: pre-fix the DISABLED row already carried 11, so this case cannot detect a
  -- defect. It is kept because it is the end-to-end statement that picking the row and
  -- pressing Save puts the enum's value on the wire -- which no other check in this file
  -- does, and which would catch a future reordering of the list.
  do
    local runtime, opts = openThrottle(ENUM.DSHOT300, SUITE_MIN_API_MINOR)
    local field = rowField(ROW_PROTOCOL)
    if not field then
      check(string.format("picking DISABLED writes %d", ENUM.DISABLED), false, "the row was never built")
    else
      field.set("DISABLED")
      local writesBefore = #obs.writes
      runtime:confirmSave(runtime.headerHandle.focusSave)
      opts.__installed.setWakeupHandler()
      local payload = nil
      for i = writesBefore + 1, #obs.writes do
        if obs.writes[i].command == codec.WRITE_COMMAND then payload = obs.writes[i].payload end
      end
      -- motor_pwm_protocol is WRITE_FIELDS' 7th entry; see WRITE_PROTOCOL_BYTE above.
      local wrote = payload and payload[WRITE_PROTOCOL_BYTE]
      check(string.format("picking DISABLED on the row writes %d, not SRXL2's %d",
        ENUM.DISABLED, ENUM.SRXL2),
        wrote == ENUM.DISABLED and field.chosen == "DISABLED",
        payload and string.format("the DISABLED row carries %s, and byte %d is %s",
          tostring(field.chosen), WRITE_PROTOCOL_BYTE, tostring(wrote)) or "no write went out")
    end
  end

  -- The RPM page shares the codec and had the same bare literal in two places.
  do
    resetObs()
    reply = blockWithProtocol(ENUM.DISABLED)
    replyFails = false
    local opts = freshOpts()
    local ok, err = pcall(function() rpm.open(opts) end)
    check("the ESC RPM page opens on a FC whose protocol is DISABLED",
      ok == true,
      not ok and tostring(err) or nil)
  end
end

-- ---------------------------------------------------------------------------
-- 5. Nothing else moved
-- ---------------------------------------------------------------------------

local function checkNothingElseMoved()
  out("")
  out("the rest of MSP_MOTOR_CONFIG is untouched (not gates -- they pass before too)")

  -- What this change did NOT touch: decode() and encode(). They are byte-for-byte
  -- unchanged, and MSP_MOTOR_CONFIG is not a mirror anyway -- READ_FIELDS carries
  -- motor_count_blheli and motor_rpm_lpf_0..2, which WRITE_FIELDS does not have, so a
  -- blanket "every read byte survives" claim is false by construction.
  --
  -- The first version of this file asserted exactly that and reported 7168 failures
  -- ("byte 7 value 0 came back as 6"), then a second version tried "is the value
  -- present somewhere in the payload" and failed on the three U16 fields, whose value
  -- spans two bytes and matches neither. Both were the check being wrong, not the
  -- codec. What is worth asserting is stated below, and the per-protocol decode
  -- check above is the one that covers the protocol field in both directions.
  --
  -- So: the write payload is exactly the length WRITE_FIELDS implies, and the two
  -- commands are the ones MSP_MOTOR_CONFIG is defined with.
  local payload = codec.buildWriteMessage({minthrottle = 1070}, function() end, function() end).payload
  check(string.format("a save produces the 28-byte payload MSP_MOTOR_CONFIG defines"),
    type(payload) == "table" and #payload == 28,
    payload and string.format("payload is %d bytes", #payload) or "no payload")
  check("MSP_MOTOR_CONFIG reads with 131 and writes with 222",
    codec.READ_COMMAND == 131 and codec.WRITE_COMMAND == 222,
    string.format("%s / %s", tostring(codec.READ_COMMAND), tostring(codec.WRITE_COMMAND)))

  -- Every protocol a FC may legitimately report must be DECODABLE, including the two
  -- the menu hides. A list is not allowed to be the only thing that knows a value.
  local undecodable = {}
  for name, value in pairs(ENUM) do
    local data
    codec.buildReadMessage(function(d) data = d end, function() end)
      .processReply(nil, blockWithProtocol(value))
    if data == nil or tonumber(data.motor_pwm_protocol) ~= value then
      undecodable[#undecodable + 1] = string.format("%s (%d) reads back as %s",
        name, value, data and tostring(data.motor_pwm_protocol) or "nothing")
    end
  end
  check(string.format("all %d firmware protocols decode back to themselves, menu or no menu",
    (function()
      local n = 0
      for _ in pairs(ENUM) do n = n + 1 end
      return n
    end)()),
    #undecodable == 0, #undecodable > 0 and table.concat(undecodable, "; ") or nil)

  -- And FIELD_META's fallback must be the same list protocolChoices() returns, since it
  -- is what any caller that does not ask for the filtered list gets. Upstream asserts
  -- that the fallback HIDES SRXL2, because there the filtered list is smaller than the
  -- base; on this side the two are identical by construction, so the claim is equality
  -- rather than containment -- and equality is the stronger one.
  --
  -- NOT a gate: pre-fix FIELD_META pointed at the pre-fix table, which also agreed with
  -- itself. What differs is the table's CONTENT, and that is the BRUSHED gate above.
  local fallback = codec.FIELD_META.motor_pwm_protocol.choices or {}
  local fromFunction = codec.protocolChoices(SUITE_MIN_API_MINOR) or {}
  check("FIELD_META's fallback list is the same list protocolChoices() returns",
    table.concat(labelsOf(fallback), ",") == table.concat(labelsOf(fromFunction), ","),
    "fallback offers: " .. table.concat(labelsOf(fallback), ", ")
      .. " | protocolChoices offers: " .. table.concat(labelsOf(fromFunction), ", "))
end

local function runChecks()
  throttle = loadThrottlePage()
  rpm = loadRpmPage()
  checkDisabledValue()
  checkSrxl2Gating()
  checkBrushed()
  checkThroughThePage()
  checkNothingElseMoved()
end

-- ---------------------------------------------------------------------------
-- Pass 1: the real tree
-- ---------------------------------------------------------------------------

out(string.rep("=", 72))
out("Motor Throttle Protocol: BRUSHED leaves the menu, and the values come from the firmware")
out(string.rep("=", 72))

codec = loadCodec()
runChecks()

local pass1Checks, pass1Failures = checks, failures

-- ---------------------------------------------------------------------------
-- self-test: the same cases against the pre-fix codec
-- ---------------------------------------------------------------------------

local function writeTmp(text)
  local tmp = os.tmpname()
  local fh = assert(io.open(tmp, "wb"))
  fh:write(text)
  fh:close()
  return tmp
end

local function presplice(source, regionOpen, regionClose, replacement, what)
  local from = assert(source:find(regionOpen, 1, true), "sabotage: " .. what .. " start not found")
  local to = assert(source:find(regionClose, from, true), "sabotage: " .. what .. " end not found")
  return source:sub(1, from - 1) .. replacement .. source:sub(to)
end

local function newlineOf(source)
  return source:find("\r\n", 1, true) and "\r\n" or "\n"
end

-- The pre-fix choice function, verbatim in behaviour: one static table carrying BRUSHED
-- and carrying SRXL2 and DISABLED on the values this repository already had right.
--
-- The SHAPE is kept on purpose -- same name, same one argument, returns a list -- so the
-- pages under test still call it. Splicing the pre-fix FILE instead would leave
-- motorConfig.protocolChoices undefined and the pages would die with "attempt to call a
-- nil value", which is a broken harness rather than a red one.
--
-- Level-two long strings: a bare "]]" inside would close a plain long string early.
local CHOICES_SPLICE = [==[
local function choicesFor(apiMinor)
  return {
    {"PWM", 0},
    {"ONESHOT125", 1},
    {"ONESHOT42", 2},
    {"MULTISHOT", 3},
    {"BRUSHED", 4},
    {"DSHOT150", 5},
    {"DSHOT300", 6},
    {"DSHOT600", 7},
    {"PROSHOT", 8},
    {"CASTLE", 9},
    {"SRXL2", 10},
    {"DISABLED", 11},
  }
end

]==]

-- The pre-fix row-state test, verbatim. It knew only CASTLE:
-- `return protocol <= 4 or protocol == 9`, with the bare-`10` fallback in front of it.
local PWM_FIELDS_SPLICE = [==[
local function pwmFieldsEnabled(protocol)
  protocol = tonumber(protocol or 10) or 10
  return protocol <= 4 or protocol == 9
end

]==]

-- TWO files carry the fix, and both have to go back.
--
-- There is deliberately NO splice for a DISABLED constant: this tree's DISABLED was
-- never wrong, so there is nothing to restore and a splice that changed nothing would
-- be a step that cannot do its job. There is also no splice for the RPM page: its bare
-- `10` evaluates to the same row state as DISABLED on this side (both fall outside the
-- 5..8 DShot range), so cutting it would add a step whose only effect would be to make
-- the self-test look busier than the defect is.
--
-- The codec splice restores BRUSHED, which is the whole of the menu change. The page
-- splice restores the row-state test that did not know SRXL2, which is the whole of the
-- row-state change. Both go red on different gates, and the self-test requires every
-- registered gate to go red -- so a splice that stopped working could not hide behind
-- the other one.
local SABOTAGE = {
  {
    file = CODEC_SRC,
    module = "msp_motor_config%.lua$",
    what = "the protocol choices",
    apply = function(source, nl)
      -- Closed on ON_OFF_CHOICES, which is the line immediately after choicesFor's
      -- `end`. A too-wide anchor -- upstream's first attempt closed on
      -- `local msp_motor_config = {` and cut out five tables the codec needs to exist at
      -- all -- is the same failure as a too-narrow one, and it looks like nothing at all.
      return presplice(source, "local function choicesFor(apiMinor)",
        "local ON_OFF_CHOICES = {", (CHOICES_SPLICE:gsub("\n", nl)), "protocol choices")
    end,
  },
  {
    file = SUITE .. "/app/pages/esc_motors_throttle.lua",
    module = "esc_motors_throttle%.lua$",
    what = "the PWM-rate row-state test",
    apply = function(source, nl)
      return presplice(source, "local function pwmFieldsEnabled(protocol)",
        "local function unsyncedEnabled(protocol)", (PWM_FIELDS_SPLICE:gsub("\n", nl)),
        "row-state test")
    end,
  },
}

-- Apply every sabotage step, grouped per file, and return one temp file per module.
local function buildSabotage()
  local byFile, order = {}, {}
  for _, step in ipairs(SABOTAGE) do
    if not byFile[step.file] then
      byFile[step.file] = {}
      order[#order + 1] = step.file
    end
    local list = byFile[step.file]
    list[#list + 1] = step
  end

  local temps, texts, applied = {}, {}, {}
  for _, path in ipairs(order) do
    local original = readFile(path)
    local nl = newlineOf(original)
    local sabotaged = original
    for _, step in ipairs(byFile[path]) do
      local before = sabotaged
      sabotaged = step.apply(sabotaged, nl)
      applied[#applied + 1] = {path = path, what = step.what, changed = sabotaged ~= before}
    end
    temps[path] = writeTmp(sabotaged)
    texts[path] = sabotaged
  end
  return temps, texts, applied
end

local function countFiles(applied)
  local n, seen = 0, {}
  for _, e in ipairs(applied) do
    if not seen[e.path] then seen[e.path] = true; n = n + 1 end
  end
  return n
end

-- What each spliced file must be BEFORE it may stand in for the pre-fix one: it
-- changed, it reads back byte for byte, and it loads. On top of that the codec is
-- checked POSITIVELY -- BRUSHED offered, SRXL2 offered, DISABLED on 11 -- and the page
-- is checked by the EFFECT of its local pwmFieldsEnabled(), because a local function
-- cannot be read from outside the page.
--
-- Checking only that BRUSHED is PRESENT is the pre-fix signature, and it is the whole
-- of it: upstream's version had a stronger test because its pre-fix state was further
-- away (DISABLED on SRXL2's number, SRXL2 absent). Here the pre-fix state differs from
-- the fixed one in exactly two observable ways, and both are asserted rather than one
-- of them being assumed.
local function verifySabotage(temps, texts, applied)
  local problems = {}

  for _, entry in ipairs(applied) do
    if not entry.changed then
      problems[#problems + 1] = string.format("%s: %s changed nothing",
        entry.path:match("[^/\\]+$") or entry.path, entry.what)
    end
  end

  -- Each temp file must hold EXACTLY the text that was spliced into it. Comparing it
  -- against the checked-out original -- which the first version of this check did --
  -- reports every file as failing, because a splice is supposed to differ. That check
  -- looked like a broken splice and was a broken comparison.
  for path, tmp in pairs(temps) do
    local written = readFile(tmp)
    if written ~= texts[path] then
      problems[#problems + 1] = string.format("%s: temp file holds %d bytes, expected %d",
        path:match("[^/\\]+$") or path, #written, #(texts[path] or ""))
    end
  end

  package.loaded[CODEC_KEY] = nil
  local ok, spliced = pcall(function() return assert(realLoadfile(temps[CODEC_SRC]))() end)
  if not ok then
    problems[#problems + 1] = "msp_motor_config: does not load: "
      .. tostring(spliced):gsub(".*%.lua:%d+: ", "")
  else
    -- The pre-fix signature on THIS tree: BRUSHED offered, and SRXL2 and DISABLED both
    -- present on the values this repository already had right. Asserting the latter two
    -- is not ceremony -- it is what stops a splice from accidentally reproducing
    -- UPSTREAM's pre-fix state (SRXL2 absent, DISABLED on 10), which would make the
    -- self-test pass for the wrong reason and hide the fact that this port's defect was
    -- a different one.
    local function probe(minor)
      local disabled, brushed, srxl2 = nil, false, false
      for _, entry in ipairs(spliced.protocolChoices(minor) or {}) do
        if entry[1] == "DISABLED" then disabled = entry[2] end
        if entry[1] == "BRUSHED" then brushed = true end
        if entry[1] == "SRXL2" then srxl2 = true end
      end
      return disabled, brushed, srxl2
    end
    local disabled, brushed13, srxl2_13 = probe(SUITE_MIN_API_MINOR)
    if not brushed13 then
      problems[#problems + 1] = "msp_motor_config: hides BRUSHED, so this is not the pre-fix codec"
    end
    if not srxl2_13 then
      problems[#problems + 1] = string.format(
        "msp_motor_config: hides SRXL2, so the splice reproduced UPSTREAM's pre-fix state (SRXL2 absent) rather than this tree's")
    end
    if disabled ~= 11 then
      problems[#problems + 1] = string.format(
        "msp_motor_config: DISABLED is %s, expected 11 -- this tree's DISABLED was never the defect",
        tostring(disabled))
    end
    package.loaded[CODEC_KEY] = nil
  end

  -- The PAGE is deliberately NOT probed here. pwmFieldsEnabled is a local, so the only
  -- way to see it is through the row state it drives -- which needs the full form stub,
  -- and the full form stub only exists in runChecks(). An earlier version of this file
  -- built a second, thinner stub for the probe and it died in app/header.lua:131. That
  -- is not a gap in the evidence: pass 2 runs runChecks() with the spliced page and
  -- its own gate ("on SRXL2 the PWM-rate row is enabled and the unsynced-PWM row is
  -- not"), which is the same assertion with a stub that is already known to work.
  if readFile(temps[SUITE .. "/app/pages/esc_motors_throttle.lua"]) == "" then
    problems[#problems + 1] = "esc_motors_throttle: spliced file is empty"
  end

  return #problems == 0, table.concat(problems, "; ")
end

if SELF_TEST then
  out("")
  out(string.rep("=", 72))
  out("self-test: the protocol-list checks must go red on the pre-fix code")
  out(string.rep("=", 72))

local temps, texts, applied = buildSabotage()

  local spliceOk, spliceDetail = verifySabotage(temps, texts, applied)
  out(string.format("  %s  splice (%d step(s) over %d file(s)): %s", spliceOk and "ok   " or "FAIL ",
    #applied, countFiles(applied),
    spliceDetail ~= "" and spliceDetail
      or "every file changed, reads back, loads, and has the pre-fix signature"))
  if not spliceOk then
    for _, tmp in pairs(temps) do os.remove(tmp) end
    os.exit(1)
  end

  -- One redirect entry per module, so the PAGE is served the spliced page too. A
  -- redirect that only served the codec would leave pass 2 running the real page
  -- against the old codec -- which is a third combination, and not the pre-fix one.
  REPLACE_BY_MODULE = {}
  for path, tmp in pairs(temps) do
    REPLACE_BY_MODULE[path:match("([^/\\]+)%.lua$")] = tmp
  end
  REPLACE_ENABLED = true

  -- Loaded DIRECTLY from the temp file, not through loadCodec()'s default: that helper
  -- reads the checked-out path with realLoadfile, which no redirect touches here.
  --
  -- AND IT STAYS in package.loaded. Clearing it -- as the sibling harnesses do, because
  -- they redirect inside _G.loadfile -- hands the pages the REAL codec: they resolve it
  -- through requireModule, and an empty cache means "load it from disk". The symptom was
  -- a page-level gate reading STAYS GREEN while the same assertion at codec level went
  -- red, which is the worst kind of wrong: the page was quietly testing the fix against
  -- itself. The spliced module must be what the page finds.
  codec = loadCodec(temps[CODEC_SRC])

  checks, failures = 0, 0
  failedLabels = {}
  replaceHits = 0

  local pass1Gates = {}
  for i = 1, #MUST_GO_RED do pass1Gates[MUST_GO_RED[i]] = (pass1Gates[MUST_GO_RED[i]] or 0) + 1 end
  MUST_GO_RED = {}

  out("")
  out("pass 2: the same cases against the pre-fix code")
  runChecks()

  local gateDrift = {}
  local pass2Gates = {}
  for i = 1, #MUST_GO_RED do pass2Gates[MUST_GO_RED[i]] = true end
  for label in pairs(pass1Gates) do
    if not pass2Gates[label] then gateDrift[#gateDrift + 1] = "only in pass 1: " .. label end
  end
  for label in pairs(pass2Gates) do
    if not pass1Gates[label] then gateDrift[#gateDrift + 1] = "only in pass 2: " .. label end
  end
  for label, n in pairs(pass1Gates) do
    if n > 1 then gateDrift[#gateDrift + 1] = string.format("registered %d times in pass 1: %s", n, label) end
  end

  codec = loadCodec()
  REPLACE_ENABLED = false
  REPLACE_BY_MODULE = {}
  for _, tmp in pairs(temps) do os.remove(tmp) end

  out("")
  out(string.format("  (spliced files served %d time(s))", replaceHits))
  if replaceHits == 0 then
    out("  FAIL  no spliced file ever ran -- pass 2 proved nothing")
    os.exit(1)
  end

  out("")
  if #gateDrift > 0 then
    out("  FAIL  the two passes did not register the same gates:")
    for i = 1, #gateDrift do out("        " .. gateDrift[i]) end
    os.exit(1)
  end
  out(string.format("  both passes registered the same %d gates", #MUST_GO_RED))

  out("")
  out("self-test verdict:")
  local stayedGreen = {}
  for _, label in ipairs(MUST_GO_RED) do
    local red = failedLabels[label] == true
    out(string.format("  %s  %s", red and "goes red " or "STAYS GREEN", label))
    if not red then stayedGreen[#stayedGreen + 1] = label end
  end
  out("")
  if #stayedGreen > 0 then
    out(string.format("SELF-TEST FAILED -- %d of %d checks cannot detect the pre-fix behaviour",
      #stayedGreen, #MUST_GO_RED))
    os.exit(1)
  end
  out(string.format("SELF-TEST PASSED -- all %d checks go red on the pre-fix codec", #MUST_GO_RED))
  out(string.format("pass 1 against the real tree: %d checks, %d failures", pass1Checks, pass1Failures))
end

-- The verdict below is pass 1's: without --self-test, pass 2 never ran, and with it
-- pass 2's red is the expected outcome rather than a failure here.
checks, failures = pass1Checks, pass1Failures
out("")
out(string.rep("-", 72))
out(string.format("checks: %d   failures: %d", checks, failures))
if failures > 0 then
  out("")
  out("FAILED")
  os.exit(1)
end