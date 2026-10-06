import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import contextlib
import io
import json
import tempfile

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


CASES = ("dark-photo", "dark-stripes", "light-photo", "light-stripes")


def identity_rows(slopes=None, levels=(0.0, 0.25, 0.5, 0.75, 1.0, 1.05, 1.1, 1.2, 1.3)):
    slopes = slopes or {}
    return {case: {v: (v if v <= 1 else 1 + slopes.get(case, 1.0) * (v - 1), 0.0) for v in levels} for case in CASES}


def gains(mapping, scene="material.materialize.bouncy", key="gains"):
    return mapping[scene][key]


def tables(rows):
    progress = {case: {v: r[0] for v, r in found.items()} for case, found in rows.items()}
    return fitvis.invert(progress)[0], fitvis.invert_above(progress)[0]


class MappingTests(unittest.TestCase):
    def test_each_preset_keeps_its_swiftui_spring_and_gets_its_own_exponent_and_overshoot_gain(self):
        curves = {
            "material.materialize": [curve("dark-photo", True, 0.55, 1.0), curve("dark-photo", False, 0.55, 1.0, 3.2), curve("light-stripes", False, 0.55, 1.0, 3.2)],
            "material.materialize.bouncy": [curve("light-photo", True, 0.5, 0.7, gain=0.5), curve("dark-stripes", False, 0.5, 0.7, 2.7)],
        }
        rows = identity_rows()
        mapping = fitvis.fit_gains(fitvis.fit_mapping(curves), curves, {}, rows, *tables(rows))
        self.assertEqual(mapping["material.materialize"]["spring"], [0.55, 1.0])
        self.assertAlmostEqual(mapping["material.materialize"]["exponent"]["value"], 3.2, delta=0.06)
        self.assertAlmostEqual(mapping["material.materialize.bouncy"]["exponent"]["value"], 2.7, delta=0.06)
        self.assertAlmostEqual(gains(mapping)["pooled"]["value"], 0.5, delta=0.03)
        self.assertFalse(gains(mapping)["pooled"]["at_grid_edge"])
        self.assertTrue(gains(mapping, "material.materialize")["pooled"]["inert"])
        self.assertEqual(gains(mapping, "material.materialize")["pooled"]["value"], 0.0)
        self.assertEqual(gains(mapping, "material.materialize", "reduce_motion_gains")["pooled"]["value"], 0.0)
        self.assertIsNone(mapping["material.materialize.bouncy"]["reduce_motion_gains"])
        self.assertEqual(mapping["material.materialize"]["cases"], ["dark-photo", "light-stripes"])

    def test_a_curve_no_exponent_can_fit_is_left_out_and_reported(self):
        good = [curve("dark-photo", False, 0.5, 0.7, 2.7, take=t) for t in ("a", "b", "c")]
        broken = curve("dark-stripes", False, 0.5, 0.7, 2.7, take="d")
        broken["alpha"] = np.clip(broken["alpha"] + 0.6 * np.sin(np.arange(len(broken["alpha"]))), -1, 2)
        found = fitvis.fit_mapping({"material.materialize.bouncy": good + [broken]})["material.materialize.bouncy"]["exponent"]
        self.assertAlmostEqual(found["value"], 2.7, delta=0.06)
        self.assertEqual([e["take"] for e in found["excluded"]], ["d"])
        self.assertEqual(found["curves"], 3)

    def test_a_gain_of_zero_is_reported_as_the_floor(self):
        curves = {"material.materialize.snappy": [curve("dark-photo", True, 0.5, 1.0)]}
        rows = identity_rows()
        mapping = fitvis.fit_gains(fitvis.fit_mapping(curves), curves, {}, rows, *tables(rows))
        found = gains(mapping, "material.materialize.snappy")["pooled"]
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

    def test_reduce_motion_gets_its_own_appear_gain_and_none_without_its_recordings(self):
        curves = {"material.materialize.bouncy": [curve("light-photo", True, 0.5, 0.7, gain=0.3)]}
        reduce_motion = {"material.materialize.bouncy": [curve("light-photo-reduce-motion", True, 0.5, 0.7, gain=0.7)]}
        mapping = fitvis.fit_gains(fitvis.fit_mapping(curves, reduce_motion), curves, reduce_motion, identity_rows(), *tables(identity_rows()))
        bouncy = mapping["material.materialize.bouncy"]
        self.assertAlmostEqual(bouncy["gains"]["pooled"]["value"], 0.3, delta=0.03)
        self.assertAlmostEqual(bouncy["reduce_motion_gains"]["pooled"]["value"], 0.7, delta=0.03)
        self.assertEqual(bouncy["reduce_motion_cases"], ["light-photo-reduce-motion"])
        self.assertEqual(list(bouncy["reduce_motion_gains"]["cases"]), ["light-photo-reduce-motion"])
        alone = fitvis.fit_gains(fitvis.fit_mapping(curves), curves, {}, identity_rows(), *tables(identity_rows()))
        self.assertIsNone(alone["material.materialize.bouncy"]["reduce_motion_gains"])


class PeakGainTests(unittest.TestCase):
    def test_the_package_visibility_function_is_mirrored_with_its_table_above_full(self):
        table = [0.0, 0.2, 1.0]
        self.assertEqual(fitvis.visibility(0, table), 0.0)
        self.assertAlmostEqual(fitvis.visibility(0.25, table), 0.1)
        self.assertAlmostEqual(fitvis.visibility(0.75, table), 0.6)
        self.assertEqual(fitvis.visibility(1, table), 1.0)
        self.assertAlmostEqual(fitvis.visibility(1.05, table), 1.08)
        self.assertAlmostEqual(fitvis.visibility(1.25, table, [1.5]), 1.25)
        self.assertAlmostEqual(fitvis.visibility(1.5, table, [1.5]), 1.5)
        self.assertAlmostEqual(fitvis.visibility(2.0, table, [1.5]), 2.0)
        self.assertAlmostEqual(fitvis.visibility(1.75, table, [1.5, 1.8]), 1.65)
        self.assertAlmostEqual(fitvis.visibility(2.5, table, [1.5, 1.8]), 2.1)

    def test_the_table_above_full_inverts_flutters_mean_progress_above_visibility_one(self):
        progress = {"a": {0.0: 0.0, 1.0: 1.0, 1.1: 1.04, 1.2: 1.08, 1.3: 1.1}, "b": {0.0: 0.0, 1.0: 1.0, 1.1: 1.06, 1.2: 1.12, 1.3: 1.14}}
        above, mean = fitvis.invert_above(progress, grid=21)
        self.assertEqual(mean, [1.0, 1.05, 1.1, 1.12])
        self.assertEqual(above, [1.1, 1.2])
        self.assertEqual(fitvis.invert_above({"a": {0.0: 0.0, 1.0: 1.0}}), ([], []))

    def test_the_gain_is_fitted_on_the_overshoot_peak_against_flutters_realised_overshoot(self):
        target = 0.4 * fitvis.spring_overshoot(0.5, 0.7)
        curves = [curve(case, True, 0.5, 0.7, gain=0.4) for case in CASES]
        flat = {case: 0.5 for case in CASES}
        rows = identity_rows(flat)
        table, above = tables(rows)
        found = fitvis.peak_gains(curves, 0.5, 0.7, rows, table, above)
        self.assertAlmostEqual(found["pooled"]["value"], 0.4, delta=0.021)
        for case in CASES:
            self.assertAlmostEqual(found["pooled"]["flutter_overshoot"][case], target, delta=0.002)
            self.assertAlmostEqual(found["pooled"]["native_overshoot"][case], target, delta=0.002)
        naive = fitvis.realised_overshoot(rows, "dark-photo", 0.4, fitvis.spring_overshoot(0.5, 0.7), table, [])
        self.assertLess(naive, 0.7 * target)

    def test_every_case_is_fitted_and_reported_with_its_grid_edge_and_appearances_can_be_fitted_apart(self):
        curves = [curve("dark-photo", True, 0.5, 0.7, gain=0.6), curve("dark-stripes", True, 0.5, 0.7, gain=0.6), curve("light-photo", True, 0.5, 0.7, gain=0.2), curve("light-stripes", True, 0.5, 0.7, gain=1.6)]
        rows = identity_rows()
        found = fitvis.peak_gains(curves, 0.5, 0.7, rows, *tables(rows))
        self.assertEqual(sorted(found["cases"]), list(CASES))
        self.assertAlmostEqual(found["cases"]["dark-photo"]["value"], 0.6, delta=0.021)
        self.assertTrue(found["cases"]["light-stripes"]["at_grid_edge"])
        self.assertFalse(found["cases"]["dark-photo"]["at_grid_edge"])
        self.assertAlmostEqual(found["appearances"]["dark"]["value"], 0.6, delta=0.021)
        self.assertGreater(found["appearances"]["light"]["value"], found["appearances"]["dark"]["value"])
        self.assertEqual(found["case_spread"]["per_take"]["dark-photo"], found["cases"]["dark-photo"]["value"])
        self.assertEqual(set(found["take_spread"]["per_take"]), {"t0"})


class SpringCheckTests(unittest.TestCase):
    def test_native_at_swiftuis_default_passes_and_a_slower_case_fails_on_its_own(self):
        mapping = {"material.materialize": {"exponent": {"value": 3.2}, "gains": {"pooled": {"value": 1.0}}}}
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

        level = {"dark-photo": {t: [0.0] for t in fitvis.SHARPNESS_AT}}
        chosen = fitvis.choose_ramp(native, level, {1.0: rows(2.4), 2.0: rows(0.5), 3.0: rows(0.2)})
        self.assertEqual(chosen["value"], 2.0)
        self.assertFalse(chosen["at_grid_edge"])
        self.assertTrue(fitvis.choose_ramp(native, level, {1.0: rows(2.4), 2.0: rows(1.0)})["at_grid_edge"])

    def test_native_per_backdrop_deviation_is_read_at_the_same_point_of_the_transition(self):
        curves = {"material.materialize": [curve("dark-photo", True, 0.45, 1.0), curve("light-photo", True, 0.65, 1.0), curve("dark-photo", False, 0.45, 1.0, 3.0), curve("light-photo", False, 0.65, 1.0, 3.0)]}
        found = fitvis.native_deviation(curves)
        self.assertEqual(len(found["dark-photo"][0.5]), 2)
        self.assertGreater(found["dark-photo"][0.5][0], 0.05)
        self.assertLess(found["dark-photo"][0.5][1], -0.05)
        for target in fitvis.SHARPNESS_AT:
            for a, b in zip(found["dark-photo"][target], found["light-photo"][target]):
                self.assertAlmostEqual(a, -b, places=9)

    def test_the_ramp_objective_weighs_sharpness_by_its_limit_and_backdrop_deviation_by_0_05_and_prints_every_k(self):
        native_sharp = {case: {0.25: -1.0, 0.5: -1.0, 0.75: -1.0} for case in ("dark-photo", "light-photo")}
        native_dev = {"dark-photo": {0.25: [0.02], 0.5: [0.02], 0.75: [0.02]}, "light-photo": {0.25: [-0.02], 0.5: [-0.02], 0.75: [-0.02]}}

        def rows(sharpness, shift):
            levels = (0.0, 0.25, 0.5, 0.75, 1.0)
            return {
                "dark-photo": {v: (min(1.0, max(0.0, v + shift * 4 * v * (1 - v))), sharpness) for v in levels},
                "light-photo": {v: (min(1.0, max(0.0, v - shift * 4 * v * (1 - v))), sharpness) for v in levels},
            }

        sharp_only = rows(-1.5, -0.11)
        balanced = rows(-1.9, 0.02)
        table = {1.0: balanced, 3.0: sharp_only, 2.0: rows(-1.7, -0.05)}
        chosen = fitvis.choose_ramp(native_sharp, native_dev, table)
        self.assertEqual(chosen["value"], 1.0)
        self.assertTrue(chosen["at_grid_edge"])
        three = chosen["table"]["3.0"]
        self.assertAlmostEqual(three["sharpness_rms"], 0.5, places=6)
        self.assertGreater(three["progress_deviation_rms"], 0.05)
        self.assertAlmostEqual(three["objective"], three["sharpness_rms"] / 1.0 + three["progress_deviation_rms"] / 0.05, places=3)
        self.assertLess(chosen["table"]["1.0"]["objective"], three["objective"])
        self.assertEqual(list(chosen["table"]), ["1.0", "2.0", "3.0"])
        printed = "\n".join(fitvis.ramp_lines(chosen))
        for k in ("1.0", "2.0", "3.0"):
            self.assertIn(f"  {k} ", printed)
        self.assertIn("<- chosen", printed.splitlines()[2])


def fitted(value, **flags):
    return {"value": value, "at_grid_edge": False, "at_floor": False, **flags}


def complete_mapping(**changes):
    def preset(exponent, normal, reduce_motion):
        return {
            "exponent": fitted(exponent),
            "exponent_cases": {case: fitted(exponent) for case in CASES},
            "gains": {"pooled": normal, "appearances": {"dark": normal, "light": normal}, "cases": {case: normal for case in CASES}},
            "reduce_motion_gains": {"pooled": reduce_motion, "appearances": {"dark": reduce_motion, "light": reduce_motion}, "cases": {f"{case}-reduce-motion": reduce_motion for case in CASES}},
        }

    mapping = {
        "material.materialize": preset(3.1, dict(fitvis.INERT), dict(fitvis.INERT)),
        "material.materialize.snappy": preset(2.65, fitted(0.4), fitted(0.6)),
        "material.materialize.bouncy": preset(2.8, fitted(0.44), fitted(0.76)),
    }
    for path, value in changes.items():
        scene, *keys = path.split(":")
        target = mapping[scene]
        for key in keys[:-1]:
            target = target[key]
        target[keys[-1]] = value
    return mapping


def summary(mapping, **extra):
    return {
        "mapping": mapping,
        "gain_mode": "pooled",
        "blur_ramp": {"value": 2.0, "at_grid_edge": False, "table": {"1.0": {}, "2.0": {}, "3.0": {}}},
        "visibility_for_progress": [round(i / 20, 4) for i in range(21)],
        "visibility_above_full": [1.1, 1.2],
        **extra,
    }


class TableTests(unittest.TestCase):
    def test_the_table_file_is_dart_the_package_reads(self):
        source = fitvis.table_source(complete_mapping(), 2, [0.0, 0.5, 1.0], [1.1, 1.25])
        self.assertIn("const double ios27BlurRampExponent = 2.0;", source)
        self.assertIn("const double ios27DefaultDisappearExponent = 3.1;", source)
        self.assertIn("const double ios27DefaultDarkAppearGain = 0.0;", source)
        self.assertIn("const double ios27BouncyDarkAppearGain = 0.44;", source)
        self.assertIn("const double ios27BouncyLightAppearGain = 0.44;", source)
        self.assertIn("const double ios27BouncyDarkReduceMotionAppearGain = 0.76;", source)
        self.assertIn("const double ios27SnappyLightReduceMotionAppearGain = 0.6;", source)
        self.assertIn("const List<double> ios27VisibilityForProgress = [\n  0.0, 0.5, 1.0,\n];", source)
        self.assertIn("const List<double> ios27VisibilityAboveFull = [1.1, 1.25];", source)

    def test_the_table_carries_either_the_pooled_gain_or_one_gain_per_appearance(self):
        mapping = complete_mapping(**{"material.materialize.bouncy:gains:appearances": {"dark": fitted(0.3), "light": fitted(0.62)}})
        pooled = fitvis.table_source(mapping, 2, [0.0, 0.5, 1.0], [1.1], "pooled")
        split = fitvis.table_source(mapping, 2, [0.0, 0.5, 1.0], [1.1], "per-appearance")
        self.assertIn("const double ios27BouncyDarkAppearGain = 0.44;", pooled)
        self.assertIn("const double ios27BouncyLightAppearGain = 0.44;", pooled)
        self.assertIn("const double ios27BouncyDarkAppearGain = 0.3;", split)
        self.assertIn("const double ios27BouncyLightAppearGain = 0.62;", split)

    def test_an_unfitted_value_is_never_written_as_a_default(self):
        for broken in (complete_mapping(**{"material.materialize.bouncy:exponent": None}), complete_mapping(**{"material.materialize.snappy:reduce_motion_gains": None})):
            with self.assertRaises(ValueError):
                fitvis.table_source(broken, 2, [0.0, 0.5, 1.0], [1.1])
        partial = complete_mapping()
        del partial["material.materialize.snappy"]
        with self.assertRaises(ValueError):
            fitvis.table_source(partial, 2, [0.0, 0.5, 1.0], [1.1])

    def test_levels_span_zero_to_one(self):
        self.assertEqual(fitvis.levels(5), [0.0, 0.25, 0.5, 0.75, 1.0])


class WriteGuardTests(unittest.TestCase):
    def test_a_complete_interior_fit_has_no_problems_and_is_written(self):
        found = summary(complete_mapping())
        self.assertEqual(fitvis.write_problems(found), [])
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "ios27_motion.dart"
            fitvis.write_table(found, [], target)
            self.assertIn("ios27VisibilityAboveFull = [1.1, 1.2];", target.read_text())

    def test_every_unfitted_or_edge_value_is_named_and_the_write_refused(self):
        mapping = complete_mapping(**{
            "material.materialize.bouncy:exponent": None,
            "material.materialize.snappy:gains:pooled": fitted(0.0, at_floor=True),
            "material.materialize.bouncy:reduce_motion_gains:pooled": fitted(1.5, at_grid_edge=True),
            "material.materialize.snappy:exponent": fitted(6.0, at_grid_edge=True),
        })
        mapping["material.materialize.bouncy"]["gains"]["pooled"] = {"value": 0.44, "identifiable": False, "from": "the normal gain"}
        found = summary(mapping, blur_ramp={"value": 4.0, "at_grid_edge": True, "table": {"1.0": {}, "4.0": {}}}, visibility_above_full=[])
        problems = fitvis.write_problems(found)
        for name in ("ios27BouncyDisappearExponent: not fitted", "ios27SnappyDarkAppearGain = 0.0: on the grid floor", "ios27SnappyLightAppearGain = 0.0: on the grid floor",
                     "ios27BouncyDarkReduceMotionAppearGain = 1.5", "ios27SnappyDisappearExponent = 6.0", "ios27BouncyDarkAppearGain: not fitted",
                     "ios27BlurRampExponent = 4.0", "ios27VisibilityAboveFull: not fitted"):
            self.assertTrue(any(problem.startswith(name) for problem in problems), name)
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "ios27_motion.dart"
            with self.assertRaises(SystemExit) as caught:
                fitvis.write_table(found, problems, target)
            self.assertNotIn(caught.exception.code, (0, None))
            self.assertIn("ios27BouncyDisappearExponent: not fitted", str(caught.exception.code))
            self.assertFalse(target.exists())

    def test_a_per_case_fit_on_a_grid_edge_refuses_the_write_unless_named_in_an_override_which_is_recorded(self):
        mapping = complete_mapping()
        mapping["material.materialize.bouncy"]["reduce_motion_gains"]["cases"]["dark-stripes-reduce-motion"] = fitted(1.5, at_grid_edge=True)
        mapping["material.materialize.bouncy"]["gains"]["cases"]["light-stripes"] = fitted(0.0, at_floor=True)
        mapping["material.materialize.snappy"]["exponent_cases"]["dark-photo"] = fitted(1.0, at_grid_edge=True)
        found = summary(mapping)
        labels = ["material.materialize.bouncy/reduce_motion_gain/dark-stripes-reduce-motion", "material.materialize.bouncy/gain/light-stripes", "material.materialize.snappy/exponent/dark-photo"]
        problems = fitvis.write_problems(found)
        self.assertEqual(len(problems), 3)
        for label in labels:
            self.assertTrue(any(problem.startswith(label) for problem in problems), label)
        recorded = []
        self.assertEqual(fitvis.write_problems(found, labels[:2], recorded), [p for p in problems if p.startswith(labels[2])])
        self.assertEqual(sorted(recorded), sorted(labels[:2]))
        self.assertEqual(fitvis.write_problems(found, labels), [])

    def test_the_inert_default_gain_is_written_and_never_called_unfitted(self):
        found = summary(complete_mapping())
        self.assertFalse([p for p in fitvis.write_problems(found) if "Default" in p])
        self.assertIn("const double ios27DefaultLightReduceMotionAppearGain = 0.0;", fitvis.table_source(found["mapping"], 2, [0.0, 0.5, 1.0], [1.1]))

    def test_levels_span_zero_to_one(self):
        self.assertEqual(fitvis.levels(5), [0.0, 0.25, 0.5, 0.75, 1.0])


if __name__ == "__main__":
    unittest.main()
