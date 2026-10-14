import argparse
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Where each app leaves gaps over 30 ms between recorded frames: per take, the first such gap after every touch-down and touch-up, and every gap over 30 ms with the glass moving on both sides, by phase. Frame caches go to a scratch folder, so archived takes are only read.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--cache", required=True)
ARGS.add_argument("takes", nargs="+", help="scene=take")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import manifest
import metrics
import takecheck
import touch
import track

LONG = takecheck.LOST_GAP
scenes = {s.id: s for s in manifest.load()}


def first_long(times, start):
    later = [t for t in times if t >= start]
    for a, b in zip(later, later[1:]):
        if b - a > LONG:
            return round((a - start) * 1000, 1), round((b - a) * 1000, 1)
    return None


summary = {}
for index, item in enumerate(OPTIONS.takes):
    scene_id, take = item.split("=", 1)
    take = Path(take)
    scene = scenes[scene_id]
    root = Path(OPTIONS.cache) / str(index)
    frames = track.extract(take / "video.mp4", touch.marker_rect(), root / "marker")
    windows = touch.touches(touch.phases(frames))
    rect = track.pixel_rect(metrics.union([tuple(scene.regions[name]) for name in scene.track]))
    times, pictures = takecheck.region_frames(take / "video.mp4", rect, root / "takecheck")
    changing = takecheck.changes(pictures)
    app = takecheck.app_of(take)
    moving = []
    for k, (down, up) in enumerate(windows):
        end = windows[k + 1][0] if k + 1 < len(windows) else up + takecheck.TAIL
        inside = [i for i, t in enumerate(times) if down <= t < end]
        for a, b, after in zip(inside, inside[1:], inside[2:]):
            gap = times[b] - times[a]
            if gap > LONG and changing[a] and changing[after]:
                moving.append((round(gap * 1000, 1), round((times[a] - down) * 1000), round((times[a] - up) * 1000)))
    downs = [first_long(times, down) for down, _ in windows]
    ups = [first_long(times, up) for _, up in windows]
    print(app, "/".join(take.parts[-4:]), "first gap over 30 ms after touch-down (ms after, gap)", downs, "after touch-up", ups, "moving gaps (gap, after down, after up)", moving, flush=True)
    entry = summary.setdefault(app, {"takes": 0, "down": [], "up": [], "moving": []})
    entry["takes"] += 1
    entry["down"] += [d[0] for d in downs if d]
    entry["up"] += [u[0] for u in ups if u]
    entry["moving"] += moving
for app, entry in sorted(summary.items()):
    gaps = np.array([g for g, _, _ in entry["moving"]]) if entry["moving"] else np.array([])
    print(f"{app}: {entry['takes']} takes; first gap over 30 ms at least {min(entry['down'], default=float('nan'))} ms after a touch-down and {min(entry['up'], default=float('nan'))} ms after a touch-up; {len(gaps)} gaps over 30 ms with the glass moving on both sides, {int((gaps < 60).sum()) if gaps.size else 0} of them under 60 ms")
