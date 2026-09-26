from collections import deque

import numpy as np
from PIL import Image

SCALE = 3
SCREEN = (402, 874)
THRESHOLDS = {
    "mad": 4.0,
    "luminance": 3.0,
    "rim_rms": 6.0,
    "bbox_pt": 1.0,
    "centre_pt": 1.0,
    "time_ms": 17.0,
    "overshoot_pct": 2.0,
    "response_pct": 5.0,
    "damping": 0.05,
}


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)


def luma(image):
    return image[..., 0] * 0.2126 + image[..., 1] * 0.7152 + image[..., 2] * 0.0722


def crop(image, rect):
    x, y, w, h = (int(round(v * SCALE)) for v in rect)
    return image[y : y + h, x : x + w]


def mad(a, b):
    return float(np.mean(np.abs(a - b)))


def _components(mask):
    height, width = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    found = []
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        seen[y, x] = True
        queue = deque([(y, x)])
        top, left, bottom, right, area = y, x, y, x, 0
        while queue:
            cy, cx = queue.popleft()
            area += 1
            top, bottom, left, right = min(top, cy), max(bottom, cy), min(left, cx), max(right, cx)
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        found.append((area, (int(left), int(top), int(right - left + 1), int(bottom - top + 1))))
    found.sort(key=lambda item: -item[0])
    return found


def glass_boxes(frame, bare, threshold=6.0, min_area=40, scale=SCALE):
    difference = np.abs(frame - bare).max(axis=2)
    height, width = difference.shape
    grid = difference[: height // scale * scale, : width // scale * scale]
    grid = grid.reshape(height // scale, scale, width // scale, scale).mean(axis=(1, 3))
    return [box for area, box in _components(grid > threshold) if area >= min_area]


def union(boxes, pad=0, bounds=SCREEN):
    if not boxes:
        return None
    left = max(0, min(b[0] for b in boxes) - pad)
    top = max(0, min(b[1] for b in boxes) - pad)
    right = min(bounds[0], max(b[0] + b[2] for b in boxes) + pad)
    bottom = min(bounds[1], max(b[1] + b[3] for b in boxes) + pad)
    return (left, top, right - left, bottom - top)


def rim_profile(frame, box, reach=12):
    x, y, w, h = box
    column = int(round((x + w / 2) * SCALE))
    lum = luma(frame)[:, column]
    limit = lum.shape[0]
    top = int(round(y * SCALE))
    bottom = int(round((y + h) * SCALE))
    span = reach * SCALE
    pieces = [lum[max(0, top - span) : min(limit, top + span)], lum[max(0, bottom - span) : min(limit, bottom + span)]]
    return np.concatenate(pieces)


def box_delta(a, b):
    if a is None or b is None:
        return float("inf")
    return float(max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[0] + a[2] - b[0] - b[2]), abs(a[1] + a[3] - b[1] - b[3])))


def centre_delta(a, b):
    if a is None or b is None:
        return float("inf")
    return float(max(abs(a[0] + a[2] / 2 - b[0] - b[2] / 2), abs(a[1] + a[3] / 2 - b[1] - b[3] / 2)))


def static_compare(native, flutter, native_bare, flutter_bare, region):
    native_region, flutter_region = crop(native, region), crop(flutter, region)
    native_boxes = glass_boxes(native_region, crop(native_bare, region))
    flutter_boxes = glass_boxes(flutter_region, crop(flutter_bare, region))
    offset = lambda boxes: [(b[0] + region[0], b[1] + region[1], b[2], b[3]) for b in boxes]
    native_main = offset(native_boxes)[0] if native_boxes else None
    flutter_main = offset(flutter_boxes)[0] if flutter_boxes else None
    result = {
        "mad": mad(native_region, flutter_region),
        "luminance": abs(float(luma(native_region).mean() - luma(flutter_region).mean())),
        "native_box": native_main,
        "flutter_box": flutter_main,
        "bbox_pt": box_delta(native_main, flutter_main),
        "centre_pt": centre_delta(native_main, flutter_main),
    }
    if native_main is not None:
        a = rim_profile(native, native_main)
        b = rim_profile(flutter, native_main)
        size = min(len(a), len(b))
        result["rim_native"] = a[:size].tolist()
        result["rim_flutter"] = b[:size].tolist()
        result["rim_rms"] = float(np.sqrt(np.mean((a[:size] - b[:size]) ** 2)))
    else:
        result["rim_rms"] = float("inf")
    result["pass"] = {key: result[key] <= THRESHOLDS[key] for key in ("mad", "luminance", "rim_rms", "bbox_pt", "centre_pt")}
    return result
