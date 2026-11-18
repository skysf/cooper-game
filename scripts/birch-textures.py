"""Generate repeatable birch bark and a cutout leaf spray for the grove (CC0)."""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

output = Path(__file__).resolve().parents[1] / "coop" / "trees"
output.mkdir(exist_ok=True)
rng = random.Random(2309)
size = 512
noise = np.random.default_rng(2309)
grain = noise.normal(0, 3.2, (size, size))
# Periodic broad streaks preserve a continuous seam around the trunk.
y, x = np.mgrid[:size, :size] * (math.tau / size)
tone = 187 + grain + 8*np.sin(3*x + 0.7*np.sin(y)) + 6*np.sin(2*y + 4*x)
bark = Image.fromarray(np.uint8(np.clip(np.stack([tone+10, tone+8, tone], axis=2), 0, 255)))
brush = ImageDraw.Draw(bark)
for _ in range(2000):
    px, py = rng.randrange(size), rng.randrange(size)
    length = int(1 + rng.expovariate(.17))
    dark = rng.randint(36, 155)
    for shift in (0, -size):
        sx = px + shift
        brush.polygon([(sx, py), (sx+length*.38, py-1), (sx+length, py),
                       (sx+length*.56, py+rng.choice([1, 1, 2]))],
                      fill=(dark+7, dark+6, dark))
bark.save(output / "birch_bark.jpg", quality=87)

scale = 2
leaf_tex = Image.new("RGBA", (256*scale, 320*scale), (64, 85, 38, 0))
d = ImageDraw.Draw(leaf_tex)
def ink(points, color, thickness=1):
    d.line([(round(x*scale), round(y*scale)) for x,y in points],
           fill=color, width=round(thickness*scale))
def stem(t):
    return (128 + 10*math.sin(t*3) + 13*t, 316-295*t)
def leaf(base, angle, length):
    u = (math.cos(angle), math.sin(angle))
    v = (-u[1], u[0])
    def loc(t, w):
        return (base[0]+length*(t*u[0]+w*v[0]), base[1]+length*(t*u[1]+w*v[1]))
    fractions = [i/16 for i in range(17)]
    def half(t):
        return (.33 * (math.sin(math.pi*t)**.8) * (1.23-.6*t)) if 0 < t < 1 else 0
    silhouette = [loc(t, s*half(t)*(.83 if i%2 else 1))
                  for s, seq in [(1, fractions), (-1, fractions[::-1])]
                  for i,t in enumerate(seq)]
    g = rng.randint(68, 125)
    d.polygon([(round(x*scale),round(y*scale)) for x,y in silhouette],
              fill=(int(g*.61),g,int(g*.32),255))
    ink([loc(0,0),loc(.88,0)],(int(g*.83),g+12,int(g*.49),255),1.2)
    for t in [.20,.34,.48,.62]:
        for s in [-1,1]:
            ink([loc(t,0),loc(t+.16,half(t+.16)*s*.88)],(int(g*.74),g+5,int(g*.4),255),.5)
ink([stem(i/20) for i in range(21)],(86,76,49,255),2.2)
for i in range(13):
    t = .055 + i*.069
    side = (-1)**i
    start = stem(t)
    span = (27+51*math.sin(math.pi*t)**.65)*(1-.4*t)
    end = (start[0]+side*span,start[1]-20-24*t)
    ink([start,end],(90,91,54,255),1.4)
    for k in range(3):
        s = .34 + .32*k
        p = tuple(a+(b-a)*s for a,b in zip(start,end))
        angle = math.atan2(-.60 + (.53 if k%2 else -.52), side*(.46+.18*k))
        leaf(p,angle,rng.uniform(26,39)*(1.04-.27*t))
leaf(stem(.98),-1.33,20)
leaf_tex.resize((256,320),Image.Resampling.LANCZOS).save(output / "birch_leaves.png", optimize=True)
