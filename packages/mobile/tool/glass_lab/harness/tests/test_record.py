import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import build
import manifest
import record


class LaunchFileTests(unittest.TestCase):
    def test_write_then_clear(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / "Documents" / "glass_lab"
            record.write_launch_file(folder, "menu.bar", "photo", True)
            written = json.loads((folder / record.LAUNCH_FILE).read_text())
            self.assertEqual(written, {"scene": "menu.bar", "backdrop": "photo", "bare": True})
            record.clear_launch_file(folder)
            self.assertFalse((folder / record.LAUNCH_FILE).exists())
            record.clear_launch_file(folder)

    def test_material_overrides_travel_in_the_launch_file(self):
        with tempfile.TemporaryDirectory() as temp:
            record.write_launch_file(temp, "material.regular", "white", False, {"frost": 24.0, "edge.blur": 6.0})
            written = json.loads((Path(temp) / record.LAUNCH_FILE).read_text())
            self.assertEqual(written["material"], {"frost": 24.0, "edge.blur": 6.0})
            record.write_launch_file(temp, "material.regular", "white", False)
            self.assertNotIn("material", json.loads((Path(temp) / record.LAUNCH_FILE).read_text()))

    def test_the_tuned_anchor_travels_with_the_overrides(self):
        with tempfile.TemporaryDirectory() as temp:
            record.write_launch_file(temp, "material.regular", "white", False, {"frost": 24.0}, 200)
            self.assertEqual(json.loads((Path(temp) / record.LAUNCH_FILE).read_text())["materialSide"], 200)
            record.write_launch_file(temp, "material.regular", "white", False, None, 200)
            self.assertNotIn("materialSide", json.loads((Path(temp) / record.LAUNCH_FILE).read_text()))


class MarkerTests(unittest.TestCase):
    def test_the_marker_and_extra_fields_travel_in_the_launch_file(self):
        with tempfile.TemporaryDirectory() as temp:
            record.write_launch_file(temp, "tool.visibility", "photo", False, marker=True, extra={"visibility": 0.4})
            written = json.loads((Path(temp) / record.LAUNCH_FILE).read_text())
            self.assertEqual(written, {"scene": "tool.visibility", "backdrop": "photo", "bare": False, "marker": True, "visibility": 0.4})

    def test_touch_scenes_show_the_marker_in_both_launches_and_still_scenes_do_not(self):
        scenes = {s.id: s for s in manifest.load()}
        for scene_id, expected in (("material.materialize", True), ("material.regular", False)):
            with mock.patch.object(record, "drive", return_value={}) as drive, \
                 mock.patch.object(record, "Recording") as recording:
                recording.return_value.__enter__.return_value.started = 0
                with tempfile.TemporaryDirectory() as temp:
                    record.capture("udid", scenes[scene_id], "native", "stripes", Path(temp))
            self.assertEqual([call.kwargs["marker"] for call in drive.call_args_list], [expected, expected])


class OtherAppsTests(unittest.TestCase):
    def test_every_other_lab_app_is_closed_so_no_back_link_shows_in_the_status_bar(self):
        with mock.patch.object(record.subprocess, "run") as run:
            record.close_other_apps("udid", record.build.NATIVE_BUNDLE)
        closed = [call.args[0][-1] for call in run.call_args_list]
        self.assertEqual(sorted(closed), sorted(record.build.FLUTTER_TARGETS.values()))
        self.assertTrue(all(call.args[0][:3] == ["xcrun", "simctl", "terminate"] for call in run.call_args_list))


class TargetTests(unittest.TestCase):
    def test_flutter_means_the_example_unless_operator_is_asked_for(self):
        base = {"group": "material", "title": "t", "inventory": "2.1", "backdrops": ["stripes"], "appearances": ["dark"], "steps": []}
        lab, apple = manifest.parse([
            {**base, "id": "material.regular", "app": "lab"},
            {**base, "id": "apple.maps.sheet", "group": "apple", "app": "com.apple.Maps"},
        ])
        self.assertEqual(record.target_for(lab, "native"), build.NATIVE_BUNDLE)
        self.assertEqual(record.target_for(lab, "flutter"), build.EXAMPLE_BUNDLE)
        self.assertEqual(record.target_for(lab, "flutter", "operator"), build.FLUTTER_BUNDLE)
        self.assertEqual(record.target_for(apple, "flutter"), "com.apple.Maps")


if __name__ == "__main__":
    unittest.main()
