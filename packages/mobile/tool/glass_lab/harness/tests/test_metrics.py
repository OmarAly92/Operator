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


class ElementRimTests(unittest.TestCase):
    def test_samples_all_four_sides_at_the_exact_edge(self):
        frame = draw_box(canvas(value=0.0), (100, 300, 150, 44), 100.0)
        sides = metrics.rim_sides(frame, (100, 300, 150, 44))
        for side in metrics.RIM_SIDES:
            self.assertEqual(len(sides[side]), 72)
            self.assertEqual(float(sides[side].min()), 0.0)
            self.assertAlmostEqual(float(sides[side].max()), 100.0, places=3)
        self.assertEqual(float(sides["top"][35]), 0.0)
        self.assertAlmostEqual(float(sides["top"][36]), 100.0, places=3)
        self.assertAlmostEqual(float(sides["right"][35]), 100.0, places=3)
        self.assertEqual(float(sides["right"][36]), 0.0)

    def test_an_end_cap_difference_is_seen_that_the_centre_column_misses(self):
        box = (100, 300, 150, 44)
        native = draw_box(canvas(value=0.0), box, 100.0)
        flutter = draw_box(native.copy(), (100, 300, 1, 44), 160.0)
        rim = metrics.element_rim(native, flutter, box)
        self.assertEqual(rim["sides"]["top"], 0.0)
        self.assertEqual(rim["sides"]["bottom"], 0.0)
        self.assertEqual(rim["sides"]["right"], 0.0)
        self.assertGreater(rim["sides"]["left"], 10.0)
        self.assertGreater(rim["rms"], 5.0)

    def test_the_element_rim_only_makes_the_rim_measure_stricter(self):
        box = (100, 300, 150, 44)
        bare = canvas(value=0.0)
        native = draw_box(canvas(value=0.0), box, 100.0)
        flutter = draw_box(native.copy(), (100, 300, 1, 44), 160.0)
        region = (88, 288, 174, 68)
        legacy = metrics.static_compare(native, flutter, bare, bare, region)
        pinned = metrics.static_compare(native, flutter, bare, bare, region, {"pill": box})
        self.assertEqual(pinned["rim_legacy"], legacy["rim_rms"])
        self.assertGreater(pinned["rim_rms"], legacy["rim_rms"])
        self.assertEqual(pinned["rim_rms"], pinned["rim_elements"]["pill"]["rms"])

    def test_analysis_scores_every_pinned_region_except_the_track(self):
        import manifest
        scenes = {s.id: s for s in manifest.load()}
        self.assertEqual(sorted(analyze.elements_for(scenes["material.regular"])), ["s200", "s44", "s88"])
        self.assertEqual(sorted(analyze.elements_for(scenes["material.tinted"])), ["block", "run"])
        self.assertEqual(analyze.elements_for(scenes["material.edge.soft"]), {})


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

    def test_matches_flutter_parts_that_overlap_the_native_element(self):
        bare = canvas()
        native = draw_box(canvas(), (20, 791, 360, 62))
        flutter = canvas()
        for box in ((24, 795, 93, 54), (150, 800, 30, 30), (300, 800, 30, 30), (20, 100, 120, 120)):
            draw_box(flutter, box)
        result = metrics.static_compare(native, flutter, bare, bare, (0, 80, 402, 794))
        self.assertEqual(result["flutter_box"], (24, 795, 306, 54))

    def test_a_faint_native_element_is_measured_by_its_parts(self):
        bare = canvas()
        native = canvas()
        for box in ((25, 795, 98, 54), (170, 800, 30, 30), (330, 800, 30, 30)):
            draw_box(native, box)
        flutter = draw_box(canvas(), (16, 788, 370, 74))
        result = metrics.static_compare(native, flutter, bare, bare, (0, 700, 402, 174))
        self.assertEqual(result["native_box"], (25, 795, 335, 54))
        self.assertEqual(result["flutter_box"], (16, 788, 370, 74))

    def test_a_full_screen_flutter_layer_does_not_widen_the_native_element(self):
        bare = canvas()
        native = draw_box(draw_box(canvas(), (0, 710, 402, 164)), (300, 18, 60, 20))
        flutter = draw_box(canvas(), (0, 0, 402, 874))
        result = metrics.static_compare(native, flutter, bare, bare, (0, 0, 402, 874))
        self.assertEqual(result["native_box"], (0, 710, 402, 164))
        self.assertGreater(result["centre_pt"], 300)

    def test_flutter_glass_missing_at_the_native_element_is_unmatched(self):
        bare = canvas()
        native = draw_box(canvas(), (284, 62, 102, 44))
        flutter = draw_box(canvas(), (17, 62, 42, 44))
        result = metrics.static_compare(native, flutter, bare, bare, (4, 50, 394, 68))
        self.assertIsNone(result["flutter_box"])
        self.assertFalse(result["pass"]["centre_pt"])

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


class JointAlignmentTests(unittest.TestCase):
    def test_aligns_all_moving_series_together(self):
        count = 80
        native = {key: [10.0] * count for key in align.KEYS}
        flutter = {key: [10.0] * count for key in align.KEYS}
        native["width"] = [float(i * 2) for i in range(count)]
        flutter["width"] = [float((i + 6) * 2) for i in range(count)]
        native["height"] = [float(i * 5) for i in range(count)]
        flutter["height"] = [float((i + 6) * 5) for i in range(count)]
        self.assertLessEqual(abs(analyze.best_lag(native, flutter) - 6), 1)

    def test_no_moving_series_means_no_lag(self):
        flat = {key: [10.0] * 30 for key in align.KEYS}
        self.assertEqual(analyze.best_lag(flat, flat), 0)


class SpringOnFullEventTests(unittest.TestCase):
    def test_springs_are_fitted_on_each_full_event_not_the_aligned_overlap(self):
        times = np.arange(0, 1.2, 1 / 120)
        curve = [10.0] + list(10 + 90 * springfit.step_response(times, 0.4, 0.7))
        native = {key: [10.0] * len(curve) for key in align.KEYS}
        flutter = {key: [10.0] * len(curve) for key in align.KEYS}
        native["width"], flutter["width"] = list(curve), list(curve)
        native["height"] = [float(i) for i in range(len(curve))]
        flutter["height"] = [float(i + 16) for i in range(len(curve))]
        result = analyze.compare_motion({"events": [{"series": native}]}, {"events": [{"series": flutter}]})
        event = result["events"][0]
        self.assertNotEqual(event["lag_ms"], 0)
        self.assertEqual(event["width"]["response_pct"], 0.0)
        self.assertEqual(event["width"]["damping"], 0.0)


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
