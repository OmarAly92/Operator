import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import manifest
import metrics
import press
import shapes


def row(glow=100.0, width=250.0, height=88.0, cx=201.0, cy=451.0):
    return {"glow": glow, "width": width, "height": height, "cx": cx, "cy": cy}


def native_press(drop_at=0.400, rise_frames=(13.0, 18.0, 20.0, 20.6), grow=12.0, up=1.0, step=1 / 60):
    times, rows = [0.0], [row()]
    t = 0.5
    for value in rise_frames:
        t += step
        times.append(t)
        rows.append(row(glow=100 + value))
    while t < up:
        t += step
        times.append(t)
        share = min(1.0, (t - 0.5) / 0.2)
        rows.append(row(glow=120.6, width=250 + grow * share, height=88 + grow * share * 88 / 250))
    released = t
    while t < released + 1.0:
        t += step
        times.append(t)
        after = t - up
        glow = 100.0 if after >= drop_at else 120.6 - 8.6 * after / drop_at
        share = max(0.0, 1 - after / 0.15)
        rows.append(row(glow=glow, width=250 + grow * share, height=88 + grow * share * 88 / 250))
    return times, rows


class PressFeatureTests(unittest.TestCase):
    def test_glow_first_growth_second_and_a_one_frame_drop_after_release(self):
        times, rows = native_press()
        found = press.features(times, rows, (0.5, 1.0))
        self.assertAlmostEqual(found["glow_peak"], 20.6, places=6)
        self.assertAlmostEqual(found["glow_rise_ms"], 3 * 1000 / 60, places=3)
        self.assertGreater(found["grow_ms"], found["glow_rise_ms"])
        self.assertAlmostEqual(found["grow_w"], 12.0, places=6)
        self.assertAlmostEqual(found["glow_drop"], 12.0, delta=0.5)
        self.assertAlmostEqual(found["glow_drop_ms"], 400, delta=1000 / 60)
        self.assertAlmostEqual(found["glow_fade_ms"], found["glow_drop_ms"], delta=1e-6)
        self.assertLess(found["shrink_ms"], 170)
        self.assertLess(abs(found["stretch"]), 0.01)
        self.assertEqual(found["centre"], 0.0)

    def test_a_glow_that_decays_smoothly_has_no_drop_time(self):
        times, rows = native_press(drop_at=10.0)
        found = press.features(times, rows, (0.5, 1.0))
        self.assertLess(found["glow_drop"], press.MIN_GLOW)
        self.assertIsNone(found["glow_drop_ms"])

    def test_the_rest_is_the_last_frame_before_touch_down(self):
        times = [0.0, 0.5, 0.52, 0.6]
        rows = [row(glow=100), row(glow=130), row(glow=130), row(glow=130)]
        found = press.features(times, rows, (0.5, 0.55))
        self.assertEqual(found["rest"]["glow"], 100)
        self.assertEqual(found["glow_peak"], 30)
        self.assertEqual(found["glow_rise_ms"], 0)

    def test_a_shape_that_does_not_light_has_no_times(self):
        times = [0.0, 0.6, 0.7, 1.2]
        rows = [row(), row(glow=101), row(glow=101.5), row()]
        found = press.features(times, rows, (0.5, 1.0))
        self.assertLess(found["glow_peak"], press.MIN_GLOW)
        for key in ("glow_rise_ms", "glow_fade_ms", "glow_drop_ms", "grow_ms", "shrink_ms"):
            self.assertIsNone(found[key])
        self.assertEqual(found["glow_drop"], 0.0)

    def test_stretch_is_the_signed_ratio_change_and_centre_the_largest_offset(self):
        times = [0.0, 0.6, 0.8, 1.0, 1.4]
        rows = [row(), row(width=260, height=88), row(width=250, height=80, cx=205, cy=454), row(), row()]
        found = press.features(times, rows, (0.5, 1.0))
        self.assertAlmostEqual(found["stretch"], (250 / 80) / (250 / 88) - 1, places=9)
        self.assertAlmostEqual(found["centre"], 5.0, places=9)

    def test_the_release_stops_at_the_next_touch(self):
        times, rows = native_press()
        later = [t + 3.0 for t in times[1:]]
        found = press.features(times + later, rows + rows[1:], (0.5, 1.0), end=3.5)
        alone = press.features(times, rows, (0.5, 1.0))
        self.assertEqual(found["glow_fade_ms"], alone["glow_fade_ms"])


class PressHoleTests(unittest.TestCase):
    def test_a_burst_after_touch_down_marks_the_step_and_its_times_are_judged_as_absent(self):
        times, rows = native_press()
        burst = [0.0, 0.5, 0.5017, 0.5034, 0.5051] + [t + 0.01 for t in times[5:]]
        found = press.features(burst, rows, (0.5, 1.0))
        self.assertTrue(found["hole"])
        clean = press.features(times, rows, (0.5, 1.0))
        self.assertFalse(clean["hole"])
        entry = press.compare(clean, found)
        for measure in press.TIMES:
            self.assertTrue(math.isnan(entry[measure]), measure)
        self.assertAlmostEqual(entry["glow_peak"], 0.0, places=6)

    def test_a_burst_at_the_cut_marks_the_step_and_a_still_frame_far_apart_does_not(self):
        times, rows = native_press()
        cut = next(i for i, t in enumerate(times) if t > 1.45)
        squeezed = list(times)
        squeezed[cut + 1] = squeezed[cut] + 0.002
        squeezed[cut + 2] = squeezed[cut] + 0.004
        self.assertTrue(press.features(squeezed, rows, (0.5, 1.0))["hole"])
        still = [0.0, 0.5, 0.9, 1.0, 1.2]
        quiet = [row(), row(), row(), row(), row()]
        self.assertFalse(press.features(still, quiet, (0.5, 1.0))["hole"])


    def test_a_flickering_glow_after_the_cut_with_frames_far_apart_is_not_a_hole(self):
        times, rows = native_press()
        kept = [i for i, t in enumerate(times) if t < 1.5]
        times = [times[i] for i in kept] + [1.65, 1.78, 1.79]
        rows = [rows[i] for i in kept] + [row(glow=100.3), row(glow=100.0), row(glow=100.3)]
        self.assertFalse(press.features(times, rows, (0.5, 1.0))["hole"])
        lost = [t if t < 1.05 else t + 0.04 for t in native_press()[0]]
        self.assertTrue(press.features(lost, native_press()[1], (0.5, 1.0))["hole"])


class PressFadeTests(unittest.TestCase):
    def test_the_level_before_the_cut_and_the_half_time_judge_the_fade(self):
        times, rows = native_press()
        found = press.features(times, rows, (0.5, 1.0))
        self.assertAlmostEqual(found["glow_level"], 12.0, delta=0.5)
        self.assertGreater(found["glow_half_ms"], 0)
        self.assertLess(found["glow_half_ms"], found["glow_drop_ms"])
        slower = press.features(*native_press(drop_at=0.6), (0.5, 1.0))
        self.assertGreater(slower["glow_half_ms"], found["glow_half_ms"])

    def test_a_glow_without_a_cut_has_no_level_and_halves_toward_rest(self):
        found = press.features(*native_press(drop_at=10.0), (0.5, 1.0))
        self.assertIsNone(found["glow_level"])
        self.assertIsNone(found["glow_half_ms"])
        times = [0.0, 0.6, 0.9] + [1.0 + 0.02 * k for k in range(1, 11)]
        rows = [row(), row(glow=120), row(glow=120)] + [row(glow=120 - 2 * k) for k in range(1, 11)]
        faded = press.features(times, rows, (0.5, 1.0))
        self.assertIsNone(faded["glow_level"])
        self.assertAlmostEqual(faded["glow_half_ms"], 100.0, places=6)


class PressCompareTests(unittest.TestCase):
    def test_absent_times_on_both_sides_agree_and_on_one_side_fail(self):
        times, rows = native_press()
        lit = press.features(times, rows, (0.5, 1.0))
        steps = [0.0] + [0.5 + k / 60 for k in range(91)]
        dark = press.features(steps, [row(glow=101 if 0.5 < t <= 1.0 else 100) for t in steps], (0.5, 1.0))
        self.assertEqual(press.compare(dark, dark)["glow_rise_ms"], 0.0)
        self.assertEqual(press.compare(lit, dark)["glow_rise_ms"], math.inf)
        self.assertAlmostEqual(press.compare(lit, dark)["glow_peak"], lit["glow_peak"] - dark["glow_peak"], places=9)

    def test_every_press_measure_has_a_threshold(self):
        for measure in press.MEASURES:
            self.assertIn(press.LIMITS[measure], metrics.THRESHOLDS)
        self.assertEqual(metrics.THRESHOLDS["ratio"], 0.01)
        self.assertEqual(metrics.THRESHOLDS["luminance"], 3.0)
        self.assertEqual(metrics.THRESHOLDS["centre_pt"], 1.0)
        self.assertEqual(metrics.THRESHOLDS["time_ms"], 17.0)


class PressSceneTests(unittest.TestCase):
    def scene(self, motion):
        return manifest.parse([{
            "id": "test.neighbours",
            "group": "material",
            "title": "two pressable glasses",
            "inventory": "2.5",
            "app": "lab",
            "backdrops": ["photo"],
            "appearances": ["dark"],
            "steps": [{"wait": 0.5}, {"press": {"at": "left", "duration": 1.0}}, {"wait": 1.0}],
            "regions": {"left": [60, 393, 141, 116], "right": [201, 393, 141, 116]},
            "track": ["left", "right"],
            "motion": list(motion),
        }])[0]

    def capture(self, glow):
        times, rows = native_press()
        rows = [dict(r, glow=100 + (r["glow"] - 100) * glow) for r in rows]
        quiet = [row() for _ in rows]
        return {"touches": [(0.5, 1.0)], "rows": {"left": {"times": times, "rows": rows}, "right": {"times": times, "rows": quiet}}, "events": []}

    def test_every_touch_step_and_tracked_shape_is_expected_and_judged(self):
        scene = self.scene(["press.glow_peak", "press.glow_rise_ms"])
        result = shapes.compare(scene, self.capture(1.0), self.capture(0.5))
        expected = shapes.expected(result, scene)
        self.assertEqual(sorted(expected), sorted(f"{n}.step1.press.{m}" for n in ("left", "right") for m in ("glow_peak", "glow_rise_ms")))
        limits = shapes.limits(result, scene)
        self.assertAlmostEqual(limits["left.step1.press.glow_peak"][0], 10.3, places=6)
        self.assertEqual(limits["left.step1.press.glow_peak"][1], 3.0)
        self.assertEqual(limits["right.step1.press.glow_peak"][0], 0.0)
        self.assertEqual(limits["right.step1.press.glow_rise_ms"][0], 0.0)

    def test_a_press_measure_with_no_touch_window_is_absent_and_fails(self):
        scene = self.scene(["press.glow_peak"])
        quiet = dict(self.capture(1.0), touches=[])
        limits = shapes.limits(shapes.compare(scene, quiet, quiet), scene)
        self.assertEqual(limits["left.step1.press.glow_peak"][0], math.inf)

    def test_a_pinned_rect_must_lie_inside_its_tracked_region(self):
        base = {
            "id": "test.pinned", "group": "material", "title": "t", "inventory": "2.5", "app": "lab",
            "backdrops": ["photo"], "appearances": ["dark"], "steps": [{"wait": 0.5}, {"press": {"at": "left", "duration": 1.0}}],
            "regions": {"left": [60, 393, 141, 116]}, "track": ["left"],
        }
        self.assertEqual(manifest.validate([dict(base, pinned={"left": [80, 407, 60, 60]})]), [])
        self.assertTrue(manifest.validate([dict(base, pinned={"left": [10, 407, 60, 60]})]))
        self.assertTrue(manifest.validate([dict(base, pinned={"right": [80, 407, 60, 60]})]))

    def test_a_pinned_rect_is_the_glow_box_in_region_pixels(self):
        self.assertEqual(shapes.pinned_px([80, 407, 60, 60], (180, 1178, 423, 348)), (60, 42, 239, 223))

    def test_the_manifest_and_the_analysis_list_the_same_press_measures(self):
        self.assertEqual([m for m in manifest.MOTION_MEASURES if m.startswith("press.")], [f"press.{m}" for m in press.MEASURES])


if __name__ == "__main__":
    unittest.main()
