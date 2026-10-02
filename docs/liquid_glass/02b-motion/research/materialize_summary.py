import sys, os
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
    start,end,_=analyze.window(d)
    fr=analyze.frames(d/'video.mp4',max(0,start-0.2),end,region,Path('probe_frames')/case.replace('/','_'))
    bare=analyze.shrink(metrics.crop(metrics.load(d/'bare'/'ready.png'),region))
    full=analyze.shrink(metrics.crop(metrics.load(d/'ready.png'),region))
    inner=(slice(14,94),slice(20,242))
    diff=full-bare; denom=float((diff**2).sum())
    rows=[]
    for t,f in zip(fr.times,fr):
        a=float(((f-bare)*diff).sum()/denom)
        res=float(np.abs(f-(bare+a*diff)).mean())
        rows.append((t-fr.times[0],a,res,lap(f[inner])))
    rows=[r for r in rows if r[1]<1.5]
    T=np.array([r[0] for r in rows]); A=np.array([r[1] for r in rows]); R=np.array([r[2] for r in rows]); L=np.array([r[3] for r in rows])
    lo=np.median(L[A<0.05]); hi=np.median(L[A>0.95])
    def seg(mask_start,dir):
        pass
    mid=len(T)//2
    out=[]
    for name,sel in (('demat',T<2.0),('mat',T>=2.0)):
        t,a,r,l=T[sel],A[sel],R[sel],L[sel]
        if dir:=None: pass
        def cross(level, falling):
            idx=np.nonzero(a<=level)[0] if falling else np.nonzero(a>=level)[0]
            return t[idx[0]] if len(idx) else float('nan')
        falling = name=='demat'
        t90=cross(0.9 if falling else 0.1,falling); t10=cross(0.1 if falling else 0.9,falling)
        t02=cross(0.02 if falling else 0.98,falling); t98=cross(0.98 if falling else 0.02,falling)
        m=(a>0.3)&(a<0.7)
        excess=(l[m]-((1-a[m])*lo+a[m]*hi)).mean() if m.any() else float('nan')
        out.append(f"{name}: 10-90% {1000*(t10-t90):.0f} ms, 2-98% {1000*(t02-t98):.0f} ms, peak resid {r.max():.2f} (rest {np.median(R[A<0.05]):.2f}), lap minus alpha-mix at mid {excess:.2f} (lap bare {lo:.2f} full {hi:.2f})")
    print(case.split('/')[-1], '|', ' || '.join(out))
