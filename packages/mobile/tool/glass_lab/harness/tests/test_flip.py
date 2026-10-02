import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import flip


class FlipTests(unittest.TestCase):
    def test_reads_inside_and_around_a_box(self):
        image = np.zeros((100, 100, 3), dtype=np.float32)
        image[40:60, 20:80] = 200
        box = (20, 40, 60, 20)
        self.assertAlmostEqual(flip.inner(image, box, 1), 200)
        self.assertEqual(flip.ring(image, box, 1), (0.0, 0.0))

    def test_over_takes_the_median_where_the_backdrop_matches(self):
        rows = [
            {"small_top": (250, 255, 182)},
            {"small_top": (251, 255, 184)},
            {"small_top": (120, 255, 90)},
            {"small_top": (0, 5, 40)},
            {"small_top": (0, 200, 70)},
        ]
        self.assertEqual(flip.over(rows, "small_top", "white"), 183)
        self.assertEqual(flip.over(rows, "small_top", "black"), 40)
        self.assertIsNone(flip.over(rows, "large", "white"))

    def test_verdicts(self):
        self.assertEqual(flip.verdict(182, 185, 250), "no flip")
        self.assertEqual(flip.verdict(245, 185, 250), "flips")
        self.assertEqual(flip.verdict(215, 185, 250), "neither")
        self.assertEqual(flip.verdict(None, 185, 250), "not seen")


if __name__ == "__main__":
    unittest.main()
