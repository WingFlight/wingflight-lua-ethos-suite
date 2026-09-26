# Addressed MSP access

wingflight-firmware is replacing its hand-written MSP config catalogue --
one opcode per settings block, each with its own serializer in `msp.c` -- with
two generic opcodes that address configuration by parameter group, offset and
length: `MSP2_WING_PARAM_READ` (0x5F22) and `MSP2_WING_PARAM_WRITE` (0x5F23).
Step 5 of the firmware's `docs/parameter-addressing-design.md` then deletes
the catalogue. This suite's pages (`lib/msp_*.lua`) speak the catalogue, so
they have to move off it first; this is how.

## The approach

The pages do not change. They keep building legacy requests and decoding
legacy replies. A layer in the MSP queue, `tasks/msp/virtual.lua`, answers
those opcodes itself: a reply is assembled from `PARAM_READ`s, a setter is
turned into `PARAM_WRITE`s, and the page receives the same bytes the
firmware's own opcode would have returned. It is the Lua twin of the
configurator's `src/js/param/virtual_msp.js`.

What each legacy opcode's bytes mean -- which parameter-group bytes each wire
field is -- differs per firmware build. The firmware extracts it at build time
from its own `msp.c` into a **codec pack** per build.

## Codec packs

- The firmware's `make manifest` writes `<fork>_<version>_<target>_codecs.lua`
  next to the build's manifest, and each firmware release publishes them.
- The suite bundles the packs of the releases it supports as
  `src/wfsuite/codecs/<build id>.lua`:
  `python bin/codecs/import-packs.py <packs or firmware obj/ directory>`.
  Packs name themselves; the script reads the build id from the file.
- At connect, with the setting on, the session reads the firmware's build id
  (`MSP2_WING_BUILD_ID`, `lib/msp_build_id.lua`) first and loads the matching
  pack. No pack for that build means addressed access stays off for the
  session and everything uses the legacy opcodes.
- A local firmware build needs its own pack copied onto the radio, into the
  suite's `codecs/` folder, the same way.

Each codec in a pack is a binary string (the encoding is documented in the
firmware's `src/utils/wf_lua_pack.py`), decoded one opcode at a time when it
is used: as Lua tables, the ~2000 unrolled wire fields of a build would cost
far more RAM. A pack carries its encoding's `format`; the suite refuses a pack
of another format, as it does one for another build.

The codecs cover plain fields, profile fields, per-index setters and replies
(`MSP_GET_*`, the index being the request's first bytes), an array element
chosen by a stored selector (the battery profile's capacity), NUL-terminated
strings in and out (`MSP_NAME`), and 64-bit fields.

## When a request is answered locally

The setting is **Developer settings → Addressed MSP**, off by default. With it
on, `Queue:processQueue()` asks `Virtual:intercept()` about each message as it
is dequeued (never in the simulator):

1. An opcode the pack has no codec for goes to the firmware.
2. A setter goes to the firmware -- unless **Developer settings → Addr.
   writes** is on as well. Then each setter opcode's first request on a
   connection goes to the firmware, and once the firmware has taken it,
   `virtual.lua` runs the codec on the same payload as a dry run: it must
   find on the board exactly the bytes it would store. That makes the
   setter *verified*, and later requests for it are written through
   `PARAM_WRITE`. Nothing extra is written to the board to verify. A setter
   the firmware refused, or a request that stored nothing, verifies
   nothing, and the next request is watched instead. Setter side effects
   (reloading a profile, rebuilding filters) are not replayed: the save
   (`MSP_EEPROM_WRITE`, always the firmware's) applies them, as it does for
   the configurator.
3. A request carrying arguments goes to the firmware, unless the codec is
   indexed and the arguments are exactly its index.
4. The first request for a reply opcode on a connection goes to the firmware,
   and the page gets that reply at once. Behind it, `virtual.lua` builds the
   same reply from `PARAM_READ`s and compares. A match makes that opcode
   *verified* for the rest of the connection; a mismatch keeps it on the
   firmware. The outcome is logged (`[virtual] opcode N ...`). An indexed
   reply is verified per index: each index is its own request.
5. A verified opcode is answered locally: its `PARAM_READ`s are queued at the
   front, and the assembled reply goes to the original `processReply`.
   Errors reach its `errorHandler`; retries, timeouts and transports are the
   queue's own.

Disconnecting drops the pack and all verification.

## Checks

`bin/tests/msp-virtual/` runs `virtual.lua` under fengari: against the
configurator's layer, which is verified against the firmware itself, for
identical bytes on random boards; and inside the real `queue.lua` for the
policy above. See its README.
