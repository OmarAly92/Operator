import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import lab
import manifest
import takecheck

SCENES = {s.id: s for s in manifest.load()}
PRESS = [{"wait": 0.5}, {"press": {"at": "glass", "duration": 1.0}}, {"wait": 1.0}, {"pressDrag": {"from": "glass", "to": {"element": "glass", "dx": 60}, "pressDuration": 0.3, "velocity": 120, "hold": 0.5}}]


def frames(start, end, step=1 / 60):
    count = int(round((end - start) / step))
    return [start + k * step for k in range(count + 1)]


class TakeRuleTests(unittest.TestCase):
    def test_the_scripted_duration_of_a_press_and_of_a_press_drag(self):
        self.assertEqual(takecheck.scripted(PRESS[1]), 1.0)
        self.assertAlmostEqual(takecheck.scripted(PRESS[3]), 0.3 + 0.5 + 0.5, places=9)
        self.assertAlmostEqual(takecheck.scripted({"pressDrag": {"from": "glass", "to": {"element": "glass", "dy": 300}, "pressDuration": 0.3, "velocity": 120, "hold": 0.5}}), 3.3, places=9)
        self.assertIsNone(takecheck.scripted({"tap": "glass"}))

    def test_a_clean_take_passes(self):
        times = frames(0.0, 6.0)
        self.assertEqual(takecheck.failures(PRESS, [(1.0, 2.0), (3.0, 4.3)], times), [])

    def test_a_burst_anywhere_from_touch_down_to_the_next_touch_is_a_capture_hole(self):
        windows = [(1.0, 2.0), (3.0, 4.3)]
        burst = sorted(frames(0.0, 6.0) + [2.0 + 1 / 60 + 0.0017, 2.0 + 1 / 60 + 0.0034])
        self.assertEqual(takecheck.failures(PRESS, windows, burst), ["capture hole (burst) at 2.018 s"])
        at_the_cut = sorted(frames(0.0, 6.0) + [4.3 + 0.45 + 0.0017, 4.3 + 0.45 + 0.0034])
        self.assertEqual(takecheck.failures(PRESS, windows, at_the_cut), ["capture hole (burst) at 4.752 s"])
        after = sorted(frames(0.0, 6.0) + [5.7 + 0.0017, 5.7 + 0.0034])
        self.assertEqual(takecheck.failures(PRESS, windows, after), [])

    def test_the_archived_dark_stripes_release_is_a_hole_with_its_lost_frames_and_its_burst(self):
        up = 23.955
        hold = [up - 0.0167 * k for k in range(8, 0, -1)] + [up]
        release = [(0.005, False), (0.080, True), (0.1017, True), (0.0483, True), (0.005, False), (0.010, False), (0.005, True), (0.015, True)]
        release += [(0.0033, False), (0.0033, False), (0.005, False)] + [(0.0167, False)] * 20
        times, changing = list(hold), [False] * len(hold)
        for gap, moved in release:
            times.append(times[-1] + gap)
            changing.append(moved)
        found = takecheck.span_holes(times, changing, [(up - 1.0, up)])
        self.assertEqual([kind for kind, _ in found], ["burst", "101.7 ms lost while the glass moved"])
        still = takecheck.span_holes(times, [False] * len(times), [(up - 1.0, up)])
        self.assertEqual([kind for kind, _ in still], ["burst"])

    def test_native_s_slow_cadence_after_its_onset_is_not_lost_and_the_same_gaps_in_flutter_are(self):
        down = 1.0
        times = [0.0, down] + [down + 0.0167 * k for k in range(1, 7)]
        for gap in (0.0483, 0.050, 0.050, 0.050, 0.050):
            times.append(times[-1] + gap)
        times += [times[-1] + 0.0167 * k for k in range(1, 30)]
        changing = [False, False] + [True] * (len(times) - 2)
        self.assertEqual(takecheck.span_holes(times, changing, [(down, 2.0)]), [])
        found = takecheck.span_holes(times, changing, [(down, 2.0)], everywhere=True)
        self.assertEqual([kind for kind, _ in found], ["48.3 ms lost while the glass moved"])

    def test_a_gap_while_the_glass_moves_in_native_s_onset_is_lost(self):
        down = 1.0
        times = [0.0, down, down + 0.0167, down + 0.0333, down + 0.0833] + [down + 0.0833 + 0.0167 * k for k in range(1, 40)]
        changing = [False, False] + [True] * (len(times) - 2)
        found = takecheck.span_holes(times, changing, [(down, 1.6)])
        self.assertEqual([kind for kind, _ in found], ["50.0 ms lost while the glass moved"])

    def test_a_gap_after_a_still_frame_or_with_no_frame_after_it_in_the_span_is_not_lost(self):
        up = 2.0
        times = [0.0, 1.0] + [1.0 + 0.0167 * k for k in range(1, 60)] + [up, up + 0.4833, up + 0.65, up + 0.9367]
        changing = [False] * (len(times) - 3) + [False, False, True]
        self.assertEqual(takecheck.span_holes(times, changing, [(1.0, up)]), [])

    def test_a_native_gap_while_the_glass_moves_late_in_the_release_is_lost(self):
        up = 2.0
        times = [0.0, 1.0] + [1.0 + 0.0167 * k for k in range(1, 60)] + [up]
        times += [up + 0.3 * k / 18 for k in range(1, 19)] + [up + 0.4] + [up + 0.4 + 0.0167 * k for k in range(1, 20)]
        changing = [False, False] + [True] * (len(times) - 2)
        found = takecheck.span_holes(times, changing, [(1.0, up)])
        self.assertEqual([kind for kind, _ in found], ["100.0 ms lost while the glass moved"])
        self.assertAlmostEqual(found[0][1] - up, 0.4, places=6)

    def test_a_native_gap_longer_than_its_twenty_hertz_period_while_held_is_lost(self):
        down, up = 1.0, 2.0
        times = [0.0, down] + [down + 0.0167 * k for k in range(1, 30)]
        times += [times[-1] + 0.1183] + [times[-1] + 0.1183 + 0.05 * k for k in range(1, 8)]
        changing = [False, False] + [True] * (len(times) - 2)
        found = takecheck.span_holes(times, changing, [(down, up)])
        self.assertEqual([kind for kind, _ in found], ["118.3 ms lost while the glass moved"])

    def test_a_gap_of_exactly_thirty_ms_on_the_recording_clock_is_not_over_the_limit(self):
        down = 1.0
        times = [0.0, down] + [down + k / 60 for k in range(1, 10)]
        times += [times[-1] + 18 / 600] + [times[-1] + 18 / 600 + k / 60 for k in range(1, 20)]
        changing = [False, False] + [True] * (len(times) - 2)
        self.assertEqual(takecheck.span_holes(times, changing, [(down, 2.0)], everywhere=True), [])

    def test_the_release_cadence_of_alternating_short_and_long_gaps_is_not_a_hole(self):
        up = 2.0
        cadence = [0.0, 1.0] + [1.0 + 0.0167 * k for k in range(1, 60)]
        cadence = [t for t in cadence if t < up] + [up]
        for gap in [0.0133, 0.015, 0.0167, 0.0033, 0.0117, 0.005] * 6:
            cadence.append(cadence[-1] + gap)
        for app in ("native", "flutter"):
            self.assertEqual(takecheck.span_holes(cadence, [True] * len(cadence), [(1.0, up)], everywhere=app == "flutter"), [])

    def test_a_first_frame_squeezed_onto_the_touch_down_frame_is_a_hole(self):
        squeezed = [0.0, 1.0, 1.0017, 1.0117, 1.0283] + frames(1.05, 6.0)
        self.assertEqual([k for k, _ in takecheck.span_holes(squeezed, [False] * len(squeezed), [(1.0, 2.0)])], ["squeezed first frame"])
        clean = [0.0, 1.0, 1.005, 1.02, 1.0367] + frames(1.05, 6.0)
        self.assertEqual(takecheck.span_holes(clean, [False] * len(clean), [(1.0, 2.0)]), [])

    def test_the_app_is_read_from_the_take_folder(self):
        self.assertEqual(takecheck.app_of(Path("run/scene/dark-photo/flutter")), "flutter")
        self.assertEqual(takecheck.app_of(Path("run/scene/dark-photo/native")), "native")
        self.assertEqual(takecheck.app_of(Path("takes/scene/dark-photo/3")), "native")

    def test_a_squeezed_press_and_a_missing_touch_fail(self):
        times = frames(0.0, 6.0)
        self.assertEqual(takecheck.failures(PRESS, [(1.0, 1.607), (3.0, 4.3)], times), ["step 1 touch 0.607 s against 1.000 s"])
        self.assertEqual(takecheck.failures(PRESS, [(1.0, 2.0)], times), ["touches 1 against 2"])

    def test_only_scenes_with_a_press_are_checked(self):
        self.assertTrue(takecheck.judged(SCENES["material.interactive"]))
        self.assertTrue(takecheck.judged(SCENES["material.neighbours.10"]))
        self.assertFalse(takecheck.judged(SCENES["material.merge"]))
        self.assertFalse(takecheck.judged(SCENES["button.press"]))


class CheckedRecordingTests(unittest.TestCase):
    def setUp(self):
        quiet = contextlib.redirect_stdout(io.StringIO())
        quiet.__enter__()
        self.addCleanup(quiet.__exit__, None, None, None)

    def test_run_records_a_failing_press_take_again_and_keeps_the_failed_one(self):
        scene = SCENES["material.interactive"]
        results = iter([{"failures": ["capture hole"]}, {"failures": []}])
        with tempfile.TemporaryDirectory() as temp:
            case = Path(temp) / "case"

            def capture(udid, scene, app, backdrop, take, target):
                take.mkdir(parents=True)

            lab.capture_checked("udid", scene, "native", "photo", case, capture=capture, check=lambda scene, take: next(results))
            self.assertTrue((case / "native").is_dir())
            self.assertEqual((case / "excluded" / "native-0" / "reason.txt").read_text(), "capture hole\n")

    def test_run_into_a_folder_that_already_holds_an_excluded_take_keeps_both(self):
        scene = SCENES["material.interactive"]
        results = iter([{"failures": ["capture hole"]}, {"failures": []}])
        with tempfile.TemporaryDirectory() as temp:
            case = Path(temp) / "case"
            old = case / "excluded" / "native-0"
            old.mkdir(parents=True)
            (old / "reason.txt").write_text("earlier\n")

            def capture(udid, scene, app, backdrop, take, target):
                take.mkdir(parents=True)

            lab.capture_checked("udid", scene, "native", "photo", case, capture=capture, check=lambda scene, take: next(results))
            self.assertEqual((old / "reason.txt").read_text(), "earlier\n")
            kept = sorted(path.name for path in (case / "excluded").iterdir())
            self.assertEqual(len(kept), 2)
            self.assertTrue((case / "native").is_dir())

    def test_run_gives_up_after_its_retries_and_keeps_the_last_take(self):
        scene = SCENES["material.interactive"]
        with tempfile.TemporaryDirectory() as temp:
            case = Path(temp) / "case"
            calls = []

            def capture(udid, scene, app, backdrop, take, target):
                calls.append(take)
                take.mkdir(parents=True)

            lab.capture_checked("udid", scene, "native", "photo", case, capture=capture, check=lambda scene, take: {"failures": ["hole"]})
            self.assertEqual(len(calls), lab.RETRIES + 1)
            self.assertTrue((case / "native").is_dir())

    def test_repeat_excludes_failing_takes_and_records_until_enough_pass(self):
        scene = SCENES["material.interactive"]
        verdicts = iter([["hole"], [], ["squeezed"], []])
        with tempfile.TemporaryDirectory() as temp:
            run = Path(temp)
            folder = run / "takes" / scene.id / "dark-photo"

            def capture(udid, scene, app, backdrop, take):
                take.mkdir(parents=True)

            def check(scene, take):
                found = {"failures": next(verdicts)}
                (take / takecheck.RESULT).write_text(json.dumps(found))
                return found

            lab.record_checked("udid", scene, "photo", folder, run, 2, capture=capture, check=check)
            self.assertEqual(lab.take_numbers(folder), [1, 3])
            self.assertEqual(lab.take_numbers(run / "excluded" / "takes" / scene.id / "dark-photo"), [0, 2])

    def test_repeat_checks_takes_already_on_disk_before_recomputing(self):
        scene = SCENES["material.interactive"]
        with tempfile.TemporaryDirectory() as temp:
            run = Path(temp)
            folder = run / "takes" / scene.id / "dark-photo"
            for number in range(3):
                (folder / str(number)).mkdir(parents=True)

            def check(scene, take):
                found = {"failures": ["hole"] if take.name == "1" else []}
                (take / takecheck.RESULT).write_text(json.dumps(found))
                return found

            lab.record_checked("udid", scene, "photo", folder, run, 0, capture=mock.Mock(), check=check)
            self.assertEqual(lab.take_numbers(folder), [0, 2])


class LeverageStopTests(unittest.TestCase):
    @staticmethod
    def pair_result(scene, case, cache=None):
        native, flutter = (Path(case) / side for side in ("native", "flutter"))
        outlier = "3" in (native.resolve().name, flutter.resolve().name)
        return {"measures": {"glass.step1.press.glow_rise_ms": (60.0 if outlier else 10.0, 17.0, "max")}}

    def noise_with(self, count):
        scene = SCENES["material.interactive"]
        with tempfile.TemporaryDirectory() as temp:
            takes = []
            for number in range(count):
                (Path(temp) / "takes" / str(number)).mkdir(parents=True)
                takes.append(Path(temp) / "takes" / str(number))
            with mock.patch.object(lab.analyze, "analyze", side_effect=self.pair_result):
                lab.case_noise(scene, takes, Path(temp) / "pairs")
            return json.loads((Path(temp) / "pairs" / "noise-sources.json").read_text())["leverage"]

    def test_the_leverage_check_waits_for_five_takes(self):
        self.assertEqual(self.noise_with(4), {})
        self.assertEqual(self.noise_with(5)["glass.step1.press.glow_rise_ms"]["take"], "3")

    def test_a_flagged_case_still_gets_its_floor_and_repeat_reports_without_stopping(self):
        with tempfile.TemporaryDirectory() as temp:
            run = Path(temp) / "run"
            noise_file = Path(temp) / "noise.json"
            noise_file.write_text(json.dumps({"material.interactive": {"dark-photo": {"old": 1.0}, "light-photo": {"old": 2.0}}}))

            def fake_record(udid, scene, backdrop, folder, run_dir, times):
                for number in range(5):
                    (folder / str(number)).mkdir(parents=True, exist_ok=True)

            def fake_noise(scene, takes, case_root):
                case_root.mkdir(parents=True, exist_ok=True)
                flagged = {"x.glow_rise_ms": {"take": "3", "noise": 60.0, "median_without": 10.0}} if case_root.name == "dark-photo" else {}
                (case_root / "noise-sources.json").write_text(json.dumps({"sources": {}, "leverage": flagged}))
                return {"new": 3.0}, 0.0

            args = mock.Mock(scene="material.interactive", times=0, appearance=None, backdrop="photo", a11y="none", into=str(run))
            with mock.patch.object(lab.build, "require_fresh"), mock.patch.object(lab.sim, "device", return_value="udid"), \
                 mock.patch.object(lab.sim, "accessibility"), mock.patch.object(lab.sim, "appearance"), \
                 mock.patch.object(lab, "record_checked", side_effect=fake_record), mock.patch.object(lab, "case_noise", side_effect=fake_noise), \
                 mock.patch.object(lab, "NOISE", noise_file), contextlib.redirect_stdout(io.StringIO()) as out:
                lab.cmd_repeat(args)
            written = json.loads(noise_file.read_text())["material.interactive"]
            self.assertEqual(written["dark-photo"], {"new": 3.0})
            self.assertEqual(written["light-photo"], {"new": 3.0})
            lines = [line for line in out.getvalue().splitlines() if line.startswith("LEVERAGE")]
            self.assertEqual(lines, ["LEVERAGE (reported, not a stop): material.interactive dark-photo x.glow_rise_ms take 3 noise 60.0 ms against a median of 10.0 ms"])
            kept = json.loads((run / "material.interactive" / "dark-photo" / "noise-sources.json").read_text())["leverage"]
            self.assertEqual(kept["x.glow_rise_ms"]["take"], "3")


class LeverageTests(unittest.TestCase):
    def test_one_take_that_sets_a_time_limit_above_three_times_its_siblings_is_flagged(self):
        values = {("0", "1"): 10.0, ("0", "2"): 12.0, ("1", "2"): 8.0, ("0", "3"): 60.0, ("1", "3"): 58.0, ("2", "3"): 55.0}
        found = lab.leverage({"glass.step1.press.glow_rise_ms": values}, 17.0)
        self.assertEqual(found["glass.step1.press.glow_rise_ms"]["take"], "3")

    def test_spread_without_one_outlier_or_under_the_fixed_threshold_is_not_flagged(self):
        even = {("0", "1"): 20.0, ("0", "2"): 25.0, ("1", "2"): 30.0}
        self.assertEqual(lab.leverage({"x.glow_rise_ms": even}, 17.0), {})
        small = {("0", "1"): 1.0, ("0", "2"): 1.0, ("1", "2"): 10.0}
        self.assertEqual(lab.leverage({"x.glow_rise_ms": small}, 17.0), {})
        self.assertEqual(lab.leverage({"x.grow_w": {("0", "1"): 9.0, ("0", "2"): 0.1, ("1", "2"): 0.1}}, 17.0), {})

    def _four(self, worst, rest):
        return {("0", "1"): rest, ("0", "2"): rest, ("1", "2"): rest, ("0", "3"): worst, ("1", "3"): rest, ("2", "3"): rest}

    def test_one_frame_of_jitter_over_the_siblings_is_not_flagged(self):
        self.assertEqual(lab.leverage({"x.glow_rise_ms": self._four(15.0, 3.3)}, 17.0), {})
        self.assertEqual(lab.leverage({"x.glow_rise_ms": self._four(25.0, 8.3)}, 17.0), {})

    def test_a_real_outlier_is_still_flagged_with_its_figures(self):
        found = lab.leverage({"x.glow_rise_ms": self._four(283.3, 16.7)}, 17.0)
        self.assertEqual(found["x.glow_rise_ms"], {"take": "3", "noise": 283.3, "median_without": 16.7})

    def test_the_jitter_limit_is_two_frames(self):
        self.assertEqual(lab.leverage({"x.glow_rise_ms": self._four(43.3, 10.0)}, 17.0), {})
        self.assertIn("x.glow_rise_ms", lab.leverage({"x.glow_rise_ms": self._four(43.4, 10.0)}, 17.0))


if __name__ == "__main__":
    unittest.main()
