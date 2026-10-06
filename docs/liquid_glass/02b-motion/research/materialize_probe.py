import sys, os, json
from pathlib import Path
sys.path.insert(0,'/Users/omaraly/development/AI/Operator/packages/mobile/tool/glass_lab/harness')
os.environ['PATH']='/opt/homebrew/bin:'+os.environ['PATH']
import numpy as np, analyze, metrics
def lap(img):
    g=metrics.luma(img)
    l=g[1:-1,1:-1]*4-g[:-2,1:-1]-g[2:,1:-1]-g[1:-1,:-2]-g[1:-1,2:]
    return float(np.abs(l).mean())
for case in sys.argv[1:]:
    d=Path(case)/'native'
    region=(70,400,262,104)
    found=analyze.window(d)
    start,end,_=found
    fr=analyze.frames(d/'video.mp4',max(0,start-0.2),end,region,Path('probe_frames')/case.replace('/','_'))
    bare=analyze.shrink(metrics.crop(metrics.load(d/'bare'/'ready.png'),region))
    full=analyze.shrink(metrics.crop(metrics.load(d/'ready.png'),region))
    inner=(slice(14,14+80),slice(20,20+222))
    diff=(full-bare)
    denom=float((diff**2).sum())
    t0=fr.times[0]
    print('##',case,'frames',len(fr),'lap bare',round(lap(bare[inner]),2),'lap full',round(lap(full[inner]),2))
    prev=None
    for t,f in zip(fr.times,fr):
        a=float(((f-bare)*diff).sum()/denom)
        model=bare+a*diff
        res=float(np.abs(f-model).mean())
        tot=float(np.abs(f-bare).mean())
        ch=0 if prev is None else float(np.abs(f-prev).mean())
        prev=f
        if ch>0.3 or prev is None:
            print(f"t={t-t0:6.3f} alpha={a:5.2f} resid={res:5.2f} |f-bare|={tot:5.2f} lap={lap(f[inner]):5.2f} luma={metrics.luma(f[inner]).mean():6.1f} dmad={ch:5.2f}")
