import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import manifest
import material_table
import tune


def scene(scene_id, **extra):
    entry = {
        "id": scene_id,
        "group": "material",
        "title": "t",
        "inventory": "2.1",
        "app": "lab",
        "backdrops": ["stripes"],
        "appearances": ["dark"],
        "steps": [],
        **extra,
    }
    return manifest.parse([entry])[0]


class ScoreTests(unittest.TestCase):
    def test_perfect_match_scores_zero(self):
        self.assertEqual(tune.score({"mad": 0, "luminance": 0, "rim_rms": 0, "centre_pt": 0, "bbox_pt": 0}), 0)

    def test_each_measure_is_capped(self):
        worst = {"mad": 1e9, "luminance": 1e9, "rim_rms": 1e9, "centre_pt": float("inf"), "bbox_pt": 1e9}
        self.assertEqual(tune.score(worst), 5 * tune.CAP)

    def test_threshold_values_score_one_each(self):
        self.assertAlmostEqual(tune.score({"mad": 4, "luminance": 3, "rim_rms": 6, "centre_pt": 1, "bbox_pt": 1}), 5)

    def test_scores_only_the_scene_measures(self):
        stat = {"mad": 8, "luminance": 3, "rim_rms": 1e9, "centre_pt": 1e9, "bbox_pt": 1e9}
        self.assertAlmostEqual(tune.score(stat, ("mad", "luminance")), 3)


class ParamTests(unittest.TestCase):
    def test_parses_ranges(self):
        grid = tune.parse_params("toneBlack=0:0.4:5,toneWhite=0.5:1:2")
        self.assertEqual(grid["toneBlack"], [0.0, 0.1, 0.2, 0.3, 0.4])
        self.assertEqual(grid["toneWhite"], [0.5, 1.0])

    def test_parses_scroll_edge_names(self):
        self.assertEqual(tune.parse_params("edge.blur=2:6:3"), {"edge.blur": [2.0, 4.0, 6.0]})
        self.assertEqual(tune.field("edge.blur"), "blur")
        self.assertEqual(tune.field("toneBlack"), "toneBlack")


class DescentTests(unittest.TestCase):
    def test_finds_the_optimum_of_a_separable_bowl(self):
        target = {"toneBlack": 0.2, "toneWhite": 0.7}
        evaluate = lambda m: (m["toneBlack"] - target["toneBlack"]) ** 2 + (m["toneWhite"] - target["toneWhite"]) ** 2
        grid = tune.parse_params("toneBlack=0:0.4:5,toneWhite=0.5:1:6")
        best, value, log = tune.coordinate_descent(evaluate, grid, {"toneBlack": 0.0, "toneWhite": 1.0})
        self.assertAlmostEqual(best["toneBlack"], 0.2)
        self.assertAlmostEqual(best["toneWhite"], 0.7)
        self.assertLess(value, 1e-9)
        self.assertGreater(len(log), 1)

    def test_start_is_kept_when_nothing_is_better(self):
        best, value, _ = tune.coordinate_descent(lambda m: abs(m["toneBlack"] - 0.1), {"toneBlack": [0.0, 0.1, 0.2]}, {"toneBlack": 0.1})
        self.assertEqual(best, {"toneBlack": 0.1})
        self.assertEqual(value, 0)


class ElementTests(unittest.TestCase):
    def test_picks_the_box_whose_shorter_side_is_closest(self):
        boxes = [(4, 455, 395, 236), (75, 329, 252, 97), (125, 237, 152, 44)]
        self.assertEqual(tune.element_box(boxes, 44), (125, 237, 152, 44))
        self.assertEqual(tune.element_box(boxes, 88), (75, 329, 252, 97))
        self.assertEqual(tune.element_box(boxes, 200), (4, 455, 395, 236))

    def test_named_regions_are_unioned_and_padded(self):
        tinted = scene("material.tinted", regions={"block": [76, 365, 250, 88], "run": [162, 501, 78, 37]})
        self.assertEqual(tune.named_region(tinted, ["block"]), (64, 353, 274, 112))
        self.assertEqual(tune.named_region(tinted, ["block", "run"]), (64, 353, 274, 197))

    def test_keys_material_rows_by_row_and_size_and_edges_by_style(self):
        self.assertEqual(tune.table_key(scene("material.regular"), "dark", "regular", 88), "dark.regular.88")
        edge = scene("material.edge.hard", regions={"edge": [0, 0, 402, 240]}, track="edge")
        self.assertEqual(tune.table_key(edge, "light", "regular", 88), "light.hard")


class FilmstripTests(unittest.TestCase):
    def test_writes_native_candidate_and_difference_side_by_side(self):
        native = np.zeros((30, 30, 3), dtype=np.float32)
        flutter = np.full((30, 30, 3), 10, dtype=np.float32)
        with tempfile.TemporaryDirectory() as temp:
            dest = Path(temp) / "best.png"
            tune.filmstrip(native, flutter, (0, 0, 10, 10), dest)
            image = np.asarray(Image.open(dest))
        self.assertEqual(image.shape, (30, 90, 3))
        self.assertEqual(int(image[0, 75, 0]), 40)


class EvaluatorTests(unittest.TestCase):
    def _evaluator(self, scene_obj, row_overrides):
        with tempfile.TemporaryDirectory() as out:
            evaluate = tune.Evaluator("udid", scene_obj, ["stripes"], 88, "example", out, row_overrides=row_overrides)
            image = np.zeros((3, 3, 3), dtype=np.float32)
            evaluate.references = lambda backdrop: (image, image, image, (0, 0, 3, 3))
            yield evaluate

    def test_sends_the_whole_material_row_merged_with_the_candidate(self):
        row = {"toneBlack": 0.1, "toneWhite": 0.8}
        for evaluate in self._evaluator(scene("material.regular"), row):
            sent = []
            with mock.patch.object(tune.record, "drive", side_effect=lambda *a, **k: sent.append(k.get("material"))), \
                 mock.patch.object(tune.metrics, "load", return_value=np.zeros((3, 3, 3), dtype=np.float32)), \
                 mock.patch.object(tune.metrics, "static_compare", return_value={"mad": 0, "luminance": 0, "rim_rms": 0, "centre_pt": 0, "bbox_pt": 0}):
                evaluate({"toneBlack": 0.3})
            self.assertEqual(sent, [{"toneBlack": 0.3, "toneWhite": 0.8}])
            self.assertEqual(evaluate.records[-1]["material"], {"toneBlack": 0.3})

    def test_sends_the_whole_scroll_edge_row_merged_with_the_candidate(self):
        edge = scene("material.edge.hard", regions={"edge": [0, 0, 402, 240]}, track="edge")
        row_overrides = {material_table.EDGE_PREFIX + "blur": 4.0, material_table.EDGE_PREFIX + "dim": 0.6}
        for evaluate in self._evaluator(edge, row_overrides):
            sent = []
            with mock.patch.object(tune.record, "drive", side_effect=lambda *a, **k: sent.append(k.get("material"))), \
                 mock.patch.object(tune.metrics, "load", return_value=np.zeros((3, 3, 3), dtype=np.float32)), \
                 mock.patch.object(tune.metrics, "static_compare", return_value={"mad": 0, "luminance": 0, "rim_rms": 0, "centre_pt": 0, "bbox_pt": 0}):
                evaluate({material_table.EDGE_PREFIX + "blur": 5.0})
            self.assertEqual(sent, [{material_table.EDGE_PREFIX + "blur": 5.0, material_table.EDGE_PREFIX + "dim": 0.6}])
            self.assertEqual(evaluate.records[-1]["material"], {material_table.EDGE_PREFIX + "blur": 5.0})


class TableTests(unittest.TestCase):
    def test_round_trip_and_update(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "ios27.dart"
            table = {"dark.regular.44": {"toneBlack": 0.1, "toneWhite": 0.75}, "light.clear.200": {"frost": 1.5}}
            material_table.write(table, path)
            self.assertEqual(material_table.read(path), table)
            material_table.update("dark.regular.44", {"toneBlack": 0.25}, path)
            self.assertEqual(material_table.read(path)["dark.regular.44"], {"toneBlack": 0.25, "toneWhite": 0.75})

    def test_rows_are_ordered_by_appearance_row_and_numeric_anchor(self):
        table = {"light.regular.44": {}, "dark.regular.200": {}, "dark.regular.44": {}, "dark.clear.88": {}}
        keys = [line.split("'")[1] for line in material_table.format_table(table).splitlines()[1:-1]]
        self.assertEqual(keys, ["dark.regular.44", "dark.regular.200", "dark.clear.88", "light.regular.44"])

    def test_scroll_edge_table_round_trips_in_style_order(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "edge.dart"
            rows = {"light.soft": {"blur": 4.0}, "dark.automatic": {"dim": 0.6}, "dark.soft": {"knee": 0.45}}
            material_table.write(rows, path, material_table.SCROLL_EDGE)
            text = path.read_text()
            self.assertTrue(text.startswith("const Map<String, Map<String, double>> ios27ScrollEdgeTable = {"))
            self.assertEqual(material_table.read(path, material_table.SCROLL_EDGE), rows)
            keys = [line.split("'")[1] for line in text.splitlines()[1:-1]]
            self.assertEqual(keys, ["dark.soft", "dark.automatic", "light.soft"])

    def test_scenes_pick_their_table(self):
        self.assertIs(material_table.for_scene("material.edge.soft"), material_table.SCROLL_EDGE)
        self.assertIs(material_table.for_scene("material.regular"), material_table.MATERIAL)

    def test_the_committed_tables_parse_with_every_row(self):
        table = material_table.read()
        self.assertEqual(len(table), 30)
        for appearance in material_table.APPEARANCES:
            for row in material_table.ROWS:
                for anchor in material_table.ANCHORS:
                    self.assertIn(f"{appearance}.{row}.{anchor}", table)
        edges = material_table.read(table=material_table.SCROLL_EDGE)
        self.assertEqual(sorted(edges), sorted(f"{a}.{s}" for a in material_table.APPEARANCES for s in material_table.STYLES))

    def test_the_committed_tables_are_in_writer_format(self):
        for table in (material_table.MATERIAL, material_table.SCROLL_EDGE):
            text = table.path.read_text()
            self.assertEqual(material_table.format_table(material_table.parse(text, table), table), text)


if __name__ == "__main__":
    unittest.main()
