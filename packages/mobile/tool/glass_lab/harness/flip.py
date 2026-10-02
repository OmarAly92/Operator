from pathlib import Path

import numpy as np

import analyze
import metrics

WHITE = 245
BLACK = 10
TOLERANCE = 12
GAP = 4
BAND = 6
REGULAR = {44: (126, 237, 150, 44), 200: (21, 465, 360, 200)}
FLIP = {"small_top": (126, 242, 150, 44), "large": (21, 460, 360, 200), "small_bottom": (126, 756, 150, 44)}


def scaled(box, scale):
    return tuple(int(round(v * scale)) for v in box)


def inner(image, box, scale):
    x, y, w, h = scaled(box, scale)
    return float(metrics.luma(image[y + h // 4 : y + h - h // 4, x + w // 4 : x + w - w // 4]).mean())


def ring(image, box, scale):
    x, y, w, h = scaled(box, scale)
    g, b = int(round(GAP * scale)), int(round(BAND * scale))
    above = metrics.luma(image[max(0, y - g - b) : y - g, x : x + w])
    below = metrics.luma(image[y + h + g : y + h + g + b, x : x + w])
    values = np.concatenate([above.ravel(), below.ravel()])
    return float(np.percentile(values, 5)), float(np.percentile(values, 95))


def observe(paths, boxes, scale=1):
    rows = []
    for path in paths:
        image = metrics.load(path)
        rows.append({name: (*ring(image, box, scale), inner(image, box, scale)) for name, box in boxes.items()})
    return rows


def over(rows, name, backdrop):
    accept = (lambda low, high: low >= WHITE) if backdrop == "white" else (lambda low, high: high <= BLACK)
    values = [row[name][2] for row in rows if name in row and accept(row[name][0], row[name][1])]
    return float(np.median(values)) if values else None


def verdict(observed, same, other, tolerance=TOLERANCE):
    if observed is None:
        return "not seen"
    if abs(observed - same) <= tolerance:
        return "no flip"
    if abs(observed - other) <= tolerance:
        return "flips"
    return "neither"


def predictions(run_dir):
    table = {}
    for appearance in ("light", "dark"):
        for backdrop in ("white", "black"):
            ready = metrics.load(Path(run_dir) / "material.regular" / f"{appearance}-{backdrop}" / "native" / "ready.png")
            for size, box in REGULAR.items():
                table[(appearance, backdrop, size)] = inner(ready, box, metrics.SCALE)
    return table


def report(run_dir, regular_run=None):
    run_dir = Path(run_dir)
    expected = predictions(regular_run or run_dir)
    lines = ["| Appearance | Glass | Over | Observed | Same appearance | Other appearance | Verdict |", "|---|---|---|---|---|---|---|"]
    for appearance in ("light", "dark"):
        case = run_dir / "material.flip" / f"{appearance}-scroll" / "native"
        found = analyze.window(case)
        rows = observe(found[2].paths if found else [], FLIP)
        other = "dark" if appearance == "light" else "light"
        for name in FLIP:
            size = 200 if name == "large" else 44
            for backdrop in ("white", "black"):
                seen = over(rows, name, backdrop)
                same, flipped = expected[(appearance, backdrop, size)], expected[(other, backdrop, size)]
                shown = "—" if seen is None else f"{seen:.0f}"
                lines.append(f"| {appearance} | {name} | {backdrop} | {shown} | {same:.0f} | {flipped:.0f} | {verdict(seen, same, flipped)} |")
    return "\n".join(lines) + "\n"
