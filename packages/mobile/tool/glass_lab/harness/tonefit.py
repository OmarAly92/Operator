from pathlib import Path

import numpy as np

import metrics

BACKDROPS = ("black", "photo", "stripes", "text", "white")


def interior(box):
    x, y, w, h = box
    return (x + h * 0.5, y + h * 0.3, w - h, h * 0.4)


def point(native, bare, box):
    region = interior(box)
    return float(metrics.luma(metrics.crop(bare, region)).mean() / 255), float(metrics.luma(metrics.crop(native, region)).mean() / 255)


def fit(points):
    xs = np.array([p[0] for p in points])
    ys = np.array([p[1] for p in points])
    basis = np.stack([(1 - xs) * (1 - 2 * xs), 4 * xs * (1 - xs), xs * (2 * xs - 1)], axis=1)
    solution, *_ = np.linalg.lstsq(basis, ys, rcond=None)
    worst = float(np.abs(basis @ solution - ys).max() * 255)
    black, mid, white = (round(float(v), 4) for v in solution)
    return {"toneBlack": black, "toneMid": mid, "toneWhite": white, "max_error_luma": round(worst, 2)}


def case_name(appearance, backdrop, a11y):
    return f"{appearance}-{backdrop}" + ("" if a11y == "none" else f"-{a11y}")


def run_fit(run_dir, scene, a11y="none"):
    fits = {}
    for appearance in scene.appearances:
        for name, box in scene.regions.items():
            if name in scene.track:
                continue
            points = []
            for backdrop in BACKDROPS:
                native = Path(run_dir) / scene.id / case_name(appearance, backdrop, a11y) / "native"
                if (native / "ready.png").exists():
                    points.append(point(metrics.load(native / "ready.png"), metrics.load(native / "bare" / "ready.png"), box))
            if len(points) >= 3:
                fits[f"{appearance}.{name}"] = fit(points)
    return fits
