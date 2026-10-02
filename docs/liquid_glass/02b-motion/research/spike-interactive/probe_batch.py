import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import probe_analyze

HERE = Path(__file__).resolve().parent


def main(run_dirs):
    results = []
    for run in run_dirs:
        run = Path(run)
        for case in sorted(run.glob("probe.*/*")):
            if not (case / "native" / "video.mp4").exists():
                continue
            scene = case.parent.name
            label = f"{scene}-{case.name}"
            try:
                summary = probe_analyze.analyze(case, HERE / "crops" / run.name, label)
            except Exception as error:
                summary = {"case": str(case), "error": repr(error)}
            summary["scene"], summary["name"], summary["run"] = scene, case.name, run.name
            (case / "probe.json").write_text(json.dumps(summary))
            results.append(summary)
            presses = summary.get("presses", [])
            line = " | ".join(
                f"{'Y' if p['reacted'] else 'n'} held{p['held_ms']} fr{p['frames_during_press']} dw{p['peak_dw']} dh{p['peak_dh']} dl{p['peak_dluma']} mad{p['peak_mad']} {p['timing']}"
                for p in presses
            )
            print(f"{scene:28s} {case.name:14s} rest {summary.get('rest_box_pt')} {line or summary.get('error')}", flush=True)
    return results


if __name__ == "__main__":
    out = main(sys.argv[1:])
    (HERE / f"results-{Path(sys.argv[1]).name}.json").write_text(json.dumps(out, indent=1))
