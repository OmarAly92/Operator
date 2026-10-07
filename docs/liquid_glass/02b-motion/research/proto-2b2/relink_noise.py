import argparse
import json
import os
import sys
from pathlib import Path

ARGS = argparse.ArgumentParser(description="Point every pair-folder link of a copied noise run that still names the removed Operator-2b1 worktree at the same take inside the copy.")
ARGS.add_argument("noise", help="the copy of the archive's noise-2b1 (never the archive itself)")
ARGS.add_argument("--old-prefix", default="/Users/omaraly/development/AI/Operator-2b1/packages/mobile/build/glass_lab/runs/noise-2b1")
OPTIONS = ARGS.parse_args()

NOISE = Path(OPTIONS.noise).resolve()
if "glass-lab-runs" in str(NOISE):
    sys.exit(f"{NOISE} is the archive: copy it first and pass the copy")
if NOISE.is_symlink() or Path(OPTIONS.noise).is_symlink():
    sys.exit(f"{OPTIONS.noise} is a link, not a copy")

moves = []
missing = []
for root, dirs, files in os.walk(NOISE):
    here = Path(root)
    if here == NOISE:
        dirs[:] = [d for d in dirs if d not in ("takes", "excluded")]
    for name in dirs + files:
        link = here / name
        if not link.is_symlink():
            continue
        target = os.readlink(link)
        if not target.startswith(OPTIONS.old_prefix):
            continue
        new = str(NOISE) + target[len(OPTIONS.old_prefix):]
        if not Path(new).exists():
            missing.append((str(link.relative_to(NOISE)), new))
            continue
        link.unlink()
        link.symlink_to(new)
        moves.append([str(link.relative_to(NOISE)), target, new])
if missing:
    for found in missing:
        print("MISSING", *found)
    sys.exit(f"{len(missing)} links name a take that is not in the copy")
(NOISE / "excluded").mkdir(exist_ok=True)
(NOISE / "excluded" / "relinks-2b2.json").write_text(json.dumps(moves, indent=1))
print(f"relinked {len(moves)} links")
