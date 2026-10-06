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

    def test_a_touch_whose_release_frame_was_lost_keeps_its_window(self):
        states = [(0.0, "idle"), (1.0, "down"), (1.4, "move"), (1.9, "idle"), (3.0, "down"), (3.1, "up"), (3.35, "idle")]
        self.assertEqual(touch.touches(states), [(1.0, 1.65), (3.0, 3.1)])
        self.assertEqual(touch.touches([(0.0, "idle"), (1.0, "down"), (1.1, "idle")]), [(1.0, 1.0)])

    def test_a_lone_release_frame_shorter_than_the_marker_hold_is_not_a_touch(self):
        states = [(0.0, "idle"), (1.0, "down"), (1.1, "idle"), (2.0, "idle"), (2.1, "up"), (2.117, "idle"), (3.0, "down"), (3.1, "up"), (3.35, "idle")]
        self.assertEqual(touch.touches(states), [(1.0, 1.0), (3.0, 3.1)])
        self.assertEqual(touch.touches([(0.0, "idle"), (2.0, "up"), (2.1, "down"), (2.2, "up"), (2.45, "idle")]), [(2.0, 2.0), (2.1, 2.2)])
        self.assertEqual(touch.touches([(0.0, "idle"), (5.0, "up")]), [(5.0, 5.0)])

    def test_a_double_tap_owns_both_of_its_windows_and_later_steps_keep_theirs(self):
        steps = [{"wait": 0.5}, {"doubleTap": "glass"}, {"wait": 1.2}, {"tap": "toggle"}]
        windows = [(1.0, 1.05), (1.2, 1.25), (3.0, 3.05)]
        self.assertEqual(touch.step_windows(steps, windows), {1: [(1.0, 1.05), (1.2, 1.25)], 3: [(3.0, 3.05)]})
        self.assertEqual(touch.owner(1.3, steps, windows), 1)
        self.assertEqual(touch.owner(3.1, steps, windows), 3)
        self.assertEqual(touch.step_times(steps, windows), {1: 1.25, 3: 3.05})

    def test_a_double_tap_that_lost_one_window_does_not_take_the_next_steps(self):
        steps = [{"wait": 0.5}, {"doubleTap": "glass"}, {"wait": 1.2}, {"tap": "toggle"}]
        windows = [(1.0, 1.05), (3.0, 3.05)]
        self.assertEqual(touch.step_windows(steps, windows), {1: [(1.0, 1.05)], 3: [(3.0, 3.05)]})
        self.assertEqual(touch.owner(3.1, steps, windows), 3)
        self.assertEqual(touch.step_times(steps, windows), {1: 1.05, 3: 3.05})

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
