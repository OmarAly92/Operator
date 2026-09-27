import json
import time
from pathlib import Path

import numpy as np
from PIL import Image

import build
import material_table
import metrics
import record
import sim

CAP = 10.0
WEIGHTS = {key: metrics.THRESHOLDS[key] for key in ("mad", "luminance", "rim_rms", "centre_pt", "bbox_pt")}
PAD = 12


def score(stat, measures=tuple(WEIGHTS)):
    return sum(min(stat[key] / WEIGHTS[key], CAP) for key in measures)


def parse_params(text):
    grid = {}
    for item in text.split(","):
        name, spec = item.split("=")
        low, high, count = spec.split(":")
        values = np.linspace(float(low), float(high), int(count))
        grid[name.strip()] = [round(float(v), 4) for v in values]
    return grid


def coordinate_descent(evaluate, grid, start, min_gain=0.01, max_passes=4):
    best = dict(start)
    best_score = evaluate(best)
    log = [(dict(best), best_score)]
    for _ in range(max_passes):
        before = best_score
        for name, values in grid.items():
            for value in values:
                if value == best.get(name):
                    continue
                candidate = {**best, name: value}
                result = evaluate(candidate)
                log.append((candidate, result))
                if result < best_score:
                    best, best_score = candidate, result
        if before - best_score < min_gain * before:
            break
    for name, values in grid.items():
        if len(values) < 2:
            continue
        step = (values[1] - values[0]) / 2
        for value in (best[name] - step, best[name] + step):
            candidate = {**best, name: round(value, 4)}
            result = evaluate(candidate)
            log.append((candidate, result))
            if result < best_score:
                best, best_score = candidate, result
    return best, best_score, log


def element_box(boxes, size):
    if not boxes:
        return None
    return min(boxes, key=lambda box: abs(min(box[2], box[3]) - size))


def named_region(scene, names):
    boxes = [tuple(scene.regions[name]) for name in names]
    return metrics.union(boxes, pad=PAD)


def table_key(scene, appearance, row, size):
    if material_table.for_scene(scene.id) is material_table.SCROLL_EDGE:
        return f"{appearance}.{scene.id.rsplit('.', 1)[1]}"
    return f"{appearance}.{row}.{size}"


def field(name):
    return name.removeprefix(material_table.EDGE_PREFIX)


def filmstrip(native, flutter, region, dest):
    a, b = metrics.crop(native, region), metrics.crop(flutter, region)
    difference = np.clip(np.abs(a - b) * 4, 0, 255)
    strip = np.concatenate([a, b, difference], axis=1).astype(np.uint8)
    Image.fromarray(strip).save(dest)


class Evaluator:
    def __init__(self, udid, scene, backdrops, size, flutter_target, out, regions=()):
        self.udid = udid
        self.scene = scene
        self.backdrops = backdrops
        self.size = size
        self.regions = tuple(regions)
        self.target = build.FLUTTER_TARGETS[flutter_target]
        self.out = Path(out)
        self.count = 0
        self.cache = {}
        self.records = []

    def _drive(self, target, backdrop, bare, folder, material=None):
        record.drive(self.udid, target, self.scene.id, [], backdrop, bare, folder, settle=1.0, material=material)
        return metrics.load(Path(folder) / "ready.png")

    def region(self, native, native_bare):
        if self.scene.track:
            return tuple(self.scene.regions[self.scene.track])
        if self.regions:
            return named_region(self.scene, self.regions)
        box = element_box(metrics.glass_boxes(native, native_bare), self.size)
        return metrics.union([box], pad=PAD) if box else (0, 0, *metrics.SCREEN)

    def references(self, backdrop):
        if backdrop not in self.cache:
            base = self.out / "reference" / backdrop
            native = self._drive(build.NATIVE_BUNDLE, backdrop, False, base / "native")
            native_bare = self._drive(build.NATIVE_BUNDLE, backdrop, True, base / "native_bare")
            flutter_bare = self._drive(self.target, backdrop, True, base / "flutter_bare")
            self.cache[backdrop] = (native, native_bare, flutter_bare, self.region(native, native_bare))
        return self.cache[backdrop]

    def __call__(self, material):
        self.count += 1
        total, stats = 0.0, {}
        for backdrop in self.backdrops:
            native, native_bare, flutter_bare, region = self.references(backdrop)
            folder = self.out / "candidates" / f"{self.count:04d}" / backdrop
            flutter = self._drive(self.target, backdrop, False, folder, material)
            stat = metrics.static_compare(native, flutter, native_bare, flutter_bare, region)
            stats[backdrop] = {key: stat[key] for key in self.scene.measures}
            total += score(stat, self.scene.measures)
        result = total / len(self.backdrops)
        entry = {"n": self.count, "material": material, "score": result, "stats": stats, "time": time.time()}
        self.records.append(entry)
        with open(self.out / "log.jsonl", "a") as handle:
            handle.write(json.dumps(entry) + "\n")
        print(f"  #{self.count} score {result:.3f} {json.dumps(material)}", flush=True)
        return result

    def filmstrips(self):
        best = min(self.records, key=lambda entry: entry["score"])
        for backdrop in self.backdrops:
            native, _, _, region = self.references(backdrop)
            flutter = metrics.load(self.out / "candidates" / f"{best['n']:04d}" / backdrop / "ready.png")
            filmstrip(native, flutter, region, self.out / f"best-{backdrop}.png")


def run(udid, scene, appearance, backdrops, grid, row, size, flutter_target, out, write=False, max_passes=4, regions=()):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    sim.appearance(udid, appearance)
    table = material_table.for_scene(scene.id)
    key = table_key(scene, appearance, row, size)
    current = material_table.read(table=table).get(key, {})
    start = {name: current.get(field(name), grid[name][len(grid[name]) // 2]) for name in grid}
    evaluate = Evaluator(udid, scene, backdrops, size, flutter_target, out, regions)
    best, best_score, _ = coordinate_descent(evaluate, grid, start, max_passes=max_passes)
    evaluate.filmstrips()
    summary = {"key": key, "scene": scene.id, "backdrops": backdrops, "start": start, "start_score": evaluate.records[0]["score"], "best": best, "best_score": best_score}
    (out / "best.json").write_text(json.dumps(summary, indent=2))
    if write:
        material_table.update(key, {field(name): value for name, value in best.items()}, table=table)
    return summary
