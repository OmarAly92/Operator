import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import analyze
import manifest

REGISTERED = re.compile(r'^\s*"([a-z0-9.]+)": \{ AnyView', re.M)


def valid_scene(**changes):
    entry = {
        "id": "menu.bar",
        "group": "presentations",
        "title": "Menu",
        "inventory": "4.6",
        "app": "lab",
        "backdrops": ["stripes"],
        "appearances": ["dark"],
        "steps": [{"wait": 0.5}, {"tap": "menu.button"}, {"tap": [100, 700]}],
    }
    entry.update(changes)
    return entry


class ValidationTests(unittest.TestCase):
    def test_accepts_a_valid_scene(self):
        self.assertEqual(manifest.validate([valid_scene()]), [])

    def test_rejects_duplicate_ids(self):
        errors = manifest.validate([valid_scene(), valid_scene()])
        self.assertTrue(any("duplicate" in e for e in errors))

    def test_rejects_unknown_backdrop_and_step(self):
        errors = manifest.validate([valid_scene(backdrops=["sunset"], steps=[{"swipe": [1, 2]}])])
        self.assertTrue(any("backdrop sunset" in e for e in errors))
        self.assertTrue(any("unknown step swipe" in e for e in errors))

    def test_rejects_bad_targets(self):
        errors = manifest.validate([valid_scene(steps=[{"tap": [1]}, {"pressDrag": {"from": "a"}}])])
        self.assertEqual(len(errors), 2)

    def test_only_apple_scenes_target_other_apps(self):
        errors = manifest.validate([valid_scene(app="com.apple.Maps")])
        self.assertTrue(any("only apple scenes" in e for e in errors))

    def test_rest_means_waits_only(self):
        rest = manifest.parse([valid_scene(steps=[{"wait": 1.0}])])[0]
        moving = manifest.parse([valid_scene()])[0]
        self.assertTrue(rest.rest)
        self.assertFalse(moving.rest)

    def test_measures_default_to_every_static_measure(self):
        scene = manifest.parse([valid_scene()])[0]
        self.assertEqual(scene.measures, manifest.STATIC_MEASURES)

    def test_measures_restrict_and_are_validated(self):
        scene = manifest.parse([valid_scene(measures=["mad", "luminance"])])[0]
        self.assertEqual(scene.measures, ("mad", "luminance"))
        errors = manifest.validate([valid_scene(measures=["mad", "sharpness"])])
        self.assertTrue(any("unknown measure sharpness" in e for e in errors))
        errors = manifest.validate([valid_scene(measures=[])])
        self.assertTrue(any("measures must be a non-empty list" in e for e in errors))

    def test_select_by_id_group_and_prefix(self):
        scenes = manifest.parse([valid_scene(), valid_scene(id="menu.submenu"), valid_scene(id="toggle", group="controls")])
        self.assertEqual([s.id for s in manifest.select(scenes, "menu")], ["menu.bar", "menu.submenu"])
        self.assertEqual([s.id for s in manifest.select(scenes, "controls")], ["toggle"])
        self.assertEqual(len(manifest.select(scenes, "all")), 3)
        with self.assertRaises(ValueError):
            manifest.select(scenes, "nothing")


class RealManifestTests(unittest.TestCase):
    def test_real_manifest_is_valid(self):
        self.assertEqual(manifest.validate(json.loads(manifest.MANIFEST.read_text())), [])

    def test_lab_ids_match_the_native_registry(self):
        swift = "".join(path.read_text() for path in (manifest.LAB / "native" / "GlassLab").glob("*Scenes.swift"))
        registered = set(REGISTERED.findall(swift))
        lab = {scene.id for scene in manifest.load() if not scene.native_only}
        self.assertEqual(lab, registered)


class TrackTests(unittest.TestCase):
    def base(self, **changes):
        entry = {"id": "x", "group": "material", "title": "t", "inventory": "2.13", "app": "lab", "backdrops": ["stripes"], "appearances": ["dark"], "steps": [], "regions": {"a": [0, 0, 1, 1], "b": [1, 1, 1, 1]}}
        entry.update(changes)
        return entry

    def test_a_single_track_name_means_a_list_of_one(self):
        self.assertEqual(manifest.parse([self.base(track="a")])[0].track, ("a",))
        self.assertEqual(manifest.parse([self.base(track=["a", "b"])])[0].track, ("a", "b"))
        self.assertEqual(manifest.parse([self.base()])[0].track, ())

    def test_topology_regions_are_validated(self):
        self.assertEqual(manifest.parse([self.base(topology="a")])[0].topology, ("a",))
        self.assertTrue(any("topology names an unknown region" in e for e in manifest.validate([self.base(topology=["z"])])))
        self.assertEqual(manifest.validate([self.base(topology=["a", "b"])]), [])

    def test_tracks_and_motion_measures_are_validated(self):
        self.assertTrue(any("unknown region" in e for e in manifest.validate([self.base(track=["a", "c"])])))
        self.assertTrue(any("non-empty list" in e for e in manifest.validate([self.base(track=[])])))
        self.assertTrue(any("unknown motion measure progress.wobble" in e for e in manifest.validate([self.base(track="a", motion=["progress.wobble"])])))
        self.assertTrue(any("need a track" in e for e in manifest.validate([self.base(motion=["progress.rms"])])))
        self.assertEqual(manifest.validate([self.base(track="a", motion=list(manifest.MOTION_MEASURES))]), [])

    def test_tracked_regions_are_not_rim_elements_and_the_union_is_the_region(self):
        scene = manifest.parse([self.base(track=["a"])])[0]
        self.assertEqual(analyze.elements_for(scene), {"b": (1, 1, 1, 1)})
        self.assertEqual(analyze.region_for(scene, Path("/nonexistent")), (0, 0, 1, 1))

    def test_touch_scenes_are_the_ones_with_touch_steps(self):
        self.assertTrue(manifest.parse([self.base(steps=[{"wait": 1}, {"tap": "x"}])])[0].touches)
        self.assertFalse(manifest.parse([self.base(steps=[{"wait": 1}])])[0].touches)


if __name__ == "__main__":
    unittest.main()
