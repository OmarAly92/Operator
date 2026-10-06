import json
import sys
from collections import defaultdict
from pathlib import Path

RUNS = Path("/Users/omaraly/development/AI/Operator-2b-proto/packages/mobile/build/glass_lab/runs")
HID = Path(__file__).resolve().parent / "hid"
INJECTION = {
    "probe.interactive": "A",
    "probe.offtext": "A-off",
    "probe.coord": "B",
    "probe.hid": "C",
}
ORDER = ["v0", "v1", "v2", "v2b", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11", "v12", "v13", "v14", "v15", "v16", "v17", "v18", "v19"]


def collect():
    found = []
    for path in sorted(RUNS.glob("*/probe.*/*/probe.json")) + sorted(HID.glob("*/*/probe.json")):
        data = json.loads(path.read_text())
        scene = path.parent.parent.name
        prefix, variant = scene.rsplit(".", 1)
        data["variant"], data["injection"], data["case_name"], data["folder"] = variant, INJECTION[prefix], path.parent.name, str(path.parent.parent.parent.relative_to(path.parent.parent.parent.parent))
        found.append(data)
    return found


def fmt(v):
    return f"{v:+.2f}".rstrip("0").rstrip(".") if v else "0"


def timing(p):
    t = p.get("timing", {})
    parts = []
    if "dw" in t:
        parts.append(f"w {t['dw']['down_to_90_ms']}/{t['dw']['release_to_settle10_ms']}")
    if "dluma" in t:
        parts.append(f"L {t['dluma']['down_to_90_ms']}/{t['dluma']['release_to_settle10_ms']}")
    return ", ".join(parts) or "-"


def main():
    rows = defaultdict(list)
    for d in collect():
        rows[(d["variant"], d["injection"])].append(d)
    lines = []
    for variant in ORDER:
        for injection in ("A", "A-off", "B", "C"):
            cases = rows.get((variant, injection))
            if not cases:
                continue
            cells = defaultdict(list)
            for c in sorted(cases, key=lambda c: c["case_name"]):
                ps = c["presses"]
                reacted = "yes" if all(p["reacted"] for p in ps) else ("no" if not any(p["reacted"] for p in ps) else "partly")
                first = ps[0]
                name = c["case_name"]
                cells["reacted"].append(f"{reacted}")
                cells["dw"].append(fmt(max((p["peak_dw"] for p in ps), key=abs)))
                cells["dh"].append(fmt(max((p["peak_dh"] for p in ps), key=abs)))
                cells["dl"].append(fmt(max((p["peak_dluma"] for p in ps), key=abs)))
                cells["mad"].append(f"{max(p['peak_mad'] for p in ps):.2f}")
                cells["timing"].append(timing(first) if first["reacted"] else "-")
                cells["held"].append(str(first["held_ms"]))
                cells["case"].append(name)
                cells["folder"].append(c["folder"])
            joined = {k: " / ".join(v) for k, v in cells.items()}
            lines.append(f"| {variant} | {injection} | {joined['case']} | {joined['reacted']} | {joined['dw']} | {joined['dh']} | {joined['dl']} | {joined['mad']} | {joined['timing']} | {joined['folder']} |")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
