from collections import deque

import numpy as np
from PIL import Image

SCALE = 3
SCREEN = (402, 874)
LAYER_FRACTION = 0.5
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
    "progress_rms": 0.05,
    "sharpness": 1.0,
    "neck_pt": 1.0,
    "count": 0.0,
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


RIM_SIDES = ("top", "bottom", "left", "right")


def rim_sides(frame, box, reach=12):
    x, y, w, h = box
    lum = luma(frame)
    height, width = lum.shape
    span = reach * SCALE
    column = min(width - 1, int(round((x + w / 2) * SCALE)))
    row = min(height - 1, int(round((y + h / 2) * SCALE)))
    top, bottom = int(round(y * SCALE)), int(round((y + h) * SCALE))
    left, right = int(round(x * SCALE)), int(round((x + w) * SCALE))
    return {
        "top": lum[max(0, top - span) : min(height, top + span), column],
        "bottom": lum[max(0, bottom - span) : min(height, bottom + span), column],
        "left": lum[row, max(0, left - span) : min(width, left + span)],
        "right": lum[row, max(0, right - span) : min(width, right + span)],
    }


def element_rim(native, flutter, box):
    a, b = rim_sides(native, box), rim_sides(flutter, box)
    sides = {side: float(np.sqrt(np.mean((a[side] - b[side]) ** 2))) for side in RIM_SIDES}
    joined = np.concatenate([a[side] - b[side] for side in RIM_SIDES])
    return {"rms": float(np.sqrt(np.mean(joined**2))), "sides": sides}


def box_delta(a, b):
    if a is None or b is None:
        return float("inf")
    return float(max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[0] + a[2] - b[0] - b[2]), abs(a[1] + a[3] - b[1] - b[3])))


def overlaps(a, b, slack=4):
    return not (
        a[0] + a[2] + slack <= b[0]
        or b[0] + b[2] + slack <= a[0]
        or a[1] + a[3] + slack <= b[1]
        or b[1] + b[3] + slack <= a[1]
    )


def matching(boxes, target):
    hits = [box for box in boxes if overlaps(box, target)]
    if not hits:
        return None
    left, top = min(b[0] for b in hits), min(b[1] for b in hits)
    right, bottom = max(b[0] + b[2] for b in hits), max(b[1] + b[3] for b in hits)
    return (left, top, right - left, bottom - top)


def centre_delta(a, b):
    if a is None or b is None:
        return float("inf")
    return float(max(abs(a[0] + a[2] / 2 - b[0] - b[2] / 2), abs(a[1] + a[3] / 2 - b[1] - b[3] / 2)))


def static_compare(native, flutter, native_bare, flutter_bare, region, elements=None):
    native_region, flutter_region = crop(native, region), crop(flutter, region)
    native_boxes = glass_boxes(native_region, crop(native_bare, region))
    flutter_boxes = glass_boxes(flutter_region, crop(flutter_bare, region))
    offset = lambda boxes: [(b[0] + region[0], b[1] + region[1], b[2], b[3]) for b in boxes]
    native_all, flutter_all = offset(native_boxes), offset(flutter_boxes)
    native_main = native_all[0] if native_all else None
    if native_main is None:
        flutter_main = flutter_all[0] if flutter_all else None
    else:
        flutter_main = matching(flutter_all, native_main)
        if flutter_main is not None and flutter_main[2] * flutter_main[3] < LAYER_FRACTION * SCREEN[0] * SCREEN[1]:
            native_main = matching(native_all, flutter_main)
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
    if elements:
        result["rim_legacy"] = result["rim_rms"]
        result["rim_elements"] = {name: element_rim(native, flutter, box) for name, box in elements.items()}
        worst = max(entry["rms"] for entry in result["rim_elements"].values())
        result["rim_rms"] = max(result["rim_rms"], worst)
    result["pass"] = {key: result[key] <= THRESHOLDS[key] for key in ("mad", "luminance", "rim_rms", "bbox_pt", "centre_pt")}
    return result
