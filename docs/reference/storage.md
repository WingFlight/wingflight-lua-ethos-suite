# Storage Writes

WFSuite owns a small set of files on the radio SD card:

- `SCRIPTS:/wfsuite.user/settings.ini`, written through `settings_store.save()`.
- Per-model `.ini` files, written through `model_preferences.save()`.
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
