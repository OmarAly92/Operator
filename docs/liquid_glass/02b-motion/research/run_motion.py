import sys, json, glob, os
sys.path.insert(0,'/Users/omaraly/development/AI/Operator/packages/mobile/tool/glass_lab/harness')
os.environ['PATH']='/opt/homebrew/bin:'+os.environ['PATH']
import numpy as np, analyze, align, springfit
out={}
for res in sorted(glob.glob('*/*/*/result.json')):
    case=os.path.dirname(res)
    r=json.load(open(res))
    region=tuple(r['region'])
    from pathlib import Path; m=analyze.motion(Path(case)/'native',region)
    events=[]
    for e in m['events']:
        s=e['series']; n=len(s['width'])
        t=np.arange(n)/align.GRID_HZ
        ev={'start':round(e['start']-m.get('first_time',0),3),'dur_s':round(n/align.GRID_HZ,3)}
        for k in align.KEYS:
            a=np.array(s[k])
            d={'from':round(a[0],1),'to':round(a[-1],1),'min':round(a.min(),1),'max':round(a.max(),1)}
            if abs(a[-1]-a[0])>=analyze.MIN_TRAVEL[k]:
                f=springfit.features(t,a); sp=springfit.fit(t,a)
                d.update({kk:round(v,3) for kk,v in f.items()})
                d.update({'fit_'+kk:round(v,3) for kk,v in sp.items()})
            ev[k]=d
        events.append(ev)
    out[case]={'region':region,'events':events,'stalls':[round(x,1) for x in m['stalls']]}
    print(case, 'events', len(events), 'stalls', len(m['stalls']), flush=True)
json.dump(out,open('native_motion.json','w'),indent=1)
