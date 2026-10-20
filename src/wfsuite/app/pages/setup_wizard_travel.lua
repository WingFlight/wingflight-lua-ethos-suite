-- Setup Wizard step: Travel check. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepTravel.svelte: how far
-- each surface goes with full stick on every axis that drives it at once,
-- as a percentage of its binding limit on each side
-- (lib/setup_wizard_surfaces.lua travelReach()). Above 100% the surface
-- reaches its limit before full stick, and the stabilizer has no travel left
-- on that side. The wizard forces PASSTHROUGH so the pilot can move the
-- sticks into the corners and watch.
--
-- Differences from the configurator: the servo balance curve is not
-- included in the reach yet (see lib/setup_wizard_surfaces.lua).

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local ui = requireModule("app/setup_wizard_ui.lua")
local surfacesLib = requireModule("lib/setup_wizard_surfaces.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.trv_title)@",
  intro = "@i18n(app.modules.setup_wizard.trv_intro)@",
  row = "@i18n(app.modules.setup_wizard.trv_row_fmt)@",
  clipping = "@i18n(app.modules.setup_wizard.trv_clipping)@",
  ok = "@i18n(app.modules.setup_wizard.trv_ok)@",
}

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)

  function self.build()
    scr:begin()
    if wiz.canMove() and wiz.forcedMode() ~= wiz.BOX_PASSTHROUGH then wiz.forceMode(wiz.BOX_PASSTHROUGH) end
    local gains = wiz.axisGains()
    local rows, clips = {}, false
    for _, s in ipairs(wiz.surfaces()) do
      local reach = surfacesLib.travelReach(s, wiz.configs[s.servo], gains)
      local neg = math.floor(reach.neg.fraction * 100 + 0.5)
      local pos = math.floor(reach.pos.fraction * 100 + 0.5)
      local over = neg > 100 or pos > 100
      clips = clips or over
      rows[#rows + 1] = {wiz.surfaceName(s), string.format(T.row, neg, pos), over}
    end
    scr:text(T.title, T.intro, clips and T.clipping or T.ok)
    scr:rows(rows)
    -- Back is the Throws step, where a clipping surface is fixed.
    return scr:row()
  end

  function self.paint() scr:paint() end
  function self.released() scr:refresh() end

  return self
end

return {new = new}
