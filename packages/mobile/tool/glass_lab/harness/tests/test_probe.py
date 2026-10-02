import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import probe


def take(scene, median, p90=0.0, frames=100):
    return {"scene": scene, "frames": frames, "raster_ms": {"median": median, "p90": p90}, "build_ms": {"median": 1.0}}


class PerfTests(unittest.TestCase):
    def test_takes_alternate_order(self):
        self.assertEqual(
            probe.perf_order(("a", "b"), 3),
            ["a", "b", "b", "a", "a", "b"],
        )

    def test_summary_uses_medians_across_takes_and_reports_glass_cost(self):
        summary = probe.perf_summary({
            "perf.none": [take("perf.none", 2.0), take("perf.none", 3.0), take("perf.none", 2.5)],
            "perf.glass": [take("perf.glass", 5.0), take("perf.glass", 4.0), take("perf.glass", 9.0)],
        })
        self.assertEqual(summary["perf.none"]["raster_median_ms"], 2.5)
        self.assertEqual(summary["perf.glass"]["raster_median_ms"], 5.0)
        self.assertEqual(summary["perf.glass"]["frames"], 300)
        self.assertEqual(summary["glass_cost_ms"], 2.5)

    def test_every_glass_scene_reports_its_cost_over_the_bare_scene(self):
        summary = probe.perf_summary({
            "perf.none": [take("perf.none", 2.0)],
            "perf.glass": [take("perf.glass", 5.0)],
            "perf.material": [take("perf.material", 6.5)],
        })
        self.assertEqual(summary["material_cost_ms"], 4.5)
        self.assertEqual(summary["glass_cost_ms"], 3.0)
        self.assertIn("perf.material", probe.PERF_SCENES)
        self.assertIn("perf.edge", probe.PERF_SCENES)


class WaitTests(unittest.TestCase):
    def test_returns_the_first_accepted_value(self):
        values = iter([None, {"x": 1}, {"x": 2}])
        self.assertEqual(probe.wait_for(lambda: next(values), lambda v: v["x"] == 2, timeout=5, interval=0), {"x": 2})

    def test_times_out(self):
        with self.assertRaises(TimeoutError):
            probe.wait_for(lambda: None, lambda v: True, timeout=0.05, interval=0.01)


class AccessibilityTests(unittest.TestCase):
    def test_every_mode_is_switched_off_even_when_the_launch_fails(self):
        modes = []
        with tempfile.TemporaryDirectory() as temp, \
                mock.patch.object(probe.record, "launch_folder", return_value=Path(temp)), \
                mock.patch.object(probe.sim, "accessibility", side_effect=lambda udid, mode: modes.append(mode)), \
                mock.patch.object(probe, "launch", side_effect=RuntimeError("launch failed")), \
                mock.patch.object(probe, "terminate") as terminate:
            with self.assertRaises(RuntimeError):
                probe.accessibility_check("udid", "bundle")
        self.assertEqual(modes[-1], "none")
        terminate.assert_called_once_with("udid", "bundle")


if __name__ == "__main__":
    unittest.main()
