import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import done_table
import manifest
import rim
import still_check


def static(value, passed):
    return {measure: value for measure in still_check.MEASURES} | {"pass": {measure: passed for measure in still_check.MEASURES}}


def write_case(root, scene, case, value, passed, flutter_pixel):
    folder = Path(root) / scene / case
    for app in ("native", "flutter"):
        (folder / app).mkdir(parents=True, exist_ok=True)
        for frame in ("ready", "settled"):
            pixel = flutter_pixel if app == "flutter" else 10
            Image.fromarray(np.full((4, 4, 3), pixel, dtype=np.uint8)).save(folder / app / f"{frame}.png")
    (folder / "result.json").write_text(json.dumps({"kind": "compared", "static": {"ready": static(value, passed), "settled": static(value, passed)}}))


class StillCheckTests(unittest.TestCase):
    def test_worse_means_a_pass_lost_or_a_failure_grown_past_noise_on_a_changed_flutter_frame(self):
        self.assertTrue(still_check.worse(3.0, 5.0, True, False, 0.0, True))
        self.assertTrue(still_check.worse(5.0, 5.6, False, False, 0.5, True))
        self.assertFalse(still_check.worse(5.0, 5.4, False, False, 0.5, True))
        self.assertFalse(still_check.worse(3.0, 2.0, True, True, 0.0, True))
        self.assertFalse(still_check.worse(3.0, 5.0, True, False, 0.0, False))

    def test_cases_in_the_2a_run_missing_from_the_new_one_are_reported(self):
        with tempfile.TemporaryDirectory() as before, tempfile.TemporaryDirectory() as after:
            write_case(before, "tabbar.rest", "dark-photo", 3.0, True, 50)
            write_case(before, "navbar.inline", "dark-photo", 3.0, True, 50)
            write_case(after, "tabbar.rest", "dark-photo", 6.0, False, 51)
            rows, missing = still_check.compare(before, after)
        self.assertEqual(missing, [("navbar.inline", "dark-photo")])
        self.assertTrue(all(row[8] for row in rows))
        self.assertEqual({row[9] for row in rows}, {1.0})


class EmptyRunTests(unittest.TestCase):
    def test_still_check_fails_on_an_empty_or_mistyped_run_or_when_nothing_was_compared(self):
        with tempfile.TemporaryDirectory() as before, tempfile.TemporaryDirectory() as after:
            for args in ([before, after], [before, str(Path(after) / "typo")]):
                with self.assertRaises(SystemExit) as caught, contextlib.redirect_stdout(io.StringIO()):
                    still_check.main(args)
                self.assertNotIn(caught.exception.code, (0, None))
            write_case(before, "tabbar.rest", "dark-photo", 3.0, True, 50)
            (Path(after) / "tabbar.rest" / "dark-photo").mkdir(parents=True)
            (Path(after) / "tabbar.rest" / "dark-photo" / "result.json").write_text(json.dumps({"kind": "error"}))
            with self.assertRaises(SystemExit) as caught, contextlib.redirect_stdout(io.StringIO()):
                still_check.main([before, after])
            self.assertNotIn(caught.exception.code, (0, None))

    def test_still_check_passes_a_run_that_compared_something(self):
        with tempfile.TemporaryDirectory() as before, tempfile.TemporaryDirectory() as after:
            write_case(before, "tabbar.rest", "dark-photo", 3.0, True, 50)
            write_case(after, "tabbar.rest", "dark-photo", 3.0, True, 50)
            with contextlib.redirect_stdout(io.StringIO()) as printed:
                still_check.main([before, after])
            self.assertIn("2 scene, case and frame triples compared", printed.getvalue())

    def test_done_table_fails_on_an_empty_or_mistyped_run_or_when_nothing_was_compared(self):
        with tempfile.TemporaryDirectory() as run:
            for args in ([run], [str(Path(run) / "typo")], []):
                with self.assertRaises(SystemExit) as caught, contextlib.redirect_stdout(io.StringIO()):
                    done_table.main(args)
                self.assertNotIn(caught.exception.code, (0, None))
            folder = Path(run) / "material.materialize" / "dark-photo"
            folder.mkdir(parents=True)
            (folder / "result.json").write_text(json.dumps({"kind": "error"}))
            with self.assertRaises(SystemExit) as caught, contextlib.redirect_stdout(io.StringIO()):
                done_table.main([run])
            self.assertNotIn(caught.exception.code, (0, None))


class RimTests(unittest.TestCase):
    def test_the_lit_band_under_the_top_edge_is_measured_in_points_whatever_its_brightness(self):
        bare = np.full((90, 300, 3), 60, dtype=np.float32)
        for brightness in (90.0, 27.0):
            frame = bare.copy()
            frame[10:80, 30:270] += 10
            frame[10:22, 30:270] += brightness
            self.assertAlmostEqual(rim.rim_width(frame, bare, (30, 10, 269, 79)), 4.0, places=6)
        self.assertTrue(np.isnan(rim.rim_width(bare + 1, bare, (30, 10, 269, 79))))


class DoneTableTests(unittest.TestCase):
    def test_progress_measures_are_counted_apart_from_the_event_gates_and_absent_ones_are_not_judged(self):
        result = {
            "measures": {
                "motion.events.native_motion": (2, 1, "min"),
                "motion.events.unpaired": (1, 0, "max"),
                "motion.block.step1e0.progress.rms": (0.01, 0.05, "max"),
                "motion.block.step1e0.progress.t10_90_ms": (float("inf"), 17, "max"),
                "ready.mad": (2.0, 4.0, "max"),
            },
            "checks": {
                "motion.events.native_motion": True,
                "motion.events.unpaired": False,
                "motion.block.step1e0.progress.rms": True,
                "motion.block.step1e0.progress.t10_90_ms": False,
                "ready.mad": True,
            },
        }
        found = done_table.summary(result)
        self.assertEqual(found["gates"], (1, 2))
        self.assertEqual(found["progress"], (1, 1, 2))
        self.assertEqual(found["failing"], ["block.step1e0.progress.t10_90_ms", "events.unpaired"])

    def test_expected_comes_from_the_scene_steps_so_a_result_missing_a_step_counts_it_as_failing(self):
        scene = manifest.select(manifest.load(), "material.materialize")[0]
        result = {
            "measures": {f"motion.block.step1e0.{measure}": (0.0, 1.0, "max") for measure in scene.motion},
            "checks": {f"motion.block.step1e0.{measure}": True for measure in scene.motion},
        }
        found = done_table.summary(result, scene)
        self.assertEqual(found["progress"], (7, 7, 14))
        self.assertEqual(found["failing"], sorted(f"block.step3e0.{measure}" for measure in scene.motion))


if __name__ == "__main__":
    unittest.main()
