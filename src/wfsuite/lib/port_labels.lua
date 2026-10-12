-- Port labels per board, for the Ports page. WingFlight edition.
--
-- The tables are empty on purpose. The Rotorflight tables (reference designs F7A1..F7C6
-- and board_name GOOSKY_F701) are not copied here: WingFlight boards do not report those
-- designs. In the WingFlight sources no target sets board_design, so there is no key that
-- could select a label set yet. Until label data for a WingFlight board is verified, every
-- lookup returns nil and the page shows the plain UART name.
--
-- To add a board: put its verified board_name (or board_design) and UART-index labels here.
-- Keys are the UART index as used by MSP_SERIAL_CONFIG identifiers (0 = UART1).

local port_labels = {}

local DESIGNS = {}
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
