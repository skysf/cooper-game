"""Fit the mine walkable surfaces and collision to the shared coast heightfield."""
from __future__ import annotations

from array import array
from bisect import bisect_right
from math import cos, hypot, pi, sin, sqrt
from pathlib import Path
import json
import sys


PROJECT = Path(__file__).resolve().parents[1]
COOP = PROJECT / "coop"
RUNTIME = COOP / "props/mines"
APRON = -3.45
BACK = 11.35
WALL_SECTIONS = (0.0, .72, 1.68, 2.74, 3.82, 4.86, 5.89, 6.96, 8.0, 9.12, 10.25, BACK)
PROFILE = ((-1, -.57), (-1, .73), (-.89, 1.67), (-.66, 2.31), (-.34, 2.66),
           (0, 2.78), (.37, 2.68), (.70, 2.34), (.92, 1.63), (1, .71), (1, -.57))
TOP = 1 << 3

SITES = {
    "coal_mine": {
        "title": "煤矿洞", "item": "coal", "origin": [-74.25, 19.8093, -31.35], "yaw": 0.0,
        "approach": [(-71.5,-51.7), (-71.5,-39.12), (-71.57,-38.15), (-72.17,-37.28),
                     (-73.13,-36.33), (-73.77,-35.53), (-74.10,-35.11), (-74.25,-34.8)],
        "seam": [-1, 8.34],
    },
    "iron_mine": {
        "title": "铁矿洞", "item": "iron_ore", "origin": [-74.25, 21.7668, -66.55], "yaw": -pi,
        "approach": [(-69.30,-53.81), (-69.85,-54.45), (-69.85,-55.0), (-70.4,-55.55),
                     (-70.4,-56.1), (-70.95,-56.65), (-71.5,-57.2), (-71.66,-57.74),
                     (-71.92,-58.33), (-72.05,-59.3), (-72.05,-61.9), (-72.31,-62.36),
                     (-73.03,-62.83), (-74.25,-63.1)],
        "seam": [1, 8.70],
    },
}


class CoastHeight:
    def __init__(self):
        data = json.loads((COOP / "coast_layout.json").read_text())
        self.x, self.z = data["origin"]
        self.cols, self.rows = data["cells"]
        self.spacing = data["spacing"]
        self.grid = array("f", (COOP / "coast/elevation.bin").read_bytes())
        if sys.byteorder == "big":
            self.grid.byteswap()

    def __call__(self, x, z):
        gx, gz = (x-self.x)/self.spacing, (z-self.z)/self.spacing
        gx, gz = max(0, min(self.cols, gx)), max(0, min(self.rows, gz))
        ix, iz = min(int(gx), self.cols-1), min(int(gz), self.rows-1)
        u, v = gx-ix, gz-iz
        i = iz*(self.cols+1)+ix
        a, b, c, d = (self.grid[j] for j in (i, i+1, i+self.cols+1, i+self.cols+2))
        if u + v <= 1:
            return a+(b-a)*u+(c-a)*v
        return d+(c-d)*(1-u)+(b-d)*(1-v)


def world(site, x, y, z):
    ox, oy, oz = site["origin"]
    c, s = cos(site["yaw"]), sin(site["yaw"])
    return [ox+c*x+s*z, oy+y, oz-s*x+c*z]


def weft(site, z):
    """Lateral shape independent of floor elevation, from splayed entry to the chamber."""
    inside = min(max(z, 0), BACK)
    phase = 0 if site["item"] == "coal" else .73
    center = .28*sin(inside*.40+phase) - .28*sin(phase)
    if z < 0:
        t = min(1, max(0, (z+2.1)/2.1))
        wide = .49 + .87*t*t*(3-2*t)
    else:
        wide = 1.36 + .19*sin(inside*.26)**2 + .23*sin(min(pi/2, max(0, inside-5.9)*.48))**2
    crown = 1.0 + .053*sin(inside*.76+phase)
    return center, wide, crown


def height_at(coast, site, x, z):
    wx, _, wz = world(site, x, 0, z)
    return coast(wx, wz)-site["origin"][1]


def floor_field(coast, site):
    depths = sorted({round(APRON + i*.29, 4) for i in range(52) if APRON+i*.29<BACK}
                    | set(WALL_SECTIONS) | {APRON, BACK})
    need = []
    for z in depths:
        center, wide, _ = weft(site,z)
        # The aperture is sculpted above the existing surface. Ahead and behind
        # samples guard against a terrain vertex poking through a floor span.
        cross = wide-.03
        fit = max(height_at(coast,site,center+cross*i/8,z+offset)
                  for i in range(-8,9) for offset in [-.10,0,.10])+.035
        interior = max(0, min(1,(z-APRON)/2.3))
        center_ground = height_at(coast,site,center,z)
        need.append(center_ground+.008+(fit-center_ground-.008)*interior)
    # A Lipschitz envelope smooths an abrupt ridge without lowering any walkable floor.
    grade = .735
    heights = [max(n-grade*abs(d-z) for d,n in zip(depths,need)) for z in depths]
    return [[z, y, *weft(site,z)[:2]] for z,y in zip(depths,heights)]


def local(site, x, y, z):
    ox,oy,oz = site["origin"]
    c,s = cos(site["yaw"]),sin(site["yaw"])
    return [c*(x-ox)-s*(z-oz), y-oy, s*(x-ox)+c*(z-oz)]


def approach_field(coast, site, floor):
    route = site["approach"]
    points = []
    distances = []
    length = 0.0
    for a,b in zip(route,route[1:]):
        piece = hypot(b[0]-a[0],b[1]-a[1])
        count = int(piece/.24)+1
        for k in range(count):
            t = k/count
            points.append((a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t))
            distances.append(length+piece*t)
        length += piece
    points.append(route[-1])
    distances.append(length)
    rows = []
    need = []
    for i,((x,z),d) in enumerate(zip(points,distances)):
        before,after = points[max(i-1,0)],points[min(i+1,len(points)-1)]
        dx,dz = difference(after,before)
        ux,_,uz = unit((dz,0,-dx))
        w = .595-.105*max(0,1-(length-d)/.92)
        fitted = max(coast(x+ux*w*t,z+uz*w*t) for t in (-1,-.75,-.5,-.25,0,.25,.5,.75,1))+.033
        transition = min(1,d/.92)
        outer = coast(x,z) + (fitted-coast(x,z))*transition
        need.append(outer)
        rows.append([x,z,ux,uz,w])
    need[-1] = floor[0][1]+site["origin"][1]
    ys = [max(y-.63*abs(q-d) for q,y in zip(distances,need)) for d in distances]
    return [[*local(site,x,y,z),w] for (x,z,ux,uz,w),y in zip(rows,ys)]


def approach_boxes(stations):
    for (xa,ya,za,wa),(xb,yb,zb,wb) in zip(stations,stations[1:]):
        delta = (xb-xa,yb-ya,zb-za)
        path = unit(delta)
        lateral = unit((zb-za,0.,xa-xb))
        up = cross(path,lateral)
        thickness = .086
        mid = ((xa+xb)*.5,(ya+yb)*.5,(za+zb)*.5)
        center = tuple(v-n*thickness*.5 for v,n in zip(mid,up))
        yield obb(center,(2*min(wa,wb)-.028,thickness,sqrt(dot(delta,delta))+.090),
                  (lateral,up,path),TOP)


def floor_at(floor, z):
    depths = [p[0] for p in floor]
    i = min(max(bisect_right(depths,z),1),len(depths)-1)
    a, b = floor[i-1],floor[i]
    t = min(max((z-a[0])/(b[0]-a[0]),0),1)
    return [a[j] + t*(b[j]-a[j]) for j in range(1,4)]


def ring(site, floor, z):
    y, cx, width = floor_at(floor,z)
    _, _, crown = weft(site,z)
    return [(cx+x*width, y+dy*crown, z) for x,dy in PROFILE]


def difference(a,b):
    return tuple(x-y for x,y in zip(a,b))


def dot(a,b):
    return sum(x*y for x,y in zip(a,b))


def cross(a,b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def unit(v):
    length = sqrt(dot(v,v))
    return tuple(x/length for x in v)


def obb(center, size, basis=((1.,0.,0.),(0.,1.,0.),(0.,0.,1.)), faces=0):
    return {"center":center, "size":size, "basis":basis, "faces":faces}


def walk_boxes(floor):
    for (za,ya,ca,wa), (zb,yb,cb,wb) in zip(floor,floor[1:]):
        path = unit((0,yb-ya,zb-za))
        lateral = (1.,0.,0.)
        up = cross(path,lateral)
        thickness = .094
        top = ((ca+cb)*.5, (ya+yb)*.5, (za+zb)*.5)
        center = tuple(v-n*thickness*.5 for v,n in zip(top,up))
        yield obb(center, (2*min(wa,wb)-.04, thickness,hypot(zb-za,yb-ya)+.026),
                  (lateral,up,path), TOP)


def shell_boxes(site, floor):
    for a, b in zip(WALL_SECTIONS,WALL_SECTIONS[1:]):
        ra, rb = ring(site,floor,a), ring(site,floor,b)
        y0, ca, _ = floor_at(floor,a)
        y1, cb, _ = floor_at(floor,b)
        path = unit((cb-ca,y1-y0,b-a))
        for i in range(len(ra)-1):
            # Short masonry sections follow the actual opening silhouette. The
            # box's local -Y face is the nearest stone face to the walk lane.
            corners = [ra[i],ra[i+1],rb[i],rb[i+1]]
            tangent = difference(ra[i+1],ra[i])
            normal = unit(cross(path,tangent))
            lateral = cross(normal,path)
            lo, hi = (list(fn(dot(p,axis) for p in corners) for axis in (lateral,normal,path))
                      for fn in (min,max))
            lo[0] -= .09
            hi[0] += .09
            lo[2] -= .11
            hi[2] += .11
            lo[1] -= .035
            hi[1] += 1.02 if i in (0,len(ra)-2) else .84
            mid = [(v+w)*.5 for v,w in zip(lo,hi)]
            center = tuple(sum(a[j]*v for a,v in zip((lateral,normal,path),mid)) for j in range(3))
            yield obb(center,difference(hi,lo),(lateral,normal,path))
    y,cx,width = floor_at(floor,BACK)
    yield obb((cx,y+1.11,BACK+.22),(width*2+.18,3.46,.50))


def manifest():
    coast = CoastHeight()
    mines = {}
    for ident, site in SITES.items():
        floor = floor_field(coast,site)
        side, depth = site["seam"]
        y,cx,width = floor_at(floor,depth)
        anchor = [cx+side*(width-.014), y+1.04, depth]
        seam_yaw = 0.0 if side == 1 else pi
        footpath = approach_field(coast,site,floor)
        route = [world(site,x,y,z) for x,y,z,_ in footpath]
        route += [world(site,cx,fy,z) for z,fy,cx,_ in floor if APRON < z <= 0]
        stems = ident.split("_",1)
        lamps = []
        for i,z in enumerate((.32,3.75,7.96,10.16)):
            local_y, x, w = floor_at(floor,z)
            side_sign = -side if i in (0,2) else side
            lamps.append({
                "at": [x+side_sign*(w-.28),local_y+1.77,z],
                "energy": 1.75 if i == 0 else 2.55,
                "range": 5.8,
                "color": [1.0,.67,.37],
            })
        frames = []
        frame_boxes = []
        for z in (.64,4.14,7.31):
            fy, fc, fw = floor_at(floor,z)
            half_gap, beam_y = fw*.88, fy+2.28
            frames.append({"at":[fc,fy,z], "halfGap":half_gap, "beamY":beam_y})
            for sign in (-1,1):
                frame_boxes.append(obb((fc+sign*half_gap,fy+.954,z),(.16,2.31,.178)))
            frame_boxes.append(obb((fc,beam_y,z),(2*half_gap+.26,.17,.19)))
        mines[ident] = {
            **{k:site[k] for k in ("title","item","origin","yaw")},
            "model": f"res://props/mines/{ident}.glb",
            "gather": anchor,
            "seam": {"model": f"res://props/mines/{stems[0]}_seam.glb",
                     "at":anchor, "yaw":seam_yaw},
            "route": route,
            "floor": floor,
            "footpath": footpath,
            "colliders": [*approach_boxes(footpath), *walk_boxes(floor), *shell_boxes(site,floor), *frame_boxes],
            "frames": frames,
            "lamps": lamps,
        }
    return {"version":1, "units":"m", "mines":mines}


def write(data):
    def compact(value):
        if isinstance(value, float):
            return round(value,6)
        if isinstance(value,(tuple,list)):
            return [compact(x) for x in value]
        if isinstance(value,dict):
            return {k:compact(v) for k,v in value.items()}
        return value

    RUNTIME.mkdir(parents=True,exist_ok=True)
    # A compact row per shape keeps the file inspectable without multiplying
    # the hundreds of OBB coordinates into thousands of separate lines.
    ready = compact(data)
    text = ['{', '  "version": 1,', '  "units": "m",', '  "mines": {']
    for index,(ident,mine) in enumerate(ready["mines"].items()):
        text.append('    '+json.dumps(ident)+': {')
        for i,(key,value) in enumerate(mine.items()):
            suffix = ',' if i+1<len(mine) else ''
            item = '      '+json.dumps(key)+': '
            if key in ("floor","colliders","route","lamps","frames","footpath"):
                text.append(item+'[')
                text += ['        '+json.dumps(row,ensure_ascii=False)+(',' if j+1<len(value) else '')
                         for j,row in enumerate(value)]
                text.append('      ]'+suffix)
            else:
                text.append(item+json.dumps(value,ensure_ascii=False)+suffix)
        text.append('    }'+(',' if index+1<len(ready["mines"]) else ''))
    text += ['  }','}','']
    (RUNTIME/"mines_manifest.json").write_text('\n'.join(text))


if __name__ == "__main__":
    write(manifest())
