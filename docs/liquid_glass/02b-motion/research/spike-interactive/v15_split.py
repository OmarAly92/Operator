import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import probe_analyze as pa


def run(case):
    native = Path(case) / "native"
    ready = pa.load(native / "ready.png")
    bare = pa.load(native / "bare" / "ready.png")
    S = pa.S
    shapes = {"A_pressed": (76, 407, 120, 88), "B_neighbour": (206, 407, 120, 88)}
    pad = 20
    x0, y0 = (76 - pad) * S, (407 - pad) * S
    w, h = (250 + 2 * pad) * S, (88 + 2 * pad) * S
    paths, times = pa.extract(native / "video.mp4", (x0, y0, w, h), native / "v15_frames")
    mt, ms = pa.marker_states(native / "video.mp4", native / "v15_marker")
    windows = pa.touch_windows(mt, ms)
    frames = [pa.load(p) for p in paths]
    rest_i = max(i for i, t in enumerate(times) if t < windows[0][0])
    rest = frames[rest_i]
    out = {}
    for name, (sx, sy, sw, sh) in shapes.items():
        ax, ay = (sx - 76 + pad) * S, (sy - 407 + pad) * S
        series = []
        for t, f in zip(times, frames):
            el = f[ay:ay + sh * S, ax:ax + sw * S]
            rel = rest[ay:ay + sh * S, ax:ax + sw * S]
            series.append((t, float(np.abs(el - rel).mean()), float(pa.luma(el).mean() - pa.luma(rel).mean())))
        presses = []
        for down, up in windows:
            inside = [s for s in series if down <= s[0] <= up]
            presses.append({"peak_mad": round(max(s[1] for s in inside), 2), "peak_dluma": round(max((s[2] for s in inside), key=abs), 2)})
        out[name] = presses
    import shutil
    shutil.rmtree(native / "v15_frames")
    return out


if __name__ == "__main__":
    print(json.dumps(run(sys.argv[1]), indent=1))
