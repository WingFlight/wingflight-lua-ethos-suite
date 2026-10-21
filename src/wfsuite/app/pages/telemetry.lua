-- Telemetry page. Loaded on demand from Setup -> Telemetry.
--
-- Ports the original suite's Setup/Telemetry module into this rebuild's
-- page_runtime pattern. The original page owns a bespoke lifecycle because
-- it predates this lite app's shared runtime; here the core behavior is
-- expressed as ordinary multi-source page data:
--   FEATURE_CONFIG: ensure the Telemetry feature bit is enabled on save.
--   TELEMETRY_CONFIG: edit the 40 sensor slot assignments, preserving slots
--   this catalog has no switch for, and force crsf_telemetry_mode to CUSTOM
--   (see the note on CRSF_TELEMETRY_MODE_CUSTOM below).
--
-- The page shows the original grouped boolean sensor list, preserves the
-- FC's telemetry header bytes, writes up to 40 selected sensor IDs back to
-- telem_sensor_slot_1..40, then lets page_runtime perform the common
-- EEPROM write and reboot-after-save path. The header Tool button applies
-- the original default sensor set.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local pageRuntime = requireModule("app/page_runtime.lua")
local featureConfig = requireModule("lib/msp_feature_config.lua")
local telemetryConfig = requireModule("lib/msp_telemetry_config.lua")
local catalog = requireModule("lib/telemetry_sensor_catalog.lua")
local slotBudget = requireModule("lib/telemetry_slot_budget.lua")

local PAGE_TITLE = "@i18n(app.modules.telemetry.name)@"
local BTN_OK = "@i18n(app.btn_ok)@"
local BTN_CANCEL = "@i18n(app.btn_cancel)@"

-- Shown beside a native-locked switch while the FC is in NATIVE mode (#2407).
-- Reuses the ELRS page's existing "native" string; the sizing hints only
-- reserve room for it and are never drawn.
local NATIVE_TAG = "@i18n(app.modules.elrs_telemetry.mode_native)@"
local NATIVE_TAG_HINT = "  WWWWWW  "
-- Sized like the switch's own "OFF [switch] ON" run, so the switch keeps its
-- width beside the tag.
local SWITCH_HINT = "  OFF  WWW  ON  "

-- Firmware's CRSF_TELEMETRY_MODE_* (src/main/pg/telemetry.h, 0 = NATIVE).
local CRSF_TELEMETRY_MODE_NATIVE = 0
local CRSF_TELEMETRY_MODE_CUSTOM = 1

local telemetryConfigPage = {
  buildReadMessage = telemetryConfig.buildReadConfigMessage,
  buildWriteMessage = telemetryConfig.buildWriteMessage,
}

local function clearTable(t)
  for k in pairs(t) do t[k] = nil end
end

local function selectedFromSlots(slots, selected)
  clearTable(selected)
  if type(slots) ~= "table" then return end
  for i = 1, #slots do
    local id = slots[i]
    if id and id ~= 0 then
      selected[id] = true
    end
  end
end

-- Sensors the FC sends in NATIVE mode regardless of what a slot says cannot be
-- switched off from here. Only active while the mode actually is NATIVE -- once
-- the page has saved once the mode is CUSTOM, these are ordinary custom sensors
-- again (ALTITUDE 0x10B2, ATTITUDE 0x1100, FLIGHT_MODE 0x1201 in
-- crsfCustomSensorDefinitions) and the pilot regains control of them.
local function isNativeLocked(crsfMode, id)
  return crsfMode == CRSF_TELEMETRY_MODE_NATIVE
    and catalog.NATIVE_LOCKED_IDS[id] == true
end

-- NOT_AT_SAME_TIME maps a parent to its children, so "is my parent
-- native-locked?" reads catalog.CONFLICTING_WITH, the reverse map derived in
-- that file. A child of a native-locked parent is out of the pilot's reach for
-- the same reason the parent is: the firmware will not send the combined and
-- the per-axis value at the same time, and in NATIVE mode it is sending the
-- parent.
local function hasNativeLockedParent(crsfMode, id)
  local parentId = catalog.CONFLICTING_WITH[id]
  return parentId ~= nil and isNativeLocked(crsfMode, parentId)
end

-- Either the id itself or its parent is being sent by the FC whatever the page
-- does, so the page must not offer to change it.
local function isFixedByFc(crsfMode, id)
  return isNativeLocked(crsfMode, id) or hasNativeLockedParent(crsfMode, id)
end

-- The ids of one catalog group that the connected firmware can send: an
-- entry with minApiMinor is left out on older firmware. apiVersionMinor is
-- nil before the handshake, which leaves those entries out too. Called once
-- per group while the page is built.
local function offeredIds(ids, apiVersionMinor)
  local out = {}
  for _, id in ipairs(ids) do
    local minApiMinor = catalog.SENSOR_LIST[id].minApiMinor
    if minApiMinor == nil or (apiVersionMinor or 0) >= minApiMinor then
      out[#out + 1] = id
    end
  end
  return out
end

-- The ids to write, in the catalog's own order, so that what the pilot sees
-- checked is what lands on the wire. Native-locked ids are included whether
-- they appear in `selected` or not, because the FC sends them anyway; children
-- of a native-locked parent are skipped for the same reason (the FC refuses to
-- send both at once).
local function collectSelected(selected, crsfMode)
  local out = {}
  for _, id in ipairs(catalog.SENSOR_IDS) do
    if isNativeLocked(crsfMode, id) then
      out[#out + 1] = id
    elseif selected[id] == true and not hasNativeLockedParent(crsfMode, id) then
      out[#out + 1] = id
    end
  end
  return out
end

-- A slot holding an id this catalog has no switch for (GPS, ESC2, the
-- temperature and FBUS sensors, the native CRSF frames, ...) is one the pilot
-- can't see here, so a save must leave it alone.
local function isUnmanaged(id)
  return id ~= nil and id ~= 0 and catalog.SENSOR_LIST[id] == nil
end

local function countUnmanaged(slots)
  local count = 0
  if type(slots) ~= "table" then return 0 end
  for i = 1, telemetryConfig.SLOT_COUNT do
    if isUnmanaged(slots[i]) then count = count + 1 end
  end
  return count
end

-- Re-emits `slots`, leaving every unmanaged slot in place and filling the
-- remaining slots from `selectedOrdered` in order. Any leftover managed
-- slots are padded with 0.
local function slotsPreservingUnmanaged(slots, selectedOrdered)
  local out = {}
  local nextSelected = 1
  for i = 1, telemetryConfig.SLOT_COUNT do
    local id = slots and slots[i]
    if isUnmanaged(id) then
      out[i] = id
    else
      local nextId = selectedOrdered[nextSelected]
      if nextId then
        out[i] = nextId
        nextSelected = nextSelected + 1
      else
        out[i] = 0
      end
    end
  end
  return out
end

local function applyDefaultSelection(selected, crsfMode, apiVersionMinor)
  clearTable(selected)
  for _, id in ipairs(catalog.DEFAULT_IDS) do
    local minApiMinor = catalog.SENSOR_LIST[id].minApiMinor
    if minApiMinor == nil or (apiVersionMinor or 0) >= minApiMinor then
      selected[id] = true
    end
  end
  -- Fixed-by-FC sensors cannot be switched off by the user, so "set defaults"
  -- must not quietly switch off a sensor the FC is sending either -- the same
  -- reason collectSelected() adds those ids back unconditionally. Children of a
  -- fixed parent are deliberately not added: the firmware will not send the
  -- combined and the per-axis value together.
  for id in pairs(catalog.NATIVE_LOCKED_IDS) do
    if isFixedByFc(crsfMode, id) then
      selected[id] = true
    end
  end
end

local function openTooManyDialog()
  form.openDialog({
    title = PAGE_TITLE,
    message = "@i18n(app.modules.telemetry.no_more_than_40)@",
    buttons = {
      {label = BTN_OK, action = function() return true end},
    },
    wakeup = function() end,
    paint = function() end,
  })
end

local function open(opts)
  local selected = {}
  local previousConflictState = {}
  local fieldsBySensor = {}
  -- The FC's crsf_telemetry_mode as read, or nil while the page is still
  -- loading. Read into a local rather than read back off runtime.data, so
  -- beforeSave/collectSelected see the mode the *page* was built against.
  local crsfMode = nil
  -- Native-lock tags by sensor id, filled in while the rows are built and
  -- retexted once the FC's mode is known (see refreshNativeTags()).
  local nativeTags = {}

  local function refreshNativeTags()
    for id, tag in pairs(nativeTags) do
      tag:value(isNativeLocked(crsfMode, id) and NATIVE_TAG or "")
    end
  end

  local function refreshConflictFields()
    for id, field in pairs(fieldsBySensor) do
      -- A sensor the FC is sending (or whose parent it is sending) stays
      -- disabled: its setter rejects a change anyway.
      if not isFixedByFc(crsfMode, id) then
        field:enable(true)
      end
    end
    for id, conflicts in pairs(catalog.NOT_AT_SAME_TIME) do
      if selected[id] == true then
        for _, conflictId in ipairs(conflicts) do
          -- A fixed-by-FC conflict is not switched off here: the FC sends it
          -- whether a slot selects it or not, so claiming it is off would be a
          -- lie the save would not keep.
          if isFixedByFc(crsfMode, conflictId) then
            selected[conflictId] = true
          else
            previousConflictState[conflictId] = selected[conflictId]
            selected[conflictId] = false
            if fieldsBySensor[conflictId] then
              fieldsBySensor[conflictId]:enable(false)
            end
          end
        end
      end
    end
  end

  local runtime
  runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE,
    logTag = "telemetry",
    sources = {
      {key = "feature", mspModule = featureConfig},
      {key = "telemetry", mspModule = telemetryConfigPage},
    },
    opts = opts,
    profileField = "none",
    rebootAfterSave = true,
    unloadPackageKeys = {
      "wfsuite.lib.msp_feature_config",
      "wfsuite.lib.msp_telemetry_config",
      "wfsuite.lib.telemetry_sensor_catalog",
      "wfsuite.lib.telemetry_slot_budget",
    },
    onLoaded = function()
      local telemetry = runtime.data.telemetry or {}
      crsfMode = telemetry.crsf_telemetry_mode
      selectedFromSlots(telemetry.slots, selected)
      previousConflictState = {}
      refreshConflictFields()
      refreshNativeTags()
      if form.invalidate then form.invalidate() end
    end,
    beforeSave = function(rt)
      local feature = rt.data.feature
      if feature then
        feature.enabledFeatures = featureConfig.setBit(
          feature.enabledFeatures,
          featureConfig.FEATURE_BIT_TELEMETRY,
          true)
      end
      local telemetry = rt.data.telemetry
      if telemetry then
        -- Preserved slots count against the 40 just as managed ones do, so
        -- the "no more than 40" refusal stays honest now that unmanaged slots
        -- are no longer overwritten with 0.
        local unmanaged = countUnmanaged(telemetry.slots)
        local ordered = collectSelected(selected, crsfMode)
        if slotBudget.overflows(#ordered, unmanaged, telemetryConfig.SLOT_COUNT) then
          -- Refused: slots and mode are left exactly as read, so the write
          -- that follows re-sends the flight controller's current state
          -- rather than a truncated version of the pilot's wish.
          openTooManyDialog()
          return
        end
        telemetry.slots = slotsPreservingUnmanaged(telemetry.slots, ordered)
        telemetry.crsf_telemetry_mode = CRSF_TELEMETRY_MODE_CUSTOM
      end
    end,
    toolIcon = "app/gfx/nav/defaults.png",
    onTool = function(focusFn)
      if not runtime.loaded then return end
      -- Captured here, not closed over directly in the dialog button's
      -- own action below -- matching app/page_runtime.lua's own
      -- confirmSave()/confirmReload() dialogs (see their comments): a
      -- dialog button's action is handed straight to Ethos same as a
      -- field setter is, so it gets the same small-indirection-table
      -- treatment.
      local controlRef = runtime.controlRef
      form.openDialog({
        title = PAGE_TITLE,
        message = "@i18n(app.modules.telemetry.msg_set_defaults)@",
        buttons = {
          {label = BTN_OK, action = function()
            local rt = controlRef and controlRef.runtime
            if rt then rt:markDirty() end
            applyDefaultSelection(selected, crsfMode, rt and rt.apiVersionMinor)
            previousConflictState = {}
            refreshConflictFields()
            if form.invalidate then form.invalidate() end
            if focusFn then focusFn() end
            return true
          end},
          {label = BTN_CANCEL, action = function()
            if focusFn then focusFn() end
            return true
          end},
        },
        wakeup = function() end,
        paint = function() end,
      })
    end,
  })

  form.clear()
  runtime:buildChrome()
  -- Captured instead of closing over `runtime` directly in the checkbox
  -- setter below -- matching app/pages/pids.lua's own dataRef convention
  -- (see its comment): Ethos retains some form callback closures past
  -- this page's own lifetime, and controlRef.runtime gets nilled on
  -- dispose (app/page_runtime.lua's own PageRuntime:dispose()), so
  -- whatever gets retained here stays small instead of pinning the whole
  -- disposed PageRuntime.
  local controlRef = runtime.controlRef
  local function markDirty()
    local rt = controlRef.runtime
    if rt then rt:markDirty() end
  end

  for _, groupKey in ipairs(catalog.GROUP_ORDER) do
    local group = catalog.SENSOR_GROUPS[groupKey]
    if group and group.ids and #group.ids > 0 then
      local panel = form.addExpansionPanel(group.title)
      panel:open(false)
      for _, id in ipairs(offeredIds(group.ids, runtime.apiVersionMinor)) do
        local sensor = catalog.SENSOR_LIST[id]
        local sensorId = id
        local line = panel:addLine(sensor.name)
        -- Only the native-locked rows carry a tag. The tag and the switch
        -- share the line; the switch keeps the right-hand slot it always had.
        local switchSlot = nil
        if catalog.NATIVE_LOCKED_IDS[sensorId] == true then
          local slots = form.getFieldSlots(line, {0, NATIVE_TAG_HINT, SWITCH_HINT})
          nativeTags[sensorId] = form.addStaticText(line, slots[2], "")
          switchSlot = slots[3]
        end
        local field = form.addBooleanField(line, switchSlot,
          function()
            -- Fixed-by-FC reads as on even if nothing put it in `selected`:
            -- the FC is sending it, so the switch must not show off.
            if isFixedByFc(crsfMode, sensorId) then return true end
            return selected[sensorId] == true
          end,
          function(value)
            -- Refuse the change outright while the FC is sending this sensor
            -- (or its parent). Returning false leaves the switch where the
            -- getter last reported it, so the pilot's tap does not make the
            -- page disagree with the FC.
            if isFixedByFc(crsfMode, sensorId) then return false end

            -- The same quantity the save check counts: the switches the save would
            -- write (native-locked ones included) and the kept native slots.
            local rt = controlRef.runtime
            local telemetrySlots = rt and rt.data and rt.data.telemetry and rt.data.telemetry.slots
            if value == true and selected[sensorId] ~= true
                and slotBudget.overflowsWithOneMore(
                  #collectSelected(selected, crsfMode),
                  countUnmanaged(telemetrySlots),
                  telemetryConfig.SLOT_COUNT) then
              openTooManyDialog()
              return false
            end

            local conflicts = catalog.NOT_AT_SAME_TIME[sensorId]
            if conflicts then
              if value == true then
                for _, conflictId in ipairs(conflicts) do
                  previousConflictState[conflictId] = selected[conflictId]
                  selected[conflictId] = false
                  if fieldsBySensor[conflictId] then
                    fieldsBySensor[conflictId]:enable(false)
                  end
                end
              else
                for _, conflictId in ipairs(conflicts) do
                  if fieldsBySensor[conflictId] then
                    fieldsBySensor[conflictId]:enable(true)
                  end
                  if previousConflictState[conflictId] ~= nil then
                    selected[conflictId] = previousConflictState[conflictId]
                    previousConflictState[conflictId] = nil
                  end
                end
              end
            end

            markDirty()
            selected[sensorId] = value == true
            if form.invalidate then form.invalidate() end
          end)
        fieldsBySensor[sensorId] = field
        runtime:registerField("telemetry:" .. sensorId, field)
      end
    end
  end

  runtime:loadInitial()
end

return {open = open}
