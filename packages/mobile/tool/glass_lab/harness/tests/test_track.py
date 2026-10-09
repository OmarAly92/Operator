import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import track
from synthetic import chroma_ringing, disks, draw, frames, frosted_pair, glass_pair, grain, pair_geometry, stripes, with_codec_lines


class PixelRectTests(unittest.TestCase):
    def test_rects_are_even_and_cover_the_region(self):
        x, y, w, h = track.pixel_rect((46.5, 377.33, 310, 148))
        self.assertEqual((x % 2, y % 2, w % 2, h % 2), (0, 0, 0, 0))
        self.assertLessEqual(x, 46.5 * 3)
        self.assertLessEqual(y, 377.33 * 3)
        self.assertGreaterEqual(x + w, (46.5 + 310) * 3)
        self.assertGreaterEqual(y + h, (377.33 + 148) * 3)


class BoxTests(unittest.TestCase):
    def test_finds_a_drawn_box_to_a_third_of_a_point_per_edge(self):
        bare = stripes()
        frame = draw(bare, (30, 20, 50, 20))
        x, y, w, h = track.box(frame, bare, track.edges(bare))
        self.assertAlmostEqual(x, 30, delta=0.34)
        self.assertAlmostEqual(y, 20, delta=0.34)
        self.assertAlmostEqual(w, 50, delta=0.67)
        self.assertAlmostEqual(h, 20, delta=0.67)

    def test_codec_lines_at_backdrop_edges_do_not_widen_the_box(self):
        bare = stripes()
        frame = with_codec_lines(draw(bare, (50, 20, 20, 20)))
        x, y, w, h = track.box(frame, bare, track.edges(bare))
        self.assertAlmostEqual(x, 50, delta=0.34)
        self.assertAlmostEqual(w, 20, delta=0.67)
        self.assertAlmostEqual(h, 20, delta=0.67)

    def test_a_box_edge_on_a_backdrop_edge_is_flagged_as_inside_the_blind_band(self):
        bare = stripes()
        on_edge = track.shape_row(draw(bare, (40, 20, 30, 20)), bare, track.edges(bare), (0, 0))
        clear = track.shape_row(draw(bare, (50, 20, 20, 20)), bare, track.edges(bare), (0, 0))
        self.assertEqual(on_edge["band"], 1.0)
        self.assertEqual(clear["band"], 0.0)

    def test_a_box_whose_top_and_bottom_cross_a_backdrop_edge_is_not_flagged(self):
        bare = stripes()
        crossing = track.shape_row(draw(bare, (30, 20, 30, 20)), bare, track.edges(bare), (0, 0))
        self.assertEqual(crossing["band"], 0.0)

    def test_nothing_drawn_has_no_box(self):
        bare = stripes()
        self.assertIsNone(track.box(with_codec_lines(bare), bare, track.edges(bare)))

    def test_shape_rows_report_absolute_centres(self):
        bare = stripes()
        row = track.shape_row(draw(bare, (30, 20, 50, 20)), bare, track.edges(bare), (100, 200))
        self.assertAlmostEqual(row["cx"], 155, delta=0.5)
        self.assertAlmostEqual(row["cy"], 230, delta=0.5)
        empty = track.shape_row(bare, bare, track.edges(bare), (100, 200))
        self.assertEqual(empty["width"], 0.0)
        self.assertTrue(np.isnan(empty["cx"]))

    def test_shape_rows_report_each_outer_edge_in_absolute_points(self):
        bare = stripes()
        row = track.shape_row(draw(bare, (30, 20, 50, 20)), bare, track.edges(bare), (100, 200))
        self.assertAlmostEqual(row["xmin"], 130, delta=1.0)
        self.assertAlmostEqual(row["xmax"], 180, delta=1.0)
        self.assertAlmostEqual(row["ymin"], 220, delta=1.0)
        self.assertAlmostEqual(row["ymax"], 240, delta=1.0)
        empty = track.shape_row(bare, bare, track.edges(bare), (100, 200))
        self.assertTrue(all(np.isnan(empty[key]) for key in ("xmin", "xmax", "ymin", "ymax")))


class ProgressTests(unittest.TestCase):
    def setUp(self):
        rng = np.random.default_rng(3)
        self.bare = rng.uniform(0, 255, (40, 60, 3)).astype(np.float32)
        self.full = self.blur(self.bare, 6) + 30
        self.inner = (slice(5, 35), slice(5, 55))

    @staticmethod
    def blur(image, passes):
        for _ in range(passes):
            image = (image + np.roll(image, 1, 0) + np.roll(image, -1, 0) + np.roll(image, 1, 1) + np.roll(image, -1, 1)) / 5
        return image

    def test_an_alpha_mix_reads_its_alpha_with_no_residual(self):
        frame = self.bare + 0.3 * (self.full - self.bare)
        row = track.progress_row(frame, self.bare, self.full, self.inner)
        self.assertAlmostEqual(row["progress"], 0.3, places=4)
        self.assertAlmostEqual(row["residual"], 0.0, places=3)
        self.assertAlmostEqual(row["sharpness"], 0.0, places=3)

    def test_a_blurred_mix_is_not_an_alpha_fade_and_is_softer(self):
        blurred = self.blur(self.bare + 0.5 * (self.full - self.bare), 2)
        row = track.progress_row(blurred, self.bare, self.full, self.inner)
        self.assertGreater(row["residual"], 5)
        self.assertLess(row["sharpness"], -1)


class TopologyTests(unittest.TestCase):
    def setUp(self):
        self.bare = np.full((360, 720, 3), 40, dtype=np.float32)
        self.edges = track.edges(self.bare)

    def test_separate_glass_counts_two_and_has_no_neck(self):
        found = track.topology_row(disks(20), self.bare)
        self.assertEqual(found["count"], 2.0)
        self.assertTrue(np.isnan(found["neck"]))

    def test_a_video_topology_row_carries_the_gap_between_two_shapes(self):
        apart = track.topology_row(disks(20), self.bare)
        self.assertEqual(apart["count"], 2.0)
        self.assertAlmostEqual(apart["gap"], 20.0, delta=2.0)
        joined = track.topology_row(disks(0, bridge=20), self.bare)
        self.assertTrue(np.isnan(joined["gap"]))
        self.assertTrue(np.isnan(track.topology_row(self.bare.copy(), self.bare)["gap"]))

    def test_a_frame_with_no_glass_has_no_neck(self):
        found = track.topology_row(self.bare.copy(), self.bare)
        self.assertEqual(found["count"], 0.0)
        self.assertTrue(np.isnan(found["neck"]))

    def test_merged_glass_counts_one_and_measures_its_narrowest_neck(self):
        row = track.topology_row(disks(0, bridge=20), self.bare)
        self.assertEqual(row["count"], 1.0)
        self.assertAlmostEqual(row["neck"], 20, delta=1)
        overlapping = track.topology_row(disks(-10), self.bare)
        self.assertAlmostEqual(overlapping["neck"], 2 * (40**2 - 35**2) ** 0.5, delta=2)

    def test_still_screenshots_see_frosted_glass_that_the_video_mask_cannot(self):
        bare = grain(sigma=3.0)
        frame = frosted_pair(bare, 20)
        self.assertEqual(track.topology(track.still_mask(frame, bare))["count"], 2.0)
        self.assertEqual(track.topology_row(frame, bare)["count"], 0.0)

    def test_glass_across_rung_stripe_boundaries_counts_one_component_per_shape(self):
        bare = stripes(width=240, height=120)
        apart = track.topology_row(chroma_ringing(glass_pair(bare, 20)), bare)
        self.assertEqual(apart["count"], 2.0)
        self.assertTrue(np.isnan(apart["neck"]))
        joined = track.topology_row(chroma_ringing(glass_pair(bare, 0, bridge=20)), bare)
        self.assertEqual(joined["count"], 1.0)
        self.assertAlmostEqual(joined["neck"], 20, delta=1)

    def test_chroma_ringing_alone_is_not_glass(self):
        bare = stripes(width=240, height=120)
        self.assertEqual(track.topology_row(chroma_ringing(bare), bare)["count"], 0.0)

    def test_glass_seen_only_by_its_rim_is_filled(self):
        apart = track.topology_row(glass_pair(self.bare, 20, gain=1.0, lift=0.0), self.bare)
        self.assertEqual(apart["count"], 2.0)
        overlapping = track.topology_row(glass_pair(self.bare, -10, gain=1.0, lift=0.0), self.bare)
        self.assertEqual(overlapping["count"], 1.0)
        self.assertAlmostEqual(overlapping["neck"], 2 * (40**2 - 35**2) ** 0.5, delta=2)

    def test_the_video_topology_mask_leaves_the_box_mask_alone(self):
        bare = stripes(width=240, height=120)
        frame = chroma_ringing(glass_pair(bare, 20))
        before = track.glass_mask(frame, bare, track.edges(bare)).copy()
        track.topology_mask(frame, bare)
        self.assertTrue((track.glass_mask(frame, bare, track.edges(bare)) == before).all())

    def test_one_component_with_no_neck_is_not_a_join(self):
        mask = np.zeros((90, 300), dtype=bool)
        mask[30:60, 30:120] = True
        mask[30:60, 180:270] = True
        mask[30:33, 30:270] = True
        found = track.topology(mask)
        self.assertEqual(found["count"], 1.0)
        self.assertTrue(np.isnan(found["neck"]))


class StillTopologyTests(unittest.TestCase):
    def test_a_smooth_outline_between_close_shapes_is_not_glass(self):
        bare = grain()
        frame = frosted_pair(bare, 4, outline=11.0, reach=7)
        self.assertEqual(track.topology(track.still_mask(frame, bare))["count"], 2.0)

    def test_glass_that_wipes_the_grain_is_glass_at_any_level(self):
        bare = grain()
        self.assertEqual(track.topology(track.still_mask(frosted_pair(bare, 20), bare))["count"], 2.0)
        joined = track.topology(track.still_mask(frosted_pair(bare, -10, rim=40.0), bare))
        self.assertEqual(joined["count"], 1.0)
        self.assertAlmostEqual(joined["neck"], 2 * (40**2 - 35**2) ** 0.5, delta=2)

    def test_bright_glass_on_a_flat_backdrop_needs_no_grain(self):
        bare = np.zeros((360, 720, 3), dtype=np.float32)
        frame = glass_pair(bare, 20, gain=0.0, lift=130.0, rim=0.0)
        self.assertEqual(track.topology(track.still_mask(frame, bare))["count"], 2.0)
        joined = track.topology(track.still_mask(glass_pair(bare, -10, gain=0.0, lift=130.0, rim=0.0), bare))
        self.assertEqual(joined["count"], 1.0)


class FillTests(unittest.TestCase):
    def test_a_closed_ring_is_filled_and_an_open_one_is_not(self):
        ring = np.zeros((40, 40), dtype=bool)
        ring[5:35, 5:35] = True
        ring[8:32, 8:32] = False
        self.assertTrue(track.fill_holes(ring)[8:32, 8:32].all())
        ring[18:22, 5:8] = False
        self.assertFalse(track.fill_holes(ring)[8:32, 8:32].any())

    def test_holes_that_reach_the_border_stay_open(self):
        mask = np.zeros((20, 30), dtype=bool)
        mask[:, 10] = True
        self.assertEqual(int(track.fill_holes(mask).sum()), 20)


class GapTests(unittest.TestCase):
    def test_two_shapes_read_the_empty_run_between_them(self):
        distance = pair_geometry((360, 720), 20)[0]
        self.assertAlmostEqual(track.gap(distance <= 0), 20, delta=0.67)
        narrow = pair_geometry((360, 720), 4)[0]
        self.assertAlmostEqual(track.gap(narrow <= 0), 4, delta=0.67)

    def test_anything_but_two_components_has_no_gap(self):
        self.assertTrue(np.isnan(track.gap(pair_geometry((360, 720), -10)[0] <= 0)))
        self.assertTrue(np.isnan(track.gap(np.zeros((360, 720), dtype=bool))))
        three = pair_geometry((360, 720), 20)[0] <= 0
        three[0:60, 0:60] = True
        self.assertTrue(np.isnan(track.gap(three)))


class TeardownTests(unittest.TestCase):
    def test_frames_after_the_last_settled_match_are_dropped(self):
        import tempfile
        from PIL import Image
        settled = np.full((30, 30, 3), 100, dtype=np.float32)
        with tempfile.TemporaryDirectory() as temp:
            paths = []
            for i, value in enumerate((100, 140, 102, 101, 30)):
                path = Path(temp) / f"{i}.png"
                Image.fromarray(np.full((30, 30, 3), value, dtype=np.uint8)).save(path)
                paths.append(path)
            kept = track.teardown_cut(frames(paths, [0.0, 0.1, 0.2, 0.3, 0.4]), settled)
            self.assertEqual(kept.times, [0.0, 0.1, 0.2, 0.3])

    def test_the_rest_frame_before_the_window_is_kept_and_retimed(self):
        clipped = track.clip(frames(["a", "b", "c", "d"], [1.0, 5.0, 5.5, 9.0]), 4.8, 6.0)
        self.assertEqual(clipped.paths, ["a", "b", "c"])
        self.assertEqual(clipped.times, [4.8, 5.0, 5.5])


if __name__ == "__main__":
    unittest.main()
