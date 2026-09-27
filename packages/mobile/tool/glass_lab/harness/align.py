import numpy as np

from metrics import glass_boxes, load, luma, mad

GRID_HZ = 120
MOTION_THRESHOLD = 0.5
QUIET_SECONDS = 0.15
HOLD_SECONDS = 0.3
STALL_MS = 25.0
EXTENT_TILE = 8
EXTENT_THRESHOLD = 10.0
SKIP_TOP_POINTS = 72
VIDEO_BOX_THRESHOLD = 12.0
KEYS = ("width", "height", "cx", "cy", "luma")
MIN_EVENT_CHANGE = {"width": 4.0, "height": 4.0, "cx": 4.0, "cy": 4.0, "luma": 1.5}


class Frames:
    def __init__(self, paths, times):
        self.paths = list(paths)
        self.times = list(times)

    def __len__(self):
        return len(self.paths)

    def __getitem__(self, index):
        return load(self.paths[index])

    def __iter__(self):
        return (load(path) for path in self.paths)


def differences(frames):
    values, previous = [0.0], None
    for frame in frames:
        if previous is not None:
            values.append(mad(frame, previous))
        previous = frame
    return values


def events(diffs, times, threshold=MOTION_THRESHOLD, quiet=QUIET_SECONDS):
    found, first, last = [], None, None
    for index, value in enumerate(diffs):
        if value <= threshold:
            continue
        if first is not None and times[index] - times[last] > quiet:
            found.append((first, last))
            first = None
        if first is None:
            first = max(0, index - 1)
        last = index
    if first is not None:
        found.append((first, last))
    return found


def stalls(diffs, times, threshold=MOTION_THRESHOLD, quiet=QUIET_SECONDS):
    gaps = []
    for first, last in events(diffs, times, threshold, quiet):
        for index in range(first + 2, last + 1):
            gap = (times[index] - times[index - 1]) * 1000
            if gap > STALL_MS:
                gaps.append(gap)
    return gaps


def row(frame, bare):
    boxes = glass_boxes(frame, bare, threshold=VIDEO_BOX_THRESHOLD, min_area=20, scale=1)
    box = boxes[0] if boxes else (0, 0, 0, 0)
    return {
        "width": float(box[2]),
        "height": float(box[3]),
        "cx": float(box[0] + box[2] / 2),
        "cy": float(box[1] + box[3] / 2),
        "luma": float(luma(frame).mean()),
    }


def event_series(frames, first, last, bare):
    stop = frames.times[last] + HOLD_SECONDS
    indices = [i for i in range(first, len(frames)) if i <= last or frames.times[i] <= stop]
    origin = max(frames.times[first], frames.times[first + 1] - 1.0 / GRID_HZ) if first + 1 < len(frames) else frames.times[first]
    times = [max(0.0, frames.times[i] - origin) for i in indices]
    rows = [row(frames[i], bare) for i in indices]
    times.append(stop - origin)
    rows.append(dict(rows[-1]))
    return resample(times, rows)


def significant(series):
    return any(np.ptp(series[key]) >= MIN_EVENT_CHANGE[key] for key in KEYS)


def resample(times, rows, hz=GRID_HZ):
    grid = np.arange(0.0, times[-1] + 1e-9, 1.0 / hz)
    return {key: np.interp(grid, times, [r[key] for r in rows]).tolist() for key in KEYS}


def extent(frames, threshold=EXTENT_THRESHOLD, tile=EXTENT_TILE):
    first, peak = None, None
    for frame in frames:
        if first is None:
            first = frame
            height, width = frame.shape[0] // tile * tile, frame.shape[1] // tile * tile
            peak = np.zeros((height // tile, width // tile), dtype=np.float32)
            continue
        difference = np.abs(frame[:height, :width] - first[:height, :width]).mean(axis=2)
        np.maximum(peak, difference.reshape(height // tile, tile, width // tile, tile).mean(axis=(1, 3)), out=peak)
    if peak is None:
        return []
    peak[: SKIP_TOP_POINTS // tile] = 0
    ys, xs = np.nonzero(peak > threshold)
    if len(xs) == 0:
        return []
    return [(int(xs.min() * tile), int(ys.min() * tile), int((xs.max() - xs.min() + 1) * tile), int((ys.max() - ys.min() + 1) * tile))]
