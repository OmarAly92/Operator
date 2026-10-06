import json
import subprocess
import sys
from pathlib import Path

UDID = "708879DD-8B2A-4547-863F-F49EE1474D8B"


def folder():
    path = subprocess.run(["xcrun", "simctl", "get_app_container", UDID, "dev.operator.glasslab", "data"], capture_output=True, text=True, check=True).stdout.strip()
    return Path(path) / "Documents" / "glass_lab" / "touches"


def summarize(path):
    entries = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    began = [e for e in entries if e["phase"] == "began"]
    phases = {}
    for e in entries:
        phases[e["phase"]] = phases.get(e["phase"], 0) + 1
    views = sorted({e["view"].split("<")[0] for e in began})
    recognizers = sorted({r.split(":")[0] for e in began for r in e["recognizers"]})
    radius = sorted({round(e["radius"], 2) for e in began})
    return {"file": path.name, "phases": phases, "began_views": views, "began_recognizers": recognizers, "radius": radius, "types": sorted({e["type"] for e in entries})}


if __name__ == "__main__":
    pattern = sys.argv[1] if len(sys.argv) > 1 else "*"
    dest = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    out = []
    for path in sorted(folder().glob(pattern + ".jsonl")):
        s = summarize(path)
        out.append(s)
        print(json.dumps(s))
        if dest:
            dest.mkdir(parents=True, exist_ok=True)
            (dest / path.name).write_text(path.read_text())
