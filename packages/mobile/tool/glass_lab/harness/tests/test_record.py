import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

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


if __name__ == "__main__":
    unittest.main()
