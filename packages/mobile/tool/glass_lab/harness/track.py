import re
import subprocess
from collections import deque
from pathlib import Path

import numpy as np

import align
import metrics

BOX_THRESHOLD = 15.0
EDGE_GAIN = 1.0
EDGE_REACH = 5
MIN_RUN = 6
SETTLED_MARGIN = 6.0
PTS = re.compile(r"pts_time:([0-9.]+)")


def pixel_rect(region, scale=metrics.SCALE):
    x, y, w, h = region
    left, top = int(np.floor(x * scale / 2)) * 2, int(np.floor(y * scale / 2)) * 2
    right, bottom = int(np.ceil((x + w) * scale / 2)) * 2, int(np.ceil((y + h) * scale / 2)) * 2
    return left, top, right - left, bottom - top


def crop_px(image, rect):
    x, y, w, h = rect
    return image[y : y + h, x : x + w]


def _box_filter(values, size, reduce):
    pad = size // 2
    padded = np.pad(values, pad, mode="edge")
    height, width = values.shape
    out = None
    for dy in range(size):
        for dx in range(size):
            window = padded[dy : dy + height, dx : dx + width]
            out = window.copy() if out is None else reduce(out, window)
    return out


def smooth(values):
    return _box_filter(values, 3, np.add) / 9.0


def edges(bare):
    gradient = np.zeros(bare.shape[:2], dtype=np.float32)
    gradient[:, 1:] = np.abs(bare[:, 1:] - bare[:, :-1]).max(axis=2)
    gradient[1:, :] = np.maximum(gradient[1:, :], np.abs(bare[1:] - bare[:-1]).max(axis=2))
    return _box_filter(gradient, EDGE_REACH, np.maximum)


def glass_mask(frame, bare, edge_map):
    difference = smooth(np.abs(frame - bare).max(axis=2))
    return difference > BOX_THRESHOLD + EDGE_GAIN * edge_map


BAND_EDGE = 20.0


def box_pixels(frame, bare, edge_map):
    mask = glass_mask(frame, bare, edge_map)
    columns = np.nonzero(mask.sum(axis=0) >= MIN_RUN)[0]
    rows = np.nonzero(mask.sum(axis=1) >= MIN_RUN)[0]
    if len(columns) == 0 or len(rows) == 0:
        return None
    return int(columns[0]), int(rows[0]), int(columns[-1]), int(rows[-1])


def box(frame, bare, edge_map, scale=metrics.SCALE):
    found = box_pixels(frame, bare, edge_map)
    if found is None:
        return None
    left, top, right, bottom = found
    return (left / scale, top / scale, (right - left + 1) / scale, (bottom - top + 1) / scale)


def in_band(edge_map, found):
    left, top, right, bottom = found
    reach = EDGE_REACH // 2
    columns = [edge_map[top : bottom + 1, max(0, c - reach) : c + reach + 1] for c in (left, right)]
    rows = [edge_map[max(0, r - reach) : r + reach + 1, left : right + 1].T for r in (top, bottom)]
    return any(part.size and float((part.max(axis=1) > BAND_EDGE).mean()) > 0.5 for part in columns + rows)


def shape_row(frame, bare, edge_map, origin, scale=metrics.SCALE):
    found = box_pixels(frame, bare, edge_map)
    luma = float(metrics.luma(frame).mean())
    if found is None:
        nan = float("nan")
        return {"width": 0.0, "height": 0.0, "cx": nan, "cy": nan, "xmin": nan, "xmax": nan, "ymin": nan, "ymax": nan, "luma": luma, "band": 0.0}
    left, top, right, bottom = found
    x, y, w, h = left / scale, top / scale, (right - left + 1) / scale, (bottom - top + 1) / scale
    return {
        "width": float(w),
        "height": float(h),
        "cx": float(origin[0] + x + w / 2),
        "cy": float(origin[1] + y + h / 2),
        "xmin": float(origin[0] + x),
        "xmax": float(origin[0] + x + w),
        "ymin": float(origin[1] + y),
        "ymax": float(origin[1] + y + h),
        "luma": luma,
        "band": float(in_band(edge_map, found)),
    }


def laplacian(image):
    gray = metrics.luma(image)
    centre = gray[1:-1, 1:-1] * 4 - gray[:-2, 1:-1] - gray[2:, 1:-1] - gray[1:-1, :-2] - gray[1:-1, 2:]
    return float(np.abs(centre).mean())


def progress_row(frame, bare, full, inner):
    travel = full - bare
    energy = float((travel**2).sum())
    if energy <= 0:
        return {"progress": float("nan"), "residual": float("nan"), "sharpness": float("nan")}
    alpha = float(((frame - bare) * travel).sum() / energy)
    mix = bare + alpha * travel
    rows, columns = inner
    return {
        "progress": alpha,
        "residual": float(np.abs(frame - mix).mean()),
        "sharpness": laplacian(frame[rows, columns]) - laplacian(mix[rows, columns]),
    }


def extract(video, rect, dest):
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    for old in dest.glob("*.png"):
        old.unlink()
    x, y, w, h = rect
    process = subprocess.run(
        [
            "ffmpeg", "-loglevel", "info", "-y", "-i", str(video),
            "-fps_mode", "passthrough",
            "-vf", f"crop={w}:{h}:{x}:{y},showinfo",
            str(dest / "%06d.png"),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    times = [float(t) for t in PTS.findall(process.stderr)]
    paths = sorted(dest.glob("*.png"))
    count = min(len(paths), len(times))
    return align.Frames(paths[:count], times[:count])


def clip(frames, start, end):
    before = [i for i, t in enumerate(frames.times) if t < start]
    inside = [i for i, t in enumerate(frames.times) if start <= t <= end]
    chosen = ([before[-1]] if before else []) + inside
    times = [max(frames.times[i], start) for i in chosen]
    return align.Frames([frames.paths[i] for i in chosen], times)


def teardown_cut(frames, settled):
    if len(frames) == 0:
        return frames
    distances = [metrics.mad(frame, settled) for frame in frames]
    limit = min(distances) + SETTLED_MARGIN
    last = max(i for i, d in enumerate(distances) if d <= limit)
    return align.Frames(frames.paths[: last + 1], frames.times[: last + 1])


TOPOLOGY_MIN_AREA = 20


def point_mask(mask, scale=metrics.SCALE):
    height, width = mask.shape[0] // scale, mask.shape[1] // scale
    return mask[: height * scale, : width * scale].reshape(height, scale, width, scale).mean(axis=(1, 3)) >= 0.5


def components(mask):
    found = []
    for area, box in metrics._components(mask):
        if area >= TOPOLOGY_MIN_AREA:
            found.append(box)
    return found


def lobes(mask):
    ys, xs = np.nonzero(mask)
    if len(xs) < 2:
        return None
    points = np.stack([xs, ys], axis=1).astype(np.float64) + 0.5
    centre = points.mean(axis=0)
    spread = np.cov((points - centre).T)
    values, vectors = np.linalg.eigh(spread)
    axis = vectors[:, int(np.argmax(values))]
    side = (points - centre) @ axis
    if (side < 0).sum() == 0 or (side >= 0).sum() == 0:
        return None
    return points[side < 0].mean(axis=0), points[side >= 0].mean(axis=0)


def cross_section(mask, point, normal):
    height, width = mask.shape
    length = 0
    for direction in (1, -1):
        step = 0 if direction == 1 else 1
        while True:
            x, y = point + normal * direction * step
            ix, iy = int(np.floor(x)), int(np.floor(y))
            if not (0 <= ix < width and 0 <= iy < height and mask[iy, ix]):
                break
            length += 1
            step += 1
    return length


def neck(mask, scale=metrics.SCALE):
    found = lobes(mask)
    if found is None:
        return 0.0
    a, b = found
    span = float(np.linalg.norm(b - a))
    if span < 1:
        return 0.0
    along = (b - a) / span
    normal = np.array([-along[1], along[0]])
    widths = [cross_section(mask, a + along * t, normal) for t in np.arange(0, span + 1e-9, 1.0)]
    return float(min(widths)) / scale if widths else 0.0


def _reach(seeds, free):
    flat = free.ravel()
    width = free.shape[1]
    starts = flat.copy()
    starts[1:] &= ~flat[:-1] | (np.arange(1, flat.size) % width == 0)
    runs = np.cumsum(starts) * flat
    hit = np.bincount(runs, weights=(seeds.ravel() & flat).astype(np.float64), minlength=int(runs.max()) + 1) > 0
    hit[0] = False
    return hit[runs].reshape(free.shape)


def fill_holes(mask):
    free = ~mask
    outside = np.zeros_like(free)
    outside[[0, -1], :] = free[[0, -1], :]
    outside[:, [0, -1]] |= free[:, [0, -1]]
    while True:
        grown = _reach(_reach(outside, free).T, free.T).T
        if (grown == outside).all():
            return ~outside
        outside = grown


def close(mask, reach):
    size = 2 * reach + 1
    return _box_filter(_box_filter(mask, size, np.maximum), size, np.minimum)


TOPOLOGY_LUMA = 8.0
TOPOLOGY_CLOSE = 2


def topology_mask(frame, bare):
    change = np.abs(metrics.luma(frame) - metrics.luma(bare)) > TOPOLOGY_LUMA
    solid = fill_holes(close(change, TOPOLOGY_CLOSE))
    edge = _box_filter(~solid, 2 * TOPOLOGY_CLOSE + 1, np.maximum)
    return solid & (change | ~edge)


STILL_RIM = 30.0
GRAIN_REMOVED = 0.8
GRAIN_MIN = 4.0
GRAIN_WINDOW = 5


def grain_removed(frame, bare):
    change = frame - bare
    shared = np.zeros(bare.shape[:2], dtype=np.float32)
    energy = np.zeros(bare.shape[:2], dtype=np.float32)
    for channel in range(3):
        texture = bare[..., channel] - smooth(bare[..., channel])
        lost = change[..., channel] - smooth(change[..., channel])
        shared += _box_filter(lost * texture, GRAIN_WINDOW, np.add)
        energy += _box_filter(texture * texture, GRAIN_WINDOW, np.add)
    return (energy > GRAIN_MIN * GRAIN_WINDOW**2) & (shared < -GRAIN_REMOVED * energy)


def still_mask(frame, bare):
    rim = np.abs(frame - bare).max(axis=2) > STILL_RIM
    return fill_holes(rim | grain_removed(frame, bare))


def topology(mask):
    parts = components(point_mask(mask))
    if len(parts) != 1:
        return {"count": float(len(parts)), "neck": float("nan")}
    width = neck(mask)
    return {"count": 1.0, "neck": width if width > 0 else float("nan")}


def _labels(mask):
    labels = np.zeros(mask.shape, dtype=np.int32)
    height, width = mask.shape
    found = 0
    for y, x in zip(*np.nonzero(mask)):
        if labels[y, x]:
            continue
        found += 1
        labels[y, x] = found
        queue = deque([(y, x)])
        while queue:
            cy, cx = queue.popleft()
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not labels[ny, nx]:
                    labels[ny, nx] = found
                    queue.append((ny, nx))
    return labels, found


def gap(mask, scale=metrics.SCALE):
    labels, found = _labels(point_mask(mask))
    centres = []
    for label in range(1, found + 1):
        ys, xs = np.nonzero(labels == label)
        if len(xs) >= TOPOLOGY_MIN_AREA:
            centres.append((np.array([xs.mean(), ys.mean()]) + 0.5) * scale)
    if len(centres) != 2:
        return float("nan")
    a, b = centres
    span = float(np.linalg.norm(b - a))
    along = (b - a) / span
    height, width = mask.shape
    empty = 0
    for t in np.arange(0, span, 1.0):
        x, y = a + along * t
        ix, iy = int(np.floor(x)), int(np.floor(y))
        if 0 <= ix < width and 0 <= iy < height and not mask[iy, ix]:
            empty += 1
    return empty / scale


def topology_row(frame, bare):
    mask = topology_mask(frame, bare)
    return dict(topology(mask), gap=gap(mask))
