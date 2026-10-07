import unittest

import numpy as np

import measure

SCALE = 3


def disc_mask(height, width, circles, scale=SCALE):
    ys = (np.arange(height * scale) + 0.5) / scale
    xs = (np.arange(width * scale) + 0.5) / scale
    x, y = np.meshgrid(xs, ys)
    mask = np.zeros(x.shape, dtype=bool)
    for cx, cy, r in circles:
        mask |= np.hypot(x - cx, y - cy) <= r
    return mask


def glyph(size, scale=SCALE):
    n = size * scale
    image = np.zeros((n, n), dtype=np.float32)
    image[n // 2 - scale * 2 : n // 2 + scale * 2, scale * 3 : n - scale * 3] = 1
    image[scale * 3 : n - scale * 3, n // 2 - scale * 2 : n // 2 + scale * 2] = 1
    image[scale * 3 : scale * 7, scale * 3 : n - scale * 8] = 1
    return image


class ProfileTests(unittest.TestCase):
    def test_profile_reads_half_width_and_centre(self):
        mask = disc_mask(100, 80, [(40, 50, 20)])
        profile = measure.profile(mask)
        row = int(50 * SCALE)
        self.assertAlmostEqual(profile["half"][row], 20.0, delta=0.4)
        self.assertAlmostEqual(profile["centre"][row], 40.0, delta=0.4)
        self.assertEqual(profile["half"][int(10 * SCALE)], 0.0)

    def test_lobes_and_necks_of_a_stack(self):
        mask = disc_mask(160, 80, [(40, 40, 20), (40, 75, 20), (40, 125, 20)])
        found = measure.stack_topology(mask)
        self.assertEqual(found["count"], 2)
        self.assertEqual(len(found["lobes"]), 3)
        self.assertEqual(len(found["necks"]), 1)
        self.assertAlmostEqual(found["necks"][0]["y"], 57.5, delta=0.7)
        expected = 2 * np.sqrt(20**2 - 17.5**2)
        self.assertAlmostEqual(found["necks"][0]["width"], expected, delta=0.8)


class CircleFitTests(unittest.TestCase):
    def test_fits_overlapping_circles_from_seeds(self):
        truth = [(40, 50, 18), (40, 90, 30)]
        mask = disc_mask(160, 80, truth)
        fits = measure.fit_circles(mask, [48.0, 95.0], [20.0, 25.0])
        for (cx, cy, r), fit in zip(truth, fits):
            self.assertAlmostEqual(fit["cy"], cy, delta=0.5)
            self.assertAlmostEqual(fit["r"], r, delta=0.5)

    def test_hidden_circle_reports_none(self):
        mask = disc_mask(160, 80, [(40, 80, 30)])
        fits = measure.fit_circles(mask, [80.0, 80.0], [30.0, 10.0])
        self.assertIsNotNone(fits[0])
        self.assertAlmostEqual(fits[0]["r"], 30.0, delta=0.5)
        self.assertIsNone(fits[1])


class CapFitTests(unittest.TestCase):
    def test_bottom_and_top_caps_of_a_merged_stack(self):
        mask = disc_mask(200, 100, [(50, 60, 20), (50, 110, 36)])
        bottom = measure.cap_fit(mask, "bottom")
        top = measure.cap_fit(mask, "top")
        self.assertAlmostEqual(bottom["cy"], 110.0, delta=0.5)
        self.assertAlmostEqual(bottom["r"], 36.0, delta=0.5)
        self.assertAlmostEqual(top["cy"], 60.0, delta=0.5)
        self.assertAlmostEqual(top["r"], 20.0, delta=0.5)


class GlyphTests(unittest.TestCase):
    def test_finds_shifted_scaled_blurred_glyph(self):
        template = glyph(24)
        canvas = np.full((120 * SCALE, 60 * SCALE), 80.0, dtype=np.float32)
        placed = measure.transform(template, 1.2, 1.5 * SCALE)
        h, w = placed.shape
        cy, cx = 70 * SCALE, 31 * SCALE
        canvas[cy - h // 2 : cy - h // 2 + h, cx - w // 2 : cx - w // 2 + w] += 50 * placed
        found = measure.find_glyph(canvas, template)
        self.assertAlmostEqual(found["cy"], 70.0, delta=0.5)
        self.assertAlmostEqual(found["cx"], 31.0, delta=0.5)
        self.assertAlmostEqual(found["scale"], 1.2, delta=0.06)
        self.assertAlmostEqual(found["blur"], 1.5, delta=0.6)
        self.assertGreater(found["ncc"], 0.9)

    def test_max_blur_caps_the_search(self):
        template = glyph(24)
        canvas = np.full((120 * SCALE, 60 * SCALE), 80.0, dtype=np.float32)
        placed = measure.transform(template, 1.0, 2.5 * SCALE)
        h, w = placed.shape
        cy, cx = 60 * SCALE, 30 * SCALE
        canvas[cy - h // 2 : cy - h // 2 + h, cx - w // 2 : cx - w // 2 + w] += 50 * placed
        found = measure.find_glyph(canvas, template, max_blur=1.0)
        self.assertLessEqual(found["blur"], 1.0)
        self.assertAlmostEqual(found["cy"], 60.0, delta=0.7)

    def test_flat_noise_never_wins(self):
        template = glyph(24) * 120 + 60
        rng = np.random.default_rng(1)
        canvas = rng.normal(0.0, 0.01, (120 * SCALE, 60 * SCALE)).astype(np.float32)
        canvas[30 * SCALE : 90 * SCALE] = 80.0
        placed = measure.transform(glyph(24), 1.0, 0.0)
        h, w = placed.shape
        cy, cx = 60 * SCALE, 30 * SCALE
        canvas[cy - h // 2 : cy - h // 2 + h, cx - w // 2 : cx - w // 2 + w] += 40 * placed
        found = measure.find_glyph(canvas, template)
        self.assertAlmostEqual(found["cy"], 60.0, delta=0.5)
        self.assertGreater(found["ncc"], 0.95)


if __name__ == "__main__":
    unittest.main()
