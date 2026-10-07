import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import analyze
import manifest
import metrics
import shapes
import springfit
from synthetic import capture_of, glass_pair, spring_series


class ShapeTopologyTests(unittest.TestCase):
    @staticmethod
    def series(join, split, length=80, neck=10.0, gap=6.0):
        nan = float("nan")
        count = [2.0] * join + [1.0] * (split - join) + [2.0] * (length - split)
        necks = [nan] * join + [neck] * (split - join) + [nan] * (length - split)
        gaps = [gap] * join + [nan] * (split - join) + [gap] * (length - split)
        return {"count": count, "neck": necks, "gap": gaps}

    def test_join_and_split_times_and_count_mismatches_are_compared(self):
        late = shapes.compare_topology(self.series(20, 60), self.series(23, 60))
        self.assertAlmostEqual(late["join_ms"], 25, places=6)
        self.assertEqual(late["split_ms"], 0)
        self.assertEqual(late["count"], 0.0)
        self.assertEqual(late["neck_rms"], 0.0)
        stuck = shapes.compare_topology(self.series(20, 60), self.series(23, 80))
        self.assertEqual(stuck["split_ms"], float("inf"))
        self.assertEqual(stuck["count"], 17.0)

    def test_the_neck_is_compared_only_where_both_apps_have_one(self):
        wider = shapes.compare_topology(self.series(20, 60), self.series(20, 60, neck=13.0))
        self.assertAlmostEqual(wider["neck_rms"], 3.0, places=6)
        late = shapes.compare_topology(self.series(20, 60), self.series(23, 60, neck=13.0))
        self.assertAlmostEqual(late["neck_rms"], 3.0, places=6)

    def test_the_gap_is_compared_only_where_both_apps_have_one(self):
        same = shapes.compare_topology(self.series(20, 60), self.series(20, 60))
        self.assertEqual(same["gap_rms"], 0.0)
        wider = shapes.compare_topology(self.series(20, 60), self.series(20, 60, gap=9.0))
        self.assertAlmostEqual(wider["gap_rms"], 3.0, places=6)
        late = shapes.compare_topology(self.series(20, 60), self.series(23, 60, gap=9.0))
        self.assertAlmostEqual(late["gap_rms"], 3.0, places=6)

    def test_a_gap_in_one_app_against_none_in_the_other_fails_and_agreeing_apps_read_zero(self):
        nan = float("nan")
        one = {"count": [1.0] * 5, "neck": [5.0] * 5, "gap": [nan] * 5}
        self.assertEqual(shapes.compare_topology(one, one)["gap_rms"], 0.0)
        found = shapes.compare_topology(one, {"count": [1.0] * 5, "neck": [5.0] * 5, "gap": [4.0] * 5})
        self.assertEqual(found["gap_rms"], float("inf"))

    def test_a_series_without_a_gap_has_no_gap_measure(self):
        plain = {"count": [1.0] * 5, "neck": [5.0] * 5}
        self.assertNotIn("gap_rms", shapes.compare_topology(plain, plain))

    def test_gap_rms_has_the_gap_threshold(self):
        self.assertEqual(shapes.LIMITS["gap_rms"], "gap_pt")
        self.assertEqual(metrics.THRESHOLDS["gap_pt"], 1.0)

    def test_apps_that_agree_on_no_transition_read_zero_not_absent(self):
        one = {"count": [1.0] * 5, "neck": [5.0] * 5}
        agreed = shapes.compare_topology(one, one)
        self.assertEqual((agreed["join_ms"], agreed["split_ms"], agreed["count"], agreed["neck_rms"]), (0.0, 0.0, 0.0, 0.0))
        apart = {"count": [2.0] * 5, "neck": [float("nan")] * 5}
        both_apart = shapes.compare_topology(apart, apart)
        self.assertEqual((both_apart["join_ms"], both_apart["split_ms"], both_apart["count"], both_apart["neck_rms"]), (0.0, 0.0, 0.0, 0.0))
        empty = {"count": [0.0] * 5, "neck": [float("nan")] * 5}
        self.assertEqual(shapes.compare_topology(empty, empty)["neck_rms"], 0.0)

    def test_a_transition_in_one_app_only_fails(self):
        joined = shapes.compare_topology(self.series(20, 80), {"count": [2.0] * 80, "neck": [float("nan")] * 80})
        self.assertEqual(joined["join_ms"], float("inf"))
        self.assertEqual(joined["split_ms"], 0.0)

    def test_one_component_without_a_neck_against_one_with_a_neck_fails(self):
        nan = float("nan")
        found = shapes.compare_topology({"count": [1.0] * 5, "neck": [nan] * 5}, {"count": [1.0] * 5, "neck": [4.0] * 5})
        self.assertEqual(found["neck_rms"], float("inf"))

    def test_a_listed_topology_measure_is_present_when_both_apps_agree(self):
        scene = manifest.parse([{"id": "x", "group": "material", "title": "t", "inventory": "2.14", "app": "lab", "backdrops": ["stripes"], "appearances": ["dark"], "steps": [{"tap": "merge"}], "regions": {"pair": [0, 0, 10, 10]}, "track": "pair", "topology": "pair", "motion": ["topology.join_ms", "topology.neck_rms"]}])[0]
        one = {"count": [1.0] * 5, "neck": [5.0] * 5}
        result = {"pairs": {"step0e0": {"shapes": {"pair": {"topology": shapes.compare_topology(one, one)}}}}, "event_count": [1, 1], "steps": [[0], [0]], "touches": [0, 0], "expected_touches": 0}
        found = shapes.limits(result, scene)
        self.assertEqual(found["pair.step0e0.topology.join_ms"][0], 0.0)
        self.assertEqual(found["pair.step0e0.topology.neck_rms"][0], 0.0)

    def test_still_necks_agree_when_neither_app_has_one(self):
        nan = float("nan")
        self.assertEqual(shapes.neck_difference({"count": 2.0, "neck": nan}, {"count": 2.0, "neck": nan}), 0.0)
        self.assertAlmostEqual(shapes.neck_difference({"count": 1.0, "neck": 25.33}, {"count": 1.0, "neck": 24.0}), 1.33, places=6)
        self.assertEqual(shapes.neck_difference({"count": 1.0, "neck": 2.0}, {"count": 2.0, "neck": nan}), float("inf"))
        self.assertEqual(shapes.neck_difference({"count": 1.0, "neck": nan}, {"count": 1.0, "neck": 4.0}), float("inf"))

    def test_still_gaps_compare_like_necks(self):
        nan = float("nan")
        self.assertEqual(shapes.gap_difference({"gap": nan}, {"gap": nan}), 0.0)
        self.assertAlmostEqual(shapes.gap_difference({"gap": 3.0}, {"gap": 2.33}), 0.67, places=6)
        self.assertEqual(shapes.gap_difference({"gap": 3.0}, {"gap": nan}), float("inf"))

    def test_static_topology_reads_the_gap_between_two_shapes(self):
        scene = manifest.parse([{"id": "x", "group": "material", "title": "t", "inventory": "2.14", "app": "lab", "backdrops": ["black"], "appearances": ["light"], "steps": [{"wait": 0.5}], "regions": {"g20": [0, 0, 240, 120], "g4": [0, 0, 240, 120]}, "topology": ["g20"]}])[0]
        bare = np.zeros((360, 720, 3), dtype=np.float32)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for app, gap in (("native", 20), ("flutter", 18)):
                (root / app / "bare").mkdir(parents=True)
                Image.fromarray(bare.astype(np.uint8)).save(root / app / "bare" / "ready.png")
                Image.fromarray(glass_pair(bare, gap, gain=0.0, lift=130.0, rim=0.0).astype(np.uint8)).save(root / app / "ready.png")
            found = shapes.static_topology(scene, root / "native", root / "flutter")["g20"]
        self.assertAlmostEqual(found["native"]["gap"], 20, delta=0.67)
        self.assertAlmostEqual(found["flutter"]["gap"], 18, delta=0.67)
        self.assertAlmostEqual(found["gap_pt"], 2, delta=0.67)
        self.assertEqual(found["count"], 0.0)
        self.assertEqual(found["neck_pt"], 0.0)

    def test_still_topology_measures_include_the_gap_with_its_own_threshold(self):
        topology = {"g20": {"count": 0.0, "neck_pt": 0.0, "gap_pt": 0.67}}
        found = analyze.topology_measures(topology, {})
        self.assertEqual(found["ready.topology.g20.gap_pt"], (0.67, 1.0, "max"))
        self.assertEqual(found["ready.topology.g20.neck_pt"], (0.0, 1.0, "max"))
        self.assertEqual(found["ready.topology.g20.count"], (0.0, 0.0, "max"))
        noisy = analyze.topology_measures(topology, {"ready.topology.g20.gap_pt": 1.0})
        self.assertEqual(noisy["ready.topology.g20.gap_pt"][1], 1.5)

    def test_the_neck_series_holds_each_frame_like_the_count(self):
        nan = float("nan")
        rows = [{"count": 2.0, "neck": nan}, {"count": 1.0, "neck": 6.0}, {"count": 1.0, "neck": 8.0}, {"count": 2.0, "neck": nan}]
        rows = [dict(row, gap=[3.0, nan, nan, 3.0][i], width=80.0, height=80.0, cx=1.0, cy=1.0, xmin=0.0, xmax=1.0, ymin=0.0, ymax=1.0, luma=1.0, progress=1.0, sharpness=0.0, residual=0.0) for i, row in enumerate(rows)]
        series = shapes.event_series([0.0, 0.05, 0.1, 0.15], rows, 0, 3)
        count, neck, gap = np.array(series["count"]), np.array(series["neck"]), np.array(series["gap"])
        self.assertTrue(np.isnan(neck[count == 2]).all())
        self.assertTrue(np.isfinite(neck[count == 1]).all())
        self.assertTrue(np.isnan(gap[count == 1]).all())
        self.assertTrue(np.isfinite(gap[count == 2]).all())


class ProgressMeasureTests(unittest.TestCase):
    def test_ten_to_ninety_matches_the_spring(self):
        features = shapes.progress_features(spring_series(0.55, 1.0))
        self.assertAlmostEqual(features["t10_90_ms"], 294, delta=9)
        leaving = shapes.progress_features(spring_series(0.55, 1.0, appearing=False, exponent=3.2))
        self.assertLess(leaving["t10_90_ms"], 170)

    def test_a_variable_rate_capture_reads_the_same_ten_to_ninety_time_within_a_frame(self):
        rng = np.random.default_rng(7)
        times = np.cumsum(np.concatenate([[0.0], rng.choice([1 / 120, 1 / 60, 0.033, 0.053], 40)]))
        rows = [{"width": 250.0, "height": 88.0, "cx": 201.0, "cy": 451.0, "xmin": 76.0, "xmax": 326.0, "ymin": 407.0, "ymax": 495.0, "luma": 100.0, "progress": float(p), "sharpness": 0.0, "residual": 0.0}
                for p in springfit.step_response(times, 0.55, 1.0)]
        series = shapes.event_series(list(times), rows, 0, len(times) - 1)
        exact = shapes.progress_features(spring_series(0.55, 1.0))["t10_90_ms"]
        self.assertAlmostEqual(shapes.progress_features(series)["t10_90_ms"], exact, delta=1000 / 120)

    def test_overshoot_is_read_in_points_of_percent(self):
        self.assertGreater(shapes.progress_features(spring_series(0.5, 0.7))["overshoot_pct"], 3)
        self.assertEqual(shapes.progress_features(spring_series(0.55, 1.0))["overshoot_pct"], 0.0)

    def test_identical_captures_measure_zero(self):
        scene = manifest.parse([{
            "id": "material.materialize", "group": "material", "title": "t", "inventory": "2.13", "app": "lab",
            "backdrops": ["stripes"], "appearances": ["dark"], "steps": [{"wait": 0.5}, {"tap": "toggle"}],
            "regions": {"block": [70, 400, 262, 104]}, "track": ["block"], "motion": ["progress.t10_90_ms", "progress.rms"],
        }])[0]
        a = capture_of(spring_series(0.55, 1.0, False, 3.2), spring_series(0.55, 1.0))
        result = shapes.compare(scene, a, a)
        found = shapes.measures(result)
        self.assertEqual(found["block.event0.progress.t10_90_ms"], 0.0)
        self.assertEqual(found["block.event1.progress.rms"], 0.0)
        limits = shapes.limits(result, scene)
        self.assertEqual(set(limits), {"events.native_motion", "events.unpaired", "touches.native", "touches.flutter", "block.event0.progress.t10_90_ms", "block.event0.progress.rms", "block.event1.progress.t10_90_ms", "block.event1.progress.rms", "block.step1e0.progress.t10_90_ms", "block.step1e0.progress.rms"})
        self.assertEqual(limits["block.event0.progress.rms"], (0.0, 0.05, "max"))
        self.assertEqual(limits["block.step1e0.progress.rms"], (float("inf"), 0.05, "max"))

    def test_a_slower_flutter_appear_fails_and_noise_raises_the_limit(self):
        scene = manifest.parse([{
            "id": "x", "group": "material", "title": "t", "inventory": "2.13", "app": "lab",
            "backdrops": ["stripes"], "appearances": ["dark"], "steps": [{"tap": "toggle"}],
            "regions": {"block": [0, 0, 10, 10]}, "track": "block", "motion": ["progress.t10_90_ms"],
        }])[0]
        result = shapes.compare(scene, capture_of(spring_series(0.55, 1.0)), capture_of(spring_series(0.7, 1.0)))
        value, limit, _ = shapes.limits(result, scene)["block.event0.progress.t10_90_ms"]
        self.assertGreater(value, 17)
        self.assertEqual(limit, 17)
        _, raised, _ = shapes.limits(result, scene, {"block.event0.progress.t10_90_ms": 100})["block.event0.progress.t10_90_ms"]
        self.assertEqual(raised, 150)

    def test_events_pair_by_the_step_that_caused_them(self):
        scene = manifest.parse([{
            "id": "x", "group": "material", "title": "t", "inventory": "2.13", "app": "lab",
            "backdrops": ["stripes"], "appearances": ["dark"], "steps": [{"tap": "a"}, {"tap": "b"}],
            "regions": {"block": [0, 0, 10, 10]}, "track": ["block"], "motion": ["progress.rms"],
        }])[0]
        native = capture_of(spring_series(0.55, 1.0, False, 3.2), spring_series(0.55, 1.0), steps=[0, 1])
        flutter = capture_of(spring_series(0.55, 1.0), steps=[1])
        result = shapes.compare(scene, native, flutter)
        self.assertEqual(list(result["pairs"]), ["step1e0"])
        self.assertEqual(shapes.measures(result)["block.step1e0.progress.rms"], 0.0)
        self.assertEqual(shapes.limits(result, scene)["events.steps"], (1, 0, "max"))


class NothingPassesByBeingAbsentTests(unittest.TestCase):
    def scene(self, motion=("progress.t10_90_ms", "progress.rms", "progress.response_pct", "progress.damping"), steps=None):
        return manifest.parse([{
            "id": "x", "group": "material", "title": "t", "inventory": "2.13", "app": "lab",
            "backdrops": ["stripes"], "appearances": ["dark"], "steps": steps or [{"tap": "a"}, {"tap": "b"}],
            "regions": {"block": [0, 0, 10, 10]}, "track": ["block"], "motion": list(motion),
        }])[0]

    def test_an_extra_flutter_event_is_unpaired_and_fails(self):
        scene = self.scene()
        native = capture_of(spring_series(0.55, 1.0, False, 3.2), spring_series(0.55, 1.0), steps=[0, 1])
        flutter = capture_of(spring_series(0.55, 1.0, False, 3.2), spring_series(0.55, 1.0), spring_series(0.5, 0.5), steps=[0, 1, 1])
        result = shapes.compare(scene, native, flutter)
        self.assertEqual(result["unpaired"], {"native": 0, "flutter": 1})
        self.assertEqual(shapes.limits(result, scene)["events.unpaired"], (1, 0, "max"))
        self.assertFalse(analyze.within(*shapes.limits(result, scene)["events.unpaired"]))

    def test_a_missing_progress_entry_fails_as_infinite(self):
        scene = self.scene()
        flat = spring_series(0.55, 1.0)
        flat["progress"] = np.full_like(flat["progress"], 0.5)
        native = capture_of(spring_series(0.55, 1.0), steps=[0])
        flutter = capture_of(flat, steps=[0])
        result = shapes.compare(scene, native, flutter)
        self.assertNotIn("progress", result["pairs"]["step0e0"]["shapes"]["block"])
        limits = shapes.limits(result, scene)
        for measure in ("t10_90_ms", "rms", "response_pct", "damping"):
            value, _, _ = limits[f"block.step0e0.progress.{measure}"]
            self.assertEqual(value, float("inf"))
            self.assertFalse(analyze.within(*limits[f"block.step0e0.progress.{measure}"]))

    def test_a_spring_fit_on_its_grid_edge_is_reported_and_fails(self):
        entry = {}
        shapes.apply_spring_fits(entry, {"response": 0.38, "damping": 2.0, "rms": 0.01, "at_grid_edge": True}, {"response": 0.4, "damping": 1.0, "rms": 0.01, "at_grid_edge": False})
        self.assertEqual(entry["fit_invalid"], {"native": "at the grid edge"})
        self.assertEqual((entry["response_pct"], entry["damping"]), (float("inf"), float("inf")))

    def test_a_value_on_its_limit_passes_whatever_the_float_rounding(self):
        self.assertTrue(analyze.within(abs(1.06 - 1.01), 0.05, "max"))
        self.assertTrue(analyze.within(0.7 - 0.6, 0.1, "min"))
        self.assertFalse(analyze.within(0.0501, 0.05, "max"))
        self.assertFalse(analyze.within(float("inf"), 0.05, "max"))

    def test_a_step_both_apps_miss_fails_every_measure_it_lists(self):
        scene = self.scene(steps=[{"wait": 0.5}, {"tap": "a"}, {"wait": 1.2}, {"tap": "b"}, {"wait": 1.2}])
        native = capture_of(spring_series(0.55, 1.0, False, 3.2), steps=[1])
        flutter = capture_of(spring_series(0.55, 1.0, False, 3.2), steps=[1])
        native["touches"] = flutter["touches"] = [(1.0, 1.05), (3.0, 3.05)]
        result = shapes.compare(scene, native, flutter)
        self.assertEqual(list(result["pairs"]), ["step1e0"])
        limits = shapes.limits(result, scene)
        for measure in ("t10_90_ms", "rms", "response_pct", "damping"):
            self.assertTrue(analyze.within(*limits[f"block.step1e0.progress.{measure}"]))
            value, _, _ = limits[f"block.step3e0.progress.{measure}"]
            self.assertEqual(value, float("inf"))
            self.assertFalse(analyze.within(*limits[f"block.step3e0.progress.{measure}"]))

    def test_a_scene_whose_apps_show_no_event_at_all_still_expects_every_touch_step(self):
        scene = self.scene(steps=[{"wait": 0.5}, {"tap": "a"}, {"wait": 1.2}, {"tap": "b"}])
        native, flutter = capture_of(), capture_of()
        native["touches"] = flutter["touches"] = [(1.0, 1.05), (3.0, 3.05)]
        names = shapes.expected(shapes.compare(scene, native, flutter), scene)
        self.assertEqual(names, [f"block.step{k}e0.progress.{m}" for k in (1, 3) for m in ("t10_90_ms", "rms", "response_pct", "damping")])

    def test_touches_are_counted_against_the_touch_steps(self):
        scene = self.scene(steps=[{"wait": 0.5}, {"tap": "a"}, {"doubleTap": "b"}])
        native, flutter = capture_of(spring_series(0.55, 1.0), steps=[1]), capture_of(spring_series(0.55, 1.0), steps=[1])
        native["touches"] = [(1.0, 1.1), (2.0, 2.05), (2.1, 2.15)]
        flutter["touches"] = [(1.0, 1.1)]
        limits = shapes.limits(shapes.compare(scene, native, flutter), scene)
        self.assertEqual(limits["touches.native"], (0, 0, "max"))
        self.assertEqual(limits["touches.flutter"], (2, 0, "max"))

    def test_stalls_and_the_first_changed_frame_are_kept_for_the_report(self):
        rows = [{"progress": p} for p in (0.0, 0.0, 0.7, 0.9, 1.0)]
        series = {"progress": [0.0, 0.5, 1.0]}
        step = shapes.first_step([0.0, 0.1, 0.15, 0.2, 0.3], rows, series, 1, 4)
        self.assertAlmostEqual(step["gap_ms"], 50, places=6)
        self.assertAlmostEqual(step["progress"], 0.7, places=6)
        scene = self.scene()
        native, flutter = capture_of(spring_series(0.55, 1.0), steps=[0]), capture_of(spring_series(0.55, 1.0), steps=[0])
        native["stalls"], flutter["stalls"] = [], [41.0]
        flutter["events"][0]["first_frame"] = {"block": {"gap_ms": 33.0, "progress": 0.73}}
        result = shapes.compare(scene, native, flutter)
        self.assertEqual(result["stalls"], {"native": [], "flutter": [41.0]})
        self.assertEqual(result["pairs"]["step0e0"]["shapes"]["block"]["first_frame"]["flutter"], {"gap_ms": 33.0, "progress": 0.73})


class OuterEdgeTests(unittest.TestCase):
    def scene(self, edges, motion):
        return manifest.parse([{
            "id": "x", "group": "material", "title": "t", "inventory": "2.14", "app": "lab",
            "backdrops": ["stripes"], "appearances": ["dark"], "steps": [{"tap": "a"}],
            "regions": {"left": [0, 0, 10, 10], "right": [10, 0, 10, 10]}, "track": ["left", "right"], "edges": edges, "motion": motion,
        }])[0]

    @staticmethod
    def capture(travel):
        flat = np.zeros(len(spring_series(0.4, 1.0)["cx"]))
        base = spring_series(0.4, 1.0)
        series = {"xmin": base["progress"] * travel + 100, "xmax": flat + 300, "ymin": flat + 10, "ymax": flat + 50}
        return {"events": [{"onset": 1.0, "series": {"left": {**base, **series}, "right": {**base, **series}}, "step": 0}], "touches": []}

    def test_an_edge_is_compared_only_for_the_regions_that_list_it(self):
        scene = self.scene({"left": ["xmin"], "right": ["xmax"]}, ["xmin.peak_ms", "xmax.peak_ms"])
        self.assertEqual(shapes.expected({"pairs": {"step0e0": {}}}, scene), ["left.step0e0.xmin.peak_ms", "right.step0e0.xmax.peak_ms"])

    def test_a_moving_edge_is_measured_and_a_still_one_is_absent(self):
        scene = self.scene({"left": ["xmin"], "right": ["xmax"]}, ["xmin.settle_ms", "xmax.settle_ms"])
        result = shapes.compare(scene, self.capture(80.0), self.capture(80.0))
        found = shapes.measures(result)
        self.assertEqual(found["left.step0e0.xmin.settle_ms"], 0.0)
        self.assertNotIn("right.step0e0.xmax.settle_ms", found)
        limits = shapes.limits(result, scene)
        self.assertEqual(limits["right.step0e0.xmax.settle_ms"][0], float("inf"))
        self.assertEqual(limits["left.step0e0.xmin.settle_ms"][0], 0.0)

    def test_a_slower_edge_fails_its_time_limit(self):
        scene = self.scene({"left": ["xmin"]}, ["xmin.settle_ms"])
        slow = self.capture(80.0)
        slow["events"][0]["series"]["left"]["xmin"] = np.interp(np.arange(len(slow["events"][0]["series"]["left"]["xmin"])) * 0.5, np.arange(len(slow["events"][0]["series"]["left"]["xmin"])), slow["events"][0]["series"]["left"]["xmin"])
        result = shapes.compare(scene, self.capture(80.0), slow)
        value, limit, bound = shapes.limits(result, scene)["left.step0e0.xmin.settle_ms"]
        self.assertGreater(value, limit)

    def test_edges_do_not_make_a_still_event_significant(self):
        series = {key: np.zeros(10) for key in ("width", "height", "cx", "cy", "luma", "progress")}
        series.update({key: np.arange(10) * 10.0 for key in ("xmin", "xmax", "ymin", "ymax")})
        self.assertFalse(shapes.significant(series))


class MotionMeasureNameTests(unittest.TestCase):
    def test_the_harness_and_the_manifest_agree_on_motion_measures(self):
        self.assertEqual(manifest.MOTION_MEASURES, shapes.MOTION_MEASURES)


if __name__ == "__main__":
    unittest.main()
