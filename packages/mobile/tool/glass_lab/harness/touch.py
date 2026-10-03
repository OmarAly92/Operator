import numpy as np

import metrics
import track

MARKER = (16, 662, 18, 18)
MARKER_INSET = 6
COLOUR_MARGIN = 80.0
DARK = 60.0
TOUCH_KINDS = ("tap", "doubleTap", "press", "pressDrag")


def marker_rect():
    x, y, w, h = MARKER
    return track.pixel_rect((x + MARKER_INSET, y + MARKER_INSET, w - 2 * MARKER_INSET, h - 2 * MARKER_INSET))


def classify(pixels):
    r, g, b = (float(v) for v in np.asarray(pixels, dtype=np.float32).reshape(-1, 3).mean(axis=0))
    if r - max(g, b) > COLOUR_MARGIN:
        return "down"
    if g - max(r, b) > COLOUR_MARGIN:
        return "move"
    if b - max(r, g) > COLOUR_MARGIN:
        return "up"
    if max(r, g, b) < DARK:
        return "idle"
    return "unknown"


def phases(frames):
    return [(time, classify(frame)) for time, frame in zip(frames.times, frames)]


def touches(states):
    found, start, previous = [], None, "idle"
    for time, state in states:
        if state in ("down", "move") and previous not in ("down", "move"):
            start = time
        if state == "up" and previous in ("down", "move") and start is not None:
            found.append((start, time))
            start = None
        elif state == "up" and previous == "idle":
            found.append((time, time))
        if state != "unknown":
            previous = state
    return found


def touch_steps(steps):
    return [index for index, step in enumerate(steps) if next(iter(step)) in TOUCH_KINDS]


def expected_touches(steps):
    return sum(2 if next(iter(steps[index])) == "doubleTap" else 1 for index in touch_steps(steps))


def step_times(steps, windows):
    times = {}
    for index, window in zip(touch_steps(steps), windows):
        kind = next(iter(steps[index]))
        times[index] = window[1] if kind in ("tap", "doubleTap") else window[0]
    return times


def owner(onset, steps, windows):
    owned = None
    for index, window in zip(touch_steps(steps), windows):
        if window[0] <= onset + 1e-6:
            owned = index
    return owned


def read(video, dest):
    return touches(phases(track.extract(video, marker_rect(), dest)))


def is_marker(box):
    x, y, w, h = box
    mx, my, mw, mh = MARKER
    return x >= mx - 2 and y >= my - 2 and x + w <= mx + mw + 2 and y + h <= my + mh + 2


def without_marker(boxes):
    return [box for box in boxes if not is_marker(box)]


def marker_free(rect):
    return not metrics.overlaps(rect, MARKER, slack=0)
