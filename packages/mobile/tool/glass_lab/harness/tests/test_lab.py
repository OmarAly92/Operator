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
        fresh.assert_not_called()


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


if __name__ == "__main__":
    unittest.main()
