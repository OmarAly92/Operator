import numpy as np

import springfit


def link(frames, gate=8.0, max_gap=0.06):
    tracks, open_tracks = [], []
    for time, values in frames:
        open_tracks = [t for t in open_tracks if time - t["points"][-1][0] <= max_gap]
        predictions = []
        for t in open_tracks:
            (t1, y1) = t["points"][-1]
            if len(t["points"]) > 1:
                (t0, y0) = t["points"][-2]
                velocity = (y1 - y0) / (t1 - t0) if t1 > t0 else 0.0
            else:
                velocity = 0.0
            predictions.append(y1 + velocity * (time - t1))
        pairs = sorted(((abs(v - p), i, j) for i, p in enumerate(predictions) for j, v in enumerate(values)), key=lambda x: x[0])
        used_tracks, used_values = set(), set()
        for distance, i, j in pairs:
            if distance > gate or i in used_tracks or j in used_values:
                continue
            open_tracks[i]["points"].append((time, values[j]))
            used_tracks.add(i)
            used_values.add(j)
        for j, v in enumerate(values):
            if j not in used_values:
                track = {"points": [(time, v)]}
                tracks.append(track)
                open_tracks.append(track)
    return tracks


def spring_from(times, values, target, onset):
    onsets = np.atleast_1d(np.asarray(onset, dtype=np.float64))
    best = None
    for candidate in onsets:
        found = _spring_at(times, values, target, float(candidate))
        if best is None or found["rms"] < best["rms"] - 1e-12:
            best = found
    best["onset_free"] = bool(len(onsets) > 1)
    return best


def _spring_at(times, values, target, onset):
    times = np.asarray(times, dtype=np.float64)
    values = np.asarray(values, dtype=np.float64)
    t = np.maximum(times - onset, 0.0)[None, None, :]
    basis = 1.0 - springfit.step_response(t, springfit.RESPONSES[:, None, None], springfit.DAMPINGS[None, :, None])
    offset = values - target
    amplitude = (basis * offset[None, None, :]).sum(axis=2) / np.maximum((basis * basis).sum(axis=2), 1e-12)
    errors = np.sqrt(np.mean((amplitude[..., None] * basis - offset[None, None, :]) ** 2, axis=2))
    i, j = np.unravel_index(np.argmin(errors), errors.shape)
    edge = i in (0, len(springfit.RESPONSES) - 1) or j in (0, len(springfit.DAMPINGS) - 1)
    return {"response": float(springfit.RESPONSES[i]), "damping": float(springfit.DAMPINGS[j]), "start": float(target + amplitude[i, j]), "rms": float(errors[i, j]), "at_grid_edge": bool(edge), "samples": int(len(times)), "onset": onset}
