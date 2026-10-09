import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

H = Path("/Users/omaraly/development/AI/Operator-2b2/packages/mobile/tool/glass_lab/harness")
sys.path.insert(0, str(H))
import touch
import track


def pts(video):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time", "-of", "csv=p=0", str(video)], capture_output=True, text=True, check=True).stdout
    return [float(x.strip().rstrip(",")) for x in out.split() if x.strip()]


def main(take, scratch):
    take = Path(take)
    dest = Path(scratch)
    dest.mkdir(parents=True, exist_ok=True)
    windows = touch.touches(touch.phases(track.extract(take / "video.mp4", touch.marker_rect(), dest)))
    times = pts(take / "video.mp4")
    paths = sorted((take / "shapes").glob("*.png"))
    print(f"touch windows {[(round(a, 3), round(b, 3)) for a, b in windows]}; shapes frames {len(paths)}; video frames {len(times)}")
    prev = None
    rows = []
    for i, p in enumerate(paths):
        a = np.asarray(Image.open(p).convert("L"), dtype=np.float32)[::3, ::3]
        d = 0.0 if prev is None else float(np.abs(a - prev).mean())
        prev = a
        rows.append((i, d))
    return windows, times, rows


if __name__ == "__main__":
    windows, times, rows = main(sys.argv[1], sys.argv[2])
    off = len(times) - len(rows)
    print("note: shapes frames are all video frames when counts match; offset", off)
    for i, d in rows:
        t = times[i] if off == 0 else float("nan")
        if d > 0.5:
            print(f"  frame {i} t {t:.3f} diff {d:.2f}")
