import sys, os
from pathlib import Path
sys.path.insert(0,'/Users/omaraly/development/AI/Operator/packages/mobile/tool/glass_lab/harness')
import numpy as np, metrics, align
for c in ('dark-stripes','light-stripes'):
    for name,box in (('glass',(132,368,138,53)),('prominent',(114,481,174,53))):
        folder=Path('el_frames')/f'{c}_{name}'
        paths=sorted(folder.glob('*.png'))
        region=(box[0]-24,box[1]-16,box[2]+48,box[3]+32)
        d=Path(f'20261002-205855/button.press/{c}/native')
        import analyze
        bare=analyze.shrink(metrics.crop(metrics.load(d/'bare'/'ready.png'),region))
        W=[]
        for p in paths:
            f=metrics.load(p)
            bs=metrics.glass_boxes(f,bare,threshold=12.0,min_area=20,scale=1)
            W.append(bs[0][2] if bs else 0)
        W=np.array(W,float)
        base=np.median(W[:5])
        hi=np.nonzero(W>base+3)[0]
        seg=hi[:np.nonzero(np.diff(hi)>1)[0][0]+1] if (np.diff(hi)>1).any() else hi
        print(c,name,'width series over first press (frames, no timestamps):',W[max(0,seg[0]-2):seg[-1]+4].astype(int).tolist())
