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


def _tune_args(**overrides):
    args = [
        "tune",
        "--scene", "material.regular",
        "--appearance", "dark",
        "--backdrops", "white",
        "--params", "frost",
    ]
    for key, value in overrides.items():
        args += [f"--{key}", value]
    return args


class TuneRejectsOperatorTests(unittest.TestCase):
    def test_tune_rejects_the_operator_target(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            with self.assertRaises(SystemExit):
                lab.parser().parse_args(_tune_args(flutter="operator"))

    def test_tune_still_accepts_the_example_target(self):
        args = lab.parser().parse_args(_tune_args(flutter="example"))
        self.assertEqual(args.flutter, "example")


class TuneRowTests(unittest.TestCase):
    def test_the_accessibility_mode_picks_its_row(self):
        self.assertEqual(lab.tune_row("reduce-transparency", None), "reduceTransparency")
        self.assertEqual(lab.tune_row("increase-contrast", None), "increaseContrast")
        self.assertEqual(lab.tune_row("none", None), "regular")
        self.assertEqual(lab.tune_row("none", "tinted"), "tinted")
        self.assertEqual(lab.tune_row("increase-contrast", "increaseContrast"), "increaseContrast")

    def test_a_row_that_the_accessibility_mode_would_not_render_is_rejected(self):
        for a11y, row in (("reduce-transparency", "regular"), ("increase-contrast", "reduceTransparency"), ("none", "increaseContrast")):
            with self.assertRaises(SystemExit):
                lab.tune_row(a11y, row)


class RunFreshnessTests(unittest.TestCase):
    def test_run_refuses_a_stale_flutter_build_before_touching_the_simulator(self):
        args = lab.parser().parse_args(["run", "material.regular", "--app", "both"])
        with mock.patch.object(lab.build, "require_fresh", side_effect=SystemExit("stale")) as fresh, \
             mock.patch.object(lab.sim, "device") as device:
            with self.assertRaises(SystemExit):
                lab.cmd_run(args)
        fresh.assert_called_once_with("example")
        device.assert_not_called()

    def test_a_native_only_run_needs_no_flutter_build_and_records_its_target(self):
        args = lab.parser().parse_args(["run", "material.regular", "--app", "native"])
        with tempfile.TemporaryDirectory() as temp, \
             mock.patch.object(lab.build, "require_fresh") as fresh, \
             mock.patch.object(lab.sim, "device", return_value="udid"), \
             mock.patch.object(lab, "run_cases"), \
             mock.patch.object(lab, "new_run_dir", return_value=Path(temp)):
            lab.cmd_run(args)
            self.assertEqual(json.loads((Path(temp) / "run.json").read_text()), {"flutter": "example", "a11y": "none"})
        fresh.assert_called_once_with("native")

    def test_repeat_refuses_a_stale_native_build_before_touching_the_simulator(self):
        args = lab.parser().parse_args(["repeat", "material.materialize"])
        with mock.patch.object(lab.build, "require_fresh", side_effect=SystemExit("stale")) as fresh, \
             mock.patch.object(lab.sim, "device") as device:
            with self.assertRaises(SystemExit):
                lab.cmd_repeat(args)
        fresh.assert_called_once_with("native")
        device.assert_not_called()

    def test_the_native_build_is_stamped_from_its_swift_sources(self):
        self.assertEqual(lab.build.SOURCES["native"], (lab.build.NATIVE / "GlassLab", lab.build.NATIVE / "GlassLabDriver"))
        self.assertEqual(lab.build.STAMPS["native"].parent, lab.build.NATIVE_DATA)


class AccessibilityRestoredOnFailureTests(unittest.TestCase):
    def test_cmd_tune_restores_none_even_when_accessibility_set_fails(self):
        args = mock.Mock(
            scene="material.regular", appearance="dark", backdrops="white", params="frost",
            row="increaseContrast", size=88, flutter="example", passes=4, write=False, region=None, pad=12, a11y="increase-contrast",
        )
        calls = []

        def fake_accessibility(udid, mode):
            calls.append(mode)
            if mode == "increase-contrast":
                raise RuntimeError("boom")

        with mock.patch.object(lab.sim, "device", return_value="udid"), \
             mock.patch.object(lab.sim, "accessibility", side_effect=fake_accessibility), \
             mock.patch.object(lab, "manifest") as fake_manifest, \
             mock.patch.object(lab, "tune") as fake_tune:
            fake_manifest.select.return_value = [mock.Mock()]
            fake_manifest.load.return_value = []
            with self.assertRaises(RuntimeError):
                lab.cmd_tune(args)

        self.assertEqual(calls, ["increase-contrast", "none"])

    def test_run_cases_restores_none_even_when_accessibility_set_fails(self):
        calls = []

        def fake_accessibility(udid, mode):
            calls.append(mode)
            if mode == "increaseContrast":
                raise RuntimeError("boom")

        with mock.patch.object(lab.sim, "accessibility", side_effect=fake_accessibility):
            with self.assertRaises(RuntimeError):
                lab.run_cases("udid", [], [], [], None, "increaseContrast", Path("/tmp"))

        self.assertEqual(calls, ["increaseContrast", "none"])


class NoiseTests(unittest.TestCase):
    def test_per_case_noise_is_read_per_case_and_old_entries_stay_scene_wide(self):
        noise = {"material.materialize": {"dark-photo": {"block.step1e0.progress.rms": 0.02}}, "menu.bar": {"event0.width.peak_ms": 8.0}}
        self.assertEqual(lab.noise_for(noise, "material.materialize", "dark-photo"), {"block.step1e0.progress.rms": 0.02})
        self.assertEqual(lab.noise_for(noise, "material.materialize", "light-photo"), {})
        self.assertEqual(lab.noise_for(noise, "menu.bar", "dark-photo"), {"event0.width.peak_ms": 8.0})
        self.assertEqual(lab.noise_for(noise, "material.regular", "dark-photo"), {})

    def test_the_teardown_entries_are_gone_from_the_committed_noise(self):
        noise = json.loads(lab.NOISE.read_text())
        self.assertFalse([name for name in noise["tabbar.drag"] if name.startswith("event2.")])

    def test_repeat_covers_every_case_unless_narrowed(self):
        import manifest
        scene = {s.id: s for s in manifest.load()}["material.materialize"]
        self.assertEqual(lab.repeat_cases(scene), [("light", "stripes"), ("light", "photo"), ("dark", "stripes"), ("dark", "photo")])
        self.assertEqual(lab.repeat_cases(scene, "dark", "photo"), [("dark", "photo")])

    def test_pairs_of_takes_have_distinct_names_past_ten_takes_and_each_take_is_captured_once(self):
        import manifest
        scene = {s.id: s for s in manifest.load()}["material.materialize"]
        calls = []

        def analyze_pair(scene, case, cache=None):
            for side in ("native", "flutter"):
                key = (scene.id, str((case / side).resolve()))
                if key not in cache:
                    calls.append(key)
                    cache[key] = {}
            return {"static": {}, "measures": {"ready.mad": (1.5, 4.0, "max"), "ready.topology.g4.neck_pt": (float("nan"), 1.0, "max")}, "shapes": {"pairs": {"step1e0": {"shapes": {"block": {"progress": {"rms": 0.01, "response_pct": float("inf")}}}}}}}

        with tempfile.TemporaryDirectory() as temp:
            takes = []
            for number in range(12):
                (Path(temp) / "takes" / str(number)).mkdir(parents=True)
                takes.append(Path(temp) / "takes" / str(number))
            with mock.patch.object(lab.analyze, "analyze", side_effect=analyze_pair):
                worst, _ = lab.case_noise(scene, takes, Path(temp) / "pairs")
            names = [p.name for p in (Path(temp) / "pairs").iterdir()]
        self.assertEqual(len(names), 66)
        self.assertEqual(len(set(names)), 66)
        self.assertIn("pair-1-11", names)
        self.assertIn("pair-11-1", [f"pair-{b}-{a}" for a, b in (n.split("-")[1:] for n in names)])
        self.assertEqual(len(calls), 12)
        self.assertEqual(worst, {"ready.mad": 1.5, "block.step1e0.progress.rms": 0.01})

    def test_takes_are_numbered_after_the_ones_already_there(self):
        with tempfile.TemporaryDirectory() as temp:
            for name in ("0", "1", "2", "pair-01"):
                (Path(temp) / name).mkdir()
            self.assertEqual(lab.take_numbers(temp), [0, 1, 2])


if __name__ == "__main__":
    unittest.main()
