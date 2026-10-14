import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import manifest
import touch

MATERIALIZE = ("material.materialize", "material.materialize.snappy", "material.materialize.bouncy")
PRESS = ("material.interactive", "material.press.circle58", "material.press.138x53", "material.press.250x44", "material.press.300x120", "material.press.360x200")
DRAGS = ("material.drag.fast", "material.drag.out", "material.drag.far", "material.drag.up")
HELD_OUT = ("material.press.circle44", "material.press.capsule36", "material.press.250x150", "material.press.300x250", "material.press.120x250")
NEIGHBOURS = ("material.neighbours.0", "material.neighbours.10", "material.neighbours.40")
PRESS_MOTION = ("delay_ms", *(m for m in manifest.MOTION_MEASURES if m.startswith("press.")))
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
            self.assertEqual(scene.motion, PRESS_MOTION)
        heights = sorted(self.scenes[s].regions["glass"][3] - 60 for s in PRESS)
        self.assertEqual(heights, [44, 54, 58, 88, 120, 200])

    def test_drag_scenes_press_drag_the_interactive_block_fast_or_out_of_the_glass(self):
        drags = {}
        for scene_id in DRAGS:
            scene = self.scenes[scene_id]
            self.assertEqual(scene.track, ("glass",))
            self.assertEqual(scene.motion, PRESS_MOTION)
            self.assertEqual(scene.backdrops, ("photo",))
            (drag,) = [step["pressDrag"] for step in scene.steps if "pressDrag" in step]
            drags[scene_id] = drag
        self.assertGreaterEqual(drags["material.drag.fast"]["velocity"], 600)
        out = drags["material.drag.out"]
        self.assertEqual(201 + out["to"]["dx"] - (201 + 125), 40)
        region = self.scenes["material.drag.out"].regions["glass"]
        self.assertLessEqual(region[0], 201 - 125 - 30)
        self.assertGreaterEqual(region[0] + region[2], 201 + out["to"]["dx"])
        self.assertEqual(drags["material.drag.far"]["to"]["dy"] - 44, 256)
        self.assertLess(drags["material.drag.up"]["to"]["dy"] + 44, 0)

    def test_the_operator_sizes_are_pressed_and_judged_like_the_2b1_sizes(self):
        for scene_id in HELD_OUT:
            scene = self.scenes[scene_id]
            self.assertEqual(scene.track, ("glass",))
            self.assertEqual(scene.backdrops, ("photo",))
            self.assertEqual(scene.motion, PRESS_MOTION)
            self.assertEqual([step["press"]["duration"] for step in scene.steps if "press" in step], [1.0])

    def test_neighbour_scenes_press_the_left_glass_and_track_both_without_overlap(self):
        for scene_id in NEIGHBOURS:
            scene = self.scenes[scene_id]
            self.assertEqual(scene.track, ("left", "right"))
            self.assertEqual(scene.backdrops, ("photo",))
            self.assertEqual(scene.motion, PRESS_MOTION)
            self.assertEqual([step["press"]["at"] for step in scene.steps if "press" in step], ["left"])
            left, right = scene.regions["left"], scene.regions["right"]
            self.assertLessEqual(left[0] + left[2], right[0])
            gap = int(scene_id.split(".")[-1])
            facing = 201 + gap / 2
            self.assertGreaterEqual(right[0] - facing, 32)
            self.assertGreaterEqual(right[0] + right[2], facing + 120 + 16)
            x, y, w, h = scene.pinned["right"]
            self.assertGreaterEqual(x - facing, 32)
            self.assertLessEqual(x + w, facing + 120 - 24)
            self.assertTrue(407 < y and y + h < 495)

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
