import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import align
import analyze
import metrics
import springfit


def canvas(width=402, height=874, value=40.0):
    return np.full((height * 3, width * 3, 3), value, dtype=np.float32)


def draw_box(image, box, value=200.0):
    x, y, w, h = (v * 3 for v in box)
    image[y : y + h, x : x + w] = value
    return image


class GlassBoxTests(unittest.TestCase):
    def test_finds_drawn_box_within_one_point(self):
        bare = canvas()
        frame = draw_box(canvas(), (100, 300, 150, 44))
        boxes = metrics.glass_boxes(frame, bare)
        self.assertEqual(len(boxes), 1)
        for got, want in zip(boxes[0], (100, 300, 150, 44)):
            self.assertLessEqual(abs(got - want), 1)

    def test_orders_components_by_area(self):
        bare = canvas()
        frame = draw_box(draw_box(canvas(), (20, 20, 30, 30)), (100, 400, 200, 100))
        boxes = metrics.glass_boxes(frame, bare)
        self.assertEqual(boxes[0][:2], (100, 400))
        self.assertEqual(len(boxes), 2)

    def test_ignores_differences_below_threshold(self):
        bare = canvas()
        frame = canvas(value=44.0)
        self.assertEqual(metrics.glass_boxes(frame, bare), [])

    def test_union_pads_and_clips(self):
        self.assertEqual(metrics.union([(5, 5, 10, 10), (380, 800, 20, 70)], pad=12), (0, 0, 402, 874))
        self.assertIsNone(metrics.union([]))


class RimProfileTests(unittest.TestCase):
    def test_returns_the_drawn_gradient(self):
        frame = canvas(value=0.0)
        ramp = np.linspace(0, 255, 874 * 3, dtype=np.float32)
        frame[:, :, :] = ramp[:, None, None]
        profile = metrics.rim_profile(frame, (100, 300, 100, 50), reach=4)
        top = ramp[(300 - 4) * 3 : (300 + 4) * 3]
        np.testing.assert_allclose(profile[: len(top)], top, atol=1e-3)


class StaticCompareTests(unittest.TestCase):
    def test_identical_frames_pass(self):
        bare = canvas()
        frame = draw_box(canvas(), (100, 300, 150, 44))
        result = metrics.static_compare(frame, frame, bare, bare, (80, 280, 190, 84))
        self.assertTrue(all(result["pass"].values()))
        self.assertEqual(result["mad"], 0.0)

    def test_centre_ignores_symmetric_growth(self):
        bare = canvas()
        native = draw_box(canvas(), (100, 300, 150, 44))
        flutter = draw_box(canvas(), (96, 296, 158, 52))
        result = metrics.static_compare(native, flutter, bare, bare, (80, 280, 200, 90))
        self.assertTrue(result["pass"]["centre_pt"])
        self.assertFalse(result["pass"]["bbox_pt"])

    def test_shifted_box_fails_bbox(self):
        bare = canvas()
        native = draw_box(canvas(), (100, 300, 150, 44))
        flutter = draw_box(canvas(), (104, 300, 150, 44))
        result = metrics.static_compare(native, flutter, bare, bare, (80, 280, 200, 84))
        self.assertFalse(result["pass"]["bbox_pt"])
        self.assertAlmostEqual(result["bbox_pt"], 4, delta=1)


class EventTests(unittest.TestCase):
    def test_splits_bursts_separated_by_quiet_time(self):
        times = [i / 120 for i in range(10)] + [1.0 + i / 120 for i in range(10)]
        diffs = [0.0] + [2.0] * 9 + [2.0] + [2.0] * 9
        self.assertEqual(align.events(diffs, times), [(0, 9), (9, 19)])

    def test_ignores_small_differences(self):
        times = [i / 120 for i in range(6)]
        self.assertEqual(align.events([0.0, 0.2, 0.3, 0.1, 0.0, 0.2], times), [])

    def test_reports_gaps_inside_motion_only(self):
        times = [0.0, 0.008, 0.016, 0.06, 0.068, 2.0, 2.008]
        diffs = [0.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0]
        self.assertEqual([round(g) for g in align.stalls(diffs, times)], [44])

    def test_resample_interpolates_on_grid(self):
        rows = [{key: 0.0 for key in align.KEYS}, {key: 12.0 for key in align.KEYS}]
        series = align.resample([0.0, 0.1], rows, hz=120)
        self.assertEqual(len(series["width"]), 13)
        self.assertAlmostEqual(series["width"][6], 6.0)

    def test_significant_needs_real_travel(self):
        flat = {key: [1.0, 1.0, 1.2] for key in align.KEYS}
        moving = dict(flat, width=[10.0, 30.0, 40.0])
        self.assertFalse(align.significant(flat))
        self.assertTrue(align.significant(moving))

    def test_extent_bounds_changed_tiles_below_the_status_area(self):
        first = np.zeros((874, 402, 3), dtype=np.float32)
        moved = first.copy()
        moved[400:480, 100:200] = 200
        moved[10:30, 10:30] = 200
        self.assertEqual(align.extent([first, moved]), [(96, 400, 104, 80)])


class SpringFitTests(unittest.TestCase):
    def test_recovers_response_and_damping(self):
        times = np.arange(0, 1.5, 1 / 60)
        for response, damping in ((0.35, 0.7), (0.5, 0.86), (0.25, 1.0), (0.8, 0.45)):
            values = 10 + 90 * springfit.step_response(times, response, damping)
            got = springfit.fit(times, values)
            self.assertLessEqual(abs(got["response"] - response) / response, 0.05)
            self.assertLessEqual(abs(got["damping"] - damping), 0.05)

    def test_features_of_underdamped_curve(self):
        times = np.arange(0, 2.0, 1 / 60)
        values = springfit.step_response(times, 0.5, 0.5)
        result = springfit.features(times, values)
        self.assertGreater(result["overshoot_pct"], 10)
        self.assertGreater(result["settle_ms"], result["peak_ms"])

    def test_flat_series_has_no_fit(self):
        self.assertIsNone(springfit.fit([0, 1, 2], [5, 5, 5]))


class ThresholdTests(unittest.TestCase):
    def test_thresholds_classify_known_inputs(self):
        self.assertLessEqual(3.9, metrics.THRESHOLDS["mad"])
        self.assertGreater(4.1, metrics.THRESHOLDS["mad"])
        self.assertEqual(metrics.THRESHOLDS["time_ms"], 17.0)


class OnsetAlignmentTests(unittest.TestCase):
    def _series(self, shift, count=60):
        native = {key: [10.0] * count for key in align.KEYS}
        native["width"] = [float(i) for i in range(count)]
        flutter = {key: [10.0] * count for key in align.KEYS}
        flutter["width"] = [float(i + shift) for i in range(count)]
        return native, flutter

    def test_recovers_a_positive_offset_within_one_frame(self):
        native, flutter = self._series(5)
        self.assertLessEqual(abs(analyze.best_lag(native, flutter) - 5), 1)

    def test_recovers_a_negative_offset_within_one_frame(self):
        native, flutter = self._series(-7)
        self.assertLessEqual(abs(analyze.best_lag(native, flutter) - -7), 1)


class MotionCheckTests(unittest.TestCase):
    def test_no_native_motion_fails_even_when_counts_match(self):
        checks = analyze.motion_checks({"event_count": [0, 0], "events": []})
        self.assertTrue(checks["events.count"])
        self.assertFalse(checks["events.native_motion"])

    def test_native_motion_passes_when_present(self):
        checks = analyze.motion_checks({"event_count": [2, 2], "events": []})
        self.assertTrue(checks["events.native_motion"])
        self.assertTrue(checks["events.count"])


if __name__ == "__main__":
    unittest.main()
