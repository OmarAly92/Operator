import json
from dataclasses import dataclass, field
from pathlib import Path

LAB = Path(__file__).resolve().parents[1]
MANIFEST = LAB / "scenes.json"
GROUPS = ("material", "navigation", "presentations", "controls", "apple")
BACKDROPS = ("stripes", "photo", "white", "black", "text", "scroll", "none")
APPEARANCES = ("light", "dark")
STEP_KINDS = ("wait", "tap", "doubleTap", "press", "pressDrag")
TOUCH_STEPS = ("tap", "doubleTap", "press", "pressDrag")
FIELDS = ("id", "group", "title", "inventory", "app", "backdrops", "appearances", "steps")
STATIC_MEASURES = ("mad", "luminance", "rim_rms", "bbox_pt", "centre_pt")
EDGE_KEYS = ("xmin", "xmax", "ymin", "ymax")
MOTION_MEASURES = (
    "delay_ms",
    "topology.count",
    "topology.join_ms",
    "topology.split_ms",
    "topology.neck_rms",
    "topology.gap_rms",
    *(f"{key}.{measure}" for key in ("width", "height", "cx", "cy", "luma", *EDGE_KEYS) for measure in ("peak_ms", "settle_ms", "overshoot_pct", "response_pct", "damping")),
    "progress.t10_90_ms",
    "progress.settle_ms",
    "progress.overshoot_pct",
    "progress.response_pct",
    "progress.damping",
    "progress.rms",
    "progress.sharpness",
)


@dataclass(frozen=True)
class Scene:
    id: str
    group: str
    title: str
    inventory: str
    app: str
    backdrops: tuple
    appearances: tuple
    steps: tuple
    regions: dict = field(default_factory=dict)
    track: tuple = ()
    prepare: tuple = ()
    measures: tuple = STATIC_MEASURES
    motion: tuple = ()
    topology: tuple = ()
    edges: dict = field(default_factory=dict)

    @property
    def native_only(self):
        return self.app != "lab"

    @property
    def rest(self):
        return all("wait" in step for step in self.steps)

    @property
    def touches(self):
        return any(next(iter(step)) in TOUCH_STEPS for step in self.steps)


def _target_errors(where, value):
    if isinstance(value, str) and value:
        return []
    if isinstance(value, list) and len(value) == 2 and all(isinstance(v, (int, float)) for v in value):
        return []
    if isinstance(value, dict) and isinstance(value.get("element"), str):
        extra = set(value) - {"element", "dx", "dy"}
        return [f"{where}: unknown target keys {sorted(extra)}"] if extra else []
    return [f"{where}: bad target {value!r}"]


def _step_errors(where, step):
    if not isinstance(step, dict) or len(step) != 1:
        return [f"{where}: a step is an object with exactly one key"]
    kind, value = next(iter(step.items()))
    if kind not in STEP_KINDS:
        return [f"{where}: unknown step {kind}"]
    if kind == "wait":
        return [] if isinstance(value, (int, float)) and value >= 0 else [f"{where}: wait needs seconds"]
    if kind in ("tap", "doubleTap"):
        return _target_errors(where, value)
    if kind == "press":
        if not isinstance(value, dict) or "at" not in value or not isinstance(value.get("duration"), (int, float)):
            return [f"{where}: press needs at and duration"]
        return _target_errors(where, value["at"])
    if not isinstance(value, dict) or "from" not in value or "to" not in value:
        return [f"{where}: pressDrag needs from and to"]
    extra = set(value) - {"from", "to", "pressDuration", "velocity", "hold"}
    errors = [f"{where}: unknown pressDrag keys {sorted(extra)}"] if extra else []
    return errors + _target_errors(where, value["from"]) + _target_errors(where, value["to"])


def validate(raw):
    errors = []
    if not isinstance(raw, list):
        return ["manifest must be a list"]
    seen = set()
    for index, entry in enumerate(raw):
        where = f"scene {index}"
        if not isinstance(entry, dict):
            errors.append(f"{where}: not an object")
            continue
        where = f"scene {entry.get('id', index)}"
        errors += [f"{where}: missing {name}" for name in FIELDS if name not in entry]
        if entry.get("id") in seen:
            errors.append(f"{where}: duplicate id")
        seen.add(entry.get("id"))
        if entry.get("group") not in GROUPS:
            errors.append(f"{where}: unknown group {entry.get('group')}")
        errors += [f"{where}: unknown backdrop {b}" for b in entry.get("backdrops", []) if b not in BACKDROPS]
        if not entry.get("backdrops"):
            errors.append(f"{where}: needs at least one backdrop")
        errors += [f"{where}: unknown appearance {a}" for a in entry.get("appearances", []) if a not in APPEARANCES]
        for number, step in enumerate(entry.get("steps", [])):
            errors += _step_errors(f"{where} step {number}", step)
        for number, step in enumerate(entry.get("prepare", [])):
            errors += _step_errors(f"{where} prepare {number}", step)
        regions = entry.get("regions", {})
        for name, rect in regions.items():
            if not (isinstance(rect, list) and len(rect) == 4 and all(isinstance(v, (int, float)) for v in rect)):
                errors.append(f"{where}: region {name} must be [x, y, w, h]")
        track = entry.get("track")
        names = [track] if isinstance(track, str) else track
        if track is not None and not (isinstance(names, list) and names and all(isinstance(n, str) for n in names)):
            errors.append(f"{where}: track must be a region name or a non-empty list of them")
        elif track is not None and any(name not in regions for name in names):
            errors.append(f"{where}: track names an unknown region")
        topology = entry.get("topology")
        names = [topology] if isinstance(topology, str) else topology
        if topology is not None and not (isinstance(names, list) and names and all(isinstance(n, str) for n in names)):
            errors.append(f"{where}: topology must be a region name or a non-empty list of them")
        elif topology is not None and any(name not in regions for name in names):
            errors.append(f"{where}: topology names an unknown region")
        edges = entry.get("edges", {})
        tracked = set(([track] if isinstance(track, str) else track or [])) | set(([topology] if isinstance(topology, str) else topology or []))
        if not isinstance(edges, dict):
            errors.append(f"{where}: edges must map a region to a non-empty list of edge keys")
            edges = {}
        for name, keys in edges.items():
            if name not in regions:
                errors.append(f"{where}: edges names an unknown region {name}")
            elif name not in tracked:
                errors.append(f"{where}: edges names a region that is not tracked {name}")
            if not (isinstance(keys, list) and keys and all(isinstance(k, str) for k in keys)):
                errors.append(f"{where}: edges must map a region to a non-empty list of edge keys")
                continue
            errors += [f"{where}: unknown edge {k}" for k in keys if k not in EDGE_KEYS]
        motion = entry.get("motion", [])
        if not isinstance(motion, list):
            errors.append(f"{where}: motion must be a list")
        else:
            errors += [f"{where}: unknown motion measure {m}" for m in motion if m not in MOTION_MEASURES]
            if motion and track is None:
                errors.append(f"{where}: motion measures need a track")
            if any(m.startswith("topology.") for m in motion) and topology is None:
                errors.append(f"{where}: topology measures need topology regions")
            wanted = [m for m in motion if m.split(".")[0] in EDGE_KEYS]
            if wanted and not edges:
                errors.append(f"{where}: edge measures need edges")
            else:
                listed = {k for keys in edges.values() if isinstance(keys, list) for k in keys}
                errors += [f"{where}: {m} needs a region with the edge {m.split('.')[0]}" for m in wanted if m.split(".")[0] not in listed]
        measures = entry.get("measures", list(STATIC_MEASURES))
        if not isinstance(measures, list) or not measures:
            errors.append(f"{where}: measures must be a non-empty list")
        else:
            errors += [f"{where}: unknown measure {m}" for m in measures if m not in STATIC_MEASURES]
        if entry.get("app") != "lab" and entry.get("group") != "apple":
            errors.append(f"{where}: only apple scenes may target another app")
    return errors


def tracks(value):
    if value is None:
        return ()
    return (value,) if isinstance(value, str) else tuple(value)


def parse(raw):
    errors = validate(raw)
    if errors:
        raise ValueError("\n".join(errors))
    return [
        Scene(
            id=entry["id"],
            group=entry["group"],
            title=entry["title"],
            inventory=entry["inventory"],
            app=entry["app"],
            backdrops=tuple(entry["backdrops"]),
            appearances=tuple(entry["appearances"]),
            steps=tuple(entry["steps"]),
            regions=dict(entry.get("regions", {})),
            track=tracks(entry.get("track")),
            prepare=tuple(entry.get("prepare", [])),
            measures=tuple(entry.get("measures", STATIC_MEASURES)),
            motion=tuple(entry.get("motion", [])),
            topology=tracks(entry.get("topology")),
            edges={name: tuple(keys) for name, keys in entry.get("edges", {}).items()},
        )
        for entry in raw
    ]


def load(path=MANIFEST):
    return parse(json.loads(Path(path).read_text()))


def select(scenes, selector):
    if selector == "all":
        return list(scenes)
    chosen = [s for s in scenes if s.id == selector or s.group == selector or s.id.startswith(selector + ".")]
    if not chosen:
        raise ValueError(f"no scene matches {selector}")
    return chosen
