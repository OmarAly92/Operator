import numpy as np

import metrics

COLUMN_HALF = 10
MIN_PEAK = 2.0


def rim_width(frame, bare, box_px, scale=metrics.SCALE):
    left, top, right, bottom = box_px
    centre = (left + right) // 2
    columns = slice(max(0, centre - COLUMN_HALF), centre + COLUMN_HALF + 1)
    column = metrics.luma(frame)[top : bottom + 1, columns].mean(axis=1) - metrics.luma(bare)[top : bottom + 1, columns].mean(axis=1)
    third = len(column) // 3
    if third < 2:
        return float("nan")
    interior = float(np.median(column[third : 2 * third]))
    band = column[:third] - interior
    peak = float(band.max())
    if peak < MIN_PEAK:
        return float("nan")
    lit = np.nonzero(band >= peak / 2)[0]
    return float(lit[-1] + 1) / scale
