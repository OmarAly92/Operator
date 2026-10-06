import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import report


def compared(scene, case, measures):
    checks = {name: False for name in measures}
    return {"scene": scene, "case": case, "kind": "compared", "pass": False, "checks": checks, "measures": measures}


class WorstMeasureTests(unittest.TestCase):
    def test_ranks_failing_measures_by_how_far_they_exceed_the_limit(self):
        result = compared("x", "c", {
            "ready.mad": [8.0, 4.0, "max"],
            "ready.bbox_pt": [30.0, 1.0, "max"],
            "motion.events.native_motion": [0, 1, "min"],
            "ready.luminance": [3.3, 3.0, "max"],
        })
        result["checks"]["ready.ok"] = True
        self.assertEqual(
            report.worst(result),
            "motion.events.native_motion 0 < 1, ready.bbox_pt 30.00 > 1.00, ready.mad 8.00 > 4.00",
        )

    def test_an_event_count_mismatch_ranks_by_its_size(self):
        result = compared("x", "c", {
            "motion.events.count": [1, 0, "max"],
            "ready.bbox_pt": [30.0, 1.0, "max"],
        })
        self.assertEqual(report.worst(result), "ready.bbox_pt 30.00 > 1.00, motion.events.count 1 > 0")

    def test_passing_case_has_no_measures(self):
        self.assertEqual(report.worst({"checks": {"ready.mad": True}, "measures": {"ready.mad": [1.0, 4.0, "max"]}}), "—")


class BacklogOrderTests(unittest.TestCase):
    def test_orders_priority_scenes_then_failures_by_ratio_then_missing_then_reference(self):
        results = [
            {"scene": "apple.maps.sheet", "case": "dark-none", "kind": "reference"},
            {"scene": "menu.bar", "case": "light-stripes", "kind": "missing"},
            compared("glass.small", "light-stripes", {"ready.mad": [5.0, 4.0, "max"]}),
            compared("glass.large", "light-stripes", {"ready.mad": [40.0, 4.0, "max"]}),
            compared("material.regular", "light-stripes", {"ready.mad": [4.5, 4.0, "max"]}),
            {"scene": "tabbar.drag", "case": "dark-stripes", "kind": "missing"},
            compared("tabbar.rest", "light-stripes", {"ready.mad": [4.5, 4.0, "max"]}),
        ]
        lines = report.markdown("runs/x", {"fail": 4}, [(None, r) for r in results], []).splitlines()
        self.assertEqual(lines[0], "# Glass lab baseline")
        rows = [line.split(" | ")[0].lstrip("| ") for line in lines if line.startswith("| ") and " | " in line and not line.startswith("| Status") and not line.startswith("| Scene") and not line.startswith("| fail")]
        self.assertEqual(rows, ["tabbar.rest", "tabbar.drag", "material.regular", "glass.large", "glass.small", "menu.bar", "apple.maps.sheet"])


class SummaryTargetTests(unittest.TestCase):
    def test_the_summary_names_the_flutter_target_the_run_captured(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertIn("against the Flutter lab app.", report.markdown(temp, {}, [], []))
            (Path(temp) / "run.json").write_text(json.dumps({"flutter": "example", "a11y": "none"}))
            self.assertIn("against the ios_liquid_glass example app.", report.markdown(temp, {}, [], []))
            (Path(temp) / "run.json").write_text(json.dumps({"flutter": "operator", "a11y": "none"}))
            self.assertIn("against Operator's debug glass lab.", report.markdown(temp, {}, [], []))


if __name__ == "__main__":
    unittest.main()
