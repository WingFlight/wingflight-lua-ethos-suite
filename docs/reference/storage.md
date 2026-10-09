# Storage Writes

WFSuite owns a small set of files on the radio SD card:

- `SCRIPTS:/wfsuite.user/settings.ini`, written through `settings_store.save()`.
- Per-model `.ini` files (`SCRIPTS:/wfsuite.user/models/<mcu-id>.ini`), written through `model_preferences.save()`: battery/smart-fuel configuration, flight statistics, and the name the flight controller reported (`[craft] name`).
- `LOGS:/wfsuite/telemetry/<mcu-id>/logs.ini`, used by the Logs page to show the model name.
- `LOGS:/wfsuite/telemetry/<mcu-id>/*.csv`, created by the flight telemetry logger.

These files are written with `src/wfsuite/lib/atomic_write.lua`. The live path is
not opened with `io.open(path, "w")` during the normal save path, because opening
that way truncates the file before a byte is written. Instead the suite writes to
a sibling temp file, flushes and closes it, then swaps it into place with
`os.rename`.

The temp file uses a deterministic name:

```text
<target path>.tmp
```

That fixed path is deliberate. If a radio loses power mid-save, the abandoned
temp file is inert and the next save overwrites the same temp path instead of
leaving a trail of stale files.

### The craft name, and the known-models list

`tasks/session.lua` writes the name the flight controller reports (`MSP_NAME`)
into `[craft] name` of that controller's file, so the radio can name a model
with no link up. The UID and the name arrive in separate replies and either may
come first; whichever comes second writes. A name that has not changed writes
nothing, and an empty answer never replaces a stored name. Saving a new craft
name on the Configuration page updates the store and session immediately via
`craft.name.saved`.

The name is stored inside double quotes (`name="007"`). The INI reader turns a
bare `007`, `0x10` or `1e3` into a number and `true` into a boolean, so a name
written without quotes would not survive a save and a load. A store written
before the name existed has no `[craft]` section and lists with no name.

`lib/known_models.lua` lists the stores on the card with no link:
`requireModule("lib/known_models.lua").list()` returns one record per file in
`models/`, sorted by id: `id`, `name` (nil if none is recorded), `path`, and
`modified`, the table `os.stat()` reports for the file. It writes nothing. It
reads every store, so call it from a tool page, not from a widget or a wakeup,
and load it where it is called -- nothing loads it at boot.

## Failure Behaviour

Before the final swap, the previous live file is untouched. A power loss while
the temp file is being written leaves the old settings or log header intact.

If `os.rename` refuses to overwrite an existing file, the writer removes the
target and retries the rename once. If that still fails, it reads the staged temp
file and falls back to a direct write so the target is not left missing. That
fallback is intentionally the last resort; on Ethos the normal path is the
rename.

If writing to the temp file raises an error, the temp file is closed and removed,
and the live file is left as it was.

The writer judges a successful rename by filesystem state, not by the return
value of `os.rename`: some builds can return no success value. The temp file
being gone is the proof that the swap happened.

## Limits

This does not detect a short write that reports success. A card that fills up
mid-write can still leave an incomplete staged file if the platform reports the
write as successful. The important property is that the live file is not touched
until staging finishes and the commit path begins.

## Verification

Run:

```sh
lua5.4 bin/storage/verify_atomic_writes.lua
```

The check drives the real `ini.lua` and `atomic_write.lua` modules on a
workstation. It records opened write handles, stages interrupted writes for
real, checks rename fallback behaviour, and verifies that the telemetry CSV
header goes through the same temp-file path.
