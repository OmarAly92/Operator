import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Isolate native's hold light at its one-frame cut and test how it adds to the glass: a constant per channel (clipped at 255), a share of the headroom 255 - c (screen), or an affine map of luma and chroma (vivid). Each model is fitted per take and then chosen by leave-one-take-out RMS: fitted on the other takes pooled, judged on the one left out.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--region", default="46,377,310,148")
ARGS.add_argument("takes", nargs="+")
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import metrics
import touch
import track

region = [float(v) for v in OPTIONS.region.split(",")]
LEVELS = np.arange(0.0, 40.0, 0.1)


def root_mean_square(values):
    return float(np.sqrt(np.mean(values ** 2)))


def additive_fit(cases):
    head = np.concatenate([c["head"] for c in cases])
    change = np.concatenate([c["change"] for c in cases])
    return float(min(LEVELS, key=lambda level: root_mean_square(np.minimum(level, head) - change)))


def additive_error(level, case):
    return root_mean_square(np.minimum(level, case["head"]) - case["change"])


def screen_fit(cases):
    head = np.concatenate([c["head"][c["head"] > 1] for c in cases])
    change = np.concatenate([c["change"][c["head"] > 1] for c in cases])
    return float((change * head).sum() / (head ** 2).sum())


def screen_error(alpha, case):
    keep = case["head"] > 1
    return root_mean_square(alpha * case["head"][keep] - case["change"][keep])


def vivid_fit(cases):
    design = np.concatenate([c["design"] for c in cases])
    change = np.concatenate([c["change"].ravel() for c in cases])
    coef, *_ = np.linalg.lstsq(design, change, rcond=None)
    return coef


def vivid_error(coef, case):
    return root_mean_square(case["design"] @ coef - case["change"].ravel())


MODELS = {"additive": (additive_fit, additive_error), "screen": (screen_fit, screen_error), "vivid": (vivid_fit, vivid_error)}
cases = []
for take in map(Path, OPTIONS.takes):
    px = track.pixel_rect(region)
    bare = track.crop_px(metrics.load(take / "bare" / "ready.png"), px)
    full = track.crop_px(metrics.load(take / "ready.png"), px)
    left, top, right, bottom = track.box_pixels(full, bare, track.edges(bare))
    frames = track.extract(take / "video.mp4", px, take / "blend")
    down, up = touch.read(take / "video.mp4", take / "marker")[0]
    inner = (slice(top + 30, bottom - 30), slice(left + 60, right - 60))
    after = [i for i, t in enumerate(frames.times) if up < t < up + 1.0]
    lumas = [float(metrics.luma(frames[i][inner]).mean()) for i in after]
    falls = [lumas[k - 1] - lumas[k] for k in range(1, len(lumas))]
    k = int(np.argmax(falls)) + 1
    before, cut = frames[after[k - 1]][inner], frames[after[k]][inner]
    base, change = cut.reshape(-1, 3), (before - cut).reshape(-1, 3)
    head = 255.0 - base
    keep = head > 1
    alpha = float((change[keep] * head[keep]).sum() / (head[keep] ** 2).sum())
    screen = float(np.sqrt(np.mean((alpha * head[keep] - change[keep]) ** 2)))
    best = None
    for level in np.arange(0.0, 40.0, 0.1):
        rms = float(np.sqrt(np.mean((np.minimum(level, head) - change) ** 2)))
        if best is None or rms < best[1]:
            best = (float(level), rms)
    luma = metrics.luma(cut).reshape(-1, 1)
    chroma = base - luma
    design = np.stack([np.ones(change.size), (np.repeat(luma, 3, axis=1)).ravel() / 255.0, chroma.ravel() / 255.0], axis=1)
    coef, *_ = np.linalg.lstsq(design, change.ravel(), rcond=None)
    vivid = float(np.sqrt(np.mean((design @ coef - change.ravel()) ** 2)))
    found = {
        "take": str(take),
        "cut_after_up_ms": round((frames.times[after[k]] - up) * 1000, 1),
        "base_luma": round(float(metrics.luma(cut).mean()), 2),
        "luma_drop": round(falls[k - 1], 2),
        "screen_alpha": round(alpha, 4),
        "screen_rms": round(screen, 3),
        "additive_level": round(best[0], 2),
        "additive_rms": round(best[1], 3),
        "vivid_coef": [round(float(v), 3) for v in coef],
        "vivid_rms": round(vivid, 3),
        "change_by_channel": [round(float(v), 2) for v in change.mean(axis=0)],
        "headroom_by_channel": [round(float(v), 2) for v in head.mean(axis=0)],
    }
    print(json.dumps(found), flush=True)
    cases.append({"take": take.parent.name, "head": head, "change": change, "design": design})
held_out = {}
for name, (fit, error) in MODELS.items():
    held_out[name] = {case["take"]: round(error(fit([c for c in cases if c is not case]), case), 3) for case in cases}
    held_out[name]["mean"] = round(float(np.mean([held_out[name][c["take"]] for c in cases])), 3)
print(json.dumps({"leave_one_take_out_rms": held_out, "chosen": min(held_out, key=lambda name: held_out[name]["mean"])}), flush=True)
