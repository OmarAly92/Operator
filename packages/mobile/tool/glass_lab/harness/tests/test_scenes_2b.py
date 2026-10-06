import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import manifest
import touch

MATERIALIZE = ("material.materialize", "material.materialize.snappy", "material.materialize.bouncy")
PRESS = ("material.interactive", "material.press.circle58", "material.press.138x53", "material.press.250x44", "material.press.300x120", "material.press.360x200")
SPACING = tuple(f"material.spacing.{c}.{p}" for c in ("default", "40") for p in ("a", "b", "c"))


class SceneTests(unittest.TestCase):
    def setUp(self):
        self.scenes = {s.id: s for s in manifest.load()}

    def test_materialize_scenes_track_the_block_on_progress_measures(self):
        for scene_id in MATERIALIZE:
            scene = self.scenes[scene_id]
            self.assertEqual(scene.track, ("block",))
            self.assertEqual(scene.regions["block"], [70, 400, 262, 104])
            self.assertEqual(set(scene.motion), {m for m in manifest.MOTION_MEASURES if m.startswith("progress.")})
            self.assertTrue(scene.touches)

    def test_press_scenes_hold_one_press_on_one_tracked_glass(self):
        for scene_id in PRESS:
            scene = self.scenes[scene_id]
            self.assertEqual(scene.track, ("glass",))
            self.assertTrue(any("press" in step for step in scene.steps))
            self.assertEqual(scene.motion, ())
        heights = sorted(self.scenes[s].regions["glass"][3] - 60 for s in PRESS)
        self.assertEqual(heights, [44, 54, 58, 88, 120, 200])

    def test_spacing_scenes_are_still_with_one_region_per_gap(self):
        gaps = []
        for scene_id in SPACING:
            scene = self.scenes[scene_id]
            self.assertTrue(scene.rest)
            self.assertEqual(scene.backdrops, ("photo",))
            self.assertEqual(set(scene.topology), set(scene.regions))
            gaps += [int(name[1:]) for name in scene.regions]
        self.assertEqual(sorted(gaps), sorted([0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 60] * 2))

    def test_no_region_of_a_touch_scene_overlaps_the_touch_marker(self):
        for scene in manifest.load():
            if scene.touches:
                for name, rect in scene.regions.items():
                    self.assertTrue(touch.marker_free(rect), f"{scene.id} {name}")


if __name__ == "__main__":
    unittest.main()
