import json, sys, math
from pathlib import Path
sys.path.insert(0, '/Users/omaraly/development/AI/Operator-2b1/packages/mobile/tool/glass_lab/harness')
import shapes, analyze, touch, manifest
S = Path(sys.argv[1])
RUNP = Path('/Users/omaraly/development/AI/Operator-2b1/packages/mobile/build/glass_lab/runs/noise-2b1')
res = json.load(open(S / 'takes' / 'scan.json'))
order = ['material.materialize', 'material.materialize.snappy', 'material.materialize.bouncy', 'material.interactive'] + [f'material.press.{s}' for s in ('138x53','250x44','300x120','360x200','circle58')]
res.sort(key=lambda r: (order.index(r['scene']), r['case'], r['take']))
scenes = {s.id: s for s in manifest.load()}
rows, flagged, raw_only = [], [], []
for r in res:
    scene = scenes[r['scene']]
    tsteps = touch.touch_steps(scene.steps)
    kinds = [next(iter(scene.steps[i])) for i in tsteps]
    tw = ' '.join(f"[{w[0]:.3f}, {w[1]:.3f}]" for w in r['touches'])
    zero = {i for i, w in enumerate(r['touches']) if abs(w[1] - w[0]) < 1e-6}
    tf = rf = False
    if not r['events']:
        rows.append((r, None, tw, r.get('error', 'no events')))
    for k, e in enumerate(r['events']):
        ti = tsteps.index(e['step']) if e['step'] in tsteps else None
        kind = kinds[ti] if ti is not None else None
        tap = kind in ('tap', 'doubleTap')
        hole = (e['gap1'] or 0) > 30 or (e['gap2'] or 0) > 30
        zt = ti in zero
        rule = (hole and zt) if tap else (hole or zt)
        burst = hole and e['burst'] >= 2
        verdict = 'YES' if (rule and burst) or (tap and burst) else ('rule only' if rule else 'no')
        tf |= verdict == 'YES'; rf |= verdict == 'rule only'
        rows.append((r, (k, e, kind, zt), tw, verdict))
    key = (r['scene'], r['case'], r['take'], r['session'])
    if tf: flagged.append(key)
    elif rf: raw_only.append(key)

def noise(scene_id, case, exclude):
    allw, keep = {}, {}
    for p in (RUNP / scene_id / case).glob('pair-*'):
        d = json.load(open(p / 'result.json'))
        found = shapes.measures(d['shapes']) if 'shapes' in d else {}
        found.update({n: v for n, (v, _, _) in d.get('measures', {}).items() if not n.startswith('motion.')})
        ids = {int(x) for x in p.name.split('-')[1:]}
        for n, v in found.items():
            if not math.isfinite(v): continue
            allw[n] = max(allw.get(n, 0.0), v)
            if not ids & exclude: keep[n] = max(keep.get(n, 0.0), v)
    return {n: (allw[n], keep.get(n, 0.0)) for n in allw if abs(allw[n] - keep.get(n, 0.0)) > 1e-9}

out = []
out.append("| scene | case | take | session | event | gap rest→1st ms | gap 1st→2nd ms | sub-5ms gaps in next 10 | 1st-frame progress | touch windows | flagged |")
out.append("|---|---|---|---|---|---|---|---|---|---|---|")
for r, ev, tw, verdict in rows:
    if ev is None:
        out.append(f"| {r['scene']} | {r['case']} | {r['take']} | {r['session']} | none | | | | | {tw} | {verdict} |"); continue
    k, e, kind, zt = ev
    ff = '' if e['ff_progress'] is None else f"{e['ff_progress']:.2f}"
    out.append(f"| {r['scene']} | {r['case']} | {r['take']} | {r['session']} | e{k} step{e['step']} ({kind}) @{e['onset']:.3f} | {e['gap1']:.1f} | {(e['gap2'] or 0):.1f} | {e['burst']} | {ff} | {tw}{' ZERO' if zt else ''} | {verdict} |")
by_case = {}
for s, c, t, _ in flagged: by_case.setdefault((s, c), set()).add(t)
nl = []
for (s, c), ex in by_case.items():
    ch = noise(s, c, ex)
    nl.append(f"\n### {s} / {c}, without take(s) {sorted(ex)}\n\n| measure | all five takes (noise.json) | unflagged takes |\n|---|---|---|")
    nl += [f"| {n} | {a:.4g} | {b:.4g} |" for n, (a, b) in sorted(ch.items())]
json.dump({'n': len(res), 'flagged': flagged, 'rule_only': raw_only}, open(S / 'flags.json', 'w'))
(S / 'table.md').write_text('\n'.join(out))
(S / 'noise.md').write_text('\n'.join(nl))
print(len(res), 'takes; flagged', flagged); print('rule only', raw_only)
