import sys
import unittest
from pathlib import Path

import numpy as np

HARNESS = Path(__file__).resolve().parents[6] / "packages/mobile/tool/glass_lab/harness"
sys.path.insert(0, str(HARNESS))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import tracking
import springfit


class SpringFromTests(unittest.TestCase):
    def test_recovers_start_response_and_damping_from_a_late_segment(self):
        times = np.arange(0.0, 1.2, 1 / 60)
        start, target, onset = 451.0, 343.0, 0.05
        values = target + (start - target) * (1 - springfit.step_response(np.maximum(times - onset, 0), 0.5, 0.8))
        visible = times > 0.35
        fit = tracking.spring_from(times[visible], values[visible], target, onset)
        self.assertAlmostEqual(fit["start"], start, delta=1.0)
        self.assertAlmostEqual(fit["response"], 0.5, delta=0.02)
        self.assertAlmostEqual(fit["damping"], 0.8, delta=0.03)

    def test_free_onset_recovers_a_delayed_start(self):
        times = np.arange(0.0, 1.2, 1 / 60)
        start, target, onset = 470.0, 343.0, 0.28
        values = target + (start - target) * (1 - springfit.step_response(np.maximum(times - onset, 0), 0.45, 0.85))
        visible = times > 0.36
        fit = tracking.spring_from(times[visible], values[visible], target, np.arange(0.0, 0.5, 1 / 120))
        self.assertAlmostEqual(fit["onset"], onset, delta=0.02)
        self.assertAlmostEqual(fit["start"], start, delta=6.0)
        self.assertAlmostEqual(fit["response"], 0.45, delta=0.03)


class TrackTests(unittest.TestCase):
    def test_links_by_prediction_and_splits_on_gaps(self):
        frames = [
            (0.00, [400.0]),
            (0.02, [398.0]),
            (0.04, [396.0, 450.0]),
            (0.06, [394.0, 445.0]),
            (0.08, [392.0]),
            (0.20, [380.0, 300.0]),
        ]
        tracks = tracking.link(frames, gate=8.0, max_gap=0.05)
        ids = sorted((t["points"][0][1], len(t["points"])) for t in tracks)
        self.assertEqual(ids, [(300.0, 1), (380.0, 1), (400.0, 5), (450.0, 2)])


if __name__ == "__main__":
    unittest.main()
