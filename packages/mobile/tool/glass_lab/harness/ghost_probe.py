import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, "tool/glass_lab/harness")

import build
import metrics
import record
import shapes
import sim
import touch
import track

STEPS = [{"wait": 0.5}, {"tap": "toggle"}, {"wait": 1.2}]
REGION = (60, 390, 282, 122)


def main(scene="tool.ghost"):
    build.require_fresh("example")
    udid = sim.device()
    sim.appearance(udid, "dark")
    out = build.OUT / "ghost" / time.strftime("%Y%m%d-%H%M%S")
    with record.Recording(udid, out / "video.mp4"):
        record.drive(udid, build.EXAMPLE_BUNDLE, scene, STEPS, "photo", False, out, marker=True)
    rect = track.pixel_rect(REGION)
    frames = track.extract(out / "video.mp4", rect, out / "frames")
    windows = touch.read(out / "video.mp4", out / "marker")
    release = windows[0][1]
    chosen = [i for i, t in enumerate(frames.times) if release - 0.05 <= t <= release + 0.35]
    ready = shapes.shrink(track.crop_px(metrics.load(out / "ready.png"), rect))
    print(f"touch {windows[0]}, {len(chosen)} frames from release - 50 ms to + 350 ms")
    tiles = []
    for i in chosen:
        frame = metrics.load(frames.paths[i])
        print(f"{frames.times[i] - release:+.3f} s  mean difference from ready {metrics.mad(shapes.shrink(frame), ready):6.2f}")
        tiles.append(frame[::2, ::2])
    sheet = np.concatenate(tiles[:10], axis=0)
    Image.fromarray(sheet.astype(np.uint8)).save(out / "removal.png")
    print(out / "removal.png")


if __name__ == "__main__":
    main(*sys.argv[1:])
