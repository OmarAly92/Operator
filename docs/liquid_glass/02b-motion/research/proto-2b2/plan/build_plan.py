import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Expand a plan template's patch markers into git diffs taken from the prototype branch, and its output markers into the last lines a replay recorded.")
ARGS.add_argument("template")
ARGS.add_argument("out")
ARGS.add_argument("--repo", required=True)
ARGS.add_argument("--results")
OPTIONS = ARGS.parse_args()

PATCH = re.compile(r"^<<PATCH (?P<name>\S+) from=(?P<base>\S+) to=(?P<head>\S+) files=(?P<files>\S+)>>$", re.M)
OUT = re.compile(r"^<<OUT (?P<label>\S+)>>$", re.M)
TESTS = re.compile(r"(^|/)tests?/")
ROOT = "packages"


def git(*args):
    return subprocess.run(["git", "-C", OPTIONS.repo, *args], check=True, capture_output=True, text=True).stdout


def changed(base, head):
    return [path for path in git("diff", "--name-only", "--no-renames", base, head, "--", ROOT).split("\n") if path]


def select(match):
    spec = match["files"]
    found = changed(match["base"], match["head"])
    if spec == "@all":
        return found
    if spec == "@tests":
        return [path for path in found if TESTS.search(path)]
    if spec == "@impl":
        return [path for path in found if not TESTS.search(path)]
    files = spec.split(",")
    for path in files:
        if path not in found:
            sys.exit(f"{match['name']}: {path} does not change between {match['base']} and {match['head']}")
    return files


def expand_patch(match):
    files = select(match)
    if not files:
        sys.exit(f"{match['name']}: no files selected by {match['files']}")
    diff = git("diff", "--full-index", "--no-color", "--no-renames", match["base"], match["head"], "--", *files)
    if "```" in diff:
        sys.exit(f"{match['name']}: the diff holds a code fence")
    return f"Patch `{match['name']}` (`{match['base'][:10]}..{match['head'][:10]}`, {len(files)} files):\n\n```diff\n{diff}```"


results = json.loads(Path(OPTIONS.results).read_text()) if OPTIONS.results else {}


def expand_out(match):
    found = results.get(match["label"])
    if not found:
        return ""
    return "Expected output ends with:\n\n```text\n" + "\n".join(found["tail"]) + "\n```"


text = Path(OPTIONS.template).read_text()
names = [m["name"] for m in PATCH.finditer(text)]
if len(names) != len(set(names)):
    sys.exit("duplicate patch names")
labels = [m["label"] for m in OUT.finditer(text)]
runs = re.findall(r"^RUN\[(\S+)\]:", text, re.M)
if len(runs) != len(set(runs)):
    sys.exit("duplicate run labels")
missing = sorted(set(labels) - set(runs))
if missing:
    sys.exit(f"output markers without a run: {missing}")
text = PATCH.sub(expand_patch, text)
text = OUT.sub(expand_out, text)
Path(OPTIONS.out).write_text(text)
print(f"{len(names)} patches and {len(runs)} runs written to {OPTIONS.out}")
