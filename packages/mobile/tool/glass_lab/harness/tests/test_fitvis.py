import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import fitvis
import springfit


def curve(case, appearing, response, damping, exponent=1.0, gain=1.0, lag=0.01, take="t0"):
    t = np.arange(-0.05, 0.9, 1 / 120)
    s = springfit.step_response(np.maximum(t - lag, 0), response, damping)
    alpha = fitvis.mapped(s, appearing, exponent, gain)
    return {"case": case, "take": take, "appearing": appearing, "t": t, "alpha": alpha, "sharpness": -2 * alpha * (1 - alpha)}


class InvertTests(unittest.TestCase):
    def test_the_table_maps_measured_progress_back_to_visibility(self):
        progress = {"dark-photo": {0.0: 0.0, 0.5: 0.8, 1.0: 1.0}, "light-photo": {0.0: 0.0, 0.5: 0.6, 1.0: 1.0}}
        table, mean = fitvis.invert(progress, grid=5)
        self.assertEqual(mean, [0.0, 0.7, 1.0])
        self.assertEqual(table[0], 0.0)
        self.assertEqual(table[-1], 1.0)
        self.assertAlmostEqual(table[2], 0.5 * 0.5 / 0.7, places=3)

    def test_a_non_monotone_measurement_is_made_monotone(self):
        table, _ = fitvis.invert({"x": {0.0: 0.0, 0.25: 0.4, 0.5: 0.35, 0.75: 0.7, 1.0: 1.0}}, grid=11)
        self.assertEqual(table, sorted(table))


class MappingTests(unittest.TestCase):
    def test_each_preset_keeps_its_swiftui_spring_and_gets_its_own_exponent_and_overshoot_gain(self):
        curves = {
            "material.materialize": [curve("dark-photo", True, 0.55, 1.0), curve("dark-photo", False, 0.55, 1.0, 3.2), curve("light-stripes", False, 0.55, 1.0, 3.2)],
            "material.materialize.bouncy": [curve("light-photo", True, 0.5, 0.7, gain=0.5), curve("dark-stripes", False, 0.5, 0.7, 2.7)],
        }
        mapping = fitvis.fit_mapping(curves)
        self.assertEqual(mapping["material.materialize"]["spring"], [0.55, 1.0])
        self.assertAlmostEqual(mapping["material.materialize"]["exponent"]["value"], 3.2, delta=0.06)
        self.assertAlmostEqual(mapping["material.materialize.bouncy"]["exponent"]["value"], 2.7, delta=0.06)
        self.assertAlmostEqual(mapping["material.materialize.bouncy"]["gain"]["value"], 0.5, delta=0.03)
        self.assertFalse(mapping["material.materialize.bouncy"]["gain"]["at_grid_edge"])
        self.assertFalse(mapping["material.materialize"]["gain"]["identifiable"])
        self.assertEqual(mapping["material.materialize"]["gain"]["value"], 0.0)
        self.assertEqual(mapping["material.materialize"]["reduce_motion_gain"]["value"], 0.0)
        self.assertEqual(mapping["material.materialize"]["cases"], ["dark-photo", "light-stripes"])

    def test_a_curve_no_exponent_can_fit_is_left_out_and_reported(self):
        good = [curve("dark-photo", False, 0.5, 0.7, 2.7, take=t) for t in ("a", "b", "c")]
        broken = curve("dark-stripes", False, 0.5, 0.7, 2.7, take="d")
        broken["alpha"] = np.clip(broken["alpha"] + 0.6 * np.sin(np.arange(len(broken["alpha"]))), -1, 2)
        found = fitvis.fit_mapping({"material.materialize.bouncy": good + [broken]})["material.materialize.bouncy"]["exponent"]
        self.assertAlmostEqual(found["value"], 2.7, delta=0.06)
        self.assertEqual([e["take"] for e in found["excluded"]], ["d"])
        self.assertEqual(found["curves"], 3)

    def test_a_gain_of_zero_is_the_floor_not_a_failed_fit(self):
        found = fitvis.fit_mapping({"material.materialize.snappy": [curve("dark-photo", True, 0.5, 0.85, gain=0.0)]})["material.materialize.snappy"]["gain"]
        self.assertEqual(found["value"], 0.0)
        self.assertTrue(found["at_floor"])
        self.assertFalse(found["at_grid_edge"])

    def test_the_spread_across_takes_is_recorded(self):
        curves = {"material.materialize": [curve("dark-photo", False, 0.55, 1.0, 3.0, take="a"), curve("dark-photo", False, 0.55, 1.0, 3.4, take="b")]}
        found = fitvis.fit_mapping(curves)["material.materialize"]["exponent_spread"]
        self.assertAlmostEqual(found["min"], 3.0, delta=0.06)
        self.assertAlmostEqual(found["max"], 3.4, delta=0.06)
        self.assertEqual(sorted(found["per_take"]), ["a", "b"])

    def test_accessibility_cases_are_left_out_of_the_fit_and_every_backdrop_stays_in(self):
        self.assertTrue(fitvis.normal_case("light-stripes"))
        self.assertTrue(fitvis.normal_case("dark-photo"))
        self.assertFalse(fitvis.normal_case("dark-photo-reduce-motion"))
        self.assertTrue(fitvis.reduce_motion_case("dark-photo-reduce-motion"))
        self.assertFalse(fitvis.reduce_motion_case("dark-photo-increase-contrast"))

    def test_reduce_motion_gets_its_own_appear_gain_and_falls_back_to_the_normal_one(self):
        curves = {
            "material.materialize.bouncy": [curve("light-photo", True, 0.5, 0.7, gain=0.3)],
            "material.materialize.snappy": [curve("light-photo", True, 0.5, 0.85, gain=0.2)],
        }
        reduce_motion = {"material.materialize.bouncy": [curve("light-photo-reduce-motion", True, 0.5, 0.7, gain=0.7)]}
        mapping = fitvis.fit_mapping(curves, reduce_motion)
        bouncy, snappy = mapping["material.materialize.bouncy"], mapping["material.materialize.snappy"]
        self.assertAlmostEqual(bouncy["gain"]["value"], 0.3, delta=0.03)
        self.assertAlmostEqual(bouncy["reduce_motion_gain"]["value"], 0.7, delta=0.03)
        self.assertEqual(bouncy["reduce_motion_cases"], ["light-photo-reduce-motion"])
        self.assertEqual(snappy["reduce_motion_gain"]["value"], snappy["gain"]["value"])
        self.assertFalse(snappy["reduce_motion_gain"]["identifiable"])
        alone = fitvis.fit_mapping({"material.materialize.bouncy": curves["material.materialize.bouncy"]})["material.materialize.bouncy"]
        self.assertEqual(alone["reduce_motion_gain"]["value"], alone["gain"]["value"])
        self.assertFalse(alone["reduce_motion_gain"]["identifiable"])


class SpringCheckTests(unittest.TestCase):
    def test_native_at_swiftuis_default_passes_and_a_slower_case_fails_on_its_own(self):
        mapping = {"material.materialize": {"exponent": {"value": 3.2}, "gain": {"value": 1.0}}}
        good = [curve("dark-photo", True, 0.55, 1.0), curve("dark-photo", False, 0.55, 1.0, 3.2)]
        self.assertTrue(fitvis.spring_check(good, mapping)["pass"])
        slow = good + [curve("light-stripes", True, 0.64, 1.0), curve("light-stripes", False, 0.64, 1.0, 3.2)]
        check = fitvis.spring_check(slow, mapping)
        self.assertFalse(check["pass"])
        self.assertTrue(check["cases"]["dark-photo"]["pass"])
        self.assertFalse(check["cases"]["light-stripes"]["pass"])


class RampTests(unittest.TestCase):
    def test_native_sharpness_is_read_at_matched_progress(self):
        found = fitvis.native_sharpness([curve("dark-photo", True, 0.55, 1.0)])
        self.assertAlmostEqual(found["dark-photo"][0.5], -0.5, delta=0.05)

    def test_the_ramp_whose_flutter_sharpness_matches_native_is_chosen(self):
        native = {"dark-photo": {0.25: -0.4, 0.5: -0.5, 0.75: -0.4}}

        def rows(depth):
            return {"dark-photo": {v: (v, -depth * v * (1 - v) * 4) for v in (0.0, 0.25, 0.5, 0.75, 1.0)}}

        chosen = fitvis.choose_ramp(native, {1.0: rows(2.4), 2.0: rows(0.5), 3.0: rows(0.2)})
        self.assertEqual(chosen["value"], 2.0)
        self.assertFalse(chosen["at_grid_edge"])
        self.assertTrue(fitvis.choose_ramp(native, {1.0: rows(2.4), 2.0: rows(1.0)})["at_grid_edge"])


class TableTests(unittest.TestCase):
    def test_the_table_file_is_dart_the_package_reads(self):
        mapping = {
            "material.materialize": {"exponent": {"value": 3.2}, "gain": {"value": 0.55, "identifiable": False}},
            "material.materialize.bouncy": {"exponent": {"value": 2.65}, "gain": {"value": 0.6}},
        }
        source = fitvis.table_source(mapping, 2, [0.0, 0.5, 1.0])
        mapping["material.materialize"]["reduce_motion_gain"] = {"value": 0.8}
        self.assertIn("const double ios27DefaultReduceMotionAppearGain = 0.8;", fitvis.table_source(mapping, 2, [0.0, 0.5, 1.0]))
        self.assertIn("const double ios27BlurRampExponent = 2.0;", source)
        self.assertIn("const double ios27DefaultDisappearExponent = 3.2;", source)
        self.assertIn("const double ios27BouncyAppearGain = 0.6;", source)
        self.assertIn("const double ios27BouncyReduceMotionAppearGain = 0.6;", source)
        self.assertNotIn("Snappy", source)
        self.assertIn("const List<double> ios27VisibilityForProgress = [\n  0.0, 0.5, 1.0,\n];", source)

    def test_levels_span_zero_to_one(self):
        self.assertEqual(fitvis.levels(5), [0.0, 0.25, 0.5, 0.75, 1.0])


if __name__ == "__main__":
    unittest.main()
