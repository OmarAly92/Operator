#!/usr/bin/env python3
import json
import os
import shutil
import sys

SOURCE = "/Users/omaraly/development/AI/alacritty/alacritty_terminal/tests/ref"
TARGET = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "crates", "vt-core", "tests", "ref")


def main():
    names = sorted(entry for entry in os.listdir(SOURCE) if os.path.isdir(os.path.join(SOURCE, entry)))
    for name in names:
        src = os.path.join(SOURCE, name)
        dst = os.path.join(TARGET, name)
        os.makedirs(dst, exist_ok=True)
        shutil.copyfile(os.path.join(src, "alacritty.recording"), os.path.join(dst, "recording"))
        with open(os.path.join(src, "size.json")) as handle:
            size = json.load(handle)
        with open(os.path.join(dst, "size.json"), "w") as handle:
            json.dump([{"offset": 0, "cols": size["columns"], "rows": size["screen_lines"]}], handle)
    print("\n".join(names))
    return 0


if __name__ == "__main__":
    sys.exit(main())
