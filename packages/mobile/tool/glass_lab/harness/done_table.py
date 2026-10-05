import json
import math
import sys
from pathlib import Path

GATE = ("events.", "touches.")


def fmt(value, digits=0):
    if value is None:
        return "-"
    if isinstance(value, float) and not math.isfinite(value):
        return "absent"
    return f"{value:.{digits}f}"


def summary(result):
    motion = {name[len("motion."):]: entry for name, entry in result["measures"].items() if name.startswith("motion.")}
    checks = {name: result["checks"][f"motion.{name}"] for name in motion}
    gates = [name for name in motion if name.startswith(GATE)]
    progress = [name for name in motion if not name.startswith(GATE)]
    return {
        "gates": (sum(checks[n] for n in gates), len(gates)),
        "progress": (sum(checks[n] for n in progress), sum(math.isfinite(motion[n][0]) for n in progress), len(progress)),
        "failing": sorted(name for name in motion if not checks[name]),
    }


def main():
    totals = {"gates": [0, 0], "progress": [0, 0, 0]}
    for run in sys.argv[1:]:
        for path in sorted(Path(run).glob("material.materialize*/*/result.json")):
            result = json.loads(path.read_text())
            name = f"{path.parent.parent.name} {path.parent.name}"
            if result.get("kind") != "compared":
                print(f"{name}: {result.get('kind')}")
                continue
            found = summary(result)
            shapes = result.get("shapes", {})
            passed, judged, expected = found["progress"]
            gate_pass, gate_count = found["gates"]
            for key, values in (("gates", found["gates"]), ("progress", found["progress"])):
                totals[key] = [a + b for a, b in zip(totals[key], values)]
            print(f"{name}: progress measures {passed} pass / {judged} judged / {expected} expected; events and touches {gate_pass}/{gate_count}; "
                  f"events {shapes.get('event_count')} unpaired {shapes.get('unpaired')} touches {shapes.get('touches')} of {shapes.get('expected_touches')}; "
                  f"stalls native {fmt_list(result.get('native_stalls'))} flutter {fmt_list(result.get('flutter_stalls'))}")
            for label, pair in shapes.get("pairs", {}).items():
                delay = pair.get("delay", {})
                for shape, entry in pair["shapes"].items():
                    first = entry.get("first_frame", {})
                    progress = entry.get("progress")
                    head = f"   {label} {shape}: delay {fmt(delay.get('native'))}/{fmt(delay.get('flutter'))} ms, first frame {first_frame(first.get('native'))}/{first_frame(first.get('flutter'))}"
                    if not progress:
                        print(f"{head}; no progress travel")
                        continue
                    n, f = progress["native"], progress["flutter"]
                    print(f"{head}; t10_90 {fmt(n['t10_90_ms'])}/{fmt(f['t10_90_ms'])} settle {fmt(n['settle_ms'])}/{fmt(f['settle_ms'])} "
                          f"overshoot {fmt(n['overshoot_pct'], 1)}/{fmt(f['overshoot_pct'], 1)} spring {spring(n['spring'])} vs {spring(f['spring'])} "
                          f"rms {fmt(progress['rms'], 3)} sharp {fmt(n['sharpness_mid'], 2)}/{fmt(f['sharpness_mid'], 2)}"
                          + (f" fit invalid {progress['fit_invalid']}" if "fit_invalid" in progress else ""))
            for failing in found["failing"]:
                value, limit, bound = result["measures"][f"motion.{failing}"]
                print(f"   FAIL {failing} {fmt(value, 3)} {'>' if bound == 'max' else '<'} {fmt(limit, 3)}")
    print(f"total: progress measures {totals['progress'][0]} pass / {totals['progress'][1]} judged / {totals['progress'][2]} expected; "
          f"events and touches {totals['gates'][0]}/{totals['gates'][1]}")


def fmt_list(values):
    return "[" + ", ".join(fmt(v) for v in values or []) + "]"


def first_frame(entry):
    if not entry:
        return "-"
    return f"{fmt(entry.get('progress'), 2)}@{fmt(entry.get('gap_ms'))}ms"


def spring(fit):
    if not fit:
        return "-"
    return f"{fit['response']:.2f}/{fit['damping']:.2f}" + ("(edge)" if fit.get("at_grid_edge") else "")


if __name__ == "__main__":
    main()
