"""Guard against the reversed-knee regression and invalid Rigby skin data."""
import json, math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
data=json.loads((ROOT/'data/story_rigby.json').read_text(encoding='utf-8'))
samples=0
for name,cast in data['cast'].items():
    for mesh in cast['meshes'].values():
        for weights in mesh['weights']:
            assert abs(sum(w['weight'] for w in weights)-1)<1e-6,(name,'weights must sum to one')
    if name=='tango':continue
    lower_by_mesh={}
    for mesh_name,mesh in cast['meshes'].items():
        crop=cast['images'][mesh['image']]['crop'];lower=[]
        for i,weights in enumerate(mesh['weights']):
            x=crop[0]+mesh['uvs'][2*i]*mesh['width']
            y=crop[1]+mesh['uvs'][2*i+1]*mesh['height']
            if y>=375:lower.append((weights,x-256,y-450))
        lower_by_mesh[mesh_name]=lower
    for animation,clip in cast['animations'].items():
        # Include actual scene blends: they must not reintroduce leg deformation.
        for frame in clip['frames'][::8]:
            if not isinstance(frame,dict) or frame['m']=='stair-descent':continue
            for weights,ox,oy in lower_by_mesh[frame['m']]:
                x=y=0
                for w in weights:
                    a,b,c,d,tx,ty=frame['b'][w['bone']]
                    x+=(a*w['x']+c*w['y']+tx)*w['weight']
                    y-=(b*w['x']+d*w['y']+ty)*w['weight']
                assert math.hypot(x-ox,y-oy)<.01,(name,animation,'standing legs moved')
                samples+=1
for stage_frame in data['frames']:
    for i,actor in enumerate(stage_frame[3]):
        assert actor[4] in data['cast'][data['ids'][i]]['animations']
        assert all(math.isfinite(v) for v in actor[:4])
        assert abs(actor[2])>=.65 and actor[3]>=.65,(data['ids'][i],'a facing change must not interpolate through zero scale')
print(f'MOTION: {samples:,} planted-leg samples passed; skin weights and scene references valid')

# Moving stair legs are intentionally articulated. Verify the solved chain,
# rather than applying the standing-only rigidity rule to a walking actor.
c=data['cast']['tiffany'];anchors=c['meshAnchors']['stair-descent']
for i,frame in enumerate(c['animations']['stairs']['frames']):
    if not isinstance(frame,dict):continue
    arm=frame['b'][anchors['shoulder']];palm=frame['b'][anchors['hand_front']]
    arm_length=math.hypot(45,26)
    assert math.hypot(arm[4]+arm[0]*arm_length-palm[4],arm[5]+arm[1]*arm_length-palm[5])<.12,('rail beyond arm reach',i)
    for name,length in [('front',math.hypot(17,48)),('back',math.hypot(-18,55))]:
        shin=frame['b'][anchors[name+'_knee']];ankle=frame['b'][anchors[name+'_ankle']]
        tip=(shin[4]+shin[0]*length,shin[5]+shin[1]*length)
        gap=math.hypot(tip[0]-ankle[4],tip[1]-ankle[5])
        assert gap<.12,('stair foot unreachable',name,i,gap)
        hip=frame['b'][anchors[name+'_hip']]
        cross=(shin[4]-hip[4])*(ankle[5]-hip[5])-(shin[5]-hip[5])*(ankle[4]-hip[4])
        assert cross<0,('stair knee bent backwards',name,i)
print('STAIRS: both knees bend forward and every ankle reaches its planted/swing target')
