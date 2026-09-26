import filecmp
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

LAB = Path(__file__).resolve().parents[2]


class GeneratedFilesTests(unittest.TestCase):
    def test_committed_project_matches_the_generator(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp) / "GlassLab.xcodeproj"
            subprocess.run([sys.executable, str(LAB / "native" / "gen_project.py"), str(out)], check=True)
            committed = LAB / "native" / "GlassLab.xcodeproj"
            for relative in ("project.pbxproj", "xcshareddata/xcschemes/GlassLab.xcscheme"):
                self.assertTrue(filecmp.cmp(out / relative, committed / relative, shallow=False), relative)

    def test_backdrops_are_deterministic(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            for out in (first, second):
                subprocess.run([sys.executable, str(LAB / "backdrops" / "generate.py"), out], check=True)
            names = sorted(p.name for p in Path(first).glob("*.png"))
            self.assertEqual(names, ["black.png", "photo.png", "scroll.png", "stripes.png", "text.png", "white.png"])
            for name in names:
                self.assertTrue(filecmp.cmp(Path(first) / name, Path(second) / name, shallow=False), name)


if __name__ == "__main__":
    unittest.main()
