import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

S = 3
PAD = 30
MARK = (16, 874 - 34 - 160 - 18, 18, 18)
THRESH = 12.0
REST_THRESH = 20.0
PTS = re.compile(r"pts_time:([0-9.]+)")


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)


def luma(a):
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def smooth(a):
    k = np.ones(3) / 3
    a = np.apply_along_axis(lambda r: np.convolve(r, k, mode="same"), 1, a)
    return np.apply_along_axis(lambda c: np.convolve(c, k, mode="same"), 0, a)


def box_of(frame, bare, min_count=None, threshold=None):
    diff = smooth(np.abs(frame - bare).max(axis=2)) > (THRESH if threshold is None else threshold)
    col_min = 0.15 * diff.shape[0] if min_count is None else min_count
    row_min = 0.15 * diff.shape[1] if min_count is None else min_count
    cols = np.nonzero(diff.sum(axis=0) >= col_min)[0]
    rows = np.nonzero(diff.sum(axis=1) >= row_min)[0]
    if len(cols) == 0 or len(rows) == 0:
        return None
    return int(cols[0]), int(rows[0]), int(cols[-1] - cols[0] + 1), int(rows[-1] - rows[0] + 1)


def rest_box(ready, bare):
    top, bottom = 72 * S, (874 - 34 - 160 - 30) * S
    sub_r, sub_b = ready[top:bottom], bare[top:bottom]
    b = box_of(sub_r, sub_b, min_count=6, threshold=REST_THRESH)
    return b[0], b[1] + top, b[2], b[3]


def extract(video, rect_px, dest):
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    x, y, w, h = rect_px
    p = subprocess.run(
        ["ffmpeg", "-loglevel", "info", "-y", "-i", str(video), "-fps_mode", "passthrough",
         "-vf", f"crop={w}:{h}:{x}:{y},showinfo", str(dest / "%06d.png")],
        capture_output=True, text=True, check=True,
    )
    times = [float(t) for t in PTS.findall(p.stderr)]
    paths = sorted(dest.glob("*.png"))
    n = min(len(paths), len(times))
    return paths[:n], times[:n]


def marker_states(video, dest):
    x, y, w, h = (v * S for v in MARK)
    paths, times = extract(video, (x + 6, y + 6, w - 12, h - 12), dest)
    states = []
    for p in paths:
        c = load(p).reshape(-1, 3).mean(axis=0)
        r, g, b = c
        if r - max(g, b) > 80:
            s = "down"
        elif g - max(r, b) > 80:
            s = "move"
        elif b - max(r, g) > 80:
            s = "up"
        elif max(r, g, b) < 60:
            s = "idle"
        else:
            s = "?"
        states.append(s)
    shutil.rmtree(dest)
    return times, states


def touch_windows(times, states):
    windows, start = [], None
    for t, s in zip(times, states):
        if s in ("down", "move") and start is None:
            start = t
        if s == "up" and start is not None:
            windows.append((start, t))
            start = None
    return windows


def analyze(case, out=None, label=None):
    case = Path(case)
    native = case / "native" if (case / "native").exists() else case
    ready = load(native / "ready.png")
    bare = load(native / "bare" / "ready.png")
    rb = rest_box(ready, bare)
    px = (max(0, rb[0] - PAD * S), max(0, rb[1] - PAD * S))
    px = (px[0] // 2 * 2, px[1] // 2 * 2)
    rect = (px[0], px[1], min(ready.shape[1] - px[0], rb[2] + 2 * PAD * S) // 2 * 2, (rb[3] + 2 * PAD * S) // 2 * 2)
    work = native / "probe_frames"
    paths, times = extract(native / "video.mp4", rect, work)
    mtimes, mstates = marker_states(native / "video.mp4", native / "probe_marker")
    windows = touch_windows(mtimes, mstates)
    x, y, w, h = rect
    ex, ey = rb[0] - x, rb[1] - y
    frames = [load(p) for p in paths]
    first_down = windows[0][0] if windows else None
    rest_index = max((i for i, t in enumerate(times) if first_down is None or t < first_down), default=0)
    rest = frames[rest_index]
    rows = []
    for t, f in zip(times, frames):
        c = box_of(f, rest, min_count=3)
        if c:
            grow_x = max(0, ex - c[0]) + max(0, c[0] + c[2] - (ex + rb[2]))
            grow_y = max(0, ey - c[1]) + max(0, c[1] + c[3] - (ey + rb[3]))
        else:
            grow_x = grow_y = 0
        el = f[ey:ey + rb[3], ex:ex + rb[2]]
        rel = rest[ey:ey + rb[3], ex:ex + rb[2]]
        rows.append({
            "t": t,
            "w": (rb[2] + grow_x) / S,
            "h": (rb[3] + grow_y) / S,
            "change_box_pt": [round(v / S, 2) for v in c] if c else None,
            "luma": float(luma(el).mean()),
            "mad": float(np.abs(el - rel).mean()),
            "mad_region": float(np.abs(f - rest).mean()),
        })
    r0 = rows[rest_index]
    for r in rows:
        r["dw"] = r["w"] - r0["w"]
        r["dh"] = r["h"] - r0["h"]
        r["dl"] = r["luma"] - r0["luma"]
    presses = []
    for wi, (down, up) in enumerate(windows):
        nxt = windows[wi + 1][0] if wi + 1 < len(windows) else up + 2.0
        inside = [i for i, r in enumerate(rows) if down <= r["t"] < up + 0.05]
        after = [i for i, r in enumerate(rows) if up <= r["t"] < nxt]
        def peak(key, idx):
            if not idx:
                return 0.0, None
            j = max(idx, key=lambda i: abs(rows[i][key]))
            return rows[j][key], j
        def sustained(idx):
            hit = [abs(rows[i]["dw"]) >= 1 or abs(rows[i]["dh"]) >= 1 or abs(rows[i]["dl"]) >= 2 or rows[i]["mad"] >= 2 for i in idx]
            return any(a and b for a, b in zip(hit, hit[1:]))
        pw, jw = peak("dw", inside)
        ph, _ = peak("dh", inside)
        pl, _ = peak("dl", inside)
        pm, jm = peak("mad", inside)
        reacted = sustained(inside)
        timing = {}
        if reacted:
            for key, pv in (("dw", pw), ("dluma", pl), ("mad", pm)):
                col = "dl" if key == "dluma" else key
                if abs(pv) < (1 if key == "dw" else 2):
                    continue
                t90 = next((rows[i]["t"] for i in inside if abs(rows[i][col]) >= 0.9 * abs(pv)), None)
                settle = None
                limit = 0.1 * abs(pv)
                for n, i in enumerate(after):
                    if all(abs(rows[k][col]) <= limit for k in after[n:]):
                        settle = rows[i]["t"]
                        break
                timing[key] = {
                    "down_to_90_ms": round((t90 - down) * 1000) if t90 is not None else None,
                    "release_to_settle10_ms": round((settle - up) * 1000) if settle is not None else None,
                }
        frames_in = len(inside)
        presses.append({
            "down": round(down, 4), "up": round(up, 4), "held_ms": round((up - down) * 1000),
            "frames_during_press": frames_in, "reacted": reacted,
            "peak_dw": round(pw, 2), "peak_dh": round(ph, 2), "peak_dluma": round(pl, 2), "peak_mad": round(pm, 2),
            "timing": timing, "peak_index": jm,
        })
    summary = {
        "case": str(case), "rest_box_pt": [round(v / S, 2) for v in rb], "pinned_pt": [round(v / S, 2) for v in rect],
        "frames": len(rows), "touch_windows": [(round(a, 3), round(b, 3)) for a, b in windows],
        "rest_index": rest_index, "rest_w": r0["w"], "rest_h": r0["h"], "presses": presses,
        "marker_states": sorted(set(mstates)),
    }
    if out:
        out = Path(out)
        out.mkdir(parents=True, exist_ok=True)
        Image.fromarray(rest.astype(np.uint8)).save(out / f"{label}-rest.png")
        for k, pr in enumerate(presses):
            if pr["reacted"] and pr["peak_index"] is not None:
                Image.fromarray(frames[pr["peak_index"]].astype(np.uint8)).save(out / f"{label}-peak{k}.png")
        (out / f"{label}-series.json").write_text(json.dumps(rows))
    shutil.rmtree(work)
    return summary


if __name__ == "__main__":
    out = sys.argv[2] if len(sys.argv) > 2 else None
    label = sys.argv[3] if len(sys.argv) > 3 else "case"
    print(json.dumps(analyze(sys.argv[1], out, label), indent=1))
