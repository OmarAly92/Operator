import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import align
import springfit


def stripes(width=120, height=60, period=40):
    image = np.zeros((height * 3, width * 3, 3), dtype=np.float32)
    colours = [(230, 70, 80), (240, 180, 90), (30, 200, 100)]
    for x in range(width * 3):
        image[:, x] = colours[(x // (period * 3)) % len(colours)]
    return image


def with_codec_lines(image, period=40, amplitude=90.0):
    noisy = image.copy()
    for x in range(period * 3, image.shape[1], period * 3):
        noisy[:, x - 1 : x + 1] += amplitude
    return np.clip(noisy, 0, 255)


def draw(image, box, value=(250, 250, 250)):
    x, y, w, h = (int(round(v * 3)) for v in box)
    out = image.copy()
    out[y : y + h, x : x + w] = value
    return out


def frames(paths, times):
    return align.Frames(paths, times)


def disks(gap, bridge=0, height=120, width=240):
    image = np.full((height * 3, width * 3, 3), 40, dtype=np.float32)
    yy, xx = np.mgrid[0 : height * 3, 0 : width * 3]
    for cx in (60, 140 + gap):
        image[(xx - cx * 3) ** 2 + (yy - 60 * 3) ** 2 <= (40 * 3) ** 2] = 250
    if bridge:
        image[(60 - bridge // 2) * 3 : (60 + bridge // 2) * 3, 95 * 3 : 105 * 3] = 250
    return image


def spring_series(response, damping, appearing=True, exponent=1.0, seconds=0.9):
    t = np.arange(0, seconds, 1 / align.GRID_HZ)
    s = springfit.step_response(t, response, damping)
    progress = s if appearing else (1 - np.clip(s, 0, 1)) ** exponent
    flat = np.zeros_like(t)
    return {"width": flat + 250, "height": flat + 88, "cx": flat + 201, "cy": flat + 451, "luma": flat + 100, "progress": progress, "sharpness": flat, "residual": flat}


def capture_of(*series, steps=None):
    return {"events": [{"onset": 1.0 + i, "series": {"block": s}, "step": None if steps is None else steps[i]} for i, s in enumerate(series)], "touches": []}


def pair_geometry(shape, gap, radius=40):
    height, width = shape[:2]
    yy, xx = np.mgrid[0:height, 0:width] + 0.5
    left = width / 2 - gap * 3 / 2 - radius * 3
    right = width / 2 + gap * 3 / 2 + radius * 3
    distance = np.minimum(np.hypot(xx - left, yy - height / 2), np.hypot(xx - right, yy - height / 2)) - radius * 3
    return distance, xx, yy, left, right


def glass_pair(bare, gap, bridge=0, gain=0.6, lift=0.0, rim=60.0):
    distance, xx, yy, left, right = pair_geometry(bare.shape, gap)
    inside = distance <= 0
    if bridge:
        inside |= (np.abs(yy - bare.shape[0] / 2) <= bridge * 3 / 2) & (xx >= left) & (xx <= right)
    frame = bare.copy()
    frame[inside] = np.clip(bare[inside] * gain + lift, 0, 255)
    edge = (distance <= 0) & (distance > -3)
    frame[edge] = np.clip(frame[edge] - rim, 0, 255)
    return frame


def chroma_ringing(image, period=40, amplitude=60.0):
    out = image.copy()
    for x in range(period * 3, image.shape[1], period * 3):
        out[:, x - 2 : x + 2, 0] -= amplitude
        out[:, x - 2 : x + 2, 1] += amplitude * 0.2126 / 0.7152
    return np.clip(out, 0, 255)


def grain(height=120, width=240, level=120.0, sigma=6.0, seed=7):
    rng = np.random.default_rng(seed)
    return np.clip(level + rng.normal(0.0, sigma, (height * 3, width * 3, 3)), 0, 255).astype(np.float32)


def blur3(image):
    padded = np.pad(image, ((1, 1), (1, 1), (0, 0)), mode="edge")
    height, width = image.shape[:2]
    return sum(padded[dy : dy + height, dx : dx + width] for dy in range(3) for dx in range(3)) / 9.0


def frosted_pair(bare, gap, lift=2.0, outline=0.0, reach=6, rim=0.0):
    distance = pair_geometry(bare.shape, gap)[0]
    inside = distance <= 0
    frame = bare.copy()
    if outline:
        band = (distance > 0) & (distance <= reach)
        frame[band] = np.clip(frame[band] - outline, 0, 255)
    frame[inside] = np.clip(blur3(blur3(bare))[inside] + lift, 0, 255)
    if rim:
        edge = inside & (distance > -3)
        frame[edge] = np.clip(frame[edge] - rim, 0, 255)
    return frame
