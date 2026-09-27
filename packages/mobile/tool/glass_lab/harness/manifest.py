import json
from dataclasses import dataclass, field
from pathlib import Path

LAB = Path(__file__).resolve().parents[1]
MANIFEST = LAB / "scenes.json"
GROUPS = ("material", "navigation", "presentations", "controls", "apple")
BACKDROPS = ("stripes", "photo", "white", "black", "text", "scroll", "none")
APPEARANCES = ("light", "dark")
STEP_KINDS = ("wait", "tap", "doubleTap", "press", "pressDrag")
FIELDS = ("id", "group", "title", "inventory", "app", "backdrops", "appearances", "steps")


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
    track: str | None = None
    prepare: tuple = ()

    @property
    def native_only(self):
        return self.app != "lab"

    @property
    def rest(self):
        return all("wait" in step for step in self.steps)


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
        if entry.get("track") is not None and entry["track"] not in regions:
            errors.append(f"{where}: track names an unknown region")
        if entry.get("app") != "lab" and entry.get("group") != "apple":
            errors.append(f"{where}: only apple scenes may target another app")
    return errors


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
            track=entry.get("track"),
            prepare=tuple(entry.get("prepare", [])),
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
