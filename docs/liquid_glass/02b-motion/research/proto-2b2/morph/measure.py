import numpy as np
from PIL import Image

SCALE = 3
LOBE_PROMINENCE = 1.0
FIT_MARGIN = 4.0
FIT_MIN_ROWS = 4.0
COARSE_SCALES = (0.6, 0.8, 1.0, 1.2, 1.4)
COARSE_BLURS = (0.0, 1.5, 3.0, 5.0)
FINE_SCALES = np.round(np.arange(0.5, 1.5001, 0.05), 3)
FINE_BLURS = np.round(np.arange(0.0, 6.001, 0.5), 3)
REFINE_REACH = 4
MIN_PIXEL_VARIANCE = 1.0
FINE_SCALE_REACH = 0.15
FINE_BLUR_REACH = 1.5


def profile(mask, scale=SCALE):
    rows = mask.shape[0]
    half = np.zeros(rows)
    centre = np.full(rows, np.nan)
    for row in range(rows):
        found = np.nonzero(mask[row])[0]
        if len(found):
            half[row] = (found[-1] - found[0] + 1) / 2 / scale
            centre[row] = (found[0] + found[-1] + 1) / 2 / scale
    return {"y": (np.arange(rows) + 0.5) / scale, "half": half, "centre": centre}


def _runs(present):
    runs, start = [], None
    for i, value in enumerate(present):
        if value and start is None:
            start = i
        if not value and start is not None:
            runs.append((start, i - 1))
            start = None
    if start is not None:
        runs.append((start, len(present) - 1))
    return runs


def _peaks(values, prominence):
    peaks = [i for i in range(len(values)) if values[i] > 0 and (i == 0 or values[i] >= values[i - 1]) and (i == len(values) - 1 or values[i] > values[i + 1])]
    while True:
        if len(peaks) <= 1:
            return peaks
        scores = []
        for n, p in enumerate(peaks):
            left = values[peaks[n - 1] : p + 1].min() if n > 0 else 0.0
            right = values[p : peaks[n + 1] + 1].min() if n + 1 < len(peaks) else 0.0
            scores.append(values[p] - max(left, right))
        worst = int(np.argmin(scores))
        if scores[worst] >= prominence:
            return peaks
        peaks.pop(worst)


def stack_topology(mask, scale=SCALE, prominence=LOBE_PROMINENCE):
    shape = profile(mask, scale)
    half, y = shape["half"], shape["y"]
    runs = [run for run in _runs(half > 0) if (run[1] - run[0] + 1) / scale >= 2.0]
    lobes, necks = [], []
    for first, last in runs:
        part = half[first : last + 1]
        peaks = _peaks(part, prominence / 2)
        for p in peaks:
            lobes.append({"y": float(y[first + p]), "width": float(2 * part[p])})
        for a, b in zip(peaks, peaks[1:]):
            low = a + int(np.argmin(part[a : b + 1]))
            span = np.nonzero(part[a : b + 1] <= part[low] + 1e-9)[0] + a
            necks.append({"y": float(y[first + int(round(span.mean()))]), "width": float(2 * part[low])})
    return {"count": len(runs), "lobes": lobes, "necks": necks, "extent": [[float(y[a] - 0.5 / scale), float(y[b] + 0.5 / scale)] for a, b in runs]}


def fit_circles(mask, seeds_cy, seeds_r, scale=SCALE, margin=FIT_MARGIN, iterations=8):
    shape = profile(mask, scale)
    y, half = shape["y"], shape["half"]
    rows = np.nonzero(half > 0)[0]
    centres = np.array(seeds_cy, dtype=np.float64)
    radii = np.array(seeds_r, dtype=np.float64)
    alive = np.ones(len(centres), dtype=bool)
    fits = [None] * len(centres)
    if len(centres) == 0 or len(rows) == 0:
        return fits
    for _ in range(iterations):
        predicted = np.sqrt(np.maximum(radii[:, None] ** 2 - (y[rows][None, :] - centres[:, None]) ** 2, 0.0))
        predicted[~alive] = -1
        distance = np.abs(y[rows][None, :] - centres[:, None])
        distance[~alive] = np.inf
        owner = np.where(predicted.max(axis=0) > 0, predicted.argmax(axis=0), distance.argmin(axis=0))
        boundary = np.nonzero(np.diff(owner) != 0)[0]
        keep = np.ones(len(rows), dtype=bool)
        for b in boundary:
            near = np.abs(y[rows] - (y[rows[b]] + y[rows[b + 1]]) / 2) < margin
            keep &= ~near
        changed = False
        for i in range(len(centres)):
            chosen = rows[(owner == i) & keep]
            if len(chosen) < FIT_MIN_ROWS * scale:
                if fits[i] is not None or alive[i]:
                    changed = changed or fits[i] is not None
                fits[i] = None
                alive[i] = False
                continue
            yy, hh = y[chosen], half[chosen]
            design = np.stack([2 * yy, np.ones_like(yy)], axis=1)
            (c, k), *_ = np.linalg.lstsq(design, hh**2 + yy**2, rcond=None)
            r2 = k + c * c
            if r2 <= 0:
                fits[i] = None
                alive[i] = False
                continue
            r = float(np.sqrt(r2))
            residual = float(np.sqrt(np.mean((np.sqrt(np.maximum(r2 - (yy - c) ** 2, 0)) - hh) ** 2)))
            cx = float(np.nanmedian(shape["centre"][chosen]))
            fits[i] = {"cy": float(c), "r": r, "cx": cx, "rows_pt": float(len(chosen) / scale), "rms": residual, "top": float(yy.min()), "bottom": float(yy.max())}
            changed = changed or abs(c - centres[i]) > 1e-3 or abs(r - radii[i]) > 1e-3
            centres[i], radii[i] = c, r
        if not changed:
            break
    return fits


def gaussian(image, sigma):
    if sigma <= 0:
        return image
    reach = int(np.ceil(3 * sigma))
    kernel = np.exp(-0.5 * (np.arange(-reach, reach + 1) / sigma) ** 2)
    kernel /= kernel.sum()
    padded = np.pad(image, reach, mode="edge")
    height, width = image.shape
    rows = sum(k * padded[:, i : i + width] for i, k in enumerate(kernel))
    return sum(k * rows[i : i + height, :] for i, k in enumerate(kernel))


def transform(template, scale, blur_px):
    h, w = template.shape
    size = (max(3, int(round(w * scale))), max(3, int(round(h * scale))))
    resized = np.asarray(Image.fromarray(template.astype(np.float32), mode="F").resize(size, Image.BILINEAR), dtype=np.float32)
    return gaussian(resized, blur_px)


def _window_sums(image, h, w):
    padded = np.pad(image, ((1, 0), (1, 0)))
    total = padded.cumsum(axis=0).cumsum(axis=1)
    return total[h:, w:] - total[:-h, w:] - total[h:, :-w] + total[:-h, :-w]


def ncc_map(image, template):
    h, w = template.shape
    if h > image.shape[0] or w > image.shape[1]:
        return None
    t = template - template.mean()
    norm = np.sqrt((t * t).sum())
    if norm <= 1e-9:
        return None
    shape = (image.shape[0] + h, image.shape[1] + w)
    product = np.fft.irfft2(np.fft.rfft2(image, shape) * np.conj(np.fft.rfft2(t, shape)), shape)
    numerator = product[: image.shape[0] - h + 1, : image.shape[1] - w + 1]
    count = h * w
    sums = _window_sums(image, h, w)
    squares = _window_sums(image * image, h, w)
    variance = squares - sums * sums / count
    flat = variance < count * MIN_PIXEL_VARIANCE
    result = numerator / (np.sqrt(np.maximum(variance, 1e-9)) * norm)
    result[flat] = -1.0
    return result


def _ncc_at(image, template, top, left):
    h, w = template.shape
    if top < 0 or left < 0 or top + h > image.shape[0] or left + w > image.shape[1]:
        return -1.0
    patch = image[top : top + h, left : left + w]
    a = patch - patch.mean()
    if (a * a).mean() < MIN_PIXEL_VARIANCE:
        return -1.0
    b = template - template.mean()
    denominator = np.sqrt((a * a).sum() * (b * b).sum())
    return float((a * b).sum() / denominator) if denominator > 1e-9 else -1.0


def find_glyph(image, template, scale=SCALE, window=None, max_blur=None):
    image = np.asarray(image, dtype=np.float32)
    best = None
    for s in COARSE_SCALES:
        for blur in [b for b in COARSE_BLURS if max_blur is None or b <= max_blur + 1e-9]:
            candidate = transform(template, s, blur * scale)
            found = ncc_map(image, candidate)
            if found is None:
                continue
            if window is not None:
                masked = np.full_like(found, -2.0)
                top, bottom = window
                h = candidate.shape[0]
                a, b = max(0, int(top * scale - h / 2)), max(0, int(bottom * scale - h / 2))
                masked[a : b + 1] = found[a : b + 1]
                found = masked
            iy, ix = np.unravel_index(int(np.argmax(found)), found.shape)
            value = float(found[iy, ix])
            if best is None or value > best[0]:
                best = (value, s, blur, iy + candidate.shape[0] / 2, ix + candidate.shape[1] / 2)
    if best is None:
        return None
    _, coarse_scale, coarse_blur, cy, cx = best
    top_score = None
    scales = [s for s in FINE_SCALES if abs(s - coarse_scale) <= FINE_SCALE_REACH + 1e-9]
    blurs = [b for b in FINE_BLURS if abs(b - coarse_blur) <= FINE_BLUR_REACH + 1e-9 and (max_blur is None or b <= max_blur + 1e-9)]
    for s in scales:
        for blur in blurs:
            candidate = transform(template, float(s), float(blur) * scale)
            h, w = candidate.shape
            base_top, base_left = int(round(cy - h / 2)), int(round(cx - w / 2))
            for dy in range(-REFINE_REACH, REFINE_REACH + 1):
                for dx in range(-REFINE_REACH, REFINE_REACH + 1):
                    value = _ncc_at(image, candidate, base_top + dy, base_left + dx)
                    if top_score is None or value > top_score[0]:
                        top_score = (value, float(s), float(blur), base_top + dy + h / 2, base_left + dx + w / 2)
    value, s, blur, cy, cx = top_score
    return {"cy": cy / scale, "cx": cx / scale, "scale": s, "blur": blur, "ncc": value}


CAP_DROP = 1.0


def cap_fit(mask, side, scale=SCALE):
    shape = profile(mask, scale)
    y, half = shape["y"], shape["half"]
    runs = _runs(half > 0)
    if not runs:
        return None
    first, last = runs[-1] if side == "bottom" else runs[0]
    order = range(last, first - 1, -1) if side == "bottom" else range(first, last + 1)
    chosen, best = [], 0.0
    for row in order:
        if half[row] < best - CAP_DROP:
            break
        best = max(best, half[row])
        chosen.append(row)
    if len(chosen) < FIT_MIN_ROWS * scale:
        return None
    chosen = np.array(chosen)
    yy, hh = y[chosen], half[chosen]
    design = np.stack([2 * yy, np.ones_like(yy)], axis=1)
    (c, k), *_ = np.linalg.lstsq(design, hh**2 + yy**2, rcond=None)
    r2 = k + c * c
    if r2 <= 0:
        return None
    return {"cy": float(c), "r": float(np.sqrt(r2)), "edge": float(yy.max() + 0.5 / scale) if side == "bottom" else float(yy.min() - 0.5 / scale), "rows_pt": float(len(chosen) / scale)}
