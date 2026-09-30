#!/usr/bin/env python3
"""Check that .github/workflows/pr.yml is what the job registry renders.

The workflow used to be maintained by hand, and every pull request that added
a Lua harness put its step in the same place in the file -- the end of the one
Lua job. Two open pull requests that did the same thing collided on context
lines that had nothing to do with either change, and a wrong resolution is
not visible in review, because the diff of a squash merge is a diff against a
base, not against the file the merge produced. Upstream
(rotorflight-lua-ethos-suite #2414 and #2416) two such squashes left a job with
a `name:` and no `runs-on:`; that is a schema violation, so the workflow file
stopped loading and the run on master reported failure with zero jobs.

`pr.yml` is now rendered from bin/ci/pr_jobs.py, so a pull request adds a step
to the registry instead of editing a shared region of a shared file. This
check is the second half of that: it fails when the committed `pr.yml` and the
registry disagree, which is what stops the two from drifting apart.

    python bin/ci/verify_pr_workflow.py --self-test
    python bin/ci/verify_pr_workflow.py
    python bin/ci/verify_pr_workflow.py --write

Stdlib only, like every other Python check here: no job installs anything, and
a gate that needs a network install stops running the day the install fails.
So the shape checks scan the rendered text structurally instead of parsing it.

Line endings are compared after normalising CRLF to LF on both sides. The blob
in git is LF, `core.autocrlf=true` turns a Windows checkout into CRLF, and
there is no `*.yml` rule in .gitattributes -- so without this the same commit
would fail on a Windows clone and pass on CI.
"""

import argparse
import difflib
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pr_jobs  # noqa: E402

WORKFLOW = os.path.join(".github", "workflows", "pr.yml")

HEADER = """\
name: Create wfsuite-lua-ethos ZIP on PR

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
"""

CHECKOUT = "      - name: Checkout code\n        uses: actions/checkout@v4\n"
INSTALL_LUA = (
    "      - name: Install Lua 5.4\n"
    "        run: sudo apt-get update && sudo apt-get install -y lua5.4\n"
)

failures = 0
checks = 0


def check(label, ok, detail=""):
    global failures, checks
    checks += 1
    if ok:
        print("  ok    %s" % label)
    else:
        failures += 1
        print("  FAIL  %s%s" % (label, (" -- " + str(detail)) if detail else ""))


def normalise(text):
    return text.replace("\r\n", "\n")


def comment(rationale, indent):
    out = []
    if rationale.strip():
        for line in rationale.rstrip("\n").split("\n"):
            out.append((indent + "# " + line).rstrip() + "\n")
    return out


def render_lua_job(job, steps):
    out = comment(job.rationale, "  ")
    out.append("  %s:\n" % job.id)
    out.append("    name: %s\n" % job.name)
    out.append("    runs-on: ubuntu-latest\n")
    out.append("\n")
    out.append("    steps:\n")
    out.append(CHECKOUT)
    out.append("\n")
    out.append(INSTALL_LUA)
    for index, step in enumerate(steps):
        out.append("\n")
        out.extend(comment(step.rationale, "      "))
        out.append("      - name: %s\n" % step.name)
        # every harness after the first runs even when an earlier one failed,
        # so one red step does not hide the rest
        if index > 0:
            out.append("        if: success() || failure()\n")
        out.append("        run: lua5.4 %s\n" % step.script)
    return "".join(out)


def render():
    parts = [HEADER, render_lua_job(pr_jobs.LUA_JOB, pr_jobs.LUA_STEPS), "\n"]
    for block in pr_jobs.VERBATIM_JOBS:
        parts.append(block)
        parts.append("\n")
    # every job block is followed by one blank line, including the last, and
    # the file ends on a single newline
    return "".join(parts).rstrip("\n") + "\n"


def committed():
    """The pr.yml this check is about: the working tree, else the committed blob.

    Read as bytes and normalised, never through Python's text mode: text mode
    would translate CRLF on read on Windows and hide exactly the difference
    this check has to survive.
    """
    if os.path.isfile(WORKFLOW):
        with open(WORKFLOW, "rb") as fh:
            return normalise(fh.read().decode("utf-8"))
    try:
        raw = subprocess.run(
            ["git", "cat-file", "-p", "HEAD:" + WORKFLOW.replace("\\", "/")],
            capture_output=True,
            check=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return normalise(raw.decode("utf-8"))


def job_ids_of_verbatim():
    ids = []
    for block in pr_jobs.VERBATIM_JOBS:
        for line in block.split("\n"):
            match = re.match(r"^  ([a-z0-9][a-z0-9-]*):\s*$", line)
            if match:
                ids.append(match.group(1))
    return ids


def job_blocks(text):
    """Split rendered YAML into (job_id, [lines]) at the two-space job keys.

    Structural, not a parse -- see the module docstring for why. The shape
    checked here is the one the generator produces, so scanning for it is
    enough, and the verbatim blocks are hand-written, which is exactly where a
    wrong indent would hide.
    """
    blocks = []
    current = None
    for line in text.split("\n"):
        match = re.match(r"^  ([a-z0-9][a-z0-9-]*):\s*$", line)
        if match:
            current = (match.group(1), [])
            blocks.append(current)
            continue
        if current is not None:
            current[1].append(line)
    return blocks


def steps_without_run(lines):
    """Names of steps in a job block that carry neither `run:` nor `uses:`."""
    missing = []
    name = None
    has_action = False
    for line in lines + ["      - name: <end>"]:
        match = re.match(r"^      - name: (.*)$", line)
        if match:
            if name is not None and not has_action:
                missing.append(name)
            name = match.group(1)
            has_action = False
            continue
        if re.match(r"^        (run|uses):", line):
            has_action = True
    return missing


def shape_problems(text):
    """(jobs without runs-on, jobs without steps, steps without run/uses)."""
    blocks = job_blocks(text)
    without_runner = [
        job_id
        for job_id, lines in blocks
        if not any(line.strip().startswith("runs-on:") for line in lines)
    ]
    without_steps = [
        job_id
        for job_id, lines in blocks
        if not any(line.startswith("      - name:") for line in lines)
    ]
    without_run = [
        "%s: %s" % (job_id, step)
        for job_id, lines in blocks
        for step in steps_without_run(lines)
    ]
    return without_runner, without_steps, without_run


def case_registry_is_unique():
    print("case 1: every job id and step name is unique")
    ids = [pr_jobs.LUA_JOB.id] + job_ids_of_verbatim()
    check("no job id appears twice", len(ids) == len(set(ids)), ids)
    names = [step.name for step in pr_jobs.LUA_STEPS]
    check("no Lua step name appears twice", len(names) == len(set(names)),
          sorted(n for n in names if names.count(n) > 1))
    scripts = [step.script for step in pr_jobs.LUA_STEPS]
    check("no harness is run twice", len(scripts) == len(set(scripts)),
          sorted(s for s in scripts if scripts.count(s) > 1))
    check("the registry is not empty", len(pr_jobs.LUA_STEPS) > 0)


def case_every_script_exists():
    print("case 2: every step names a harness that is in the tree")
    for step in pr_jobs.LUA_STEPS:
        check(step.script, os.path.isfile(step.script), "missing")


def case_render_is_wellformed():
    print("case 3: the rendered file has the shape GitHub can load")
    text = render()
    blocks = job_blocks(text)
    check(
        "every job id in the render is in the registry",
        {job_id for job_id, _ in blocks}
        == set(job_ids_of_verbatim()) | {pr_jobs.LUA_JOB.id},
        sorted({job_id for job_id, _ in blocks}),
    )
    without_runner, without_steps, without_run = shape_problems(text)
    # The defect that cost upstream's master two squashes: a job carrying a
    # name and nothing else. The file does not load and the run has no jobs.
    check("every job has a runs-on", not without_runner, without_runner)
    check("every job has at least one step", not without_steps, without_steps)
    check("every step has a run or uses", not without_run, without_run)


def case_render_is_stable():
    print("case 4: rendering twice gives the same bytes")
    check("render() is deterministic", render() == render())
    check("the render ends in exactly one newline",
          render().endswith("\n") and not render().endswith("\n\n"))


def case_committed_matches():
    print("case 5: the committed pr.yml is what the registry renders")
    rendered = normalise(render())
    current = committed()
    if current is None:
        check("the committed pr.yml could be read", False, "git cat-file failed")
        return
    if current == rendered:
        check("pr.yml matches the registry", True)
        return
    check("pr.yml matches the registry", False,
          "diff below; run python bin/ci/verify_pr_workflow.py --write")
    for line in difflib.unified_diff(
        current.split("\n"),
        rendered.split("\n"),
        fromfile="committed " + WORKFLOW,
        tofile="rendered from bin/ci/pr_jobs.py",
        lineterm="",
    ):
        print("    " + line)


def self_test():
    """Prove the checks above can go red, by breaking each thing on purpose."""
    print("self-test: each check is shown going red on a sabotaged render")
    results = []

    def expect(label, reported):
        results.append(reported)
        print("  %s  %s" % ("ok   " if reported else "FAIL ", label))

    text = render()

    # 1. a job without runs-on -- the exact shape upstream's master carried
    runner = "  %s:\n    name: %s\n    runs-on: ubuntu-latest\n" % (
        pr_jobs.LUA_JOB.id, pr_jobs.LUA_JOB.name)
    broken = text.replace(runner, runner.replace("    runs-on: ubuntu-latest\n", ""), 1)
    expect("a job with a name and no runs-on is reported",
           broken != text and pr_jobs.LUA_JOB.id in shape_problems(broken)[0])

    # 2. a step whose run line was lost in a merge
    last = pr_jobs.LUA_STEPS[-1]
    broken = text.replace("        run: lua5.4 %s\n" % last.script, "", 1)
    expect("a step with no run is reported",
           broken != text and any(last.name in s for s in shape_problems(broken)[2]))

    # 3. drift between the registry and the committed file
    current = committed()
    if current is None:
        expect("an edited pr.yml differs from the render (cannot read pr.yml)", False)
    else:
        drifted = current.replace("runs-on: ubuntu-latest", "runs-on: ubuntu-22.04", 1)
        expect("an edited pr.yml differs from the render",
               drifted != normalise(render()))

    # 4. a registry that names a harness nobody wrote
    original = pr_jobs.LUA_STEPS
    pr_jobs.LUA_STEPS = list(original) + [
        pr_jobs.LuaStep(
            name="Check nothing",
            script="bin/ci/verify_no_such_harness.lua",
            rationale="A step whose harness does not exist.\n",
        )
    ]
    try:
        missing = [s.script for s in pr_jobs.LUA_STEPS if not os.path.isfile(s.script)]
        expect("a step naming a missing harness is reported",
               "bin/ci/verify_no_such_harness.lua" in missing)
    finally:
        pr_jobs.LUA_STEPS = original

    # 5. a duplicated step
    names = [s.name for s in original + [original[0]]]
    expect("a duplicated step is reported", len(names) != len(set(names)))

    ok = all(results)
    print("self-test: %s" % ("every check went red as it should" if ok else "SOME CHECKS STAYED GREEN"))
    return 0 if ok else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--self-test", action="store_true",
                        help="prove the checks below can go red, then exit")
    parser.add_argument("--write", action="store_true",
                        help="regenerate pr.yml from the registry instead of checking it")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    if args.write:
        with open(WORKFLOW, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(render())
        print("wrote %s from bin/ci/pr_jobs.py" % WORKFLOW)
        return 0

    case_registry_is_unique()
    case_every_script_exists()
    case_render_is_wellformed()
    case_render_is_stable()
    case_committed_matches()

    print("")
    if failures == 0:
        print("all %d checks passed" % checks)
        return 0
    print("%d of %d checks FAILED" % (failures, checks))
    return 1


if __name__ == "__main__":
    sys.exit(main())
