import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import manifest
import tonefit


def curve(x, black, mid, white):
    return black * (1 - x) * (1 - 2 * x) + 4 * mid * x * (1 - x) + white * x * (2 * x - 1)


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.full((2622, 1206, 3), value, dtype=np.uint8)).save(path)


class ToneFitTests(unittest.TestCase):
    def test_recovers_the_three_tone_points_from_backdrop_and_glass_brightness(self):
        points = [(x, curve(x, 0.12, 0.47, 0.58)) for x in (0.0, 0.36, 0.67, 0.9, 1.0)]
        result = tonefit.fit(points)
        self.assertAlmostEqual(result["toneBlack"], 0.12, places=3)
        self.assertAlmostEqual(result["toneMid"], 0.47, places=3)
        self.assertAlmostEqual(result["toneWhite"], 0.58, places=3)
        self.assertLess(result["max_error_luma"], 0.01)

    def test_samples_the_interior_away_from_the_rim(self):
        self.assertEqual(tonefit.interior((21, 465, 360, 200)), (121, 525, 160, 80))

    def test_fits_every_pinned_region_of_a_native_run(self):
        scene = manifest.parse([{
            "id": "material.regular", "group": "material", "title": "t", "inventory": "2.1", "app": "lab",
            "backdrops": list(tonefit.BACKDROPS), "appearances": ["dark"], "steps": [],
            "regions": {"s88": [76, 329, 250, 88]},
        }])[0]
        with tempfile.TemporaryDirectory() as temp:
            for backdrop, bare in zip(tonefit.BACKDROPS, (0, 110, 170, 230, 255)):
                native = Path(temp) / "material.regular" / f"dark-{backdrop}" / "native"
                save(native / "bare" / "ready.png", bare)
                save(native / "ready.png", round(255 * curve(bare / 255, 0.125, 0.478, 0.577)))
            fits = tonefit.run_fit(temp, scene)
        self.assertEqual(list(fits), ["dark.s88"])
        self.assertAlmostEqual(fits["dark.s88"]["toneMid"], 0.478, places=2)


if __name__ == "__main__":
    unittest.main()
