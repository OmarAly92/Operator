import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import align
import touch


class TouchTests(unittest.TestCase):
    def test_colours_classify(self):
        self.assertEqual(touch.classify(np.full((4, 4, 3), (255, 0, 0))), "down")
        self.assertEqual(touch.classify(np.full((4, 4, 3), (0, 255, 0))), "move")
        self.assertEqual(touch.classify(np.full((4, 4, 3), (0, 0, 255))), "up")
        self.assertEqual(touch.classify(np.full((4, 4, 3), (5, 5, 5))), "idle")
        self.assertEqual(touch.classify(np.full((4, 4, 3), (128, 128, 128))), "unknown")

    def test_touches_pair_each_down_with_its_release(self):
        states = [(0.0, "idle"), (1.0, "down"), (1.5, "move"), (2.0, "up"), (2.3, "idle"), (3.0, "down"), (3.05, "up"), (3.1, "down"), (3.2, "up")]
        self.assertEqual(touch.touches(states), [(1.0, 2.0), (3.0, 3.05), (3.1, 3.2)])

    def test_a_tap_shorter_than_a_frame_shows_only_its_release(self):
        self.assertEqual(touch.touches([(0.0, "idle"), (17.578, "up"), (17.797, "idle")]), [(17.578, 17.578)])

    def test_events_belong_to_the_step_whose_touch_came_last(self):
        steps = [{"wait": 0.5}, {"tap": "toggle"}, {"wait": 1.2}, {"press": {"at": "glass", "duration": 1.0}}]
        windows = [(1.0, 1.1), (3.0, 4.0)]
        self.assertIsNone(touch.owner(0.5, steps, windows))
        self.assertEqual(touch.owner(1.2, steps, windows), 1)
        self.assertEqual(touch.owner(3.05, steps, windows), 3)
        self.assertEqual(touch.step_times(steps, windows), {1: 1.1, 3: 3.0})

    def test_the_marker_is_never_a_glass_box(self):
        self.assertEqual(touch.without_marker([(16, 662, 18, 18), (76, 400, 250, 88)]), [(76, 400, 250, 88)])

    def test_the_marker_never_joins_the_changed_extent(self):
        first = np.zeros((800, 400, 3), dtype=np.float32)
        changed = first.copy()
        changed[400:480, 96:200] = 255
        changed[662:680, 16:34] = 255
        self.assertEqual(align.extent([first, changed]), [(16, 400, 184, 280)])
        self.assertEqual(align.extent([first, changed], ignore=(touch.MARKER,)), [(96, 400, 104, 80)])
        marker_only = first.copy()
        marker_only[662:680, 16:34] = 255
        self.assertEqual(align.extent([first, marker_only], ignore=(touch.MARKER,)), [])


if __name__ == "__main__":
    unittest.main()
