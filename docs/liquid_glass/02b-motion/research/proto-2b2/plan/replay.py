import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Apply a plan's patches and run its RUN lines in document order on a fresh export, committing per patch, and record or check each run's last output lines.")
ARGS.add_argument("plan")
ARGS.add_argument("--repo", required=True)
ARGS.add_argument("--results", required=True)
ARGS.add_argument("--stop-after")
ARGS.add_argument("--skip-runs", action="store_true")
OPTIONS = ARGS.parse_args()

TOKEN = re.compile(
    r"^Patch `(?P<name>[^`]+)`[^\n]*\n\n```diff\n(?P<diff>.*?)```"
    r"|^RUN\[(?P<label>[^\]]+)\]: `(?P<command>[^`]+)` => (?P<expect>PASS|FAIL)[^\n]*(?:\n\nExpected output ends with:\n\n```text\n(?P<tail>.*?)\n```)?",
    re.M | re.S,
)
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
TIMER = re.compile(r"^\d\d:\d\d ")
SUMMARY = re.compile(r"All tests passed!|No issues found!|^OK$|^Ran \d+ tests|^built for |^moved |^\[\(")
FAILURE = re.compile(r"FAILED|Some tests failed|[Ee]rror|[Ff]ailed")
ROOT = re.compile(r"/Users/[^ ]*?/Operator[^/ ]*")
PROGRESS = re.compile(r"^(\+\d+(?: -\d+)?): (?=All tests passed|Some tests failed)")
DURATION = re.compile(r"\((?:ran )?in \d+(?:\.\d+)?m?s\)|in \d+(?:\.\d+)?s")


def normalise(line):
    line = ANSI.sub("", line).rstrip()
    line = ROOT.sub("<repo>", line)
    line = TIMER.sub("", line)
    line = PROGRESS.sub(lambda found: found.group(1) + ": ", line)
    return DURATION.sub("in <time>", line)


def run(*args, data=None):
    return subprocess.run(args, cwd=OPTIONS.repo, input=data, check=True, capture_output=True, text=True)


text = Path(OPTIONS.plan).read_text()
results = {}
problems = []
patches = 0
for match in TOKEN.finditer(text):
    if match["name"]:
        name = match["name"]
        try:
            run("git", "apply", "--3way", "--whitespace=nowarn", "-", data=match["diff"])
        except subprocess.CalledProcessError as error:
            sys.exit(f"{name}: git apply failed\n{error.stderr}")
        run("git", "add", "-A")
        run("git", "commit", "-q", "-m", f"replay {name}\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>")
        patches += 1
        print(f"applied {name}", flush=True)
        if name == OPTIONS.stop_after:
            break
        continue
    if OPTIONS.skip_runs:
        continue
    label, expect = match["label"], match["expect"]
    done = subprocess.run(["bash", "-c", match["command"]], cwd=OPTIONS.repo, capture_output=True, text=True, timeout=3600)
    lines = [normalise(line) for line in (done.stdout + done.stderr).split("\n") if line.strip()]
    if expect == "FAIL":
        named = [line for line in lines if FAILURE.search(line)]
        kept = (named or lines)[-1:]
    else:
        named = [line for line in lines if SUMMARY.search(line)]
        kept = named[-2:] if named else lines[-2:]
    outcome = "PASS" if done.returncode == 0 else "FAIL"
    results[label] = {"command": match["command"], "expect": expect, "outcome": outcome, "exit": done.returncode, "tail": kept}
    flag = "ok" if outcome == expect else "MISMATCH"
    if outcome != expect:
        problems.append(f"{label}: expected {expect}, got {outcome}")
    elif match["tail"] is not None and [normalise(line) for line in match["tail"].split("\n")] != kept:
        problems.append(f"{label}: output differs: plan {match['tail']!r} against {kept!r}")
        flag = "OUTPUT"
    print(f"{flag} {label}: {outcome} {' | '.join(kept)}", flush=True)
    Path(OPTIONS.results).write_text(json.dumps(results, indent=1))
print(f"{patches} patches, {len(results)} runs, {len(problems)} problems")
for problem in problems:
    print("PROBLEM", problem)
sys.exit(1 if problems else 0)
