import sys, os, json
from pathlib import Path
sys.path.insert(0,'/Users/omaraly/development/AI/Operator/packages/mobile/tool/glass_lab/harness')
os.environ['PATH']='/opt/homebrew/bin:'+os.environ['PATH']
import numpy as np, analyze, align, springfit
for case in sys.argv[1:]:
    d=Path(case)/'native'
    r=json.load(open(Path(case)/'result.json'))
    region=tuple(r['region'])
    start,end,_=analyze.window(d)
    fr=analyze.frames(d/'video.mp4',max(0,start-0.2),end,region,Path('prog_frames')/case.replace('/','_'))
    imgs=[f for f in fr]; times=np.array(fr.times)
    diffs=align.differences(fr)
    evs=align.events(diffs,fr.times)
    print('##',case,'region',region)
    for (a,b) in evs:
        s,e=imgs[a],imgs[b]
        if np.abs(e-s).mean()>20: 
            print(f'  skip teardown-like event at {times[a]-times[0]:.2f}'); continue
        D=e-s; den=float((D**2).sum())
        if den==0: continue
        idx=list(range(a,b+1))
        p=np.array([float(((imgs[i]-s)*D).sum()/den) for i in idx]); t=times[idx]-times[a]
        grid=np.arange(0,t[-1]+1e-9,1/120); pg=np.interp(grid,t,p)
        f=springfit.features(grid,pg); sp=springfit.fit(grid,pg)
        def cross(level):
            k=np.nonzero(pg>=level)[0]; return grid[k[0]]*1000 if len(k) else float('nan')
        gaps=np.diff(t)*1000
        print(f"  ev t={times[a]-times[0]:.2f}s dur={1000*t[-1]:.0f}ms mad={np.abs(D).mean():.2f} 10-90%={cross(0.9)-cross(0.1):.0f}ms t50={cross(0.5):.0f}ms overshoot={f['overshoot_pct']:.1f}% settle={f['settle_ms']:.0f}ms fit r{sp['response']:.2f} z{sp['damping']:.2f} e{sp['rms']:.3f} maxgap={gaps.max():.0f}ms")
