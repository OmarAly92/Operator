#!/usr/bin/env python3
import json
import sys


def main():
    if len(sys.argv) != 2:
        print("usage: alacritty-grid-text.py <ref dir>", file=sys.stderr)
        return 2
    with open(f"{sys.argv[1]}/grid.json") as handle:
        grid = json.load(handle)
    raw = grid["raw"]
    assert raw["zero"] == 0, "grid.json is serialised after truncate(); zero must be 0"
    rows = []
    for line in reversed(raw["inner"]):
        text = "".join(cell["c"] for cell in line["inner"] if "WIDE_CHAR_SPACER" not in (cell.get("flags") or ""))
        rows.append(text.rstrip())
    print("\n".join(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
