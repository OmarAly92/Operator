import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, "tool/glass_lab/harness")

import analyze
import manifest
import metrics
import shapes
import track

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
SCRATCH = sys.argv[2]
R = Path("build/glass_lab/runs")
SCENES = {s.id: s for s in manifest.load()}
FONT = ImageFont.load_default()


def load(run, scene, case):
    data = {}
    for app in ("native", "flutter"):
        source = R / run / scene / case / app
        with tempfile.TemporaryDirectory(dir=SCRATCH) as tmp:
            folder = Path(tmp) / app
            folder.mkdir()
            for name in ("video.mp4", "ready.png", "settled.png", "bare", "timing.json"):
                if (source / name).exists():
                    (folder / name).symlink_to((source / name).resolve())
            window = analyze.window(folder)
            capture = shapes.capture(SCENES[scene], folder, window[:2] if window else None)
            frames = track.extract(folder / "video.mp4", track.pixel_rect(metrics.union(list(shapes.regions(SCENES[scene]).values()))), folder / "shapes")
            onsets = [e["onset"] for e in capture["events"]]
            images = {round(t, 4): Image.open(p).convert("RGB").copy() for t, p in zip(frames.times, frames.paths) if any(o - 0.05 <= t <= o + 0.85 for o in onsets)}
        rows = capture["rows"]["block"]
        data[app] = {
            "times": rows["times"],
            "progress": [r["progress"] for r in rows["rows"]],
            "images": images,
            "events": {e["step"]: e["onset"] for e in capture["events"]},
        }
    return data


def pick(d, step, target=None, after=None, span=0.8):
    onset = d["events"][step]
    best = None
    for t, p in zip(d["times"], d["progress"]):
        if not (onset - 0.02 <= t <= onset + span) or not np.isfinite(p):
            continue
        key = abs(p - target) if target is not None else abs((t - onset) - after)
        if best is None or key < best[0]:
            best = (key, t, p)
    _, t, p = best
    return d["images"][round(t, 4)], t - onset, p


def tile(img, text, scale):
    img = img.resize((img.width // scale, img.height // scale), Image.LANCZOS) if scale > 1 else img
    canvas = Image.new("RGB", (img.width, img.height + 18), (255, 255, 255))
    canvas.paste(img, (0, 18))
    ImageDraw.Draw(canvas).text((4, 3), text, fill=(0, 0, 0), font=FONT)
    return canvas


def sheet(rows, path, title):
    width = max(sum(t.width for t in r) for r in rows)
    height = sum(max(t.height for t in r) for r in rows) + 20
    out = Image.new("RGB", (width, height), (255, 255, 255))
    ImageDraw.Draw(out).text((4, 4), title, fill=(0, 0, 0), font=FONT)
    y = 20
    for r in rows:
        x = 0
        for t in r:
            out.paste(t, (x, y))
            x += t.width
        y += max(t.height for t in r)
    out.save(path, optimize=True)
    print(path, out.size)


run = "20261006-204707"
dark = load(run, "material.materialize", "dark-photo")
light = load(run, "material.materialize", "light-photo")
rows = []
for name, data in (("dark-photo", dark), ("light-photo", light)):
    row = []
    for app in ("native", "flutter"):
        img, dt, p = pick(data[app], 1, target=0.5)
        row.append(tile(img, f"{name} disappear {app}: progress {p:.2f} at +{dt * 1000:.0f} ms", 1))
    rows.append(row)
sheet(rows, OUT / "fix3-h1-half-progress-sharpness.png", f"H1/H2: native | Flutter at half progress, default disappear, k = 1, run {run}")

stripes = load(run, "material.materialize", "light-stripes")
rows = []
for after in (0.05, 0.1, 0.15):
    row = []
    for app in ("native", "flutter"):
        img, dt, p = pick(stripes[app], 3, after=after)
        row.append(tile(img, f"light-stripes appear {app}: +{dt * 1000:.0f} ms, progress {p:.2f}", 2))
    rows.append(row)
sheet(rows, OUT / "fix3-h4-light-stripes-appear.png", f"H4: native | Flutter at equal times after onset, default light-stripes appear, k = 1, run {run}")
