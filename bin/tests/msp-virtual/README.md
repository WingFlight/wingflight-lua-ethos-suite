# Checks for `tasks/msp/virtual.lua`

The suite answers legacy MSP config opcodes from addressed parameter access
(see `docs/msp-addressed-access.md`). These scripts check that code off the radio, under
[fengari](https://github.com/fengari-lua/fengari) (Lua 5.3 in node). They need
the sibling checkouts of wingflight-configurator and wingflight-firmware, and a
firmware build's manifest and codec pack (`make manifest` in the firmware).

```
cd bin/tests/msp-virtual
npm install

FW=../../../../wingflight-firmware/obj
node compare.mjs    ../../../../wingflight-configurator ../../../src/wfsuite/tasks/msp/virtual.lua \
                    $FW/wingflight_4.6.0_STM32F7X2_codecs.lua $FW/wingflight_4.6.0_STM32F7X2_manifest.json
node queue_test.mjs ../../../../wingflight-configurator ../../../src/wfsuite \
                    $FW/wingflight_4.6.0_STM32F7X2_codecs.lua $FW/wingflight_4.6.0_STM32F7X2_manifest.json
```

- **`compare.mjs`** runs every codec in the pack through `virtual.lua` and
  through the configurator's `src/js/param/virtual_msp.js` on the same random
  board (non-zero profile selections), and requires identical reply bytes
  (indexed replies at every index), identical boards after each setter --
  written back from its getter, and fed random payloads -- and the same
  refusals of an index or a selector out of range. The
  configurator's layer is the one verified against the firmware itself
  (`verify_msp`, and on SITL `scripts/verify-msp-sitl.mjs`), so agreement here
  carries that verification over to the radio. A planted bug in sign
  extension, profile or index addressing, a selector or a string bound makes
  it fail.
- **`queue_test.mjs`** drives the real `tasks/msp/queue.lua` with a fake
  transport: the first request for an opcode goes to the firmware and is
  verified behind it; later ones are answered locally; an indexed reply is
  verified per index; an opcode whose codec disagrees with the firmware,
  setters, and requests with other arguments keep going to the firmware;
  nothing is intercepted with the setting off.

fengari has no `collectgarbage()`; `queue_test.mjs` stubs it.
