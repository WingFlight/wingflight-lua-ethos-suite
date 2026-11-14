-- Port labels per board design, for the Ports page and the Setup Wizard.
--
-- Keys: boardDesign as reported by MSP_BOARD_INFO (e.g. "F7B5" for the
-- VANTAC_RF007, "F7C5" for the Nexus X and XR; wingflight-targets sets it with
-- board_design). Inner keys: UART index as used by MSP_SERIAL_CONFIG
-- identifiers (0 = UART1). Values: the silkscreen name the Wingflight
-- Configurator shows for that port.
--
-- The data follows wingflight-configurator (src/tabs/configuration/util.js,
-- PORT_NAMES_RF2). The Configurator's circled letters are plain letters here:
-- the Ethos font has no glyphs for them and draws a gap instead. A port named
-- "S.BUS" is the one lib/setup_wizard_bus.lua offers first for a servo bus.
--
-- To add a board: put its verified board_design (or board_name, in BY_NAME)
-- and UART-index labels here.

local port_labels = {}

local DESIGNS = {
  F7A1 = {[0] = "DSM D", [1] = "S.BUS", [2] = "Port C", [3] = "Port A", [4] = "Port E", [5] = "Port B"},
  F7A2 = {[0] = "DSM D", [1] = "S.BUS", [2] = "Port G", [3] = "Port A", [4] = "Port E", [5] = "Port G"},
  F7A3 = {[0] = "DSM D", [1] = "S.BUS", [2] = "Port C", [3] = "Port A", [4] = "Int.Rx", [5] = "Port B"},
  F7A4 = {[0] = "DSM D", [1] = "S.BUS", [2] = "Port G", [3] = "Port A", [4] = "Int.Rx", [5] = "Port G"},
  F7B1 = {[0] = "S.BUS", [1] = "TELEM", [2] = "Port C", [3] = "Port A", [4] = "DSM D", [5] = "Port B"},
  F7B2 = {[0] = "S.BUS", [1] = "TELEM", [2] = "Port G", [3] = "Port A", [4] = "DSM D", [5] = "Port G"},
  F7B3 = {[0] = "S.BUS", [1] = "TELEM", [2] = "Port C", [3] = "Port A", [4] = "Port E", [5] = "Port B"},
  F7B4 = {[0] = "S.BUS", [1] = "TELEM", [2] = "Port G", [3] = "Port A", [4] = "Port E", [5] = "Port G"},
  F7B5 = {[0] = "S.BUS", [1] = "TELEM", [2] = "Port C", [3] = "Port A", [4] = "Int.Rx", [5] = "Port B"},
  F7B6 = {[0] = "S.BUS", [1] = "TELEM", [2] = "Port G", [3] = "Port A", [4] = "Int.Rx", [5] = "Port G"},
  -- F7B5 with the FBUS mux FPGA (RF007 V3): UART1 and UART6 go to the FPGA
  F7B5M = {[0] = "FBUS Mux", [1] = "TELEM", [2] = "Port C", [3] = "Port A", [4] = "Int.Rx", [5] = "FPGA"},
  F7C1 = {[0] = "S.BUS", [1] = "TELEM", [2] = "Port C", [3] = "Port A", [4] = "DSM D", [5] = "Port B"},
  F7C2 = {[0] = "S.BUS", [1] = "TELEM", [2] = "Port G", [3] = "Port A", [4] = "DSM D", [5] = "Port G"},
  F7C3 = {[0] = "S.BUS", [1] = "TELEM", [2] = "Port C", [3] = "Port A", [4] = "Port E", [5] = "Port B"},
  F7C4 = {[0] = "S.BUS", [1] = "TELEM", [2] = "Port G", [3] = "Port A", [4] = "Port E", [5] = "Port G"},
  F7C5 = {[0] = "S.BUS", [1] = "TELEM", [2] = "Port C", [3] = "Port A", [4] = "Int.Rx", [5] = "Port B"},
  F7C6 = {[0] = "S.BUS", [1] = "TELEM", [2] = "Port G", [3] = "Port A", [4] = "Int.Rx", [5] = "Port G"},
  -- FrSky Aegis Lite (STM32H730): UART3 RX, UART4 C1, UART7 TX on S9 (TLM), UART10 C2
  H7A1 = {[2] = "RX", [3] = "C1", [6] = "S9(TLM)", [9] = "C2"},
}
local BY_NAME = {}

port_labels.DESIGNS = DESIGNS
port_labels.BY_NAME = BY_NAME

-- Returns the silkscreen name for a UART index, or nil when there is none and the plain
-- UART name should be shown. A board_name listed in BY_NAME is answered from that entry
-- only, so a generic board_design can never pick up another board's labels.
function port_labels.lookup(boardDesign, identifier, boardName)
  local byName = boardName and BY_NAME[boardName]
  if byName then return byName[identifier] end
  local design = boardDesign and DESIGNS[boardDesign]
  return design and design[identifier] or nil
end

return port_labels
