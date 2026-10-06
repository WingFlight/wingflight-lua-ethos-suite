"""The job list of .github/workflows/pr.yml, as data.

`pr.yml` used to be edited by hand, and every pull request that added a Lua
harness inserted its step at the same place -- the end of the one Lua job.
Two open pull requests that did the same thing therefore collided on context
lines that had nothing to do with either change, and a wrong resolution can
leave a file GitHub refuses to load: upstream (rotorflight-lua-ethos-suite
#2414 and #2416) squash-merged two such resolutions that left a job with a
name and no runs-on, and the run on master reported failure with zero jobs.

So `pr.yml` is generated from here. Adding a harness means adding a LuaStep
to LUA_STEPS and running `python bin/ci/verify_pr_workflow.py --write`;
nothing edits `pr.yml` by hand any more.

Two kinds of entry, because the jobs are not all the same shape:

* `LUA_JOB` / `LUA_STEPS` is the uniform one -- one job that checks out,
  installs lua5.4, and runs every harness as its own step. Every step after
  the first carries `if: success() || failure()`, so one red harness does
  not hide the rest. The rationale is the reason the harness exists, and it
  is the part that has to survive being moved into a Python string.

* `VERBATIM_JOBS` keeps its YAML verbatim. Those jobs need a matrix, an
  env block, or several commands, and modelling GitHub Actions step
  semantics in Python would add a second thing to review without making the
  file any less of a single source. The literals are raw, because a shell
  command in them ends with a backslash and Python would otherwise read that
  as a line continuation and fold the command onto one line.

The rationale is kept line for line as it reads in `pr.yml`, including its
wrapping, because that text is written to be read next to the step it
explains.
"""

from typing import NamedTuple


class LuaJob(NamedTuple):
    """The one job every Lua harness runs in."""

    id: str
    name: str
    rationale: str


class LuaStep(NamedTuple):
    """One harness, run as a step of LUA_JOB."""

    name: str
    script: str
    rationale: str


# The job id and name predate the other harnesses and are kept as they are:
# renaming them would change the check names branch protection may refer to.
LUA_JOB = LuaJob(
    id='flight-record',
    name='Flight record across a link loss',
    rationale=r'''A flight is a state machine that only misbehaves across a link loss, which
no build step can reach. This pins it: a brief in-flight drop stays one
record, and a pack swap stays two.
'''
)

LUA_STEPS = [
    LuaStep(
        name='Check the flight record behaviour',
        script='bin/flight_record/verify_flight_record.lua',
        rationale=''
    ),
    LuaStep(
        name='Check the SmartFuel announcements',
        script='bin/tests/smartfuel_announce.lua',
        rationale=r'''Same Lua job: a fresh connect must not announce "low fuel" from a
SmartFuel reading that is 0 only because no battery is known yet.
'''
    ),
    LuaStep(
        name='Check the FBL Status arming flags',
        script='bin/tests/arming_flags.lua',
        rationale=r'''FBL Status must keep arming-disable reasons out of the narrow value
column, where the joined list was cut off on small screens.
'''
    ),
    LuaStep(
        name='Check the GPS arm-without-fix toggle',
        script='bin/tests/gps_arm_without_fix.lua',
        rationale=r'''GPS Navigation writes MSP_GPS_RESCUE back from the FC's own reply with
only the arming byte changed, so the fields the suite does not show are
never overwritten, and the page still saves when the FC lacks the field.
'''
    ),
    LuaStep(
        name='Check atomic storage writes',
        script='bin/storage/verify_atomic_writes.lua',
        rationale=r'''Settings and log headers are staged to a temp file before replacing the
live file, so a power loss during a save does not truncate the data the
suite owns on the SD card.
'''
    ),
    LuaStep(
        name='Check the MSP queue after an aborted request',
        script='bin/msp_queue/verify_msp_queue.lua',
        rationale=r'''An MSP request abandoned between two of its frames used to leave the
shared TX buffer occupied, after which no request could be framed at
all -- every configuration page then hung until the script was
reloaded. It needs a queue, a clock and a link that stops answering,
so no build step reaches it.
'''
    ),
    LuaStep(
        name='Check the background task drain budgets',
        script='bin/perf/verify_clock_budgets.lua',
        rationale=r'''Three drain loops run inside one background-task wakeup with no yield
point in between; on a single-core MCU sharing time with Ethos's UI, their
budget is UI latency. This drives them against a permanently full queue
and a clock that charges real time per frame, so it measures the budgets
instead of trusting them -- and checks that bounding the poll does not
break reply assembly, which is what says how far a budget may be cut.
'''
    ),
    LuaStep(
        name='Check the MSP queue on disconnect and the per-message GC',
        script='bin/msp_gc/verify_msp_disconnect.lua',
        rationale=r'''A disconnect must drop the MSP request queue -- including mid-flight,
which takes a different branch through the reset -- so the next
handshake is not queued FIFO behind a backlog no FC can answer. And
completing a message must not force a full GC cycle, which section 9
of the lifecycle doc measured as buying nothing. Both need a session
task and a collector that can be observed.
'''
    ),
    LuaStep(
        name='Check the dashboard image caches',
        script='bin/dashboard/verify_image_caches.lua',
        rationale=r'''clearCaches()'s images branch had no caller, so every decoded
dashboard bitmap survived theme reloads, model changes and widget
close. This checks the reload now releases them, that the bitmap map
is LRU-bounded, and that the paint-path draw memo neither pins a
bitmap nor allocates per draw.
'''
    ),
    LuaStep(
        name='Check field layout slot pooling',
        script='bin/field_layout/verify_field_layout.lua',
        rationale=r'''Ethos form widgets retain closures across form.clear(), so
app/field_layout.lua pools accessor slots per page+field shape. This
checks the pool is reused across visits, never shrunk on release,
detaches dataRef/controlRef safely, and keeps two closures per slot.
'''
    ),
    LuaStep(
        name='Check a short MSP payload is reported, not decoded',
        script='bin/msp_battery/verify_msp_battery.lua',
        rationale=r'''lib/mspcodec.lua's readU8 returned nil past the end of a payload where
its siblings substituted 0, and the smartfuel decoder divided that nil
by 1000 -- a short reply raised out of the background task. A radio
only produces a short reply under conditions nobody can script, so the
payload lengths are pinned here against wingflight-firmware's handler.
'''
    ),
    LuaStep(
        name='Check a failed ESC/servo guard read is retried',
        script='bin/esc_guard/verify_esc_guard_retry.lua',
        rationale=r'''The ESC forward-programming and servo BUS tiles are gated by guards
that read the FC once. A timeout or bus error used to latch them shut
until the menu was reopened; they now retry after a backoff. That
retry reaches neither a build nor a package step, so it is pinned here.
'''
    ),
    LuaStep(
        name='Check the dialog teardown when a page is left',
        script='bin/dialog_lifecycle/verify_dialog_lifecycle.lua',
        rationale=r'''Leaving a page -- Back, or closing the tool -- ran its dialog teardown
on a form Ethos may already have stopped updating, and a save/reload
confirmation still up outlived the page with an OK button that did
nothing. The pages are loaded for real here under a form whose writes
raise once teardown starts.
'''
    ),
    LuaStep(
        name="Check a page's data stays tagged with the profile it came from",
        script='bin/page_runtime/verify_profile_anchor.lua',
        rationale=r'''A page tags its data with the profile it was read for, and the tag was
taken when the read finished rather than when it started. A pilot who
switched profile while that read was in flight got the previous
profile's values on screen, anchored to the new profile -- so nothing
reloaded, and Save wrote the old profile's values into the new one.
Only a switch inside an MSP round-trip reaches it, so the MSP answers
are held here and the session.update lands while a read is in flight.
5 of its 17 checks go red on the pre-fix page_runtime.lua.
'''
    ),
    LuaStep(
        name="Check the Tool button hands a page a callable focus function",
        script='bin/page_runtime/verify_tool_focus.lua',
        rationale=r'''Every page's onTool is function(focusFn), and calls focusFn() when its
dialog closes or is cancelled. The header's Tool button called it as
runtime:onTool(focus), so the page got the runtime table as focusFn and
calibrating the accelerometer ended in "focusFn is not callable (a
table value)". This presses the real page_runtime.lua's Tool button and
closes the dialog the way the pages do; 4 of its 5 checks go red on the
pre-fix page_runtime.lua.
'''
    ),
    LuaStep(
        name='Check an unwritable card does not discard the log buffer',
        script='bin/logging/verify_log_flush_retry.lua',
        rationale=r'''A flight log is the pilot's evidence after a crash, and both ways it
could lose rows were silent: an io.open that failed emptied the buffer,
and a failed write() trimmed the rows it had just failed to persist.
Only a card that cannot be written reaches either path, so the real
logger is driven here with io.open and the handle's write() as seams.
'''
    ),
    LuaStep(
        name="Check the tool's UI is not loaded at boot",
        script='bin/tool_ui/verify_tool_ui_lazy.lua',
        rationale=r'''The system tool's UI subtree (menu_container, header, tile_grid,
navigation, both menu guards and their MSP codecs, memstats) loads on
first create(), not at boot. Nothing reaches that from a build step.
'''
    ),
    LuaStep(
        name='Check the tool adds no MSP requests across cycles',
        script='bin/tool_ui/verify_no_extra_msp.lua',
        rationale=r'''Deferring that load must not add MSP traffic or accumulate anything
per open/close cycle. This counts msp.request at bus.publish over
three tool cycles plus 100 wakeups inside a guarded menu, and goes red
if a guard stops latching (309 requests instead of 6).
'''
    ),
    LuaStep(
        name='Check bus publish is bounded and the stack minimum is tracked',
        script='bin/stack/verify_stack_bounds.lua',
        rationale=r'''The bus is the only channel between the tool, the dashboard and the
background task, and publish() calls its handlers synchronously -- a
handler that publishes back into the same topic recurses, and in the
reference Lua VM every Lua-to-Lua call is one C stack level. This
drives a real cycle and asserts it terminates at the guard rather than
at the VM's own "C stack overflow", and that the memory log reports
the smallest mainStackAvailable it has ever seen.
'''
    ),
    LuaStep(
        name='Check the wakeup path allocates nothing per call',
        script='bin/allocation_churn/verify_allocation_churn.lua',
        rationale=r'''The dashboard wakeup path runs several times a second and session.update
is published at up to 20 Hz, so a table rebuilt per call there is the
sawtooth in the '[bgtask mem] lua=' log rather than a detail. Three such
sites were removed: the subscriber copy in lib/bus.lua, the name table and
its result table in getSensorStats(), and the per-call closure in
transformValue(). Ported from rotorflight-lua-ethos-suite#2435.

No build and no package step reaches this -- it needs the collector held off
and a loop that calls the function thousands of times. Every allocation
assertion is paired in both directions: the current code has to come out
under the bound and the removed code over it. The same run pins what a
pooled iteration copy can get wrong -- a handler unsubscribed long ago must
not come back through a leftover slot -- and the one value the change
alters, an rssi box reading its own min/max instead of link quality's.
'''
    ),
    LuaStep(
        name='Check the collector pause and the forced collects',
        script='bin/gc_pause/verify_gc_pause.lua',
        rationale=r'''The collector's pause decides when a cycle starts: live * pause / 100.
The default is 200, so the heap may reach twice what is live before anything
is reclaimed at all, while Ethos kills a script whose heap passes its limit.
main.lua lowers it to 120 -- but the one line has a foot-gun in it, and that
is what this pins: `collectgarbage("setpause")` with the argument omitted
does not read the pause, it SETS IT TO 0 ("collect constantly"). So the
applied value is printed at boot instead of read back, and no file under
src/ may call either setter without an explicit value. It also fixes the
call before background_task.init(), keeps Queue:_finish() free of a forced
collect, and keeps the teardown collects in Queue:clear() and the three ESC
dispose paths. Ported from rotorflight-lua-ethos-suite#2441.

Pass --self-test to prove every check can go red on a sabotaged copy.
'''
    ),
    LuaStep(
        name='Check the root menu close key',
        script='bin/tool_ui/verify_root_close_key.lua',
        rationale=r'''Every screen but one installed a handler for the physical Back/Close key. The
root menu installed none, on the stated assumption that Ethos's own default
closes the tool on the first press. It does not -- that default takes two, the
first dropping the form's input focus -- so the root menu had two ways out that
disagreed with each other: the on-screen Menu button left in one press, the
hardware RTN in two. Neither a build nor a package step reaches any of it.

The harness drives the real tool.lua through registerSystemTool, create() and
event() and asserts that RTN and EXIT reach goBack() at the root, that goBack()
is the same path the back button takes, that a long ENTER, a model key and a
touch event are still passed through untouched, and that RTN in a submenu pops
one level without exiting. Ported from rotorflight-lua-ethos-suite#2442.

Pass --self-test to prove the seven root checks go red against a copy of
app/menu_container.lua with the pre-fix root branch put back.
'''
    ),
    LuaStep(
        name='Check the Ethos instruction budget',
        script='bin/perf/verify_instruction_budget.lua',
        rationale=r'''Ethos aborts any Lua callback that runs 20000 VM instructions ("Max
instructions count reached"), and nothing on the radio says how close one
runs. This drives the real dashboard widget through every theme and flight
state, and the real background task through boot, link up, steady CRSF with
ELRS frames, an ELRS backlog and link down, and the real system tool through
every menu and every page (opened cold, read replies served by the MSP
codecs' simulator fixtures), counting instructions with a debug hook on
desktop Lua. Any callback at or over the limit fails, so a theme with too
many boxes, a new per-tick cost, or a page that builds its form in one
oversized pass is caught here instead of as stalled frames, a dropped
background tick in flight, or a page that never draws. The Ports page did
exactly that before this check covered the app: its function lists cost
~32k instructions with 4 serial ports and ~324k with 12, in one wakeup.
'''
    ),
    LuaStep(
        name='Check the ESC forward-programming signature gate',
        script='bin/esc_signature/verify_esc_signature.lua',
        rationale=r'''AM32, BLHeli_S and Bluejay share one menu protocol ID. Drive their real
pages and codecs to check that a mismatched ESC never builds an editor or
sends MSP 218, while a matching ESC opens and saves successfully. Also
require every ESC tile's codec to declare its expected signature.
Ported from rotorflight-lua-ethos-suite#2452. Pass --self-test to prove all
30 gate checks fail when isCompatibleEsc() is replaced with return true.
'''
    ),
    LuaStep(
        name='Check the YGE Motor Timing word is translated both ways',
        script='bin/esc_parameters_yge/verify_esc_parameters_yge.lua',
        rationale=r'''The YGE ESC spells its four automatic timing modes 16..19 and its six
fixed advance angles 1..6, but lib/msp_esc_parameters_yge.lua handed the
Motor Timing row's list position to and from the wire unchanged: an ESC
reporting 17 (Auto Eff) showed Auto Norm, and picking 0 deg wrote 17. The
FC passes the block through without looking, so drive the real page,
field_layout and page_runtime against the codec's own simulator reply.
Also pin that the flags byte's reserved bits survive a save. Ported from
rotorflight-lua-ethos-suite#2456. Pass --self-test to prove all 22 gate
checks fail against the pre-fix codec.
'''
    ),
    LuaStep(
        name='Check the YGE 12 V BEC ceiling and the HV-BEC bit',
        script='bin/esc_parameters_yge/verify_yge_bec12v.lua',
        rationale=r'''Seven of the 21 YGE models have an HV BEC that runs to 12.0 V, but BEC
Voltage was capped at 8.4 V for all of them, and the flags byte's HV-BEC
bit (bit 3) was never set. The ceiling now follows the model through one
ESC_MODELS table (which also adds the missing 4691 Saphir 125v2), the row
is hidden on the five Opto models that have no BEC, and beforeSave sets
or clears bit 3 only when the pilot moved the voltage. Ported from
rotorflight-lua-ethos-suite#2459. Pass --self-test to prove all 11 gate
checks fail with the fix cut back out of the three files that carry it.
'''
    ),
    LuaStep(
        name='Check the ESC selector offers only the ESCs that exist',
        script='bin/esc_target_selector/verify_esc_target_selector.lua',
        rationale=r'''Every 4-way forward-programming page opens on
app/pages/esc_forward_4way.lua, which built all four ESC rows and greyed
out the surplus, so a single-ESC model saw three dead lines. It now builds
one row per ESC the FC reports, and skips the selector on exactly one ESC.
A missing count or a failed read is "unknown", not "one ESC": the page
keeps all four rows with only ESC 1 openable rather than entering
pass-through on a twin-motor model unasked. No other harness loads this
page (they stub it to avoid its os.clock() delays). Ported from
rotorflight-lua-ethos-suite#2460. Pass --self-test to prove all 5 gate
checks fail with the fix cut back out.
'''
    ),
    LuaStep(
        name='Check that unedited ESC bytes survive a save',
        script='bin/esc_raw_bytes/verify_esc_raw_bytes.lua',
        rationale=r'''The Bluejay and AM32 forward-programming codecs built the write payload
from the parsed fields alone, and the flight controller merges nothing:
MSP_SET_ESC_PARAMETERS (wingflight-firmware msp.c:3565-3576) copies the
66 (Bluejay) or 50 (AM32) bytes sent over the ESC's block and commits
them. So every byte encode() did not reproduce was a byte the ESC was
told changed: Bluejay rewrote 655 of the possible startup-power,
PWM-frequency and PWM-threshold values on a save with nothing edited,
and AM32 248 of 256 timing-advance values (two firmware generations
number the same positions differently). encode() now starts from the
ESC's own bytes and writes a field only when the pilot moved it; a
write with no ESC bytes behind it is refused rather than sent as zeros.
The exhaustive check runs every byte position against all 256 values
through the real codecs, pages and page runtime. Ported from
rotorflight-lua-ethos-suite#2461. Pass --self-test to prove all 14 gate
checks fail with the pre-fix codecs spliced back in.
'''
    ),
    LuaStep(
        name='Check that a short FlyRotor block is refused, not zero-filled',
        script='bin/esc_flyrotor_payload/verify_flyrotor_payload.lua',
        rationale=r'''The FlyRotor block is 56 bytes by the flight controller's own compiled
page table (wingflight-firmware esc_sensor.c:1933-1934, four pages of
22 + 12 + 10 + 10 plus the 2-byte header), and the FC hands it over only
once every page is cached, so a shorter reply is a truncated read, not
a smaller layout. lib/mspcodec.lua reads past the end as 0, and the
codec did not check the length: a 40-byte reply opened an editor whose
unseen ADV and OTHER settings were zero, and Save wrote those zeros to
the ESC (flyParamCommit writes every page that differs). decode() now
refuses a short block, encode() refuses a table that is not a decoded
one, and the length guard is summed from the same widths as the layout.
The layout is walked against the firmware page table and the round trip
is exhaustive (56 positions x 256 values). Ported from
rotorflight-lua-ethos-suite#2462 (open upstream at the time of the
port). Pass --self-test to prove all 8 gate checks fail with the
pre-fix codec spliced back in.
'''
    ),
    LuaStep(
        name='Check that the biased ESC words never reach 0xFFFF',
        script='bin/esc_xdfly_bias/verify_xdfly_bias.lua',
        rationale=r'''Three of the twenty-one XDFly block's words are stored one below the number
the page shows (FIELD_OFFSETS: gov_p 1, gov_i 1, motor_poles 1), and encode()
subtracted the bias without clamping the result. A value of 0 therefore packed
0 - 1 = -1, and mspcodec.writeU16 MASKS rather than clamps -- toByte() is
math_floor(value) % 256 (lib/mspcodec.lua:87-89) -- so both bytes came out 0xFF.

0xFFFF is not an arbitrary number here. It is what the ESC answers a write it
refused, and the firmware says so: wingflight-firmware
src/main/sensors/esc_sensor.c:3819 -- "when setting a param and the ESC responds
with 0xFFFF, setting the param was not successful".

WHAT IS NOT CLAIMED. The page cannot produce a value below the bias:
FIELD_META's min equals the bias for all three fields, and field_layout.lua
hands that straight to form.addNumberField, so this is a latent defect, not an
observed one. Two things keep it worth fixing rather than documenting:
`data and data[key] or 0` packs 0 for an ABSENT key, which lands on 0xFFFF by
itself, and encode() is a library function that every writer reaches, not the
widget alone.

OMP and ZTW are driven too. Both requireModule() this codec and delegate
buildWriteMessage to it (omp:8/:43-46, ztw:8/:43-46), so a clamp landing in only
the XDFLY file would leave two vendors broken -- and pass 2 of the self-test has
to seed the base key with the sabotaged codec before loading them, or
requireModule() re-reads the repaired file off disk and both vendor gates stay
green.

8 of its 22 checks are gates. Pass --self-test to prove that: it cuts the clamp out
of encode() and requires all eight to go red, comparing verdicts BY NAME. It
verifies its own cut five ways first. Two of those verifications exist because
this file got it wrong first, and both failures were silent -- pass 2 ran the
FIXED codec twice and reported every gate green:
  * "  for i = 1, #EDIT_FIELDS do" appears in decode() AND in encode(), so a cut
    anchored on the loop alone replaced the wrong one and left the clamp standing.
  * the codec's own self-cache guard is keyed "wfsuite.lib.msp_esc_parameters_xdfly",
    so loading the sabotaged copy under a different key cleared nothing and the
    guard returned the fixed module.

Three checks are deliberately NOT gates, and the file says which: the
FIELD_OFFSETS round-trip over the legal range (the pre-fix code got that right),
the whole-block sweep, and the two vendors' signature bytes. The sweep is the
subtle one: without the clamp, -1 masks to 0xFFFF inside the SAME two bytes the
clamp writes, so it cannot tell the defect from the fix. A gate that cannot fail
is worse than no check at all.

Ported from rotorflight-lua-ethos-suite#2468. NOT ported with it: the EdgeTX half.
This repository's own EdgeTX sibling carries the same bias table and no clamp
either (wingflight-lua-edgetx src/SCRIPTS/WF/MSP/mspEscXdfly.lua:151-152, and
its writeU16 masks with bit32.band at MSP/mspHelper.lua:37-41), which is a
separate piece of work in another repository.
'''
    ),
    LuaStep(
        name='Check the Tune Advisor history on disarm',
        script='bin/tests/tune_history.lua',
        rationale=r'''The FC keeps its tune advisor statistics in RAM; the radio saves each
flight on disarm, clears the FC, and the page combines the last 5 flights
on the current tune. Pins the capture (one flight per disarm, then a
clear; 5 flights kept; a disarm during a link loss captured on reconnect;
firmware without the command asked once) and the aggregate (only the
newest tune, counts added, ratios weighted).
'''
    ),
    LuaStep(
        name='Check the Hobbywing V5 OPTO layout',
        script='bin/esc_hw5_opto/verify_hw5_opto.lua',
        rationale=r'''The HW5 codec chose its field layout by a profile key, and only one OPTO
profile existed, so every other OPTO model fell through to the default
layout: an OPTO ESC has no BEC byte, so every field from item 5 up was
read and written one byte off, on a page that looked normal. The layout
is now chosen by variant (OPTO found in the firmware string or either
model string), and an OPTO model gets no BEC Voltage row. Ported from
rotorflight-lua-ethos-suite#2463. Pass --self-test to prove all 12 gate
checks fail on the pre-fix codec.
'''
    ),
    LuaStep(
        name='Check the Hobbywing V5 Startup Time conversion',
        script='bin/esc_hw5_startup/verify_hw5_startup.lua',
        rationale=r'''Startup Time is declared 4..25 s, but decode() handed the page the raw
byte, which runs 0..21, so the shortest start-up showed "0s" on a row
that begins at 4. The codec now adds 4 on read and takes it off on
write (clamped to 21), matching the EdgeTX page the HW5 layouts come
from, so a save writes back the byte the ESC sent. Ported from
rotorflight-lua-edgetx-suite#2464. Pass --self-test to prove all 6 gate
checks fail on the pre-fix codec.
'''
    ),
    LuaStep(
        name='Check the YGE ESCs can be told apart by their serial number',
        script='bin/esc_parameters_yge/verify_yge_serial.lua',
        rationale=r'''lib/msp_esc_parameters_yge.lua decodes the ESC's own serial number -- WIRE_FIELDS
carries {"serial_number", "u32"} -- and summaryFor() printed two parts, the model
label and the firmware version. A pilot with four YGE ESCs had no way to tell them
apart on the screen. The EdgeTX suite shows it as the `S/N:` part of its subheader
(rotorflight-lua-edgetx-suite src/rfsuite/ui/controls.lua:335-356).

Both decisions follow the sibling suite rather than argue for themselves, which its
getEscVersion() settles in one line:

    local sn = getUInt(buffer, {29, 30, 31, 32})
    return sn ~= 0 and tostring(sn) or ""

Decimal, and nothing printed for a zero -- "S/N 0" would read like data and
identify nothing. Those indices also settle the offset, which looks two bytes out
from here and is not: that page carries `local mspHeaderBytes = 2` and its getUInt
adds it to every index, so 29 + 2 = 31, which is where serial_number starts in this
suite. Verified here against the shipped fixture, not against a comment.

The serial is display only. encode() writes every WIRE_FIELD from the table
page_runtime hands it, and the page drops the module on dispose, so the number is
neither written nor held; the harness pins the first half by pressing the pilot's
own Save and reading the wire.

3 of the harness's 12 checks go red without the fix. Four that looked like gates
are checks instead, and the harness says which: a codec that shows no serial at all
also shows no "S/N 0", raises nothing on a nil, and already wrote the ESC's own
serial bytes back unchanged.

Ported from rotorflight-lua-edgetx-suite#2469.
'''
    ),
    LuaStep(
        name='Check the Scorpion ESCs can be told apart, and the word labelled FW was not one',
        script='bin/esc_parameters_scorpion/verify_scorpion_serial.lua',
        rationale=r'''Bytes 57..62 of the Scorpion block were carried as three anonymous U16s named
padding_1, padding_2 and padding_3, and the summary line read two byte offsets out of
the raw block by hand:

    return string.format("%s / FW %08X / v%d", model,
      uintFromRaw(data, {55, 56, 57, 58}),
      uintFromRaw(data, {61, 62}))

The sibling suite names those bytes, and the widths add up exactly -- 4 + 2 = the 6
bytes the three U16s occupied:

    rotorflight-lua-edgetx-suite src/rfsuite/tasks/msp/api/esc_parameters_scorpion.lua
    ... {"motor_startup_sound","U16"}, {"serial_number","U32"},
        {"firmware_version","U16"}, {"soft_start_time","U16"}, ...

So "FW %08X" was assembled from motor_startup_sound (55-56) and the LOW HALF of
serial_number (57-58) -- a number with nothing behind it, shown on the page since
the codec was written. Nothing that meant anything goes away with it: the version
was already on the line as "v%d" from bytes 61-62, which that list calls
firmware_version. That page has NO header compensation, unlike the YGE one, so its
byte numbers and this suite's are the same numbers.

The reference prints the serial in decimal and nothing for a zero, so both decisions
follow it. uintFromRaw had no caller left afterwards and is removed rather than left
defined: an unused helper in a codec is an invitation to reach for byte offsets
again, which is how the FW word came to be labelled wrong.

4 of the harness's 14 checks go red without the change. Two that look like gates are
checks instead, and the harness says which: the field-list parity check compares two
transcriptions and never reads the codec, and "two ESCs that differ only in serial do
not render the same line" was ALREADY true before the change, because the word
labelled FW was built from bytes that include the low half of the serial -- true for
the wrong reason, which makes it useless as a gate. The gate that ties the naming
claim to the code is the fixture round-trip: the serial the codec decodes has to be
the u32 at byte 57.

Ported from rotorflight-lua-edgetx-suite#2469.
'''
    ),
    # Appended after the xdfly-bias port, so this entry is a pure addition rather than
    # a re-registration of any step above.
    LuaStep(
        name="Check that the Throttle Protocol list follows the firmware's enum",
        script='bin/motor_protocol/verify_motor_protocol.lua',
        rationale=r'''The Throttle Protocol row offered BRUSHED, which is not a protocol. The
firmware removed the support and kept slot 4 as a placeholder so the numbers after it
would not move -- wingflight-firmware src/main/drivers/motor.h:34 still carries
"// BRUSHED" on PWM_TYPE_RESERVED, and checkMotorProtocolEnabled()
(drivers/motor.c:155-177) has no case for it, so a FC configured with 4 reports the
motor output as not enabled. It is dropped from the menu outright: keeping it visible
when the FC already reports 4 would need the form rebuilt after the payload arrives,
and field_layout has no re-spec path (buildSingle calls addLine, so a second call
would put a second row on the screen). Round-trip integrity is preserved and checked --
decoding slot 4 and saving back commits 4 unchanged.

WHAT IS NOT CLAIMED. This port is not the upstream change verbatim, and the difference
is the point. Upstream's list had no SRXL2, so its DISABLED entry sat on 10 -- which
is SRXL2 -- and selecting DISABLED armed a serial ESC link instead of switching the
motor output off. THIS LIST CARRIED SRXL2 AND HAD DISABLED ON 11 ALREADY, so there
was no wrong wire value here and the "picking DISABLED writes 11" case is a check, not
a gate. Nor is a version gate: upstream needed one because SRXL2 requires API 12.10 and
that suite's floor is 12.09, while this suite's floor is 22.13
(lib/msp_api_version.lua:26), past every protocol's introduction. A gate that cannot
refuse anything is a second thing to keep true.

What did survive is five bare `10` literals in the two ESC pages, used as the fallback
for a motor_pwm_protocol the FC never sent -- and 10 is SRXL2. Measured, not assumed:
on this side those literals produced the row state the right constants produce, so no
row was wrongly enabled. What they made possible is worse: the row-state test had to
grow to cover SRXL2, and at that point a literal 10 would have silently turned
DISABLED's row state into SRXL2's. All five now read motorConfig.DISABLED_PROTOCOL.

3 of its 25 checks are gates. Pass --self-test to prove that: it restores BRUSHED in
the codec and the row-state test in the page, and requires all three to go red by
name. The splice is verified before use, and it also asserts that SRXL2 is STILL
offered and DISABLED is still 11 -- otherwise a botched splice could reproduce UPSTREAM's
pre-fix state and the self-test would pass for the wrong reason.

Ported from rotorflight-lua-ethos-suite#2465.
'''
    ),
    LuaStep(
        name='Check the YGE block is as long as the count the ESC reports',
        script='bin/esc_parameters_yge/verify_yge_block_length.lua',
        rationale=r'''The YGE parameter block is not a fixed size. The flight controller derives its length
from the count the ESC itself reports (rotorflight-firmware src/main/io/esc_sensor.c:
ygeParamCount = ygeParams[0], paramPayloadLength = ygeParamCount * 2,
escGetParamFullBufferLength() = PARAM_HEADER_SIZE + paramPayloadLength with
PARAM_HEADER_SIZE = 2, and OPENYGE_PARAM_CACHE_SIZE_MAX = 64), so the real range is
1..64 parameters. The codec described 30 fixed fields, 58 bytes -- 2 + 28 * 2, right
for an ESC reporting 28 and for no other.

Its own fixture said 32 and stopped at 58: measured, bytes 3..4 read 32 and
2 + 32 * 2 = 66, which is the length the EdgeTX suite's fixture carries for the same
ESC. So the shipped fixture described an ESC eight bytes longer than the block it stood
for, and every save was that much short.

On the write side a short payload is not a truncation. msp.c's only length check on
MSP_SET_ESC_PARAMETERS is `if (len == 0)`, sbufReadData's memcpy has no bounds check,
and the destination paramUpdBuffer is a static array nothing clears per message -- so
the firmware copies the overflow out of the PREVIOUS contents of that buffer and
escCommitParameters() writes those bytes to the ESC.

Three rules, and the second is the one a reviewer should check hardest:

  1. The payload is exactly 2 + 2 * count, with the unknown tail carried through a
     read and written back verbatim. Not zeroed: a zero there is a parameter the pilot
     never saw and never chose.
  2. A block that cannot be written AS THE ESC DESCRIBED IT is REFUSED, not padded.
     A count of 0 or one past 64 is refused; a block that arrives short of what its own
     count demands is refused; and a count below 28 is refused because the block ends
     inside the field list, so at least one named field was never read and writing it
     would mean inventing it. That is the misalignment case, and padding it to 58 would
     be the defect. The refusal is lib/msp_governor_profile.lua's shape (#2446), and
     app/page_runtime.lua reads a nil message as a REFUSED write and names the reason.
  3. A field the buffer did not carry stays ABSENT rather than decoding as zero.
     mspcodec.lua reads a missing byte as 0, so a short block used to decode into a
     table of plausible zeros with nothing wrong anywhere.

8 of the harness's 12 checks go red without the fix, over every count from 1 to 64
rather than a sample. The one that looks like a gate and is not checks the harness's own
buffer builder, so it is green in both passes by construction and says so.

Two harnesses asserted that the fixture's length EQUALS what their field tables cover,
which is what let a fixture describe the wrong ESC. They now assert two things: that
the named fields cover the first 58 bytes, and that the fixture's length is what its
own count asks for. One of them also drove the codec with a two-field hand-built
table, which the refusal now rejects -- correctly, since such a table carries no count
and no length -- so it decodes the fixture first and overrides the field under test.

Not claimed: the count a real YGE ESC reports. Every number above comes from the
fixture; there is no YGE hardware here, and what an ESC does with a misaligned block is
unchecked. The firmware-side half of #2458 -- msp.c comparing sbufBytesRemaining(src)
against len the way MSP_SET_4WIF_ESC_FWD_PROG does -- is one line in another
repository.

Ported from rotorflight-lua-ethos-suite#2472 (open upstream at the time of the
port); the two YGE codecs differ in four lines, all of them the namespace.
'''
    ),
    LuaStep(
        name='Check the battery profile index bases',
        script='bin/battery_profile/verify_battery_profile_index.lua',
        rationale=r'''#154 replaced four copies of a helper that accepted either base at once, and shipped
without a harness, so nothing ran against the fix that removed it. That helper
tested `>= 1 and <= 6` first and decremented, then tested `>= 0 and <= 5` -- two
overlapping ranges, so the first one swallowed every internal index of 1..5.
Selecting pack 5 wrote pack 4's index to the FC, and normalize(0) == normalize(1)
== 0, so a real 1 -> 2 pack change read as "no change" and the dashboard widget's
already-selected guard dropped it.

Two properties are pinned here that a cheaper-looking rewrite would lose: index0()
is injective over 0..5, so two different packs never normalise to the same value,
and the round trip internal index -> label -> sensor reading -> internal index is
lossless for all six packs, which is what keeps the announced pack number equal to
the reading the FC reports.

The harness runs on the pre-fix sources and reports 26 of 37 checks red, the
call-site sweep naming the four files that still carried their own copy. The sweep
is the half worth keeping: the module itself would still pass a value-level test
while a local copy of the old helper crept back in beside it.

Not claimed: the pack number on the radio. Only the arithmetic and the call sites
are checked here, on Desktop Lua. Nothing in this harness ran on a transmitter, and
no pack swap was driven against a flight controller.
'''
    ),
    LuaStep(
        name='Check the Bluejay LED Control row',
        script='bin/bluejay_led_control/verify_bluejay_led_control.lua',
        rationale=r'''app/pages/esc_forward_bluejay.lua declared an LED Control row and gated it on
msp.supportsLedControl(), which read _raw[67] and compared it with the five ASCII
letters naming Bluejay's five LED-capable pinouts. The MSP 217 reply is 66 bytes --
two header bytes plus BLHELI_S_MSP_NUM_EEPROM_BYTES (0x40) -- so _raw[67] is nil,
the comparison is false, and esc_forward_vendor.lua's fieldEnabled() requires
`== true`: the row could never be shown on any ESC. Measured here rather than
assumed, because the whole case rests on the length.

The row is gone rather than repaired, and the reasons are in the firmware.
mathiasvr/bluejay lists all 26 supported ESCs with their LED counts in
Bluejay.asm:63-91 and exactly five have one (E_ 3, J_ 3, M_ 1, Q_ 2, U_ 3; every
other layout reads "_" there, Z_ reads "-"), but those letters are EQU constants of
the build. The EEPROM segment at 1A00h (Bluejay.asm:321-364) holds 41 parameter
bytes and not one is a layout letter; the only layout-related byte is
Eep_Layout_Revision, written from the firmware-wide EEPROM_LAYOUT_REVISION = 204
(Bluejay.asm:319), which every layout shares. Byte 43 of the block IS the LED byte --
Eep_Pgm_LED_Control, segment offset 0x28 -- so the byte can be written, but nothing
on the wire says whether writing it does anything. And the row's choice list was
BLHeli_S's: Bluejay drives one pin per LED, two bits each, lit when the pair is
non-zero (Bluejay.asm:1525-1556), so that list's "Green" is one LED on rather than a
colour. Putting the row back means per-LED on/off, which is a decision about the UI
and not a repair of this byte. Byte 43 is kept as the name reserved_28, so the block
still decodes and re-encodes all 66 bytes -- the flight controller commits exactly
escGetParamBufferLength() of them, so a dropped field entry would have shortened the
payload rather than removed a row.

Three gates. The first is the defect class and outlives this row: no criterion and no
label on the page may read a byte the reply does not carry. The reads are traced
through a metatable on _raw, so the check reports WHICH byte was reached for, and a
revision test like atLeast(209) -- correctly false for a layout-204 ESC -- is not
caught, because it reads layout_revision, which decode() did produce. The other two
pin the decision itself, so a correct LED row can come back only deliberately, with
the criterion that makes it reachable.

Four checks are deliberately NOT gates, because they were true before the fix as
well: the reply is 66 bytes and has no byte 67, byte 43 round-trips unchanged over
all 256 values, every one of the 66 positions still has exactly one owning field,
and byte 43 is among them under the name reserved_28. They are the guard on what the
rename could have broken.

3 of its 7 checks go red on the pre-fix page and codec. Pass --self-test to prove
that rather than take it on trust: it splices the pre-fix row and the pre-fix
criterion back into copies of both files, proves each splice is the pre-fix code
before letting it stand in for one -- different file, reads back, loads, and writes
the same 66 bytes -- and requires all three to fail.

The defect was here first and came to the sibling suite with it; this suite carries
no byte-67 read of its own any more. The Rotorflight Configurator made the other
choice and documents it: tabs/esc_programming/manufacturers/bluejay.js:11-13 cites
that function as the thing it chose NOT to replicate, and shows the row
unconditionally.
Ported from rotorflight-lua-ethos-suite#2475, which closes rotorflight #2453.
'''
    ),
]

VERBATIM_JOBS = [
    # create-zip
r'''  # Per-language PR builds (mirrors push.yml behavior)
  create-zip:
    name: Build PR ZIP (${{ matrix.lang }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        # keep this in sync with push.yml (add/remove locales as needed)
        lang: [en, de, es, fr, it, nl, pt-br, no, cs, pl, he, zh-cn]

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Set build variables (PR version)
        run: |
          PR_NUMBER='${{ github.event.pull_request.number }}'
          echo "GIT_VER=PR-${PR_NUMBER}" >> $GITHUB_ENV

      - name: Create wingflight-lua-ethos-suite-${{ env.GIT_VER }}-${{ matrix.lang }}.zip
        run: |
          python bin/package/build_package.py \
            --lang '${{ matrix.lang }}' \
            --artifact-version '${{ env.GIT_VER }}' \
            --artifact-name 'wingflight-lua-ethos-suite-${{ env.GIT_VER }}-${{ matrix.lang }}.zip' \
            --output-dir .

      - name: Validate ETHOS package manifest
        run: |
          python bin/package/validate_ethos_manifest_zip.py \
            'wingflight-lua-ethos-suite-${{ env.GIT_VER }}-${{ matrix.lang }}.zip'

      - name: Upload per-locale ZIP
        uses: actions/upload-artifact@v4
        with:
          name: wingflight-lua-ethos-suite-${{ env.GIT_VER }}-${{ matrix.lang }}
          path: wingflight-lua-ethos-suite-${{ env.GIT_VER }}-${{ matrix.lang }}.zip
          if-no-files-found: error
'''
    ,
    # sensor-table-completeness
r'''  # tasks/elrs_sensors.lua's parseFrame() stops at the first appId it has no
  # decoder for and cannot skip it -- the pair's byte width lives only in
  # src/wfsuite/lib/elrs_sensor_table.lua. So one appId the table is missing
  # silently costs every sensor packed after it in the same frame, and the
  # symptom looks like a dead sensor. The table is compared against
  # wingflight-firmware's TLM_SENSOR(...) list, read at a pinned commit so a
  # firmware that adds an appId shows up here as a deliberate change.
  sensor-table-completeness:
    name: Sensor table completeness
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Prove the check can go red
        run: python bin/telemetry/verify_sensor_table.py --self-test

      - name: Check every broadcast appId has a decoder
        run: python bin/telemetry/verify_sensor_table.py
'''
    ,
    # documentation-rule
r'''  # The rule in .agents/rules/documentation.md asks that a change a pilot can observe
  # updates its page file in the same pull request, and that a pull request which needs
  # no documentation change says why. Nothing checked either half, so both rested on
  # the author remembering at the moment they are least likely to.
  #
  # The check is deliberately narrower than the rule says, because no static check can
  # decide what a pilot can observe: it asks nothing of a pull request that changes
  # nothing under src/, passes one that changes src/ and also docs/, and passes one
  # that changes src/ and no docs/ only if its body carries a `Documentation:` line of
  # its own. Whether that reason is a good one is the reviewer's call.
  documentation-rule:
    name: Documentation rule
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          # the check diffs against the base commit, which a shallow clone does not carry
          fetch-depth: 0

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Prove the check can go red
        run: python bin/docs/verify_documentation_rule.py --self-test

      - name: Write the pull request body to a file
        # through the environment, never interpolated into the script: a pull request
        # body is text anybody can write
        env:
          PR_BODY: ${{ github.event.pull_request.body }}
        run: printf '%s' "$PR_BODY" > pr-body.txt

      - name: Check the documentation rule
        run: |
          python bin/docs/verify_documentation_rule.py \
            --base '${{ github.event.pull_request.base.sha }}' \
            --body-file pr-body.txt
'''
    ,
    # pr-workflow-drift
r'''  # pr.yml is rendered from bin/ci/pr_jobs.py, so two pull requests that each
  # add a harness add a registry entry rather than colliding on the same lines
  # of this file. This job is the other half of that: a registry edited without
  # regenerating leaves the two disagreeing, and it also pins the shape a bad
  # merge produced upstream twice -- every job needs a runs-on and a step.
  pr-workflow-drift:
    name: The pull request workflow matches its registry
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Prove the check can go red
        run: python bin/ci/verify_pr_workflow.py --self-test

      - name: Check pr.yml against the registry
        run: python bin/ci/verify_pr_workflow.py
'''
    ,
]
