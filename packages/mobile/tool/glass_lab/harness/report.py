import html
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops

STRIP_STEP = 6
STRIP_FRAMES = 24


def svg_lines(series, width=520, height=160, colors=("#1f77b4", "#d62728")):
    values = [v for line in series.values() for v in line]
    if not values:
        return ""
    low, high = min(values), max(values)
    span = high - low or 1.0
    count = max(len(line) for line in series.values())
    paths = []
    for (name, line), color in zip(series.items(), colors):
        points = " ".join(
            f"{i / max(1, count - 1) * width:.1f},{height - (v - low) / span * height:.1f}" for i, v in enumerate(line)
        )
        paths.append(f'<polyline fill="none" stroke="{color}" stroke-width="1.5" points="{points}"><title>{html.escape(name)}</title></polyline>')
    legend = " ".join(f'<span style="color:{c}">{html.escape(n)}</span>' for n, c in zip(series, colors))
    return f'<div class="chart"><svg viewBox="0 0 {width} {height}" width="{width}" height="{height}">{"".join(paths)}</svg><div>{legend}</div></div>'


def diff_image(native, flutter, out):
    a = Image.open(native).convert("RGB")
    b = Image.open(flutter).convert("RGB").resize(a.size)
    ImageChops.difference(a, b).point(lambda v: min(255, v * 4)).save(out)


def thumb(source, out, width=201):
    image = Image.open(source).convert("RGB")
    image.resize((width, round(image.height * width / image.width))).save(out)


def strip(frames_dir, out):
    if not Path(frames_dir).exists():
        return False
    paths = sorted(Path(frames_dir).glob("*.png"))[::STRIP_STEP][:STRIP_FRAMES]
    if not paths:
        return False
    images = [Image.open(p).convert("RGB") for p in paths]
    width, height = images[0].size
    scale = min(1.0, 120 / width)
    size = (max(1, round(width * scale)), max(1, round(height * scale)))
    sheet = Image.new("RGB", (size[0] * len(images), size[1]), (128, 128, 128))
    for index, image in enumerate(images):
        sheet.paste(image.resize(size), (index * size[0], 0))
    sheet.save(out)
    return True


def fmt(value):
    if isinstance(value, float):
        return "∞" if value == float("inf") else f"{value:.2f}"
    return html.escape(str(value))


def case_section(scene_id, case_dir, result, assets):
    rel = lambda p: html.escape(str(Path(p).relative_to(assets.parent)))
    parts = [f'<h3 id="{html.escape(scene_id)}-{html.escape(result["case"])}">{html.escape(scene_id)} · {html.escape(result["case"])}</h3>']
    native_dir, flutter_dir = case_dir / "native", case_dir / "flutter"
    images = []
    for app_dir in (native_dir, flutter_dir):
        for name in ("ready", "settled"):
            source = app_dir / f"{name}.png"
            if source.exists():
                target = assets / f"{scene_id}-{result['case']}-{app_dir.name}-{name}.png"
                thumb(source, target)
                images.append(f'<figure><img src="{rel(target)}"><figcaption>{app_dir.name} {name}</figcaption></figure>')
    if result.get("kind") == "compared":
        for name in ("ready", "settled"):
            target = assets / f"{scene_id}-{result['case']}-diff-{name}.png"
            diff_image(native_dir / f"{name}.png", flutter_dir / f"{name}.png", target)
            thumb(target, target)
            images.append(f'<figure><img src="{rel(target)}"><figcaption>diff ×4 {name}</figcaption></figure>')
    parts.append(f'<div class="row">{"".join(images)}</div>')
    motion = result.get("motion") or {}
    for app_dir in (native_dir, flutter_dir):
        target = assets / f"{scene_id}-{result['case']}-{app_dir.name}-strip.png"
        if strip(app_dir / "frames", target):
            parts.append(f'<div><div class="label">{app_dir.name} filmstrip (about 50 ms per frame)</div><img class="strip" src="{rel(target)}"></div>')
    if motion:
        parts.append(f'<div class="small">motion events native/flutter: {motion["event_count"][0]}/{motion["event_count"][1]}</div>')
    for number, event in enumerate(result.get("native_events", [])):
        parts.append(f'<div class="label">native event {number}</div>' + svg_lines({key: event["series"][key] for key in ("width", "height")}))
    for number, event in enumerate(motion.get("events", [])):
        for key in ("width", "height", "cx", "cy", "luma"):
            if key not in event:
                continue
            entry = event[key]
            parts.append(f'<div class="label">event {number} · {key}</div>' + svg_lines({"native": entry["native"], "flutter": entry["flutter"]}))
            springs = ""
            if "native_spring" in entry:
                springs = f' · spring native {fmt(entry["native_spring"]["response"])}s/{fmt(entry["native_spring"]["damping"])}, flutter {fmt(entry["flutter_spring"]["response"])}s/{fmt(entry["flutter_spring"]["damping"])}'
            parts.append(f'<div class="small">rms {fmt(entry["rms"])}{springs}</div>')
    for name, stat in (result.get("static") or {}).items():
        if "rim_native" in stat:
            parts.append(f'<div class="label">rim profile ({name})</div>' + svg_lines({"native": stat["rim_native"], "flutter": stat["rim_flutter"]}))
        rows = "".join(
            f'<tr><td>{key}</td><td>{fmt(stat[key])}</td><td class="{"ok" if ok else "bad"}">{"pass" if ok else "fail"}</td></tr>'
            for key, ok in stat["pass"].items()
        )
        parts.append(f"<table><tr><th>{name}</th><th>value</th><th></th></tr>{rows}</table>")
    if result.get("flutter_stalls"):
        parts.append(f'<div class="small bad">Flutter frame gaps over 25 ms: {", ".join(fmt(g) for g in result["flutter_stalls"])}</div>')
    return "".join(parts)


def worst(result):
    checks = result.get("checks") or {}
    failing = [k for k, ok in checks.items() if not ok]
    return ", ".join(failing[:3]) if failing else "—"


def build(run_dir, scenes):
    run_dir = Path(run_dir)
    assets = run_dir / "report_assets"
    assets.mkdir(exist_ok=True)
    results = []
    for result_path in sorted(run_dir.glob("*/*/result.json")):
        results.append((result_path.parent, json.loads(result_path.read_text())))
    by_scene = {s.id: s for s in scenes}
    counts = {"pass": 0, "fail": 0, "missing": 0, "reference": 0, "error": 0}
    rows, sections = [], []
    for case_dir, result in results:
        kind = result.get("kind")
        if kind == "compared":
            status = "pass" if result.get("pass") else "fail"
        else:
            status = kind
        counts[status] = counts.get(status, 0) + 1
        scene = by_scene.get(result["scene"])
        title = scene.title if scene else ""
        anchor = f'{result["scene"]}-{result["case"]}'
        rows.append(
            f'<tr><td><a href="#{html.escape(anchor)}">{html.escape(result["scene"])}</a></td><td>{html.escape(result["case"])}</td>'
            f'<td>{html.escape(title)}</td><td class="{status}">{status}</td><td>{html.escape(worst(result))}</td></tr>'
        )
        sections.append(case_section(result["scene"], case_dir, result, assets))
    summary = " · ".join(f"{k}: {v}" for k, v in counts.items())
    page = f"""<!doctype html><html><head><meta charset="utf-8"><title>Glass lab report</title>
<style>
body{{font:14px -apple-system,system-ui,sans-serif;margin:24px;background:#fafafa;color:#111}}
table{{border-collapse:collapse;margin:8px 0}}td,th{{border:1px solid #ddd;padding:4px 8px;text-align:left}}
.pass,.ok{{color:#0a7d32}}.fail,.bad{{color:#c0262d}}.missing{{color:#8a6d00}}.reference,.error{{color:#555}}
.row{{display:flex;gap:8px;flex-wrap:wrap}}figure{{margin:0}}figcaption,.label,.small{{font-size:12px;color:#555}}
img.strip{{max-width:100%}}.chart svg{{background:#fff;border:1px solid #eee}}h3{{margin-top:40px}}
</style></head><body>
<h1>Glass lab report</h1><p>{summary}</p>
<table><tr><th>scene</th><th>case</th><th>title</th><th>status</th><th>failing measures</th></tr>{"".join(rows)}</table>
{"".join(sections)}
</body></html>"""
    (run_dir / "report.html").write_text(page)
    return run_dir / "report.html", counts, results


def markdown(run_dir, counts, results, scenes):
    by_scene = {s.id: s for s in scenes}
    lines = [
        "# Glass lab baseline",
        "",
        f"Run: `{Path(run_dir).name}`. Native iOS 27 (iPhone 17 Pro simulator) against Operator's Flutter glass.",
        "",
        "| Status | Count |",
        "|---|---|",
    ]
    lines += [f"| {key} | {value} |" for key, value in counts.items()]
    lines += ["", "| Scene | Case | Title | Status | Failing measures |", "|---|---|---|---|---|"]
    for _, result in results:
        kind = result.get("kind")
        status = ("pass" if result.get("pass") else "fail") if kind == "compared" else kind
        scene = by_scene.get(result["scene"])
        title = scene.title if scene else ""
        lines.append(f"| {result['scene']} | {result['case']} | {title} | {status} | {worst(result)} |")
    return "\n".join(lines) + "\n"
