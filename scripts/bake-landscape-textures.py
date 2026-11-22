"""Bake reusable UV maps for the three field-photo studies (Pillow + NumPy)."""
from pathlib import Path
import math
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art/field_regions/photo_landscapes"
OUT = ROOT / "coop/vegetation/photo_landscapes"
SIZE = 512


def reed_plume():
    # Individual hanging side branches with overlapping sunlit glumes and silks.
    scale = 2
    rng = random.Random(144)
    layer = Image.new("RGBA", (SIZE*scale, SIZE*scale), (226, 211, 179, 0))
    pen = ImageDraw.Draw(layer)

    def line(pts, color, width):
        pen.line([(int(x*scale), int(y*scale)) for x, y in pts], color, max(1, round(width*scale)))

    def axis(t):
        return 248+26*t+9*math.sin(t*math.pi), 489-455*t

    line([axis(i/36) for i in range(37)], (173, 151, 108, 255), 3)
    for i in range(235):
        t = rng.uniform(.015, .975)
        x, y = axis(t)
        side = rng.choice([-1, 1])
        spread = (math.sin(math.pi*t)**.62)*rng.uniform(.28, 1)
        length = rng.uniform(70, 157)*(1-.46*t)
        width = side*spread*165
        shade = rng.uniform(.78, 1.03)
        base = tuple(min(255, int(c*shade)) for c in (223, 207, 175))
        def branch(s):
            return x+width*(s**1.18), y-length*s+22*spread*s*s
        line([branch(k/6) for k in range(7)], (*base, 245), 1.25)
        for k in range(4, 17):
            s = k/18 + rng.uniform(-.017, .017)
            a, b = branch(s)
            awn = rng.uniform(8, 20)*(1.25-.55*s)
            dx = side*awn*rng.uniform(.28, 1.05)
            col = tuple(min(255, c+rng.randint(0, 23)) for c in base)
            line([(a,b), (a+dx*.47,b-awn*.47), (a+dx,b-awn)], (*col, 244), rng.uniform(.7, 1.8))
    return layer.resize((SIZE,SIZE), Image.Resampling.LANCZOS)


def leaf_map():
    y,x=np.mgrid[0:SIZE,0:SIZE]/(SIZE-1)
    t=1-y
    half=(np.sin(np.pi*np.clip(t,0,1))**.78)*(.47-.22*t)
    local=abs(x-.5)/(half+.0001)
    # A rounded, pointed blade, light rib, side veins and shaded margins.
    notch=(t<.16)&(abs(x-.5)<(.16-t)*.55)
    mask=(local<1)&~notch
    rib=(.53-t*.29)*abs(x-.5)
    phase=(t-rib-abs(x-.5)**1.55*.75)*10
    veins=np.exp(-(np.sin(phase*np.pi)/(0.09+local*.04))**2)*(.60-.30*local)
    spine=np.exp(-((x-.5)/(.004+.007*(1-t)))**2)
    rand=np.random.default_rng(713).normal(0,.018,(SIZE,SIZE))
    glow=.79+.23*(1-local)+.14*(x-.46)+.025*np.sin(phase*2*np.pi)+rand
    rgb=np.array([82,104,49])[None,None,:]*np.clip(glow,.62,1.35)[:,:,None]
    rgb+=(veins*.29+spine*.59)[:,:,None]*[57,52,26]
    alpha=(255*mask).astype('uint8')
    return Image.fromarray(np.dstack([np.clip(rgb,0,255).astype('uint8'),alpha]))


def canopy_cluster():
    # Use sunlit and shaded leaf groups from the photographed bank. The mask
    # separates a branching spray with open gaps, ready to wrap over a 3D crown.
    source=Image.open(ART/'references/wooded_ravine.jpg').convert('RGB')
    photo=source.crop((15,616,443,1025)).resize((408,512),Image.Resampling.LANCZOS)
    rgb=np.asarray(photo).astype(float)
    light=np.asarray(photo.filter(ImageFilter.GaussianBlur(20))).mean(axis=2)
    rgb*=np.clip((62+light.mean())/(light+62),.70,1.46)[:,:,None]
    rgb=rgb*.80+np.array([10,17,6])
    mask=Image.new('L',(408,512)); draw=ImageDraw.Draw(mask)
    rng=random.Random(2084)
    for side in [-1,1]:
        for j in range(9):
            root=np.array([204.,448.-j*38])
            tip=root+np.array([side*(40+122*math.sin((j+1)/11*math.pi)), -36.-rng.random()*36])
            draw.line([tuple(root),tuple(tip)],fill=255,width=4)
            for k in range(60):
                t=rng.random(); a,b=root+(tip-root)*t
                a+=rng.gauss(0,11); b+=rng.gauss(0,15)
                width=rng.uniform(5,17); length=rng.uniform(9,29)
                direction=side*rng.uniform(.25,1.)
                draw.polygon([(a,b),(a-width,b-length*.43),(a+direction*length,b-length),
                              (a+width,b-length*.31)],fill=255)
    alpha=np.asarray(mask.filter(ImageFilter.GaussianBlur(.55))).astype(float)
    return Image.fromarray(np.dstack((np.clip(rgb,0,255),alpha)).astype('uint8'))


def atlas():
    img=Image.new('RGBA',(1024,1024))
    img.paste(reed_plume(),(0,0))
    img.paste(leaf_map(),(SIZE,0))
    y,x=np.mgrid[0:SIZE,0:SIZE]/(SIZE-1)
    rng=np.random.default_rng(221)
    fine=(rng.random(SIZE)-.5)[None,:]*.11
    for offset,base in [(0,[128,143,65]),(SIZE,[164,158,86])]:
        ridges=.045*np.sin(129*x+3*np.sin(6*y))+.028*np.cos(x*446+y*6)
        value=.89+.13*np.cos((x-.48)*6)+ridges+fine+.09*y
        rgb=np.clip(value[:,:,None]*base+np.exp(-((x-.49)/.016)**2)[:,:,None]*[31,33,14],0,255).astype('uint8')
        img.paste(Image.fromarray(rgb).convert('RGBA'),(offset,SIZE))
    img.paste(canopy_cluster(),(616,512))
    img.save(OUT/'field_botany.png',optimize=True)


def cliff():
    im=Image.open(ART/'references/terraced_cut.jpg').convert('RGB')
    # A single bare face between the grass bench and the foreground shrubs.
    crop=im.crop((614,1064,1102,1340)).resize((640,384),Image.Resampling.LANCZOS)
    color=np.asarray(crop).astype(float)
    light=np.asarray(crop.filter(ImageFilter.GaussianBlur(15))).mean(axis=2)
    color*=np.clip((light.mean()+8)/(light+8),.71,1.32)[:,:,None]
    # Blend overlapping opposite margins in both axes into one periodic tile.
    for axis,overlap in [(1,96),(0,64)]:
        values=np.swapaxes(color,0,axis)
        body=values[:-overlap].copy()
        f=np.linspace(0,1,overlap,endpoint=False)
        f=(f*f*(3-2*f))[:,None,None]
        body[:overlap]=(1-f)*values[-overlap:]+f*values[:overlap]
        color=np.swapaxes(body,0,axis)
    color=np.clip(color,0,255).astype('uint8')
    Image.fromarray(color).save(OUT/'rose_shale.jpg',quality=93,subsampling=0)


if __name__=='__main__':
    OUT.mkdir(exist_ok=True,parents=True)
    atlas()
    cliff()
