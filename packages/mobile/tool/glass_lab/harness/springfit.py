import numpy as np

RESPONSES = np.linspace(0.05, 1.5, 146)
DAMPINGS = np.linspace(0.1, 1.2, 111)


def step_response(t, response, damping):
    t = np.asarray(t, dtype=np.float64)
    omega = 2 * np.pi / np.asarray(response, dtype=np.float64)
    zeta = np.asarray(damping, dtype=np.float64)
    under = zeta < 1
    wd = omega * np.sqrt(np.abs(1 - zeta**2))
    safe_wd = np.where(wd == 0, 1e-9, wd)
    decay = np.exp(-zeta * omega * t)
    under_curve = 1 - decay * (np.cos(safe_wd * t) + zeta * omega / safe_wd * np.sin(safe_wd * t))
    critical = 1 - np.exp(-omega * t) * (1 + omega * t)
    r1 = -omega * (zeta - np.sqrt(np.abs(zeta**2 - 1)))
    r2 = -omega * (zeta + np.sqrt(np.abs(zeta**2 - 1)))
    denominator = np.where(r1 == r2, 1e-9, r2 - r1)
    over_curve = 1 - (r2 * np.exp(r1 * t) - r1 * np.exp(r2 * t)) / denominator
    near_critical = np.abs(zeta - 1) < 1e-6
    return np.where(under, under_curve, np.where(near_critical, critical, over_curve))


def normalize(values):
    values = np.asarray(values, dtype=np.float64)
    travel = values[-1] - values[0]
    if abs(travel) < 1e-9:
        return None
    return (values - values[0]) / travel


def fit(times, values):
    normalized = normalize(values)
    if normalized is None:
        return None
    t = np.asarray(times, dtype=np.float64)[None, None, :]
    curves = step_response(t, RESPONSES[:, None, None], DAMPINGS[None, :, None])
    errors = np.sqrt(np.mean((curves - normalized[None, None, :]) ** 2, axis=2))
    i, j = np.unravel_index(np.argmin(errors), errors.shape)
    return {"response": float(RESPONSES[i]), "damping": float(DAMPINGS[j]), "rms": float(errors[i, j])}


def features(times, values):
    normalized = normalize(values)
    if normalized is None:
        return None
    times = np.asarray(times, dtype=np.float64)
    peak = int(np.argmax(normalized))
    outside = np.nonzero(np.abs(normalized - 1) > 0.02)[0]
    settle = times[outside[-1] + 1] if len(outside) and outside[-1] + 1 < len(times) else times[0]
    return {
        "peak_ms": float(times[peak] * 1000),
        "overshoot_pct": float(max(0.0, normalized[peak] - 1) * 100),
        "settle_ms": float(settle * 1000),
    }
