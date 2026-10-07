import argparse
import json
import sys
from pathlib import Path

import numpy as np

ARGS = argparse.ArgumentParser(description="Still topology of every native N7 take with the harness's still mask: count, neck and gap per region, dark against light against light-black, checked against the light-photo silhouette.")
ARGS.add_argument("--harness", required=True)
ARGS.add_argument("--runs", required=True, help="the build/glass_lab/runs folder")
ARGS.add_argument("--silhouette", required=True, help="n7-photo-silhouette.json")
ARGS.add_argument("--out", required=True)
ARGS.add_argument("--summary", required=True)
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))

import manifest
import metrics
import track

SCENES = {scene.id: scene for scene in manifest.load()}
FRESH = ("20261007-000000", "20261007-002556")
EARLIER = ("20261004-003527",)
NECK_PX = 1.0 / metrics.SCALE + 1e-6


def spacing(scene_id):
    part = scene_id.split(".")[2]
    return 8.0 if part == "default" else float(part)


def takes(runs):
    found = []
    for run in FRESH + EARLIER:
        for scene_dir in sorted((runs / run).glob("material.spacing.*")):
            for case_dir in sorted(scene_dir.iterdir()):
                if (case_dir / "native" / "ready.png").exists():
                    found.append((scene_dir.name, case_dir.name, run, case_dir / "native"))
    for scene_dir in sorted((runs / "noise-2b1" / "takes").glob("material.spacing.*")):
        for case_dir in sorted(scene_dir.iterdir()):
            for take in sorted(case_dir.iterdir()):
                if (take / "ready.png").exists():
                    found.append((scene_dir.name, case_dir.name, f"noise-2b1/{take.name}", take))
    return found


def value(number):
    return round(float(number), 3) if np.isfinite(number) else None


def measure(scene_id, folder):
    scene = SCENES[scene_id]
    frame, bare = metrics.load(folder / "ready.png"), metrics.load(folder / "bare" / "ready.png")
    found = {}
    for name in scene.topology:
        px = track.pixel_rect(scene.regions[name])
        mask = track.still_mask(track.crop_px(frame, px), track.crop_px(bare, px))
        row = track.topology(mask)
        found[name] = {"count": row["count"], "neck": value(row["neck"]), "gap": value(track.gap(mask))}
    return found


silhouette = {}
for entry in json.loads(Path(OPTIONS.silhouette).read_text()):
    if entry["case"] == "light-photo":
        for name, row in entry["regions"].items():
            silhouette[(entry["scene"], name)] = {"count": row["count"], "neck": row.get("neck"), "gap": row.get("gap_seen")}

rows = []
for scene_id, case, run, folder in takes(Path(OPTIONS.runs)):
    for name, row in measure(scene_id, folder).items():
        rows.append({"scene": scene_id, "region": name, "gap_drawn": float(name[1:]), "spacing": spacing(scene_id), "case": case, "run": run, **row})

table = {}
for row in rows:
    if row["run"] not in FRESH:
        continue
    entry = table.setdefault(f"{row['scene']}/{row['region']}", {"spacing": row["spacing"], "gap_drawn": row["gap_drawn"], "silhouette": silhouette.get((row["scene"], row["region"]))})
    entry[row["case"]] = {k: row[k] for k in ("count", "neck", "gap")}

problems = []
for key, entry in table.items():
    sil = entry["silhouette"]
    counts = {case: entry[case]["count"] for case in ("dark-photo", "light-photo", "light-black") if case in entry}
    if len(set(counts.values())) > 1:
        problems.append(f"{key}: counts differ {counts}")
    if sil and counts.get("light-photo") != sil["count"]:
        problems.append(f"{key}: light-photo {counts.get('light-photo')} against silhouette {sil['count']}")
    light = entry.get("light-photo", {})
    if sil and sil["neck"] is not None and light.get("neck") is not None and abs(light["neck"] - sil["neck"]) > NECK_PX:
        problems.append(f"{key}: light-photo neck {light['neck']} against silhouette {sil['neck']}")

earlier = []
for row in rows:
    if row["run"] in FRESH:
        continue
    sil = silhouette.get((row["scene"], row["region"]))
    fresh = table.get(f"{row['scene']}/{row['region']}", {}).get(row["case"], {})
    if (sil and row["count"] != sil["count"]) or (fresh and row["count"] != fresh["count"]):
        earlier.append(f"{row['scene']}/{row['region']} {row['case']} {row['run']}: count {row['count']} against silhouette {sil and sil['count']} and fresh {fresh.get('count')}")

neck_dark_light = [abs(e["dark-photo"]["neck"] - e["light-photo"]["neck"]) for e in table.values() if e.get("dark-photo", {}).get("neck") is not None and e.get("light-photo", {}).get("neck") is not None]
neck_light_sil = [abs(e["light-photo"]["neck"] - e["silhouette"]["neck"]) for e in table.values() if e["silhouette"] and e["silhouette"]["neck"] is not None and e.get("light-photo", {}).get("neck") is not None]
gap_dark_light = [abs(e["dark-photo"]["gap"] - e["light-photo"]["gap"]) for e in table.values() if e.get("dark-photo", {}).get("gap") is not None and e.get("light-photo", {}).get("gap") is not None]

report = {
    "mask": {"rim": track.STILL_RIM, "grain_removed": track.GRAIN_REMOVED, "grain_min": track.GRAIN_MIN, "grain_window": track.GRAIN_WINDOW},
    "takes": len({(r["scene"], r["case"], r["run"]) for r in rows}),
    "regions_measured": len(rows),
    "fresh_problems": problems,
    "earlier_take_problems": earlier,
    "neck_dark_vs_light_max": max(neck_dark_light) if neck_dark_light else None,
    "neck_light_vs_silhouette_max": max(neck_light_sil) if neck_light_sil else None,
    "gap_dark_vs_light_max": max(gap_dark_light) if gap_dark_light else None,
    "table": table,
    "rows": rows,
}
Path(OPTIONS.out).write_text(json.dumps(report, indent=1))

lines = [
    f"still mask: rim > {track.STILL_RIM} levels, or the bare's 3x3 grain removed by more than {track.GRAIN_REMOVED} over a {track.GRAIN_WINDOW}x{track.GRAIN_WINDOW} window where the grain energy exceeds {track.GRAIN_MIN} per pixel; holes filled",
    f"takes {report['takes']}, regions {report['regions_measured']}",
    f"fresh runs {', '.join(FRESH)}: {len(problems)} problems",
    *("  " + p for p in problems),
    f"2B.1 takes ({', '.join(EARLIER)} and noise-2b1/takes): {len(earlier)} count disagreements with the silhouette or the fresh take",
    *("  " + p for p in earlier),
    f"neck |dark - light| max {report['neck_dark_vs_light_max']}, |light - silhouette| max {report['neck_light_vs_silhouette_max']}, gap |dark - light| max {report['gap_dark_vs_light_max']}",
    "",
    f"{'scene/region':32s} {'S':>4s} {'sil':>14s} {'dark-photo':>22s} {'light-photo':>22s} {'light-black':>22s}",
]
for key, entry in sorted(table.items(), key=lambda kv: (kv[1]["spacing"], kv[0].split("/")[0], kv[1]["gap_drawn"])):
    sil = entry["silhouette"]
    cell = lambda r: "-" if not r else f"{int(r['count'])} n{r['neck']} g{r['gap']}"
    lines.append(f"{key:32s} {entry['spacing']:4.0f} {('-' if not sil else str(int(sil['count'])) + ' n' + str(sil['neck'])):>14s} {cell(entry.get('dark-photo')):>22s} {cell(entry.get('light-photo')):>22s} {cell(entry.get('light-black')):>22s}")
Path(OPTIONS.summary).write_text("\n".join(lines) + "\n")
print("\n".join(lines[:8 + len(problems) + len(earlier)]))
