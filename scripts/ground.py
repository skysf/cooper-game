"""Bake an opaque, repeatable 8 m trail strip. Reuse the same source at both seams."""
from pathlib import Path
from PIL import Image
import numpy as np

out = Path('shared/textures')
N = 2048
def photo(name, channel, size=512):
    return np.asarray(Image.open(out/f'{name}_{channel}.jpg').convert('RGB').resize((size,size),Image.Resampling.LANCZOS),dtype=np.float32)
def tile(name, channel):
    return np.tile(photo(name,channel), (4,4,1))
def smooth(x):
    t = np.clip(x,0,1)
    return t*t*(3-2*t)
def write(image, filename):
    Image.fromarray(np.clip(image,0,255).astype('uint8')).save(out/filename,quality=89,subsampling=0,optimize=True)
def grade_floor(rgb):
    # Damp, decomposing litter; keep leaf veins and the fine twigs legible.
    luma = np.sum(rgb*np.array([.3,.59,.11],dtype=np.float32),axis=-1,keepdims=True)
    return (.78*rgb+.22*luma)*np.array([.57,.62,.61],dtype=np.float32)

write(grade_floor(photo('forest_floor','diff',1024)),'litter_diff.jpg')
# The blend's outer edge covers only the forest photograph and repeats at the same UV phase.
for ch in ['arm','nor_gl']:
    (out/f'litter_{ch}.jpg').write_bytes((out/f'forest_floor_{ch}.jpg').read_bytes())
u=np.arange(N,dtype=np.float32)[None,:]/N
v=np.arange(N,dtype=np.float32)[:,None]/N
x=(u-.5)*8
theta=np.float32(2*np.pi)
def wave(a,b,phase):return np.sin(theta*(a*u+b*v)+phase)
def noise():
    rng=np.random.default_rng(42)
    result=np.zeros((N,N),dtype=np.float32)
    for l,w in [(3,.48),(8,.25),(17,.14),(41,.08),(99,.05)]:
        grid=rng.uniform(-1,1,(l,l)).astype(np.float32)
        # A periodic low-pass noise tile without nonmatching edges.
        big=np.tile(grid,(3,3)); img=Image.fromarray(big).resize((3*N,3*N),Image.Resampling.BICUBIC)
        result += np.asarray(img.crop((N,N,2*N,2*N)))*w
    return result
n=noise()
mud=tile('mud_forest','diff')
floor=grade_floor(tile('forest_floor','diff'))
edge=1.53+.22*wave(0,1,.7)+.14*wave(0,3,2)+.07*wave(0,7,.85)
dist=np.abs(x+.19*wave(0,1,3.5))
grain=(np.mean(floor,axis=2)-74)/90
blend=smooth((edge-dist + n*.98 + grain*.24 +.72)/1.43)
# Irregular smooth hollows along the worn tracks; the mud substrate shows through.
rut=np.exp(-((dist-.73-.09*wave(0,2,1.4))/.31)**2)
wet=smooth((n*1.24+.52*rut+.14*wave(2,1,3.1)-.34)*7)*blend
blade=wave(41,3,1)+.4*wave(69,7,2)+.2*wave(92,5,1)
reflect=np.stack(np.broadcast_arrays(26+5*blade,31+6*blade,30+7*blade),axis=-1)
ripples=np.clip(wave(9,61,1.6)+.75*wave(13,96,2.4)-1.32,0,1)*wet
blend3=blend[:,:,None];wet3=wet[:,:,None]
mud=mud*np.array([1.04,1.12,1.23],dtype=np.float32)
mud=mud*(1-wet3*.56)+reflect*wet3*.56+ripples[:,:,None]*11
write(floor*(1-blend3)+mud*blend3,'trail_diff.jpg')
for channel in ['arm','nor_gl']:
    a=tile('forest_floor',channel);b=tile('mud_forest',channel)
    if channel=='arm':
        b[:,:,1]*=1-.84*wet
        b[:,:,0]=(1-.48*wet)*b[:,:,0]+.48*wet*255
    else:
        b[:,:,:2]=(1-.91*wet3)*b[:,:,:2]+.91*wet3*127
        b[:,:,2]=(1-.91*wet)*b[:,:,2]+.91*wet*255
    write(a*(1-blend3)+b*blend3,'trail_'+channel+'.jpg')
