"""Dilate image color past white backdrop at the turnaround silhouettes to protect UV borders."""
import sys
from pathlib import Path
import numpy as np
from PIL import Image


def bilinear(rgb,x,y):
    x=np.clip(x,0,rgb.shape[1]-1.001)
    y=np.clip(y,0,rgb.shape[0]-1.001)
    u=x.astype(int); v=y.astype(int)
    fx=(x-u)[:,:,None]; fy=(y-v)[:,:,None]
    return (rgb[v,u]*(1-fx)+rgb[v,u+1]*fx)*(1-fy)+(rgb[v+1,u]*(1-fx)+rgb[v+1,u+1]*fx)*fy


def projections(atlas, photo, female):
    # Sample front, back and the supplied true side views in a single continuous
    # skin unwrap. Opposite panels meet at the exact same side-view texel.
    body_z=[.82,.88,.96,1.04,1.12,1.19,1.25,1.30,1.36,1.404,1.435,1.455]
    if female:
        body_front=[404,378,351,326,295,272,251,228,203,179,165,153]
        body_back=[397,371,346,319,292,270,248,227,204,181,164,152]
        body_side=[398,378,352,327,303,278,254,231,206,184,170,159]
        side_center=[894,896,902,906,904,901,902,897,889,883,879,877]
    else:
        body_front=[409,384,359,337,309,282,265,246,228,209,194,185]
        body_back=[401,380,358,340,312,291,269,251,225,213,193,183]
        body_side=[401,380,356,335,310,291,266,248,228,205,194,184]
        side_center=[851,851,850,851,852,852,850,851,851,862,864,862]
    body_width=[48,50,49,45,45,54,58,62,62,46,26,15]
    head_z=[1.485,1.497,1.516,1.535,1.555,1.577,1.596,1.617,1.639,1.664,1.688,1.708,1.717]
    portrait=([(255,320,15),(258,314,37),(263,301,56),(264,279,72),(267,248,78),(269,224,82),
               (267,184,82),(260,159,87),(255,147,89),(249,112,84),(241,87,70),(235,66,45),(232,59,15)] if female else
              [(224,426,15),(224,417,47),(222,396,66),(222,365,83),(225,333,94),(222,305,96),
               (221,262,94),(219,244,94),(216,220,92),(214,196,90),(212,164,78),(212,141,56),(212,127,19)])
    hside_y=([141,138,133,126,119,111,99,92,83,70,60,51,48] if female else [175,170,164,154,143,133,121,113,103,94,85,77,73])
    hside_x=([907,905,904,901,898,897,895,894,892,888,884,881,879] if female else [852,850,848,845,845,846,847,848,850,853,855,858,860])
    for is_face in (False,True):
        for front in (True,False):
            if is_face:
                y0,y1=(483,731) if front else (747,995)
                levels=head_z
            else:
                y0,y1=(10,234) if front else (246,470)
                levels=body_z
            h=y1-y0+1; w=241 if is_face else 181
            nz,an=np.meshgrid(np.linspace(levels[-1],levels[0],h),np.linspace(-np.pi/2,np.pi/2,w),indexing='ij')
            si=np.sin(an); co=np.cos(an)
            def interp(sample):return np.interp(nz,levels,sample)
            signed=co if front else -co
            if is_face:
                if front:
                    ux=interp([r[0] for r in portrait])+(si if not female else -np.abs(si))*interp([r[2] for r in portrait])
                    vy=interp([r[1] for r in portrait])
                else:
                    ux=(1190 if female else 1170)-si*interp([8,15,18,20,24,26,27,27,25,23,20,15,7])
                    vy=(151 if female else 182)-(nz-1.485)*365
                sx=interp(hside_x)+signed*(17 if female else -17)
                sy=interp(hside_y)
                mix=np.clip((co-.09)/.45,0,1)
            else:
                cx=(579 if front else 1190) if female else (577 if front else 1170)
                ux=cx+(si if front else -si)*interp(body_width)
                vy=interp(body_front if front else body_back)
                sx=interp(side_center)+signed*(13 if female else -13)
                sy=interp(body_side)
                mix=np.clip((co-.095)/.63,0,1)
            mix=(mix*mix*(3-2*mix))[:,:,None]
            tile=bilinear(photo,ux,vy)*mix+bilinear(photo,sx,sy)*(1-mix)
            atlas[y0:y1+1,1390:1390+w]=np.clip(tile,0,255)
            # Populate two neighboring texels so mipmapping doesn't sample the background.
            atlas[y0-2:y0,1390:1390+w]=atlas[y0,1390:1390+w]
            atlas[y1+1:y1+3,1390:1390+w]=atlas[y1,1390:1390+w]
            atlas[y0-2:y1+3,1388:1390]=atlas[y0-2:y1+3,1390:1391]
            atlas[y0-2:y1+3,1390+w:1392+w]=atlas[y0-2:y1+3,1389+w:1390+w]

source, dest = map(Path, sys.argv[1:3])
rgb = np.array(Image.open(source).convert("RGB"))
if "高级" not in source.name:
    hi = rgb.max(axis=2).astype(float)
    lo = rgb.min(axis=2).astype(float)
    # Include neutral gray photographic foot shadows in the backdrop mask.
    valid = (lo < 152) | ((hi - lo) > 23)
    # Extrapolate neighboring colors before JPEG encoding. Do not touch the original.
    for _ in range(105):
        if valid.all(): break
        total = np.zeros(rgb.shape, dtype=np.uint16)
        count = np.zeros(valid.shape, dtype=np.uint8)
        for dy, dx in [(0,1),(0,-1),(1,0),(-1,0),(1,1),(-1,-1)]:
            vs = np.roll(valid,(dy,dx),(0,1))
            cs = np.roll(rgb,(dy,dx),(0,1))
            if dy>0: vs[:dy]=False
            if dy<0: vs[dy:]=False
            if dx>0: vs[:,:dx]=False
            if dx<0: vs[:,dx:]=False
            total += cs*vs[:,:,None]
            count += vs
        fringe = ~valid & (count>0)
        rgb[fringe] = total[fringe] // count[fringe,None]
        valid |= fringe
    # Reserve the unused left atlas margin for continuous body and neck skin.
    # The tonal range is sampled from the arm, jaw and neck in each portrait.
    female="女性" in source.name
    yy,xx=np.mgrid[0:203,0:96]
    noise=np.random.default_rng(219).normal(0,1.9,(203,96))
    jx,jy=((210,355) if female else (220,473))
    donor=rgb[jy:jy+26,jx:jx+30].astype(float)
    pore=donor.mean(2)
    pore-=np.median(pore)
    value=.075*np.cos((xx/95-.50)*np.pi*2)+.035*np.cos((yy/202-.25)*np.pi*2)
    value+=.021*np.sin(xx*.27+yy*.048)+.0008*pore[yy%26,xx%30]
    base=np.array([168,112,77] if female else [141,91,65])
    rgb[1:204,0:96]=np.clip(base*(1+value[:,:,None])+noise[:,:,None],0,255)
    xx,yy=np.meshgrid(np.linspace(-1,1,96),np.linspace(0,1,98))
    top=np.array([122,77,52] if female else [98,64,48])
    bottom=np.array([171,114,78] if female else [152,101,73])
    w=np.clip(yy*1.18,0,1)[:,:,None]
    neck=top*(1-w)+bottom*w
    shade=1+.055*np.cos(xx*np.pi)+.055*np.cos((xx-.3+yy*.31)*np.pi*2)
    rgb[222:320,0:96]=np.clip(neck*shade[:,:,None]+noise[:98,:,None]*.59,0,255)
if "高级" not in source.name:
    atlas=np.full((1024,2048,3),78,dtype=np.uint8)
    atlas[:768,:1376]=rgb
    projections(atlas,rgb,female)
    rgb=atlas
Image.fromarray(rgb).save(dest,quality=87,subsampling=0,optimize=True)
