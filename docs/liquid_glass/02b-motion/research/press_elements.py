import sys, os
from pathlib import Path
sys.path.insert(0,'/Users/omaraly/development/AI/Operator/packages/mobile/tool/glass_lab/harness')
os.environ['PATH']='/opt/homebrew/bin:'+os.environ['PATH']
import numpy as np, analyze, metrics, springfit, align
for c in ('dark-stripes','light-stripes'):
    d=Path(f'20261002-205855/button.press/{c}/native')
    start,end,_=analyze.window(d)
    for name,box in (('glass',(132,368,138,53)),('prominent',(114,481,174,53))):
        region=(box[0]-24,box[1]-16,box[2]+48,box[3]+32)
        fr=analyze.frames(d/'video.mp4',max(0,start-0.2),end,region,Path('el_frames')/f'{c}_{name}')
        bare=analyze.shrink(metrics.crop(metrics.load(d/'bare'/'ready.png'),region))
        T=np.array(fr.times)-fr.times[0]
        W=[];H=[];Lu=[]
        for f in fr:
            bs=metrics.glass_boxes(f,bare,threshold=12.0,min_area=20,scale=1)
            bx=bs[0] if bs else (0,0,0,0)
            W.append(bx[2]);H.append(bx[3]);Lu.append(float(metrics.luma(f[16:16+box[3],24:24+box[2]]).mean()))
        W=np.array(W,float);H=np.array(H,float);Lu=np.array(Lu)
        base_w=np.median(W[:5]); base_h=np.median(H[:5])
        print(f"{c} {name}: rest {base_w:.0f}x{base_h:.0f}  max {W.max():.0f}x{H.max():.0f} (scale w {W.max()/base_w:.3f} h {H.max()/base_h:.3f})  luma rest {np.median(Lu[:5]):.1f} max {Lu.max():.1f} min {Lu.min():.1f}")
        up=W>base_w+3
        idx=np.nonzero(up)[0]
        if len(idx):
            segs=np.split(idx,np.nonzero(np.diff(idx)>1)[0]+1)
            for s in segs:
                t0=T[s[0]];t1=T[s[-1]]
                k0=max(0,s[0]-1)
                peak=W[s].max(); 
                k90=s[np.nonzero(W[s]>=base_w+0.9*(peak-base_w))[0][0]]
                kend=min(len(W)-1,s[-1]+1)
                after=np.nonzero((np.arange(len(W))>s[-1])&(W<=base_w+1))[0]
                tr=T[after[0]] if len(after) else float('nan')
                print(f"   press seg {t0:.2f}-{t1:.2f}s peak w {peak:.0f}; rise-to-90% {1000*(T[k90]-T[k0]):.0f} ms; release back-to-rest {1000*(tr-T[s[-1]]):.0f} ms after last high frame; frames in seg {len(s)}")
