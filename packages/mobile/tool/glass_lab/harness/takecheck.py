import json
import math
import re
import shutil
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image

import metrics
import touch
import track

HOLE_GAP = 0.0045
LOST_GAP = 0.030
ONSET = 0.090
HOLD_GAP = 0.060
TAIL = 1.2
CHANGE = 0.2
PTS = re.compile(r"pts_time:([0-9.]+)")
TOLERANCE = 0.2
RESULT = "takecheck.json"
PRESS_KINDS = ("press", "pressDrag")


def judged(scene):
    return any(next(iter(step)) in PRESS_KINDS for step in scene.steps)


def scripted(step):
    kind, value = next(iter(step.items()))
    if kind == "press":
        return float(value["duration"])
    if kind == "pressDrag":
        target = value["to"] if isinstance(value["to"], dict) else {}
        distance = math.hypot(target.get("dx", 0.0), target.get("dy", 0.0))
        velocity = value.get("velocity")
        travel = distance / velocity if velocity else 0.0
        return float(value.get("pressDuration", 0.0)) + travel + float(value.get("hold", 0.0))
    return None


def span_holes(times, changing, windows, everywhere=False, tail=TAIL):
    found = []
    for k, (down, up) in enumerate(windows):
        end = windows[k + 1][0] if k + 1 < len(windows) else up + tail
        inside = [i for i, t in enumerate(times) if down <= t < end]
        gaps = [(inside[j], inside[j + 1], times[inside[j + 1]] - times[inside[j]]) for j in range(len(inside) - 1)]
        if gaps and gaps[0][2] < HOLE_GAP:
            found.append(("squeezed first frame", times[gaps[0][1]]))
        for (a, b, first), (_, c, second) in zip(gaps, gaps[1:]):
            if first < HOLE_GAP and second < HOLE_GAP:
                found.append(("burst", times[b]))
                break
        for (a, b, gap), (_, after, _) in zip(gaps, gaps[1:]):
            held = down + ONSET <= times[a] < up
            if round(gap, 4) > LOST_GAP and changing[a] and changing[after] and (everywhere or not held or round(gap, 4) > HOLD_GAP):
                found.append((f"{gap * 1000:.1f} ms lost while the glass moved", times[b]))
                break
    return found


def changes(values):
    values = [np.asarray(v, dtype=np.float32) for v in values]
    return [False] + [bool(np.abs(b - a).mean() > CHANGE) for a, b in zip(values, values[1:])]


def region_frames(video, rect, dest):
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    for old in dest.glob("*.png"):
        old.unlink()
    x, y, w, h = rect
    process = subprocess.run(
        ["ffmpeg", "-loglevel", "info", "-y", "-i", str(video), "-fps_mode", "passthrough", "-vf", f"crop={w}:{h}:{x}:{y},scale={w // metrics.SCALE}:{h // metrics.SCALE},format=gray,showinfo", str(dest / "%06d.png")],
        capture_output=True,
        text=True,
        check=True,
    )
    times = [float(t) for t in PTS.findall(process.stderr)]
    paths = sorted(dest.glob("*.png"))
    count = min(len(paths), len(times))
    return times[:count], [np.asarray(Image.open(path), dtype=np.float32) for path in paths[:count]]


def app_of(take):
    return "flutter" if Path(take).name.startswith("flutter") else "native"


def failures(steps, windows, times, changing=None, app="native"):
    found = []
    expected = touch.expected_touches(steps)
    if len(windows) != expected:
        found.append(f"touches {len(windows)} against {expected}")
    groups = touch.step_windows(steps, windows)
    for index, group in sorted(groups.items()):
        duration = scripted(steps[index])
        if duration is None:
            continue
        actual = group[-1][1] - group[0][0]
        if abs(actual - duration) > TOLERANCE * duration:
            found.append(f"step {index} touch {actual:.3f} s against {duration:.3f} s")
    if changing is None:
        changing = [True] * len(times)
    found += [f"capture hole ({kind}) at {at:.3f} s" for kind, at in span_holes(times, changing, windows, app == "flutter")]
    return found


def check(scene, take, cache=None):
    take = Path(take)
    root = Path(cache) if cache else take
    frames = track.extract(take / "video.mp4", touch.marker_rect(), root / "marker")
    windows = touch.touches(touch.phases(frames))
    rect = track.pixel_rect(metrics.union([tuple(scene.regions[name]) for name in scene.track]))
    times, pictures = region_frames(take / "video.mp4", rect, root / "takecheck")
    found = failures(scene.steps, windows, times, changes(pictures), app_of(take))
    result = {"scene": scene.id, "touches": [[round(a, 3), round(b, 3)] for a, b in windows], "failures": found}
    if cache is None:
        (take / RESULT).write_text(json.dumps(result, indent=1))
    return result


def read(take):
    path = Path(take) / RESULT
    return json.loads(path.read_text()) if path.exists() else None


def exclude(take, run_dir, result):
    take = Path(take)
    target = Path(run_dir) / "excluded" / take.relative_to(run_dir)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(take), str(target))
    (target / "reason.txt").write_text("\n".join(result["failures"]) + "\n")
    return target
