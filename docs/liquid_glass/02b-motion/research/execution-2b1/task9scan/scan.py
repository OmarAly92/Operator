import argparse, sys, json, datetime
from pathlib import Path
from multiprocessing import Pool
ARGS = argparse.ArgumentParser(description='Scan noise takes for capture holes.')
ARGS.add_argument('scratch', help='folder for staged takes and scan.json')
ARGS.add_argument('--harness', required=True, help='packages/mobile/tool/glass_lab/harness of the checkout to analyse with')
ARGS.add_argument('--takes', required=True, help='the noise run\'s takes folder, e.g. <runs>/noise-2b1/takes')
OPTIONS = ARGS.parse_args()
sys.path.insert(0, str(Path(OPTIONS.harness).resolve()))
import manifest, analyze, shapes, touch
RUN = Path(OPTIONS.takes)
SCR = Path(OPTIONS.scratch)
SCENES = ['material.materialize', 'material.materialize.snappy', 'material.materialize.bouncy', 'material.interactive'] + [f'material.press.{s}' for s in ('138x53','250x44','300x120','360x200','circle58')]
BOUNDARY = datetime.datetime(2026,10,4,4,2,30).timestamp()

def stage(src, dst):
    dst.mkdir(parents=True, exist_ok=True)
    for name in ('video.mp4', 'ready.png', 'settled.png', 'bare', 'timing.json'):
        link = dst / name
        if not link.exists() and (src / name).exists():
            link.symlink_to((src / name).resolve())

def one(job):
    sid, case, n = job
    scene = manifest.select(manifest.load(), sid)[0]
    d = SCR / sid / case / str(n)
    stage(RUN / sid / case / str(n), d)
    start = json.loads((d / 'timing.json').read_text())['start']
    out = {'scene': sid, 'case': case, 'take': n, 'session': 1 if start < BOUNDARY else 2, 'events': [], 'touches': []}
    found = analyze.window(d)
    if found is None:
        out['error'] = 'no window'; return out
    cap = shapes.capture(scene, d, found[:2])
    name = scene.track[0]
    times = cap['rows'][name]['times']
    out['touches'] = cap['touches']; out['stalls'] = cap['stalls']
    for e in cap['events']:
        first = times.index(e['onset']) - 1
        g1 = (times[first+1]-times[first])*1000
        g2 = (times[first+2]-times[first+1])*1000 if first+2 < len(times) else None
        burst = sum(1 for k in range(first+1, min(first+11, len(times)-1)) if (times[k+1]-times[k])*1000 < 5.0)
        out['events'].append({'onset': e['onset'], 'step': e['step'], 'gap1': g1, 'gap2': g2, 'burst': burst, 'ff_progress': e['first_frame'][name]['progress']})
    return out

if __name__ == '__main__':
    out = SCR / 'scan.json'
    done = json.load(open(out)) if out.exists() else []
    seen = {(r['scene'], r['case'], r['take']) for r in done}
    jobs = [(s, c.name, int(t.name)) for s in SCENES for c in sorted((RUN / s).iterdir()) for t in sorted(c.iterdir(), key=lambda p: int(p.name))]
    jobs = [j for j in jobs if j not in seen]
    print(len(jobs), 'to do', flush=True)
    with Pool(6) as pool:
        for r in pool.imap_unordered(one, jobs):
            done.append(r); print(r['scene'], r['case'], r['take'], flush=True)
            json.dump(done, open(out, 'w'))
    print('done', flush=True)
