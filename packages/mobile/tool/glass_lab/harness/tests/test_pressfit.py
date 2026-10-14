import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pressfit
import springfit


def case(height, grow):
    return {"size": (250.0, height, "capsule"), "features": {"grow_w": grow * 1.09}, "plateau": grow}


def spring_case(height, settled, response=0.26, damping=0.615):
    times = np.concatenate([[0.0], np.arange(0.5, 1.5 + 1e-9, 1 / 120)])
    shares = np.where(times >= 0.55, springfit.step_response(np.maximum(times - 0.55, 0.0), response, damping), 0.0)
    rows = {"times": times.tolist(), "width": (250.0 + settled * shares).tolist()}
    found = {"key": "k", "times": times, "rows": rows, "down": 0.5, "up": 1.5, "size": (250.0, height, "capsule")}
    found["plateau"] = pressfit.plateau(found)
    found["features"] = {"grow_w": float(settled * shares.max())}
    return found


class PressFitTests(unittest.TestCase):
    def test_a_height_law_is_recovered_with_its_cap_and_no_width_term(self):
        cases = [case(h, min(16.0, 1000.0 / h)) for h in (44, 53, 58, 88, 120, 200)]
        found = pressfit.fit_growth_law(cases)
        height = found["forms"]["height"]
        self.assertAlmostEqual(height["cap"], 16.0, places=2)
        self.assertAlmostEqual(height["at_100"], 10.0, places=2)
        self.assertEqual(height["power"], 1.0)
        self.assertLess(height["rms"], 1e-6)
        self.assertEqual(pressfit.law_value(height, 250, 44), 16.0)
        self.assertEqual(pressfit.law_value(height, 44, 44), 16.0)
        self.assertTrue(found["within"])

    def test_a_law_in_width_and_height_is_recovered_on_portrait_and_landscape_sizes(self):
        sizes = ((58, 58), (138, 53), (250, 44), (250, 88), (300, 120), (250, 150), (360, 200), (300, 250), (120, 250), (88, 200), (360, 100))
        law = lambda w, h: min(16.0, 9.0 * (100.0 / h) ** 1.2 * (100.0 / w) ** 0.3)
        cases = [{"size": (float(w), float(h), "capsule"), "features": {}, "plateau": law(w, h)} for w, h in sizes]
        found = pressfit.fit_growth_law(cases)
        both = found["forms"]["height_width"]
        self.assertAlmostEqual(both["power"], 1.2, delta=0.011)
        self.assertAlmostEqual(both["width_power"], 0.3, delta=0.051)
        self.assertFalse(found["forms"]["height"]["within"])
        self.assertEqual(found["chosen"], "height_width")
        self.assertGreater(pressfit.law_value(both, 120, 250), pressfit.law_value(both, 300, 250))
        self.assertGreater(pressfit.law_value(both, 360, 100), pressfit.law_value(both, 100, 360))

    def test_the_law_is_fitted_on_the_settled_growth_so_a_spring_overshoot_is_not_counted_twice(self):
        cases = [spring_case(h, min(16.0, 1000.0 / h)) for h in (44, 53, 58, 88, 120, 200)]
        self.assertGreater(cases[0]["features"]["grow_w"], 16.0 * 1.05)
        self.assertAlmostEqual(cases[0]["plateau"], 16.0, delta=0.05)
        found = pressfit.fit_growth_law(cases)["forms"]["height"]
        self.assertAlmostEqual(found["cap"], 16.0, delta=0.06)
        self.assertAlmostEqual(found["at_100"], 10.0, delta=0.05)

    def test_the_glow_rings_leave_out_pixels_outside_the_glass(self):
        scale = 3
        height, width = 88 * scale, 250 * scale
        change = np.full((height, width), 20.0)
        ys, xs = np.mgrid[0:height, 0:width]
        x, y = (xs + 0.5) / scale - 125, (ys + 0.5) / scale - 44
        change[~pressfit.inside_shape(x, y, 250, 88, "capsule")] = 0.0
        found = pressfit.rings(change, 250, 88, "capsule", scale)
        self.assertTrue(all(abs(value - 20.0) < 1e-9 for _, value in found))
        self.assertGreater(max(d for d, _ in found), 120)

    def test_the_cut_is_read_per_size_and_a_size_without_one_takes_its_nearest(self):
        fits = [
            ({"size": (58.0, 58.0, "circle")}, {"hold_level": 11.0, "swell": 40.0, "cut_ms": 620.0}),
            ({"size": (250.0, 88.0, "capsule")}, {"hold_level": 11.0, "swell": 9.0, "cut_ms": 405.0}),
            ({"size": (360.0, 200.0, "rect32")}, {"hold_level": 0.0, "swell": 5.0, "cut_ms": None}),
        ]
        table = pressfit.size_table(fits, 86.0)
        self.assertEqual([row["cut_ms"] for row in table], [620.0, 405.0, 405.0])
        self.assertEqual(table[2]["cut_from"], [250.0, 88.0])

    def test_problems_name_spring_fits_on_the_grid_edge_and_a_thin_reduce_motion_cut(self):
        summary = {
            "law": {"on_edge": False},
            "growth": {"response": 0.26},
            "release": {"response": 0.33},
            "glow": {"rise_response": 0.06, "hold_ms": 57.0, "fade_response": 0.38, "cut_ms": 422.0, "reduce_motion_cut_ms": 570.0, "reduce_motion_presses": 3},
            "sigma": {"on_edge": False},
            "sizes": [{}],
            "edge_share": 0.5,
        }
        found = pressfit.problems(summary)
        self.assertTrue(any("grid edge" in p for p in found))
        self.assertTrue(any("3 presses" in p for p in found))
        clean = dict(summary, edge_share=0.1, glow=dict(summary["glow"], reduce_motion_presses=5))
        self.assertEqual(pressfit.problems(clean), [])

    def test_a_form_that_misses_a_measured_size_by_more_than_the_size_threshold_is_not_chosen(self):
        sizes = ((58, 58), (138, 53), (250, 44), (250, 88), (250, 88), (250, 88), (300, 120), (250, 150), (360, 200), (300, 250))
        cases = [{"size": (float(w), float(h), "capsule"), "features": {}, "plateau": min(15.84, 9.69 * (100.0 / h) ** 1.6)} for w, h in sizes]
        found = pressfit.fit_growth_law(cases)
        self.assertFalse(found["forms"]["area"]["within"])
        self.assertTrue(found["forms"]["height"]["within"])
        self.assertIn(found["chosen"], ("height", "height_width"))
        self.assertTrue(all(abs(r) <= pressfit.SIZE_LIMIT for r in found["residuals"].values()))

    def test_problems_name_a_law_with_a_height_outside_the_size_threshold(self):
        summary = {
            "law": {"on_edge": False, "within": False},
            "growth": {"response": 0.26},
            "release": {"response": 0.33},
            "glow": {"rise_response": 0.06, "hold_ms": 57.0, "fade_response": 0.38, "cut_ms": 422.0, "reduce_motion_cut_ms": 570.0, "reduce_motion_presses": 5},
            "sigma": {"on_edge": False},
            "sizes": [{}],
            "edge_share": 0.1,
        }
        self.assertTrue(any("within" in p for p in pressfit.problems(summary)))

    def test_the_law_reads_every_take_s_plateau_holed_or_not(self):
        times = [0.0] + [0.5 + k / 60 for k in range(70)]
        width = [250.0] + [262.0] * 70
        entry = lambda hole: {
            "touches": [[0.5, 1.6]],
            "takecheck": {"failures": ["capture hole"] if hole else []},
            "steps": {"step1": {"glass": {"hole": hole}}},
            "series": {"glass": {"times": times, "width": width, "height": [88.0] * 71, "glow": [100.0] * 71, "cx": [201.0] * 71, "cy": [451.0] * 71}},
        }
        series = {"material.interactive/dark-photo/a": entry(True), "material.interactive/light-photo/b": entry(False), "material.interactive/dark-stripes/c": entry(False)}
        found = list(pressfit.plateaus(series))
        self.assertEqual(sorted(c["key"] for c in found), ["material.interactive/dark-photo/a", "material.interactive/light-photo/b"])
        self.assertTrue(all(abs(c["plateau"] - 12.0) < 1e-9 for c in found))
        self.assertEqual([c["key"] for c in pressfit.presses(series)], ["material.interactive/light-photo/b", "material.interactive/dark-stripes/c"])

    def test_the_glow_profile_is_the_median_of_its_takes(self):
        profiles = [{"take": str(k), "box_pt": [250, 88], "shape": "capsule", "profile": [(0.5, 20.0 + k), (1.5, 18.0 + k)], "hold_level": 11.0 + k} for k in range(3)]
        found = pressfit.median_profile(profiles)
        self.assertEqual(found["profile"], [(0.5, 21.0), (1.5, 19.0)])
        self.assertEqual(found["hold_level"], 12.0)

    def test_a_profile_key_names_its_native_take(self):
        self.assertEqual(pressfit.profile_take("runs", "material.interactive/dark-photo-reduce-motion/20261009-085013"), Path("runs/20261009-085013/material.interactive/dark-photo-reduce-motion/native"))

    def test_a_spring_is_recovered_without_renormalising_its_end(self):
        t = np.arange(0.0, 0.4, 1 / 120)
        values = springfit.step_response(t, 0.3, 0.7)
        found = pressfit.fit_raw(t, values)
        self.assertAlmostEqual(found["response"], 0.3, places=2)
        self.assertAlmostEqual(found["damping"], 0.7, places=2)

    def test_a_glow_that_jumps_then_settles_is_fitted_with_its_jump(self):
        t = np.concatenate([[0.0], np.arange(1 / 120, 0.6, 1 / 120)])
        values = 0.6 + 0.4 * springfit.step_response(t, 0.2, 1.0)
        values[0] = 0.0
        found = pressfit.fit_jump(t, values)
        self.assertAlmostEqual(found["jump"], 0.6, places=2)
        self.assertAlmostEqual(found["response"], 0.2, places=2)

    def test_the_reach_is_the_time_the_spring_takes_to_a_share(self):
        spring = {"response": 0.3, "damping": 1.0}
        reached = pressfit.reach(spring, 0.5)
        self.assertAlmostEqual(float(springfit.step_response(reached, 0.3, 1.0)), 0.5, delta=0.01)

    def test_the_glow_width_is_recovered_from_a_ring_profile(self):
        profile = [(d + 0.5, 11.0 + 14.0 * np.exp(-((d + 0.5) ** 2) / (2 * 61.0**2))) for d in range(0, 120)]
        found = pressfit.fit_sigma(profile, 11.0)
        self.assertEqual(found["sigma"], 61.0)
        self.assertAlmostEqual(found["peak"], 14.0, places=3)

    def test_a_gaussian_much_wider_than_the_glass_averages_to_one(self):
        self.assertAlmostEqual(pressfit.gaussian_mean(10, 10, 1000.0, shape="circle"), 1.0, places=4)
        self.assertLess(pressfit.gaussian_mean(360, 200, 61.0, shape="rect32"), pressfit.gaussian_mean(58, 58, 61.0, shape="circle"))

    def test_write_refuses_a_summary_with_problems_and_writes_one_without(self):
        summary = {
            "law": {"cap": 16.78, "at_100": 10.15, "power": 1.0, "on_edge": False},
            "growth": {"delay": 0.05, "response": 0.26, "damping": 0.6},
            "release": {"delay": 0.02, "response": 0.33, "damping": 0.6},
            "glow": {"rise_jump": 0.0, "rise_response": 0.06, "rise_damping": 1.9, "hold_ms": 57.0, "fade_response": 0.38, "fade_damping": 1.05, "cut_ms": 422.0, "reduce_motion_cut_ms": 570.0, "reduce_motion_presses": 5},
            "sigma": {"sigma": 61.0, "on_edge": False},
            "edge_share": 0.0,
            "sizes": [{"area": 3364.0, "hold": 11.0, "swell_peak": 39.0, "cut_ms": 620.0}, {"area": 72000.0, "hold": 0.0, "swell_peak": 15.0, "cut_ms": 400.0}],
        }
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "ios27_press.dart"
            pressfit.write_table(summary, target)
            text = target.read_text()
            self.assertIn("const double ios27PressGrowthCap = 16.78;", text)
            self.assertIn("const List<double> ios27PressGlowAreas = [3364.0, 72000.0];", text)
            broken = dict(summary, glow=dict(summary["glow"], cut_ms=None))
            with self.assertRaises(SystemExit):
                pressfit.write_table(broken, Path(folder) / "other.dart")
            self.assertFalse((Path(folder) / "other.dart").exists())


    def test_a_refit_where_no_form_keeps_every_size_within_the_threshold_writes_nothing(self):
        grown = {(58, 58): 16.0, (250, 88): 11.0, (250, 120): 3.0, (250, 150): 9.0, (250, 200): 2.0, (300, 250): 7.0}
        cases = [{"size": (float(w), float(h), "capsule"), "features": {}, "plateau": g} for (w, h), g in grown.items()]
        law = pressfit.fit_growth_law(cases)
        self.assertFalse(any(form["within"] for form in law["forms"].values()))
        self.assertFalse(law["within"])
        summary = {
            "law": law,
            "growth": {"delay": 0.05, "response": 0.26, "damping": 0.6},
            "release": {"delay": 0.02, "response": 0.33, "damping": 0.6},
            "glow": {"rise_jump": 0.0, "rise_response": 0.06, "rise_damping": 1.9, "hold_ms": 57.0, "fade_response": 0.38, "fade_damping": 1.05, "cut_ms": 422.0, "reduce_motion_cut_ms": 570.0, "reduce_motion_presses": 5},
            "sigma": {"sigma": 61.0, "on_edge": False},
            "edge_share": 0.0,
            "sizes": [{"area": 3364.0, "hold": 11.0, "swell_peak": 39.0, "cut_ms": 620.0}],
        }
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "ios27_press.dart"
            target.write_text("shipped\n")
            with self.assertRaises(SystemExit) as stopped:
                pressfit.write_table(summary, target)
            self.assertIn("within", str(stopped.exception))
            self.assertEqual(target.read_text(), "shipped\n")

if __name__ == "__main__":
    unittest.main()
