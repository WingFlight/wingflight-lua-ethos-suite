-- Mixer Rules page. Loaded on demand from Setup -> Mixer Rules.
--
-- Edits the MSP_MIXER_RULES / MSP_SET_MIXER_RULE command pair (cmd
-- 172/173, see lib/msp_mixer_rules.lua) -- the 32-slot rule table that
-- actually maps an input onto an output, distinct from both
-- app/pages/mixer_config.lua's MSP_MIXER_INPUT (per-axis Roll/Pitch/Yaw
-- gain scaling) and app/pages/curves.lua's MSP_MIXER_CURVES (the curve
-- *shapes* a rule's own Curve field can reference).
--
-- Two screens, mirroring app/pages/servos_pwm.lua's list->editor shape
-- (simpler than app/pages/curves.lua's three-screen category->slot->editor,
-- since there's only one pool here, not two):
--   open(): one-off whole-pool GET (own progress dialog, like
--     servos_pwm.lua's own top-level open()), then openList().
--   openList(): a full-width scrollable row per rule over the already-
--     fetched pool (every slot listed, matching Curves' own "list every
--     slot" convention -- no separate Add button; tapping an unused slot
--     IS how you add a rule), each row summarizing its rule
--     (operation/input/output, see summaryFor()) rather than a bare
--     "Rule N" tile -- tapping a row opens openEditor().
--   openEditor(): a PageRuntime-backed editor for one rule. Unlike a
--     curve, a rule has no point-array substructure -- lib/msp_mixer_rules.lua's
--     decoded shape is already flat scalar fields, so (unlike curves.lua's
--     own page-local flatten/unflatten) this page needs no extra glue
--     between the codec and app/field_layout.lua.
--
-- Move Up/Move Down/Delete Rule are exposed directly on configured list
-- rows, where the slot order is visible. Rule evaluation ORDER matters
-- (a Set rule establishes a base value; later Add/Mul rules for the same
-- output compound on it in array order -- see lib/msp_mixer_rules.lua's
-- header), so Move Up/Down swap this rule's data with the adjacent
-- slot's and write both back, mirroring wingflight-configurator's own
-- Mixer.swapRules; Delete clears this slot to lib/msp_mixer_rules.lua's
-- defaultRule() (oper=0, matching the firmware's own "unused" gate). All
-- three write directly (plus an EEPROM commit) rather than going through
-- the editor's pending-edit Save flow.
--
-- `condition` is exposed as a bare "None"/"Condition 1".."Condition 16"
-- index -- Logic Conditions (LOGIC_CONDITION_COUNT=16) has no port in
-- this suite at all (no name, no gating status), same treatment `curve`
-- slots got before app/pages/curves.lua existed. `weight`/`weightNeg` are
-- exposed raw (two plain signed fields) rather than reconstructed into
-- wingflight-configurator's derived Weight/Differential%/Reverse
-- presentation -- both raw fields are independently meaningful (gain
-- applied when input is positive vs. negative) without it, so this page
-- doesn't need to duplicate that conversion logic at all. That conversion
-- (src/tabs/mixer/util.js in that project) round-trips normal Reverse +
-- Differential rules correctly as of its 2026-08-10 fix, but stays
-- documented there as lossy for out-of-range/mismatched-sign values from
-- hand-editing via CLI -- another reason to keep this page on the raw
-- fields rather than inherit that edge case here too.

local requireModule = assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local closeKey = requireModule("app/close_key.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local header = requireModule("app/header.lua")
local pageRuntime = requireModule("app/page_runtime.lua")
local progressDialog = requireModule("app/progress_dialog.lua")
local curveSlotLabels = requireModule("app/curve_slot_labels.lua")
local eeprom = requireModule("lib/msp_eeprom.lua")
local mixerRules = requireModule("lib/msp_mixer_rules.lua")

local PAGE_TITLE = "@i18n(app.modules.mixer_rules.name)@"
local MSG_LOADING_TITLE = "@i18n(app.msg_loading)@"
local MSG_LOADING_BODY = "@i18n(app.msg_loading_from_fbl)@"
local MSG_LOAD_ERROR = "@i18n(app.modules.ports.load_error_prefix)@"
local BTN_OK = "@i18n(app.btn_ok)@"
local BTN_CANCEL = "@i18n(app.btn_cancel)@"

-- oper: 0=None(unused)/1=Set/2=Add/3=Mul -- matches lib/msp_mixer_rules.lua's
-- own FIELD_META.oper range and wingflight-configurator's Mixer.js operNames.
local OPER_OPTIONS = {
  {"@i18n(app.modules.mixer_rules.oper_none)@", 0},
  {"@i18n(app.modules.mixer_rules.oper_set)@", 1},
  {"@i18n(app.modules.mixer_rules.oper_add)@", 2},
  {"@i18n(app.modules.mixer_rules.oper_mul)@", 3},
}

-- input: 27 entries (wire values 0-26), matching wingflight-configurator's
-- Mixer.js inputNames exactly -- 0 None, 1-4 Stabilized R/P/Y/T, 5-8 RC
-- Command R/P/Y/T, 9-12 RC Channel R/P/Y/T, 13-15 RC Channel Aux 1-3,
-- 16-26 RC Channel 8-18 (raw numbered channels beyond the named first 7).
local INPUT_OPTIONS = {
  {"@i18n(app.modules.mixer_rules.input_none)@", 0},
  {"@i18n(app.modules.mixer_rules.input_stab_roll)@", 1},
  {"@i18n(app.modules.mixer_rules.input_stab_pitch)@", 2},
  {"@i18n(app.modules.mixer_rules.input_stab_yaw)@", 3},
  {"@i18n(app.modules.mixer_rules.input_stab_throttle)@", 4},
  {"@i18n(app.modules.mixer_rules.input_rccmd_roll)@", 5},
  {"@i18n(app.modules.mixer_rules.input_rccmd_pitch)@", 6},
  {"@i18n(app.modules.mixer_rules.input_rccmd_yaw)@", 7},
  {"@i18n(app.modules.mixer_rules.input_rccmd_throttle)@", 8},
  {"@i18n(app.modules.mixer_rules.input_rcch_roll)@", 9},
  {"@i18n(app.modules.mixer_rules.input_rcch_pitch)@", 10},
  {"@i18n(app.modules.mixer_rules.input_rcch_yaw)@", 11},
  {"@i18n(app.modules.mixer_rules.input_rcch_throttle)@", 12},
  {"@i18n(app.modules.mixer_rules.input_rcch_aux1)@", 13},
  {"@i18n(app.modules.mixer_rules.input_rcch_aux2)@", 14},
  {"@i18n(app.modules.mixer_rules.input_rcch_aux3)@", 15},
}
for ch = 8, 18 do
  INPUT_OPTIONS[#INPUT_OPTIONS + 1] = {
    string.format("@i18n(app.modules.mixer_rules.input_rcch_fmt)@", ch),
    16 + (ch - 8),
  }
end

-- output: 31 entries (wire values 0-30) -- 0 None, 1-8 PWM Servo 1-8,
-- 9-26 Bus Servo 1-18 (wire value minus 8), 27-30 Motor 1-4 (wire value
-- minus 26) -- matches wingflight-configurator's Mixer.js outputNames/
-- outputLabel() PWM-vs-Bus split (PWM_SERVO_COUNT=8), and this suite's
-- own app/pages/servos_pwm.lua/servos_bus.lua naming.
local OUTPUT_OPTIONS = {
  {"@i18n(app.modules.mixer_rules.output_none)@", 0},
}
for n = 1, 8 do
  OUTPUT_OPTIONS[#OUTPUT_OPTIONS + 1] = {
    string.format("@i18n(app.modules.mixer_rules.output_pwm_servo_fmt)@", n),
    n,
  }
end
for n = 1, 18 do
  OUTPUT_OPTIONS[#OUTPUT_OPTIONS + 1] = {
    string.format("@i18n(app.modules.mixer_rules.output_bus_servo_fmt)@", n),
    8 + n,
  }
end
for n = 1, 4 do
  OUTPUT_OPTIONS[#OUTPUT_OPTIONS + 1] = {
    string.format("@i18n(app.modules.mixer_rules.output_motor_fmt)@", n),
    26 + n,
  }
end

-- condition: 0=always active, 1-16=Logic Condition N (bare index -- see
-- this file's own header for why).
local CONDITION_OPTIONS = {
  {"@i18n(app.modules.mixer_rules.condition_none)@", 0},
}
for n = 1, 16 do
  CONDITION_OPTIONS[#CONDITION_OPTIONS + 1] = {
    string.format("@i18n(app.modules.mixer_rules.condition_slot_fmt)@", n),
    n,
  }
end

-- curve: 0=None, 1-8 = the same Mixer-category 8-slot pool
-- app/pages/curves.lua edits -- shares the exact "Curve N" label
-- convention app/pages/master_gains.lua already uses for its own
-- gain-curve pickers.
local CURVE_OPTIONS = curveSlotLabels.optionsTable(8)

local function ruleTitle(n)
  return string.format("@i18n(app.modules.mixer_rules.tile_rule_fmt)@", n)
end

local function cloneRule(rule)
  if not rule then return mixerRules.defaultRule() end
  return {
    oper = rule.oper or 0,
    input = rule.input or 0,
    output = rule.output or 0,
    offset = rule.offset or 0,
    weight = rule.weight or 0,
    weightNeg = rule.weightNeg or 0,
    speed = rule.speed or 0,
    curve = rule.curve or 0,
    condition = rule.condition or 0,
  }
end

-- Looks up the already-i18n-resolved display label for a wire value out
-- of one of the *_OPTIONS tables above -- "@i18n(KEY)" + "@" tags (split
-- here so this comment itself doesn't get matched and flagged unresolved
-- by the resolver -- see app/header.lua's own comment for the same
-- issue) are a build-time text substitution (see
-- .vscode/scripts/resolve_i18n_tags.py), so by the time this code
-- actually runs, option[1] is already plain display text, safe to read
-- back for a summary string.
local function labelFor(options, value)
  for _, opt in ipairs(options) do
    if opt[2] == value then return opt[1] end
  end
  return tostring(value)
end

-- One-line list-row summary: "N. Empty" for an unused slot, or
-- "N. <Operation>  <Input> -> <Output>" for a configured one -- lets the
-- list screen show enough to recognize a rule at a glance, matching
-- Ethos's own native list screens (e.g. the built-in Mixes page) rather
-- than a bare "Rule N" tile a pilot would have to open to identify.
local function summaryFor(index, rule)
  if mixerRules.isEmpty(rule) then
    return index .. ". @i18n(app.modules.mixer_rules.tile_empty)@"
  end
  return index .. ". " .. labelFor(OPER_OPTIONS, rule.oper) .. "  " ..
    labelFor(INPUT_OPTIONS, rule.input) .. " -> " .. labelFor(OUTPUT_OPTIONS, rule.output)
end

local openList

local function writeRule(index, rule)
  bus.publish("msp.request", mixerRules.buildWriteMessage(index, rule))
end

local function commitRuleActions()
  bus.publish("msp.request", eeprom.buildWriteMessage())
end

local function moveRule(opts, listState, index, delta)
  local other = index + delta
  if other < 0 or other > mixerRules.RULE_COUNT - 1 then return end

  local mine = listState.pool[index + 1]
  local theirs = listState.pool[other + 1]
  listState.pool[index + 1], listState.pool[other + 1] = theirs, mine
  listState.selected = other + 1
  writeRule(other, mine)
  writeRule(index, theirs)
  commitRuleActions()
  openList(opts, listState)
end

local function deleteRule(opts, listState, index)
  local cleared = mixerRules.defaultRule()
  listState.pool[index + 1] = cleared
  listState.selected = index + 1
  writeRule(index, cleared)
  commitRuleActions()
  openList(opts, listState)
end

local function confirmDeleteRule(opts, listState, index)
  form.openDialog({
    title = "@i18n(app.modules.mixer_rules.delete_rule)@",
    message = summaryFor(index + 1, listState.pool[index + 1]),
    buttons = {
      {label = BTN_OK, action = function()
        deleteRule(opts, listState, index)
        return true
      end},
      {label = BTN_CANCEL, action = function() return true end},
    },
    wakeup = function() end,
    paint = function() end,
    options = TEXT_LEFT,
  })
end

local function openEditor(opts, listState, index)
  local runtime
  runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE .. " / " .. ruleTitle(index + 1),
    logTag = "mixer_rules_editor",
    mspModule = mixerRules.forSlot(index),
    initialData = cloneRule(listState.pool[index + 1]),
    opts = {
      onBack = function() openList(opts, listState) end,
      setEventHandler = opts.setEventHandler,
      setWakeupHandler = opts.setWakeupHandler,
      setPaintHandler = opts.setPaintHandler,
      setCleanupHandler = opts.setCleanupHandler,
    },
    profileField = "none",
    unloadPackageKeys = {"wfsuite.lib.msp_mixer_rules"},
    beforeSave = function(rt)
      listState.pool[index + 1] = cloneRule(rt.data)
    end,
  })

  form.clear()
  runtime:buildChrome()

  fieldLayout.buildSingle(runtime, "@i18n(app.modules.mixer_rules.operation)@", {key = "oper", choices = OPER_OPTIONS})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.mixer_rules.input)@", {key = "input", choices = INPUT_OPTIONS})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.mixer_rules.output)@", {key = "output", choices = OUTPUT_OPTIONS})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.mixer_rules.offset)@", {key = "offset"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.mixer_rules.weight)@", {key = "weight"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.mixer_rules.weight_neg)@", {key = "weightNeg"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.mixer_rules.speed)@", {key = "speed"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.mixer_rules.curve)@", {key = "curve", choices = CURVE_OPTIONS})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.mixer_rules.condition)@", {key = "condition", choices = CONDITION_OPTIONS})

  runtime:loadInitial()
end

openList = function(opts, listState)
  form.clear()
  local headerHandle = header.build(PAGE_TITLE, {onBack = opts.onBack})

  if opts.setEventHandler then
    opts.setEventHandler(function(category, value)
      if closeKey.shouldHandleClose(category, value) then
        opts.onBack()
        return true
      end
      return false
    end)
  end
  if opts.setWakeupHandler then opts.setWakeupHandler(nil) end
  if opts.setPaintHandler then opts.setPaintHandler(nil) end
  if opts.setCleanupHandler then opts.setCleanupHandler(nil) end

  -- One full-width row per rule, normal document flow (form.addLine() +
  -- form.getFieldSlots() for the row's own y/h) rather than a tile grid
  -- -- Ethos's own native list screens (e.g. the built-in Mixes page)
  -- scroll a plain stack of rows like this natively, and a full-width
  -- row has room for a real summary (see summaryFor()) instead of a bare
  -- "Rule N" tile label.
  --
  -- x/w come from lcd.getWindowSize() instead of the slot's own x/w --
  -- confirmed live: form.getFieldSlots(line, {0}) on a blank-titled line
  -- still reserves an implicit label-zone on the left (roughly half the
  -- screen), giving a single {0} flex slot only the remaining right
  -- portion, not the true full width. app/pages/alignment.lua's own
  -- control row already works around this exact gap the same way --
  -- trust the slot for y/h only, compute x/w by hand.
  --
  -- Left/right margins deliberately asymmetric: confirmed live, a
  -- scrollable page (this list, unlike any single-screen editor built so
  -- far) reserves a scrollbar gutter on the right (~12px) that
  -- lcd.getWindowSize() doesn't appear to already exclude -- rows sized
  -- off the raw window width ran under/into that gutter.
  local winW = ({lcd.getWindowSize()})[1]
  local rowLeftMargin = 4
  local rowRightMargin = 12
  local rowX, rowW = rowLeftMargin, winW - rowLeftMargin - rowRightMargin
  local buttonGap = 4
  local actionW = math.max(30, math.floor(winW * 0.07))
  local actionTotalW = (actionW * 3) + (buttonGap * 3)

  local buttons = {}
  for i = 1, mixerRules.RULE_COUNT do
    local rule = listState.pool[i]
    local active = not mixerRules.isEmpty(rule)
    local line = form.addLine("")
    local slot = form.getFieldSlots(line, {0})[1]
    local mainW = active and (rowW - actionTotalW) or rowW
    buttons[i] = form.addButton(line, {x = rowX, y = slot.y, w = mainW, h = slot.h}, {
      text = summaryFor(i, rule),
      options = FONT_S + LEFT,
      press = function()
        listState.selected = i
        openEditor(opts, listState, i - 1)
      end,
    })

    if active then
      local x = rowX + mainW + buttonGap
      form.addButton(line, {x = x, y = slot.y, w = actionW, h = slot.h}, {
        text = "Up",
        options = FONT_S + CENTERED,
        press = function() moveRule(opts, listState, i - 1, -1) end,
      })
      x = x + actionW + buttonGap
      form.addButton(line, {x = x, y = slot.y, w = actionW, h = slot.h}, {
        text = "Dn",
        options = FONT_S + CENTERED,
        press = function() moveRule(opts, listState, i - 1, 1) end,
      })
      x = x + actionW + buttonGap
      form.addButton(line, {x = x, y = slot.y, w = actionW, h = slot.h}, {
        text = "X",
        options = FONT_S + CENTERED,
        press = function() confirmDeleteRule(opts, listState, i - 1) end,
      })
    end
  end

  if buttons[listState.selected] then
    buttons[listState.selected]:focus()
  else
    headerHandle.focusMenu()
  end
end

local function open(opts)
  local disposed = false
  local pendingPool = nil
  local pendingError = nil
  local dialog = nil

  local function closeDialog(force)
    if not dialog then return end
    local d = dialog
    dialog = nil
    pcall(function() d:value(100) end)
    pcall(function() d:close(force == true) end)
  end

  local function goBack()
    disposed = true
    closeDialog(true)
    if opts.onBack then opts.onBack() end
  end

  form.clear()
  header.build(PAGE_TITLE, {onBack = goBack})
  form.addLine(MSG_LOADING_TITLE)
  dialog = progressDialog.open({
    title = MSG_LOADING_TITLE,
    message = MSG_LOADING_BODY,
  })

  if opts.setEventHandler then
    opts.setEventHandler(function(category, value)
      if closeKey.shouldHandleClose(category, value) then
        goBack()
        return true
      end
      return false
    end)
  end
  if opts.setCleanupHandler then
    opts.setCleanupHandler(function()
      disposed = true
      closeDialog(true)
    end)
  end
  if opts.setWakeupHandler then
    opts.setWakeupHandler(function()
      if disposed then return end
      if pendingError then
        pendingError = nil
        closeDialog()
        form.clear()
        header.build(PAGE_TITLE, {onBack = goBack})
        form.addLine(MSG_LOAD_ERROR .. " " .. PAGE_TITLE)
        return
      end
      if pendingPool then
        local listState = {pool = pendingPool, selected = 1}
        closeDialog()
        opts.setWakeupHandler(nil)
        openList(opts, listState)
      end
    end)
  end

  bus.publish("msp.request", mixerRules.buildReadPoolMessage(function(pool)
    if disposed then return end
    pendingPool = pool
  end, function()
    if disposed then return end
    pendingError = true
  end))
end

return {open = open}
