-- Shared "Curve N" slot-label text, used by both app/pages/pid_controller.lua
-- (fw_tpa_curve/gain_curve_0/1/2 choice fields -- "which curve slot is
-- assigned here") and app/pages/curves.lua (the slot-tile grid -- "which
-- shape am I editing"), so both places render identical text from one
-- source rather than duplicating the numbering scheme in two files.
--
-- i18n tags resolve via build-time text substitution (see
-- .vscode/scripts/resolve_i18n_tags.py); the resolved translation string
-- itself carries a %d placeholder filled in here at runtime, the same
-- idiom app/alignment_visual.lua's live_fmt/offset_fmt use.

if package.loaded["wfsuite.app.curve_slot_labels"] then
  return package.loaded["wfsuite.app.curve_slot_labels"]
end

local curve_slot_labels = {}

-- 1-based slot number (1..curveCount) -> "Curve N". Used by the Curves
-- page's own slot grid, which only ever lists real slots to open (no
-- "None" tile there).
function curve_slot_labels.slotTitle(n)
  return string.format("@i18n(app.modules.pid_controller.curve_slot_fmt)@", n)
end

-- Builds a {label, wireValue} choice table for a fw_tpa_curve/gain_curve_*
-- style field: wire value 0 = "None", wire value n (1..curveCount) = the
-- curve at pool index n-1 (i.e. what app/pages/curves.lua's slot grid
-- shows as "Curve n").
function curve_slot_labels.optionsTable(curveCount)
  local options = {{"@i18n(app.modules.pid_controller.curve_none)@", 0}}
  for n = 1, curveCount do
    options[#options + 1] = {curve_slot_labels.slotTitle(n), n}
  end
  return options
end

package.loaded["wfsuite.app.curve_slot_labels"] = curve_slot_labels
return curve_slot_labels
