-- Setup Wizard step: Airframe. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepAirframe.svelte and the
-- Mixer tab's model setup dialog: choose a model type and its options, and
-- the wizard writes the whole mix (lib/setup_wizard_mix.lua, a port of
-- Mixer.buildWizardRules()) and the model type. One question per screen,
-- with a picture of the result so far:
--
--   current   what the model has now; Keep it, or Change
--   type      regular, flying wing, V-tail, delta, rudder-elevator trainer
--   ailerons / tail / wingYaw / flaps / follow / motors / diff
--             only the questions the type asks
--   review    the servos this sets, a warning when the board has fewer
--             servo outputs, and Apply
--
-- Custom mixes stay on the Mixer Rules page, as in the configurator. Thrust
-- vectoring is left to the Configurator: applying a type here replaces the
-- whole rule table, thrust vector rules included, and the review says so.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local ui = requireModule("app/setup_wizard_ui.lua")
-- Freed when the step closes (app/setup_wizard_ui.lua's notLoaded()).
local OWNED = ui.notLoaded({"wfsuite.lib.setup_wizard_mix"})
local art = requireModule("app/setup_wizard_art.lua")
local mix = requireModule("lib/setup_wizard_mix.lua")
local surfacesLib = requireModule("lib/setup_wizard_surfaces.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.air_title)@",
  current = "@i18n(app.modules.setup_wizard.air_current_fmt)@",
  custom = "@i18n(app.modules.setup_wizard.air_custom)@",
  none = "@i18n(app.modules.setup_wizard.air_no_surfaces)@",
  keep = "@i18n(app.modules.setup_wizard.air_keep)@",
  change = "@i18n(app.modules.setup_wizard.air_change)@",
  typeQ = "@i18n(app.modules.setup_wizard.air_q_type)@",
  aileronsQ = "@i18n(app.modules.setup_wizard.air_q_ailerons)@",
  tailQ = "@i18n(app.modules.setup_wizard.air_q_tail)@",
  wingYawQ = "@i18n(app.modules.setup_wizard.air_q_wing_yaw)@",
  flapsQ = "@i18n(app.modules.setup_wizard.air_q_flaps)@",
  followQ = "@i18n(app.modules.setup_wizard.air_q_follow)@",
  motorsQ = "@i18n(app.modules.setup_wizard.air_q_motors)@",
  diffQ = "@i18n(app.modules.setup_wizard.air_q_diff)@",
  review = "@i18n(app.modules.setup_wizard.air_review_fmt)@",
  tooFew = "@i18n(app.modules.setup_wizard.air_too_few_fmt)@",
  tvGone = "@i18n(app.modules.setup_wizard.air_tv_removed)@",
  apply = "@i18n(app.modules.setup_wizard.air_apply)@",
  applied = "@i18n(app.modules.setup_wizard.air_applied)@",
  back = "@i18n(app.modules.setup_wizard.btn_back)@",
  yes = "@i18n(app.modules.setup_wizard.btn_yes)@",
  no = "@i18n(app.modules.setup_wizard.btn_no)@",
  next = "@i18n(app.modules.setup_wizard.btn_next)@",
  motor = "@i18n(app.modules.setup_wizard.air_motor_fmt)@",
}

local TYPE_NAMES = {
  [0] = "@i18n(app.modules.setup_wizard.air_type_regular)@",
  [1] = "@i18n(app.modules.setup_wizard.air_type_flying_wing)@",
  [2] = "@i18n(app.modules.setup_wizard.air_type_vtail)@",
  [3] = "@i18n(app.modules.setup_wizard.air_type_delta)@",
  [4] = "@i18n(app.modules.setup_wizard.air_type_trainer)@",
  [5] = "@i18n(app.modules.setup_wizard.air_type_custom)@",
}

local CHOICE_NAMES = {
  none = "@i18n(app.modules.setup_wizard.air_none)@",
  single = "@i18n(app.modules.setup_wizard.air_ail_single)@",
  independent = "@i18n(app.modules.setup_wizard.air_ail_independent)@",
  elevatorOnly = "@i18n(app.modules.setup_wizard.air_tail_elevator)@",
  elevatorRudder = "@i18n(app.modules.setup_wizard.air_tail_elevator_rudder)@",
  rudder = "@i18n(app.modules.setup_wizard.air_yaw_rudder)@",
}

local FLAP_CHOICES = {
  {key = "none", text = "@i18n(app.modules.setup_wizard.air_none)@"},
  {key = 1, text = "@i18n(app.modules.setup_wizard.air_flaps_one)@"},
  {key = 2, text = "@i18n(app.modules.setup_wizard.air_flaps_two)@"},
  {key = 0, text = "@i18n(app.modules.setup_wizard.air_flaperons)@"},
}

-- The model's surfaces as "S1 Aileron, S2 Aileron, ...", from a rule table.
local function describe(wiz, rules)
  local parts = {}
  for _, s in ipairs(surfacesLib.surfacesFromRules(rules, 26)) do
    parts[#parts + 1] = "S" .. (s.servo + 1) .. " " .. wiz.kindName(s.kind)
  end
  local motors = 0
  for _, r in ipairs(rules) do
    if r.oper == 1 and r.input == 4 and r.output >= mix.MOTOR_OUTPUT_OFFSET then motors = motors + 1 end
  end
  for m = 1, motors do parts[#parts + 1] = string.format(T.motor, m) end
  return #parts > 0 and table.concat(parts, ", ") or T.none
end

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)

  local screen = "current"
  local modelType = nil         -- MODEL_TYPES entry being set up
  local options = nil
  local questions = {}          -- screens for this type, in order
  local qi = 0

  local function go(name)
    screen = name
    wiz.rebuild()
  end

  -- The question screens a type asks, given the answers so far.
  local function questionList()
    local list = {}
    if modelType.ailerons and modelType.ailerons.options then list[#list + 1] = "ailerons" end
    if modelType.tailControl and modelType.tailControl.options then list[#list + 1] = "tail" end
    if modelType.wingYaw and modelType.wingYaw.options then list[#list + 1] = "wingYaw" end
    list[#list + 1] = "flaps"
    if options.flaps and options.flapServos == 2 and options.ailerons == "independent" then
      list[#list + 1] = "follow"
    end
    list[#list + 1] = "motors"
    if options.motors == 2 then list[#list + 1] = "diff" end
    return list
  end

  local function nextQuestion()
    questions = questionList()
    qi = qi + 1
    go(questions[qi] or "review")
  end

  local function prevQuestion()
    qi = qi - 1
    if qi < 1 then
      qi = 0
      go("type")
    else
      go(questions[qi])
    end
  end

  local function chooseType(tp)
    modelType = tp
    options = mix.defaultOptions(tp)
    qi = 0
    nextQuestion()
  end

  local function answer(field, value)
    return function()
      options[field] = value
      nextQuestion()
    end
  end

  local function preview()
    local rules = mix.buildRules(options)
    return art.layout(surfacesLib.surfacesFromRules(rules, 26), nil), rules
  end

  local function optionButtons(field, opts)
    local specs = {{text = T.back, weight = 0.6, small = true, press = prevQuestion}}
    for _, o in ipairs(opts) do
      specs[#specs + 1] = {text = CHOICE_NAMES[o] or o, press = answer(field, o), primary = options[field] == o}
    end
    return scr:buttons(specs)
  end

  local function yesNo(field)
    return scr:buttons({
      {text = T.back, weight = 0.6, small = true, press = prevQuestion},
      {text = T.no, press = answer(field, false), primary = not options[field]},
      {text = T.yes, press = answer(field, true), primary = options[field] == true},
    })
  end

  function self.build()
    scr:begin()
    local cfg = wiz.mixConfig()

    if screen == "current" then
      local value = cfg and cfg.model_type or 0
      local body = string.format(T.current, TYPE_NAMES[value] or TYPE_NAMES[0], describe(wiz, wiz.rules()))
      scr:text(T.title, body, value == mix.MODEL_TYPE_CUSTOM and T.custom or nil)
      scr:picture(art.layout(wiz.surfaces(), nil))
      local hasSurfaces = #wiz.surfaces() > 0
      return scr:buttons({
        {text = T.change, primary = not hasSurfaces, press = function() go("type") end},
        {text = T.keep, primary = hasSurfaces, disabled = not hasSurfaces, press = function() wiz.finishStep() end},
      })

    elseif screen == "type" then
      scr:text(T.title, T.typeQ)
      local specs = {}
      for _, tp in ipairs(mix.MODEL_TYPES) do
        specs[#specs + 1] = {text = TYPE_NAMES[tp.value], press = function() chooseType(tp) end,
          primary = cfg and cfg.model_type == tp.value}
      end
      return scr:grid(specs, 2, {{text = T.back, press = function() go("current") end}})

    elseif screen == "review" then
      local layout, rules = preview()
      local used = mix.servosUsed(rules)
      local warn
      if used > wiz.servoCount() then warn = string.format(T.tooFew, used, wiz.servoCount()) end
      for _, r in ipairs(wiz.rules() or {}) do
        if r.oper ~= 0 and r.input >= 27 and r.input <= 29 then
          warn = (warn and (warn .. " ") or "") .. T.tvGone
          break
        end
      end
      scr:text(TYPE_NAMES[modelType.value], string.format(T.review, describe(wiz, rules)), warn)
      scr:picture(layout)
      return scr:buttons({
        {text = T.back, press = prevQuestion},
        {text = T.apply, primary = true, press = function()
          wiz.setMix(mix.ruleTable(options), modelType.value)
          go("applied")
        end},
      })

    elseif screen == "applied" then
      scr:text(T.title, T.applied .. " " .. describe(wiz, wiz.rules()))
      scr:picture(art.layout(wiz.surfaces(), nil))
      return scr:buttons({
        {text = T.change, press = function() go("type") end},
        {text = T.next, primary = true, press = function() wiz.finishStep() end},
      })
    end

    -- A question.
    local layout = preview()
    scr:picture(layout)
    if screen == "ailerons" then
      scr:text(TYPE_NAMES[modelType.value], T.aileronsQ)
      return optionButtons("ailerons", modelType.ailerons.options)
    elseif screen == "tail" then
      scr:text(TYPE_NAMES[modelType.value], T.tailQ)
      return optionButtons("tailControl", modelType.tailControl.options)
    elseif screen == "wingYaw" then
      scr:text(TYPE_NAMES[modelType.value], T.wingYawQ)
      return optionButtons("wingYaw", modelType.wingYaw.options)
    elseif screen == "flaps" then
      scr:text(TYPE_NAMES[modelType.value], T.flapsQ)
      local specs = {{text = T.back, weight = 0.6, small = true, press = prevQuestion}}
      local current = options.flaps and options.flapServos or "none"
      for _, c in ipairs(FLAP_CHOICES) do
        -- Flaperons are the ailerons drooping: only with two of them.
        if c.key ~= 0 or options.ailerons == "independent" then
          specs[#specs + 1] = {text = c.text, small = true, primary = current == c.key, press = function()
            options.flaps = c.key ~= "none"
            options.flapServos = (c.key == "none") and 1 or c.key
            nextQuestion()
          end}
        end
      end
      return scr:buttons(specs)
    elseif screen == "follow" then
      scr:text(TYPE_NAMES[modelType.value], T.followQ)
      return yesNo("flapsFollowAilerons")
    elseif screen == "motors" then
      scr:text(TYPE_NAMES[modelType.value], T.motorsQ)
      local specs = {{text = T.back, weight = 0.6, small = true, press = prevQuestion}}
      for n = 0, 2 do
        specs[#specs + 1] = {text = tostring(n), primary = options.motors == n, press = answer("motors", n)}
      end
      return scr:buttons(specs)
    else -- diff
      scr:text(TYPE_NAMES[modelType.value], T.diffQ)
      return yesNo("diffThrustYaw")
    end
  end

  function self.paint() scr:paint() end
  function self.released() scr:refresh() end

  return self
end

return {new = new, owned = OWNED}
