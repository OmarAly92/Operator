import contextlib
import io
import sys
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


class AccessibilityRestoredOnFailureTests(unittest.TestCase):
    def test_cmd_tune_restores_none_even_when_accessibility_set_fails(self):
        args = mock.Mock(
            scene="material.regular", appearance="dark", backdrops="white", params="frost",
            row="regular", size=88, flutter="example", passes=4, write=False, region=None, a11y="increaseContrast",
        )
        calls = []

        def fake_accessibility(udid, mode):
            calls.append(mode)
            if mode == "increaseContrast":
                raise RuntimeError("boom")

        with mock.patch.object(lab.sim, "device", return_value="udid"), \
             mock.patch.object(lab.sim, "accessibility", side_effect=fake_accessibility), \
             mock.patch.object(lab, "manifest") as fake_manifest, \
             mock.patch.object(lab, "tune") as fake_tune:
            fake_manifest.select.return_value = [mock.Mock()]
            fake_manifest.load.return_value = []
            with self.assertRaises(RuntimeError):
                lab.cmd_tune(args)

        self.assertEqual(calls, ["increaseContrast", "none"])

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
