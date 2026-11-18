"""Build the two original cutout textures. The generated PNGs ship with the scene."""
from PIL import Image, ImageDraw
from random import Random
from math import sin, cos, pi
from pathlib import Path

def spray(kind):
    rng = Random(893 if kind == 'fir' else 714)
    n = 768
    image = Image.new('RGBA', (n,n), (53,75,46,0))
    draw = ImageDraw.Draw(image)
    def line(a,b,c,w):
        draw.line((a,b), fill=c, width=max(1,round(w)))
    # From a branch collar to a tapered tip; lateral shoots fan into the gaps.
    root = (n*.5,n*.985)
    spine = [(root[0]+n*.025*sin(t*.15),root[1]-t*n*.0185) for t in range(52)]
    for i in range(50,-1,-1):
        x,y=spine[i]
        t=i/51
        line((x,y),spine[i+1] if i<51 else (x,y-4),(84,71,46,255),7*(1-t)+1)
        if i < 4: continue
        for side in [-1,1]:
            length=(1-t)**.65 * (0.38 if kind=='fir' else .49)*n*rng.uniform(.72,1.16)
            rise=length*rng.uniform(.45,.86)
            prev=(x,y)
            for j in range(1,14):
                q=j/13
                xx=x+side*length*q; yy=y-rise*q**1.2
                line(prev,(xx,yy),(83,84,45,255),2.1)
                prev=(xx,yy)
                for direction in [-1,1]:
                    a=rng.uniform(.45,1.15)*direction
                    sx=side*cos(a); sy=sin(a)-.52
                    if kind=='fir':
                        l=(.25+.75*(1-q)**.7)*rng.uniform(18,45)*(1-.45*t)
                        tip=(xx+l*sx,yy+l*sy)
                        line((xx,yy),tip,(60,77,41,255),3)
                        # Fine needles in light/shade clusters on either side of the shoot.
                        for k in range(1,8):
                            p=k/8
                            for s in [-1,1]:
                                L=(1-.55*p)*rng.uniform(3,9)
                                color=rng.choice([(73,93,61),(52,74,48),(89,106,69),(67,87,62),(106,119,78)])
                                bx=xx+p*l*sx; by=yy+p*l*sy
                                line((bx,by),(bx+L*(sx-s*.78*sy),by+L*(sy+s*.78*sx)),color+(255,),2.2)
                    else:
                        l=(1-q*.65)*rng.uniform(12,20)*(1-.52*t)
                        w=l*.20
                        col=rng.choice([(73,95,46),(93,114,51),(62,82,45),(104,118,58)])
                        draw.polygon([(xx,yy),(xx+l*.40*sx-w*sy,yy+l*.4*sy+w*sx),
                                      (xx+l*sx,yy+l*sy),(xx+l*.5*sx+w*sy,yy+l*.5*sy-w*sx)],fill=col+(255,))
    image.resize((512,512),Image.Resampling.LANCZOS).save(Path('shared/textures')/(kind+'.png'), optimize=True)

for kind in ['fir','fern']: spray(kind)
