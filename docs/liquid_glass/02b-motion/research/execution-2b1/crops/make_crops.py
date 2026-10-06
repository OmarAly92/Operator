import json, shutil, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, "tool/glass_lab/harness")
import analyze, manifest, metrics, shapes, track

S = Path(sys.argv[1]); OUT = Path(sys.argv[2]); OUT.mkdir(parents=True, exist_ok=True)
R = Path("build/glass_lab/runs")
scenes = {s.id: s for s in manifest.load()}

def load(run, scene, case):
    data = {}
    for app in ("native", "flutter"):
        dst = S / run / scene / case / app
        if not dst.exists():
            shutil.copytree(R / run / scene / case / app, dst)
        window = analyze.window(dst)
        cap = shapes.capture(scenes[scene], dst, window[:2] if window else None)
        paths = sorted((dst / "shapes").glob("*.png"))
        frames = track.extract(dst / "video.mp4", track.pixel_rect(metrics.union(list(shapes.regions(scenes[scene]).values()))), dst / "shapes")
        index = {round(t, 4): p for t, p in zip(frames.times, frames.paths)}
        rows = cap["rows"]["block"]
        events = {e["step"]: e["onset"] for e in cap["events"]}
        data[app] = {"times": rows["times"], "progress": [r["progress"] for r in rows["rows"]], "index": index, "events": events}
    return data

def pick(d, step, target=None, after=None, span=0.7):
    onset = d["events"][step]
    best = None
    for t, p in zip(d["times"], d["progress"]):
        if not (onset - 0.02 <= t <= onset + span) or not np.isfinite(p):
            continue
        key = abs(p - target) if target is not None else abs((t - onset) - after)
        if best is None or key < best[0]:
            best = (key, t, p)
    _, t, p = best
    return Image.open(d["index"][round(t, 4)]).convert("RGB"), t - onset, p

FONT = ImageFont.load_default()
def tile(img, text, scale):
    img = img.resize((img.width // scale, img.height // scale), Image.LANCZOS) if scale > 1 else img
    canvas = Image.new("RGB", (img.width, img.height + 18), (255, 255, 255))
    canvas.paste(img, (0, 18))
    ImageDraw.Draw(canvas).text((4, 3), text, fill=(0, 0, 0), font=FONT)
    return canvas

def sheet(rows, path, title):
    width = max(sum(t.width for t in r) for r in rows); height = sum(max(t.height for t in r) for r in rows) + 20
    out = Image.new("RGB", (width, height), (255, 255, 255))
    ImageDraw.Draw(out).text((4, 4), title, fill=(0, 0, 0), font=FONT)
    y = 20
    for r in rows:
        x = 0
        for t in r:
            out.paste(t, (x, y)); x += t.width
        y += max(t.height for t in r)
    out.save(path, optimize=True)
    print(path, out.size, path.stat().st_size)

run = "20261005-233131"
d = load(run, "material.materialize", "dark-photo")
l = load(run, "material.materialize", "light-photo")
rows = []
for name, data in (("dark-photo", d), ("light-photo", l)):
    row = []
    for app in ("native", "flutter"):
        img, dt, p = pick(data[app], 1, target=0.5)
        row.append(tile(img, f"{name} disappear {app}: progress {p:.2f} at +{dt*1000:.0f} ms", 1))
    rows.append(row)
sheet(rows, OUT / "b1-half-progress-sharpness.png", f"b1: native | Flutter at half progress, default disappear, run {run}")

rows = []
for after in (0.033, 0.067, 0.1):
    row = []
    for app in ("native", "flutter"):
        img, dt, p = pick(d[app], 1, after=after)
        row.append(tile(img, f"dark-photo disappear {app}: +{dt*1000:.0f} ms, progress {p:.2f}", 2))
    rows.append(row)
sheet(rows, OUT / "b2-dark-photo-disappear.png", f"b2: native | Flutter at equal times after onset, default dark-photo disappear, run {run}")

ls = load("20261006-001644", "material.materialize", "light-stripes")
rows = []
for after in (0.1, 0.2, 0.3):
    row = []
    for app in ("native", "flutter"):
        img, dt, p = pick(ls[app], 3, after=after, span=0.8)
        row.append(tile(img, f"light-stripes appear {app}: +{dt*1000:.0f} ms, progress {p:.2f}", 2))
    rows.append(row)
sheet(rows, OUT / "b3-light-stripes-appear.png", "b3: native | Flutter at equal times after onset, default light-stripes appear, run 20261006-001644")
