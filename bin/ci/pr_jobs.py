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
