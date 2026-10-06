import numpy as np
from PIL import Image
B="/Users/omaraly/development/AI/Operator-2b1/packages/mobile/build/glass_lab/runs"; A="/Users/omaraly/development/AI/Operator-ios-liquid-glass/packages/mobile/build/glass_lab/runs"
def L(p): return np.asarray(Image.open(p).convert("RGB")).astype(np.float64)
def edge(profile, start):
    g = np.abs(np.diff(profile, axis=0)).sum(axis=1)
    pos = start + 1 + np.arange(len(g))
    return float((g * pos).sum() / g.sum())
FRAMES = {"2A": (A, "20261002-205855"), "pre-fix": (B, "20261006-013200"), "new": (B, "20261006-175336")}
BUTTONS = {"glass": dict(xl=401, xr=804, yt=1117, yb=1249, cx=603.0, cy=1183.5), "prominent": dict(xl=343, xr=862, yt=1456, yb=1588, cx=603.0, cy=1522.5)}
W = 4
for case in ("dark-stripes", "light-stripes"):
    for label, (root, run) in FRAMES.items():
        im = L(f"{root}/{run}/button.press/{case}/flutter/ready.png")
        for name, b in BUTTONS.items():
            cy = int(b["cy"]); hs = []
            lefts, rights = [], []
            for y in range(cy - 6, cy + 7):
                lefts.append(edge(im[y, b["xl"]-W:b["xl"]+W+1], b["xl"]-W)); rights.append(edge(im[y, b["xr"]-W:b["xr"]+W+1], b["xr"]-W))
            tops, bots = [], []
            for x in list(range(b["xl"] + 70, b["xl"] + 110)) + list(range(b["xr"] - 110, b["xr"] - 70)):
                tops.append(edge(im[b["yt"]-W:b["yt"]+W+1, x], b["yt"]-W)); bots.append(edge(im[b["yb"]-W:b["yb"]+W+1, x], b["yb"]-W))
            l, r, t, bo = map(np.mean, (lefts, rights, tops, bots))
            print(f"{case:13} {label:7} {name:9} L {l:8.3f} R {r:8.3f} centre x {(l+r)/2:8.3f} (layout {b['cx']})  width {r-l:7.3f} | T {t:8.3f} B {bo:8.3f} centre y {(t+bo)/2:8.3f} (layout {b['cy']}) height {bo-t:7.3f}")
