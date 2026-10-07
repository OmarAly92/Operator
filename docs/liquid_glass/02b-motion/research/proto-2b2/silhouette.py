from collections import deque

import numpy as np

RING = 30.0


def silhouette(frame, bare, ring=RING):
    barrier = np.abs(frame - bare).max(axis=2) > ring
    height, width = barrier.shape
    outside = np.zeros_like(barrier)
    queue = deque()
    for y in range(height):
        for x in (0, width - 1):
            if not barrier[y, x] and not outside[y, x]:
                outside[y, x] = True
                queue.append((y, x))
    for x in range(width):
        for y in (0, height - 1):
            if not barrier[y, x] and not outside[y, x]:
                outside[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < height and 0 <= nx < width and not outside[ny, nx] and not barrier[ny, nx]:
                outside[ny, nx] = True
                queue.append((ny, nx))
    return ~outside
