import json
import sys
import tempfile
import unittest
from pathlib import Path

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
