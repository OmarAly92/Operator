import json
import statistics
import subprocess
import time
from pathlib import Path

import record
import sim

PERF_FILE = "perf.json"
ACCESSIBILITY_FILE = "accessibility.json"
PERF_SCENES = ("perf.none", "perf.glass", "perf.material", "perf.edge")
FLAGS = {"reduce-transparency": "reduceTransparency", "increase-contrast": "increaseContrast", "reduce-motion": "reduceMotion"}


def read_json(path):
    try:
        return json.loads(Path(path).read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def wait_for(read, accept, timeout, interval=0.25):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = read()
        if value is not None and accept(value):
            return value
        time.sleep(interval)
    raise TimeoutError("the app never reported the expected value")


def launch(udid, bundle, scene_id, backdrop="stripes"):
    folder = record.launch_folder(udid, bundle)
    record.write_launch_file(folder, scene_id, backdrop, False)
    subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", udid, bundle], check=True, capture_output=True)
    return folder


def terminate(udid, bundle):
    subprocess.run(["xcrun", "simctl", "terminate", udid, bundle], capture_output=True)


def perf_order(scenes, takes):
    return [scene for take in range(takes) for scene in (scenes if take % 2 == 0 else tuple(reversed(scenes)))]


def perf_take(udid, bundle, scene_id, timeout=40):
    folder = record.launch_folder(udid, bundle)
    (folder / PERF_FILE).unlink(missing_ok=True)
    try:
        launch(udid, bundle, scene_id)
        return wait_for(lambda: read_json(folder / PERF_FILE), lambda value: value.get("scene") == scene_id, timeout)
    finally:
        terminate(udid, bundle)
        record.clear_launch_file(folder)


def perf_summary(takes):
    summary = {}
    for scene_id, results in takes.items():
        summary[scene_id] = {
            "takes": len(results),
            "frames": sum(r["frames"] for r in results),
            "raster_median_ms": statistics.median(r["raster_ms"]["median"] for r in results),
            "raster_p90_ms": statistics.median(r["raster_ms"]["p90"] for r in results),
            "build_median_ms": statistics.median(r["build_ms"]["median"] for r in results),
        }
    if "perf.none" in summary:
        for scene_id in summary.copy():
            if scene_id != "perf.none":
                summary[f"{scene_id.removeprefix('perf.')}_cost_ms"] = summary[scene_id]["raster_median_ms"] - summary["perf.none"]["raster_median_ms"]
    return summary


def perf(udid, bundle, takes=3, scenes=PERF_SCENES):
    results = {scene: [] for scene in scenes}
    for scene_id in perf_order(scenes, takes):
        results[scene_id].append(perf_take(udid, bundle, scene_id))
    return perf_summary(results)


def accessibility_check(udid, bundle, modes=tuple(FLAGS), timeout=10):
    folder = record.launch_folder(udid, bundle)
    (folder / ACCESSIBILITY_FILE).unlink(missing_ok=True)
    results = {}
    sim.accessibility(udid, "none")
    try:
        launch(udid, bundle, "material.regular")
        read = lambda: read_json(folder / ACCESSIBILITY_FILE)
        wait_for(read, lambda value: not any(value.values()), timeout)
        for mode in modes:
            sim.accessibility(udid, mode)
            try:
                seen = wait_for(read, lambda value: value.get(FLAGS[mode]) is True, timeout)
                results[mode] = {"live": True, "seen": seen}
            except TimeoutError:
                results[mode] = {"live": False, "seen": read()}
            sim.accessibility(udid, "none")
            try:
                wait_for(read, lambda value: not any(value.values()), timeout)
            except TimeoutError:
                results[mode]["reset"] = False
    finally:
        sim.accessibility(udid, "none")
        terminate(udid, bundle)
        record.clear_launch_file(folder)
    return results
