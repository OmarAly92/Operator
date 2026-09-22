#!/usr/bin/env python3
import json
import os
import shutil
import sys

SOURCE = "/Users/omaraly/development/AI/alacritty/alacritty_terminal/tests/ref"
TARGET = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "crates", "vt-core", "tests", "ref")


FLAG_BITS = {
    "ITALIC": 1 << 0,
    "UNDERLINE": 1 << 1,
    "DOUBLE_UNDERLINE": 1 << 2,
    "UNDERCURL": 1 << 3,
    "DOTTED_UNDERLINE": 1 << 4,
    "DASHED_UNDERLINE": 1 << 5,
    "STRIKEOUT": 1 << 6,
    "HIDDEN": 1 << 8,
}
TAG_INDEXED = 0x0100_0000
TAG_RGB = 0x0200_0000
DEFAULT_UNDERLINE = 255


def underline_code(extra):
    colour = (extra or {}).get("underline_color")
    if not colour:
        return DEFAULT_UNDERLINE
    if "Spec" in colour:
        spec = colour["Spec"]
        return TAG_RGB | (spec["r"] << 16) | (spec["g"] << 8) | spec["b"]
    if "Indexed" in colour:
        index = colour["Indexed"]
        return index if index < 16 else TAG_INDEXED | index
    return DEFAULT_UNDERLINE


def cell_is_blank(cell):
    return (
        cell["c"] == " "
        and not (cell.get("flags") or "")
        and cell["fg"] == {"Named": "Foreground"}
        and cell["bg"] == {"Named": "Background"}
        and not (cell.get("extra") or {}).get("zerowidth")
    )


def row_segments(line):
    cells = [cell for cell in line["inner"] if "WIDE_CHAR_SPACER" not in (cell.get("flags") or "")]
    while cells and cell_is_blank(cells[-1]):
        cells.pop()
    char_index = [0] * (len(cells) + 1)
    for index, cell in enumerate(cells):
        zerowidth = (cell.get("extra") or {}).get("zerowidth") or []
        char_index[index + 1] = char_index[index] + 1 + len(zerowidth)
    segments = []
    for index, cell in enumerate(cells):
        attrs = 0
        for flag in (cell.get("flags") or "").split("|"):
            attrs |= FLAG_BITS.get(flag.strip(), 0)
        underline = underline_code(cell.get("extra"))
        if attrs == 0 and underline == DEFAULT_UNDERLINE:
            continue
        from_char, to_char = char_index[index], char_index[index + 1]
        if segments and segments[-1][1] == from_char and segments[-1][2] == attrs and segments[-1][3] == underline:
            segments[-1][1] = to_char
        else:
            segments.append([from_char, to_char, attrs, underline])
    return segments


def write_styles(name):
    with open(os.path.join(SOURCE, name, "grid.json")) as handle:
        grid = json.load(handle)
    raw = grid["raw"]
    assert raw["zero"] == 0
    rows = [row_segments(line) for line in reversed(raw["inner"])]
    while rows and not rows[-1]:
        rows.pop()
    with open(os.path.join(TARGET, name, "styles.json"), "w") as handle:
        json.dump({"rows": rows}, handle)


def main():
    if "--styles" in sys.argv:
        for name in sys.argv[sys.argv.index("--styles") + 1:]:
            write_styles(name)
        return 0
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
