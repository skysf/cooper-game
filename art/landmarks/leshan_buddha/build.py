"""Build the seated Leshan landmark in metres. Blender Z is up, the Buddha faces -Y."""
from bisect import bisect_right
from math import atan2, cos, exp, pi, sin, sqrt, tau
from pathlib import Path
import tempfile
import sys
import runpy

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
NAME = "leshan_buddha"
BIG_NAIL = (1.10, 0.96)  # half-width, half-length
BIG_TOE_X = 4.43
BIG_NAIL_Y = -16.96
BIG_NAIL_Z = 2.28

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
surface_collection = bpy.data.collections.new("Leshan • carved sandstone")
scene.collection.children.link(surface_collection)
objects = []


def packed_relief(source, name, normal=False):
    """Reuse the project's CC0 Rock Face 03 grain, removing its large-scale lighting."""
    im = bpy.data.images.load(str(ROOT / 'coop/coast' / source))
    if normal:
        im.colorspace_settings.name = 'Non-Color'
    size = 1024
    im.scale(size, size)
    pixels = np.empty(size * size * 4, dtype='f')
    im.pixels.foreach_get(pixels)
    pixels = pixels.reshape(size, size, 4)
    if normal:
        vec = pixels[:, :, :3] * 2 - 1
        vec[:, :, :2] *= .32
        vec /= np.maximum(.001, np.linalg.norm(vec, axis=2, keepdims=True))
        pixels[:, :, :3] = .5 + vec * .5
    else:
        lum = np.maximum(.005, pixels[:, :, :3] @ np.array([.2126, .7152, .0722]))
        lum = np.log(lum)
        blurred = sum(np.roll(np.roll(lum, a, 0), b, 1)
                      for a in (-22, -9, 0, 9, 22) for b in (-22, -9, 0, 9, 22)) / 25
        pixels[:, :, :3] = np.clip(.79 + .145 * (lum-blurred)[:, :, None]
                                    + .08 * (blurred - np.mean(blurred))[:, :, None], .50, .98)
    pixels[:, :, 3] = 1
    im.pixels.foreach_set(pixels.ravel())
    im.update()
    # Do not change the source image. Reopen the derived PNG before packing it.
    with tempfile.TemporaryDirectory() as directory:
        path = str(Path(directory) / (name + '.png'))
        im.filepath_raw = path
        im.file_format = 'PNG'
        im.save()
        bpy.data.images.remove(im)
        packed = bpy.data.images.load(path)
        packed.name = name
        if normal:
            packed.colorspace_settings.name = 'Non-Color'
        packed.pack()
        packed.filepath = '//' + name + '.png'
    return packed


def stone_material():
    mat = bpy.data.materials.new("Weathered sandstone")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = .91
    shader.inputs['Specular IOR Level'].default_value = .22
    color = nodes.new('ShaderNodeTexImage')
    color.image = packed_relief('cliff_color.jpg', 'Sandstone grain')
    tint = nodes.new('ShaderNodeVertexColor')
    tint.layer_name = 'Stone'
    multiply = nodes.new('ShaderNodeMixRGB')
    multiply.blend_type = 'MULTIPLY'
    multiply.inputs[0].default_value = 1
    links.new(color.outputs['Color'], multiply.inputs[1])
    links.new(tint.outputs['Color'], multiply.inputs[2])
    links.new(multiply.outputs[0], shader.inputs['Base Color'])
    normal = nodes.new('ShaderNodeTexImage')
    normal.image = packed_relief('cliff_normal.jpg', 'Sandstone microrelief', True)
    bump = nodes.new('ShaderNodeNormalMap')
    links.new(normal.outputs['Color'], bump.inputs['Color'])
    links.new(bump.outputs['Normal'], shader.inputs['Normal'])
    return mat


MAT = stone_material()
# sRGB swatches are modulated in metres over the entire carving, including its separate parts.
PALETTE = {
    'face': (176, 128, 109), 'body': (139, 115, 98), 'hand': (159, 128, 108),
    'robe': (117, 107, 94), 'hem': (136, 115, 98), 'rock': (145, 119, 97),
    'foot': (155, 125, 103), 'nail': (174, 143, 119), 'lip': (161, 108, 94),
    'hair': (73, 74, 66), 'brow': (83, 70, 60), 'crease': (102, 77, 65),
}


def field(p, spacing, seed):
    p = p / np.asarray(spacing)
    cell = np.floor(p)
    f = p - cell
    f *= f * (3 - 2 * f)
    value = np.zeros(len(p))
    for i in (0, 1):
        for j in (0, 1):
            for k in (0, 1):
                n = np.sin((cell[:, 0]+i)*127.1 + (cell[:, 1]+j)*311.7
                           + (cell[:, 2]+k)*74.7 + seed)*43758.5453
                value += (n-np.floor(n)) * (f[:, 0] if i else 1-f[:, 0]) * (
                    f[:, 1] if j else 1-f[:, 1]) * (f[:, 2] if k else 1-f[:, 2])
    return value


def stone_colors(points, kind):
    p = np.asarray(points)
    large = field(p, [4, 4, 5], 2.7)
    streak = field(p, [.65, .85, 7.0], 18.0)
    fleck = field(p, [.49, .49, .49], 6.1)
    strata = np.sin(p[:, 2]*2.55 + p[:, 0]*.19 + large*3.1)
    amp = .52 if kind in ('face', 'brow', 'crease', 'lip', 'hair') else 1.
    value = 1 + amp*(.39*(large-.5) + .37*(streak-.5) + .17*(fleck-.5) + .025*strata)
    srgb = np.array(PALETTE[kind]) / 255 * value[:, None]
    patina = np.clip((.59-large)*2.1 + (.42-streak)*.52, 0, .52) * amp
    srgb = srgb*(1-patina[:, None]) + np.array([.29,.32,.25])*patina[:, None]
    linear = np.where(srgb <= .04045, srgb/12.92, ((srgb+.055)/1.055)**2.4)
    return np.column_stack((linear, np.ones(len(p)))).astype('f')


def mesh(name, verts, faces, kind):
    m = bpy.data.meshes.new(name)
    m.from_pydata(verts, [], faces)
    m.update()
    m.materials.append(MAT)
    m.polygons.foreach_set('use_smooth', np.ones(len(m.polygons), dtype=bool))
    v = np.asarray(verts, dtype='f')
    col = m.color_attributes.new(name='Stone', type='FLOAT_COLOR', domain='POINT')
    col.data.foreach_set('color', stone_colors(v, kind).ravel())
    m.color_attributes.active_color = col
    # Dominant-axis UVs keep grain at the same physical size on soles, faces and vertical hems.
    normals = np.empty(3*len(faces), dtype='f')
    m.polygons.foreach_get('normal', normals)
    n = normals.reshape(-1, 3)
    dom = np.repeat(np.abs(n).argmax(axis=1), [len(f) for f in faces])
    vi = np.empty(len(m.loops), dtype='i')
    m.loops.foreach_get('vertex_index', vi)
    xyz = v[vi]
    uv = np.column_stack((np.where(dom == 0, xyz[:, 1], xyz[:, 0]),
                          np.where(dom == 2, xyz[:, 1], xyz[:, 2]))) / 4.5
    layer = m.uv_layers.new(name="Stone grain metres")
    layer.data.foreach_set('uv', np.ascontiguousarray(uv, dtype='f').ravel())
    o = bpy.data.objects.new(name, m)
    surface_collection.objects.link(o)
    objects.append(o)
    return o


def sp(v, power):
    return (-1 if v < 0 else 1) * abs(v)**power


def gau(v, width):
    return exp(-.5*(v/width)**2)


class Profile:
    """Shape-preserving cubic interpolation through measured cross-sections."""
    def __init__(self, rows):
        self.x = [r[0] for r in rows]
        self.y = np.asarray([r[1:] for r in rows], dtype=float)
        self.width = np.diff(self.x)
        s = np.diff(self.y, axis=0) / self.width[:, None]
        self.t = np.zeros_like(self.y)
        self.t[0], self.t[-1] = s[0], s[-1]
        for i in range(1, len(rows)-1):
            a, b = s[i-1], s[i]
            same = (a*b)>0
            self.t[i, same] = 2*a[same]*b[same]/(a[same]+b[same])

    def __call__(self, x):
        i = min(len(self.x)-2, max(0, bisect_right(self.x, x)-1))
        t = min(1.,max(0.,(x-self.x[i])/self.width[i]))
        return ((1+2*t)*(1-t)**2*self.y[i] + t*(1-t)**2*self.width[i]*self.t[i]
                + t*t*(3-2*t)*self.y[i+1] + t*t*(t-1)*self.width[i]*self.t[i+1])


def rings_data(rings):
    count = len(rings[0])
    v = [p for ring in rings for p in ring]
    faces = [(j*count+i, j*count+(i+1)%count, (j+1)*count+(i+1)%count,(j+1)*count+i)
             for j in range(len(rings)-1) for i in range(count)]
    # Cap the rings with triangle fans to preserve their boundary on import.
    for end, reverse in ((0, True), (len(rings)-1, False)):
        c = len(v)
        v.append(tuple(np.mean(rings[end], axis=0)))
        for i in range(count):
            a,b=end*count+i,end*count+(i+1)%count
            faces.append((c,b,a) if reverse else (c,a,b))
    return v,faces


def solid(name, rings, kind):
    return mesh(name, *rings_data(rings), kind)


def loft(name, rows, kind, power=.83, around=72, levels=48, relief=None):
    profile = Profile(rows)
    rings=[]
    for z in np.linspace(rows[0][0],rows[-1][0],levels):
        x,y,rx,ry = profile(z)
        ring=[]
        for j in range(around):
            a=tau*j/around
            d=relief(z,a) if relief else 0
            ring.append((x+(rx+d)*sp(sin(a),power),y-(ry+d)*sp(cos(a),power),z))
        rings.append(ring)
    return solid(name,rings,kind)


def volume_axis(name, sections, kind, around=36, levels=24, power=.88):
    """Swept ovals with X and cross-path radii, used for sleeves, hands and fingers."""
    points=np.asarray([s[:3] for s in sections])
    times=np.r_[0,np.cumsum(np.linalg.norm(np.diff(points,axis=0),axis=1))]
    profile=Profile([(t,*s) for t,s in zip(times,sections)])
    rings=[]
    for t in np.linspace(0,times[-1],levels):
        s=profile(t)
        tangent=Vector(profile(min(t+.03,times[-1]))[:3]-profile(max(t-.03,0))[:3]).normalized()
        e=Vector((1,0,0)); e=(e-tangent*e.dot(tangent)).normalized()
        b=tangent.cross(e).normalized()
        ring=[]
        for j in range(around):
            a=tau*j/around
            pt=Vector(s[:3])+e*(s[3]*sp(cos(a),power))+b*(s[4]*sp(sin(a),power))
            ring.append(tuple(pt))
        rings.append(ring)
    return solid(name,rings,kind)


def rock_relief(z,a):
    return .19*sin(5*a+.05*z)+.14*sin(11*a-.16*z)+.11*sin(3.1*z+.8*sin(a*3))

# Ground level passes through the soles. The support below zero can be buried at installation.
loft('Waterside ledge-col',[(-1.65,0,-2.4,14.1,16.4),(-1.35,0,-2.4,14.9,17.0),
     (-.29,0,-2.4,15.2,17.3),(0,0,-2.4,14.95,17.1)],'rock',.48,88,19,rock_relief)
loft('Hewn seat-col',[(0,0,4.5,12.1,7.4),(2,0,4.65,12.5,7.6),
     (21,0,4.3,12.35,7.8),(26,0,4.15,12.8,8.1),(28.6,0,4.1,12.2,7.7)],
     'rock',.46,84,54,rock_relief)

for side,label in ((1,'L'),(-1,'R')):
    def mirrored(points):
        return [(side*x,y,z,rx,ry) for x,y,z,rx,ry in points]

    # Longitudinal foot sections retain a high instep, broad metatarsals and grounded heel.
    foot_specs=[(-15.86,7.18,1.03,2.91,.81),(-15.28,7.38,1.23,4.05,1.12),
                (-13.62,7.46,1.49,4.42,1.40),(-11.92,7.44,2.02,4.09,1.92),
                (-9.55,7.32,2.75,3.50,2.62),(-7.22,7.22,2.87,2.89,2.79),
                (-5.12,7.17,2.40,2.69,2.31),(-4.1,7.11,2.02,2.25,1.93),
                (-3.51,7.1,1.65,.4,1.30)]
    foot_curve=Profile(foot_specs)
    rings=[]
    for y in np.linspace(foot_specs[0][0],foot_specs[-1][0],39):
        xc,zc,rx,rz=foot_curve(y); ring=[]
        for j in range(64):
            a=tau*j/64
            x=side*xc+rx*sp(sin(a),.88)
            z=zc+rz*sp(cos(a),.83)
            ring.append((x,y,max(.025,z)))
        rings.append(ring)
    solid('Instep_'+label+'-col',rings,'foot')

    digits=[(BIG_TOE_X,-16.28,1.36,2.10,2.18),(6.64,-16.15,.93,1.82,1.93),
            (8.25,-15.92,.83,1.66,1.79),(9.71,-15.64,.74,1.48,1.60),
            (10.99,-15.12,.65,1.32,1.43)]
    for idx,(cx,cy,rx,ry,height) in enumerate(digits):
        suffix=f'{label}_{idx+1}'
        nx,ny=BIG_NAIL if idx==0 else (rx*.69,ry*.41)
        nyc=BIG_NAIL_Y if idx==0 else cy-.47
        top=BIG_NAIL_Z if idx==0 else height+.078
        def nail_surface(a, radius, drop):
            u=sp(sin(a),.71)*radius; v=-sp(cos(a),.76)*radius
            return (side*cx+nx*u*(1+.034*v), nyc+ny*v, top+drop-.020*u*u-.014*v*v)
        toe_profile=[(.012,.72),(.12,.88),(.28,.96),(.49,1.0),(.67,.98)]
        rings=[]
        for k,r in toe_profile:
            ring=[]
            for j in range(64):
                a=tau*j/64
                x=side*cx+rx*r*sp(sin(a),.72)*(1-.035*cos(a))
                y=cy-ry*r*sp(cos(a),.79)+.11*k
                ring.append((x,y,height*k))
            rings.append(ring)
        # The nail bed and cuticle follow the perimeter of the same nail, including the tip.
        base=rings[-1]
        for t in (.18,.40,.68,.87,1.):
            ring=[]
            for j,p in enumerate(base):
                a=tau*j/64
                edge=nail_surface(a,1.027,-.059)
                v=np.array(p)*(1-t)+np.array(edge)*t
                v[2]+=.17*sin(pi*t)*(.5-.5*cos(a))
                ring.append(tuple(v))
            rings.append(ring)
        for r in (.92,.45,.04):
            rings.append([nail_surface(tau*j/64,r,-.080) for j in range(64)])
        solid('Toe_'+suffix+'-col',rings,'foot')
        rings=[]
        for r,dz in ((.82,-.17),(1.,-.087),(.99,-.044),(.953,-.009),(.80,0),(.57,0),(.27,0),(.03,0)):
            rings.append([nail_surface(tau*j/64,r,dz) for j in range(64)])
        name='HalluxNail_'+label+'-col' if idx==0 else 'Toenail_'+suffix
        nail=solid(name,rings,'nail')
        if idx==0:
            nail['landing_radius_m']=.29
            nail['standing_centers_local_xy_m']=[v for dx in (-.42,.42) for dy in (-.39,.39)
                                                 for v in (side*cx+dx,nyc+dy)]

    def leg_folds(z,a):
        f=cos(a)
        fold=0
        for base,depth,drift in ((6.8,.26,.7),(9.3,.31,1.3),(16.9,.17,.9),
                                  (21.3,.29,1.15),(23.9,.31,.8),(27.7,.22,.65)):
            line=base+drift*(1-cos(a))+1.20*sin(a+.07*z)*side
            fold+=.64*depth*(gau(z-line,.47)-.52*gau(z-line-.52,.30))*(.36+.64*max(0,cos(a-side*.5)))
        return fold + .16*sin(4*a+.06*z)+.10*cos(7*a-.12*z)*max(f,0)
    shins=[(3.35,7.20,-7.55,2.38,2.36),(4.8,7.22,-7.75,2.91,2.82),
           (8.5,7.30,-7.80,3.42,3.22),(15,7.55,-7.55,3.64,3.27),
           (23,7.65,-7.77,3.75,3.45),(28.5,7.68,-8.1,4.08,3.89),
           (30.8,7.65,-8.0,3.98,3.79),(32.9,7.59,-7.4,3.32,3.28),
           (34,7.55,-7.05,1.95,2.16)]
    loft('Robed shin and knee_'+label+'-col',[(z,side*x,y,rx,ry) for z,x,y,rx,ry in shins],
         'robe',.85,72,94,leg_folds)
    volume_axis('Seated thigh_'+label+'-col',mirrored([
        (7.62,-9.30,30.10,3.1,2.5),(7.55,-7.45,30.25,4.04,3.36),
        (7.18,-3.8,29.96,4.16,3.68),(6.68,.9,29.1,4.45,4.28),
        (6.32,3.9,28.7,4.02,3.3)]),'robe',48,29)

    volume_axis('Sleeve_'+label+'-col',mirrored([
        (7.10,1.30,51.20,2.36,2.61),(8.86,1.0,50.40,2.91,3.24),
        (10.12,.40,48.08,2.94,3.12),(10.98,-.03,44.47,2.70,2.87),
        (11.22,-.56,42.25,2.63,2.74),(10.82,-2.0,39.67,2.52,2.7),
        (9.62,-4.84,36.55,2.46,2.59),(8.32,-7.15,34.02,2.26,2.48),
        (8.12,-7.58,33.51,2.07,2.32)]),'robe',52,44)
    volume_axis('Hand on knee_'+label,mirrored([
        (8.21,-7.31,34.05,1.71,1.65),(8.10,-8.88,33.55,2.02,1.34),
        (7.94,-10.44,32.71,2.42,1.18),(7.92,-11.21,31.82,2.57,1.07),
        (7.93,-11.66,31.06,2.29,.87)]),'hand',48,24)
    for j,(offset,length,radius) in enumerate([(-1.63,3.73,.68),(-.49,4.35,.70),(.70,4.02,.64),(1.77,3.08,.56)]):
        x=7.94+offset
        end=31.48-length
        volume_axis(f'Finger_{label}_{j+2}',mirrored([
            (x,-11.17,31.89,radius*.98,.84),(x+offset*.035,-11.95,30.89,radius,.84),
            (x+offset*.075,-12.31,29.28 if length>3.1 else 29.91,radius*.96,.75),
            (x+offset*.15,-12.28,end+.48,radius*.84,.60),
            (x+offset*.14,-12.15,end+.10,radius*.58,.43),(x+offset*.14,-12.11,end,.15,.10)]),'hand',26,16)
    volume_axis('Thumb at knee_'+label,mirrored([
        (6.34,-9.76,32.90,1.01,.91),(5.92,-10.26,32.27,.92,.84),
        (5.38,-10.82,31.38,.85,.74),(5.01,-10.91,30.39,.70,.62),
        (5.01,-10.84,30.11,.31,.35)]),'hand',28,20)

def apron_folds(z,a):
    front=max(0,cos(a))
    d=.28*cos(5*a+.3*sin(z*.2))+.11*sin(9*a-.12*z)
    for center,width in ((8.5,.36),(13.2,.43),(20.2,.41),(24.6,.30),(28.8,.42)):
        line=center+3.4*(1-front)+.75*sin(a*2+.11*z)
        d+=.38*gau(z-line,width)-.22*gau(z-line-.55,.36)
    return d*(.2+.8*front)

loft('Drapery between the legs-col',[(4.5,0,.8,4.9,3.8),(6.2,-.3,.25,5.6,4.35),
     (11,-.2,.1,5.6,4.35),(20,.2,-.25,5.6,4.8),(25.5,.1,-1.65,6.81,5.82),
     (29.2,0,-1.85,8.5,6.30),(31.7,0,-1.0,8.84,6.1),(33.,0,-.55,8.05,5.8)],
     'robe',.78,80,88,apron_folds)
chest_rows=[(26.5,0,1.30,7.9,5.7),(29,0,.7,9.10,6.10),(34,0,.40,9.42,6.10),
            (39.5,0,.48,9.45,5.92),(44,0,.64,10.05,6.0),(48,0,1.04,10.68,6.08),
            (50.8,0,1.28,10.50,5.53),(52.15,0,1.36,9.40,5.06),
            (53.6,0,1.16,5.7,4.48),(54.2,0,1.03,4.54,3.99)]
cp=Profile(chest_rows)
loft('Chest beneath collar',[(z,x,y,max(.1,rx-.13),max(.1,ry-.14)) for z,x,y,rx,ry in chest_rows],
     'body',.86,72,44)

def neckline(a):
    front=max(0,cos(a))
    return 53.50-8.80*front**3.1+.96*sin(a)*front+.36*cos(3*a)*front

def torso_point(z,a):
    x,y,rx,ry=cp(z)
    c,s=cos(a),sin(a)
    d=.16+.37*gau(z-(neckline(a)-.40),.32)-.11*gau(z-(neckline(a)-.97),.28)
    for height,dip,shift,deep in ((29.7,3.8,-.50,.36),(32.3,3.1,-.30,.29),(37.1,5.5,-.50,.34),
                                  (39.8,4.1,-.35,.38),(42.5,3.1,.12,.26)):
        line=height+dip*(1-cos(a+shift))+.55*sin(a*2+.3)
        d+=(deep*gau(z-line,.44)-deep*.53*gau(z-line-.62,.38))*(.25+.75*max(0,c))
    return (x+(rx+d)*sp(s,.86),y-(ry+d)*sp(c,.86),z)

rings=[]
for t in np.linspace(0,1,77):
    rings.append([torso_point(27.3+(neckline(a)-27.3)*t,a) for a in np.arange(104)*tau/104])
solid('Monastic robe and collar-col',rings,'robe')
loft('Neck',[(51.1,0,1.03,4.55,3.83),(52.1,0,.88,4.71,4.12),
      (53.5,0,.64,4.23,3.95),(55.0,0,.49,4.06,3.83),(56.9,0,.43,4.09,3.92),
      (58.0,0,.5,3.52,3.31)],'face',.84,84,46,
      lambda z,a:.18*gau(z-53.55-.27*(1-cos(a)),.22)+.13*gau(z-54.76-.23*(1-cos(a)),.24))

# The sculpt uses the existing sandstone palette throughout. Eyes and ears have carved interiors.
head_rows=[(55.5,.25,.52,1.1),(55.80,2.18,2.48,.77),(56.30,3.40,3.62,.52),
           (57.40,4.22,4.17,.50),(59.35,4.77,4.37,.46),(61.8,5.10,4.57,.49),
           (64.25,5.23,4.61,.54),(66.5,5.15,4.57,.58),(68.15,4.81,4.37,.62),
           (69.55,3.8,3.58,.64),(70.28,2.40,2.32,.66),(70.64,.15,.15,.67)]
hp=Profile(head_rows)
P=.85
EYE_Z=62.45

def brow(ax):
    t=max(0.,min(1.,(ax-.68)/3.26))
    return 63.58+.39*sin(pi*t)+.13*(1-t)

def mouth(x):
    return 58.64+.20*(x/1.64)**2+.028*cos(x*2.85)

# Bridge width and projection at each level, from the rounded columella up into the glabella.
nose_rows=[(59.30,.40,0),(59.44,.42,.28),(59.56,.51,.83),(59.70,.64,1.29),
           (59.87,.76,1.66),(60.12,.82,1.89),(60.37,.78,1.91),(60.69,.66,1.78),
           (61.16,.58,1.60),(61.72,.52,1.42),(62.35,.46,1.12),(63.15,.44,.69),
           (63.80,.57,.31),(64.45,.72,.09),(65.04,.82,0)]
nose_profile=Profile(nose_rows)

def face_relief(x,z,nose_section=None):
    ax=abs(x)
    d=.44*gau(ax-2.78,1.08)*gau(z-60.98,1.12)
    d+=.16*gau(ax-3.14,.84)*gau(z-61.41,.71)
    d-=.09*gau(ax-3.57,.80)*gau(z-59.62,1.10)
    d-=.42*gau(ax-2.05,1.38)*gau(z-62.61,.60)
    d+=.44*gau(ax-2.10,1.33)*gau(z-brow(ax),.44)
    width,projection=nose_section if nose_section is not None else nose_profile(z)
    dorsal=ax/width
    bridge=projection*(.78*exp(-.61*dorsal**3.0)+.22*gau(x,width*1.57))
    wing=1.37*gau(ax-.96,.345)*gau(z-60.02-.10*(ax-.96),.413)
    # A rounded union keeps each ala beside the tip, without adding their projections.
    fillet=.60*min(1.,2*min(bridge,wing))
    join=max(0.,fillet-abs(bridge-wing))
    d+=max(bridge,wing)+join*join/(4*max(fillet,1e-8))
    d+=.16*gau(ax-.91,.47)*gau(z-60.37,.70)
    nostril_z=59.54+.20*(ax-.76)
    d-=.29*gau(ax-.76,.166)*gau(z-nostril_z,.112)
    d+=.16*exp(-.65*(ax/1.12)**4)*gau(z-59.62,.33)
    d-=.095*gau(ax-1.32,.16)*gau(z-60.12,.34)
    d+=.075*gau(ax-.24,.14)*gau(z-59.22,.35)+.24*gau(x,.94)*gau(z-59.45,.40)
    d+=.29*gau(x,1.42)*gau(z-58.82,.73)
    mw=exp(-(x/1.73)**6); ml=mouth(x)
    d+=mw*(.22*gau(z-ml-.16,.18)+.32*gau(z-ml+.19,.19)-.15*gau(z-ml,.078))
    d+=.47*gau(x,1.78)*gau(z-57.10,.71)
    d-=.13*gau(ax-(1.15+.38*(60.05-z)),.23)*gau(z-59.25,.81)
    return d

def base_head(a,z,section=None,nose_section=None):
    rx,ry,cy=section if section is not None else hp(z)
    c=cos(a);x=rx*sp(sin(a),P);y=cy-ry*sp(c,P)
    if c>0 and z<67.3:
        y-=face_relief(x,z,nose_section)*min(1,max(0,(c-.07)/.57))
    return (x,y,z)

def face_y(x,z):
    rx,ry,cy=hp(z)
    s=min(.99999,(abs(x)/rx)**(1/P))
    c=sqrt(1-s*s)
    return cy-ry*c**P-face_relief(x,z)*min(1,max(0,(c-.07)/.57))

def carved_step(inner, outer, radius):
    """Rounded edge of an inset cut into the stone."""
    t = min(1., max(0., (outer-radius)/(outer-inner)))
    return t*t*(3-2*t)


def eye_projection(x, z, center):
    # The lid clips the upper part of the iris. The exposed segment has a bevel and a cupped pupil.
    dx, dz = x-center, z-EYE_Z
    sclera = .13 + .20*(1-(dx/1.59)**2) - .115*((dz+.19)/.74)**2 + .10*dz
    iris = sqrt(((dx+.045)/.68)**2 + ((dz-.10)/.72)**2)
    pupil = sqrt(((dx+.045)/.32)**2 + ((dz-.055)/.35)**2)
    inset = carved_step(.72, 1.12, iris) * (.24 + .17*exp(-.85*iris*iris))
    inset += .21*carved_step(.18, 1.16, pupil)
    return sclera - inset


def lid_projection(t, up, down):
    upper = .48*gau(t-.13, .23) + .095*gau(t-.35, .20) - .115*gau(t-.64, .12)
    lower = .162*gau(t-.13, .21) + .055*gau(t-.34, .19) - .036*gau(t-.61, .15)
    return up**.78*upper + down**.76*lower + .038*(1-t)**2


def add_eye(verts, faces, rim, sign, eye_weights):
    """Turn the skin into a lid, its undercut and the exposed eye in one continuous surface."""
    previous = [index for _, index in rim]
    center = 2.12

    def stitch(points, weight):
        nonlocal previous
        first = len(verts)
        verts.extend(points)
        ring = list(range(first, len(verts)))
        eye_weights.extend((i, weight) for i in ring if weight > 0.)
        for i, a in enumerate(previous):
            j = (i+1) % len(ring)
            face = (a, previous[j], ring[j], ring[i])
            faces.append(face if sign > 0 else face[::-1])
        previous = ring

    axes = []
    for theta, _ in rim:
        u, v = cos(theta), sin(theta)
        up, down = max(0.,v), max(0.,-v)
        mid = EYE_Z + .055*u + .075*u*u
        edge_z = mid + .17*up**1.65 - .63*down**1.56
        axes.append((center+1.74*u, mid+.88*up-.99*down, center+1.58*u, edge_z, up, down))

    for t in (1., .82, .67, .52, .38, .26, .16, .085, .034, 0.):
        points = []
        for bx, bz, ex, ez, up, down in axes:
            x, z = ex+(bx-ex)*t, ez+(bz-ez)*t
            points.append((sign*x, face_y(x,z)-lid_projection(t,up,down), z))
        stitch(points, carved_step(.34, 1., t))

    # Roll the lip back under the upper lid before following the carved globe towards its centre.
    inner = [(.994, -.033, .85), (.982, -.057, .46), (.965, -.031, .15), (.945, 0., 0.)]
    inner.extend((r, 0., 0.) for r in np.linspace(.92, .035, 34))
    for radius, overlap, lip_fraction in inner:
        points = []
        for _, _, ex, ez, up, down in axes:
            x = center + (ex-center)*radius
            z = EYE_Z + (ez-EYE_Z)*radius + (up-.30*down)*overlap
            depth = (1-lip_fraction)*eye_projection(x,z,center) + lip_fraction*lid_projection(0.,up,down)
            points.append((sign*x, face_y(x,z)-depth, z))
        stitch(points, 1.)
    apex = len(verts)
    verts.append((sign*center, face_y(center,EYE_Z)-eye_projection(center,EYE_Z,center), EYE_Z))
    eye_weights.append((apex, 1.))
    for i, a in enumerate(previous):
        tri = (a, previous[(i+1)%len(previous)], apex)
        faces.append(tri if sign > 0 else tri[::-1])


def shade_eye_recesses(head, eye_weights):
    # The web renderer supplies direct light. Bake local sky occlusion into the existing sandstone
    # grain so the iris cuts also read at island distance, after the mesh and shadows switch LOD.
    data = head.data
    tree = BVHTree.FromPolygons([v.co for v in data.vertices], [p.vertices[:] for p in data.polygons])
    colors = data.color_attributes['Stone'].data
    samples = []
    for i in range(64):
        r = sqrt((i+.5)/64)
        a = i*pi*(3-sqrt(5))
        samples.append((r*cos(a), r*sin(a), sqrt(1-r*r)))
    up = Vector((0,0,1))
    reach = 1.65
    for index, blend in eye_weights:
        v = data.vertices[index]
        normal = v.normal
        tangent = up.cross(normal)
        if tangent.length_squared < .0001:
            tangent = Vector((1,0,0)).cross(normal)
        tangent.normalize()
        bitangent = normal.cross(tangent)
        if v.co.x < 0:
            tangent.negate()
        origin = v.co + normal*.006
        blocked = total = 0.
        for tx, ty, nz in samples:
            ray = tangent*tx + bitangent*ty + normal*nz
            weight = .30 + max(0., ray.z)
            total += weight
            _, _, hit, distance = tree.ray_cast(origin, ray, reach)
            if hit is not None:
                blocked += weight*(1-(distance/reach)**2)
        light = max(.15, (1-min(1.,blocked/total))**1.85)
        red, green, blue, alpha = colors[index].color
        scale = 1. - blend*(1.-light)
        colors[index].color = (red*scale, green*scale, blue*scale, alpha)


def carved_head():
    # Leave two chart-aligned openings. The lid patches reuse the head's rim vertices exactly.
    zlo,zhi=61.42,63.45
    rx=hp(EYE_Z)[0]
    def angle_at(x):
        return np.arcsin((x/rx)**(1/P))
    a0,a1=angle_at(.33),angle_at(3.98)
    front_x=np.r_[np.linspace(0,1.48,28),np.linspace(1.55,4.85,38)]
    front=angle_at(front_x)
    angles=np.unique(np.round(np.r_[np.arange(-pi,pi,.061),front,-front,a0,a1,-a0,-a1],7))
    zvals=np.unique(np.round(np.r_[np.linspace(55.50,70.64,83),np.arange(57.82,64.41,.079),
                                   [z for z,_,_ in nose_rows],zlo,zhi],6))
    start=int(np.argmin(abs(zvals-zlo)));stop=int(np.argmin(abs(zvals-zhi)))
    holes=[]
    for sign in (1,-1):
        ends=sorted(int(np.argmin(abs(angles-v))) for v in (sign*a0,sign*a1))
        holes.append((*ends,sign))
    verts=[];faces=[];grid={}
    for k,z in enumerate(zvals):
        section=hp(z); nose=nose_profile(z)
        for j,a in enumerate(angles):
            if start<k<stop and any(left<j<right for left,right,_ in holes):
                continue
            grid[k,j]=len(verts)
            verts.append(base_head(a,z,section,nose))
    for k in range(len(zvals)-1):
        for j in range(len(angles)):
            if start<=k<stop and any(left<=j<right for left,right,_ in holes):
                continue
            nxt=(j+1)%len(angles)
            faces.append((grid[k,j],grid[k,nxt],grid[k+1,nxt],grid[k+1,j]))
    for end,reverse in ((0,True),(len(zvals)-1,False)):
        ring=[grid[end,j] for j in range(len(angles))]
        cap=len(verts)
        verts.append(tuple(np.mean([verts[i] for i in ring],axis=0)))
        for i in range(len(ring)):
            face=(cap,ring[i],ring[(i+1)%len(ring)])
            faces.append(face[::-1] if reverse else face)
    eye_weights=[]
    for left,right,sign in holes:
        rim=[]
        for k in range(start,stop+1):
            for j in (range(left,right+1) if k in (start,stop) else (left,right)):
                x=rx*abs(sin(angles[j]))**P
                u=(x-(.33+3.98)*.5)/((3.98-.33)*.5)
                v=(zvals[k]-(zhi+zlo)*.5)/((zhi-zlo)*.5)
                rim.append((atan2(v,u),grid[k,j]))
        add_eye(verts,faces,sorted(rim),sign,eye_weights)
    head=mesh('Face • carved Maitreya',verts,faces,'face')
    shade_eye_recesses(head,eye_weights)

carved_head()

def carved_accent(name,path,width,rise,kind):
    verts=[];faces=[]
    for i,(x,z) in enumerate(path):
        t=i/(len(path)-1);h=width(t)
        for j,v in enumerate((-1.,-.82,-.44,0.,.46,.84,1.)):
            level=z+v*h
            bevel=max(0.,1-v*v)**.8*rise*(sin(pi*t)**.55)
            verts.append((x,face_y(x,level)-.010-bevel,level))
            if i and j:
                p=len(verts)-1;faces.append((p-8,p-1,p,p-7))
    if path[-1][0]<path[0][0]:faces=[face[::-1] for face in faces]
    return mesh(name,verts,faces,kind)

for sign,side in ((1,'L'),(-1,'R')):
    carved_accent('Carved brow '+side,[(sign*x,brow(x)) for x in np.linspace(.67,3.97,59)],
                  lambda t:.012+.204*sin(pi*t)**.66*(1.30-.58*t),.115,'brow')
carved_accent('Quiet mouth',[(x,mouth(x)) for x in np.linspace(-1.75,1.75,65)],
              lambda t:.005+.032*sin(pi*t)**.70,.016,'crease')

def smooth_outline(points,per_segment=4):
    p=np.asarray(points);result=[]
    for j in range(len(p)):
        a,b,c,d=(p[(j+i)%len(p)] for i in (-1,0,1,2))
        for t in np.arange(per_segment)/per_segment:
            result.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t**3))
    return np.array(result)

def ear_shell(sign,side):
    # U measures distance towards the back of the head. Z is height above the soles.
    outline=smooth_outline([(.06,65.32),(.68,65.18),(1.14,64.75),(1.37,64.04),
        (1.36,63.26),(1.13,62.41),(.83,61.58),(.57,60.70),(.43,59.77),
        (.39,58.81),(.27,58.19),(-.03,57.92),(-.39,57.99),(-.59,58.36),
        (-.62,59.20),(-.60,60.13),(-.70,60.85),(-.99,61.47),(-1.20,62.20),
        (-1.27,63.05),(-1.19,63.90),(-.94,64.62),(-.52,65.12)])
    origin=np.array((-.04,62.48))
    def distance_to_path(points,path):
        a=path[:-1];ab=np.diff(path,axis=0)
        delta=points[:,None,:]-a
        f=np.clip((delta*ab).sum(2)/(ab*ab).sum(1),0,1)
        return np.sqrt(((delta-f[:,:,None]*ab)**2).sum(2).min(1))
    folds=[
        ([(.01,61.30),(.20,61.61),(.43,62.10),(.53,62.62),(.44,63.10),(.23,63.61),(.15,64.06)],.16,.34),
        ([(.46,62.89),(.23,63.12),(0.,63.23),(-.31,63.20),(-.51,63.08)],.15,.27),
        ([(-.86,62.24),(-.69,62.25),(-.48,62.08),(-.48,61.86)],.19,.39),
        ([(.14,61.60),(-.02,61.43),(-.25,61.39)],.15,.17),
        ([(-.35,60.92),(-.31,60.42),(-.28,59.83),(-.24,59.37)],.12,-.085)]
    def world(points,depth):
        u,z=points.T
        cx=5.09+.145*(z-62.4);cy=.08+.075*(z-62.4)
        return np.column_stack((sign*(cx+.49*u+.872*depth),cy+.872*u-.49*depth,z))
    def ring(t,front):
        points=origin+(outline-origin)*t
        u,z=points.T
        if front:
            edge=distance_to_path(points,np.vstack((outline,outline[0])))
            upper=np.clip((z-60.45)/1.48,0,1);upper=upper*upper*(3-2*upper)
            # A rolled helix turns down into the scapha, enclosing the forked antihelix.
            dep=.40+.12*(1-t*t)
            dep+=(.24+.38*upper)*np.exp(-.5*((edge-.225)/.175)**2)
            dep-=.16*upper*np.exp(-.5*((edge-.53)/.16)**2)
            dep-=.41*np.exp(-.5*((u+.06)/.58)**2-.5*((z-62.95)/1.01)**2)
            dep-=.22*np.exp(-.5*((u+.22)/.30)**2-.5*((z-62.02)/.36)**2)
            for path,w,h in folds:
                d=distance_to_path(points,np.asarray(path))
                dep+=h*np.exp(-.5*(d/w)**2)
            dep+=.16*np.exp(-.5*((z-59.15)/.78)**2-.5*(u/.44)**2)
        else:
            dep=-.12-.78*(1-t*t)
        pts=world(points,dep)
        return pts[::-1] if sign>0 else pts
    rings=[ring(t,False) for t in (.025,.32,.62,.82,.93,.98)]
    # Round the silhouette and keep the front cartilage continuous with the back.
    rings.append(world(outline,.11)[::-1] if sign>0 else world(outline,.11))
    rings.extend(ring(t,True) for t in np.linspace(.992,.014,58))
    solid('Long earlobe '+side,rings,'face')

for sign,side in ((1,'L'),(-1,'R')):
    ear_shell(sign,side)

def hair_edge(a):
    temple=abs(atan2(sin(a),cos(a)))
    temple_lock=2.60*gau(temple-1.25,.208)
    return 64.82+1.83*cos(a)+.13*cos(2*a)-temple_lock+.70*gau(temple-1.69,.24)

def hair_point(a,t):
    # Follow the same cranium as the forehead. The front hairline rises over the brow.
    z=hair_edge(a)+(70.64-hair_edge(a))*sin(t*pi*.5)
    x,y,z=base_head(a,z)
    return np.array((x+.065*sin(a),y-.065*cos(a),z+.045))

angles=np.arange(94)*tau/94
solid('Hairline and crown',[[tuple(hair_point(a,t)) for a in angles] for t in np.linspace(.0,.999,41)],'hair')
# Staggered rows run horizontally across the scalp and continue down the temples.
# Spacing is measured along the surface so that the whorls stay round on the crown.
def scalp(a,z):
    x,y,z=base_head(a,z)
    return np.array((x+.065*sin(a),y-.065*cos(a),z+.045))

hair_v=[];hair_f=[]
def whorl(center,tangent,up,normal,width,height,phase):
    start=len(hair_v);segments=14
    for r in (1.,.91,.78,.65,.53,.41,.30,.19,.075):
        for j in range(segments):
            a=tau*j/segments
            spiral=(.5+.5*cos(a-10.8*r+phase))**2
            relief=-.016+.202*sqrt(max(0.,1-r*r))+.052*spiral*sin(pi*r)**.62
            hair_v.append(tuple(center+tangent*width*r*cos(a)+up*height*r*sin(a)+normal*relief))
    for row in range(8):
        for j in range(segments):
            i=start+segments*row;j2=(j+1)%segments
            hair_f.append((i+j,i+j2,i+segments+j2,i+segments+j))
    hair_f.append(tuple(start+8*segments+j for j in range(segments)))

heights=np.linspace(62.1,70.631,360)
meridian=np.array([scalp(pi/2,z) for z in heights])
arcs=np.r_[0,np.cumsum(np.linalg.norm(np.diff(meridian,axis=0),axis=1))]
for row,dist in enumerate(np.arange(.23,arcs[-1]-.16,.477)):
    z=np.interp(dist,arcs,heights)
    sample_angles=np.linspace(0,tau,225)
    samples=np.array([scalp(a,z) for a in sample_angles])
    distances=np.r_[0,np.cumsum(np.linalg.norm(np.diff(samples,axis=0),axis=1))]
    count=max(5,round(distances[-1]/.573))
    for k in range(count):
        a=np.interp((k+.50*(row%2))*distances[-1]/count,distances,sample_angles)
        center=scalp(a,z)
        span=(scalp(a+.004,z)-scalp(a-.004,z))/.008
        along=np.linalg.norm(span);tangent=span/along
        rise=scalp(a,z+.004)-scalp(a,z-.004)
        normal=np.cross(tangent,rise);normal/=np.linalg.norm(normal)
        up=np.cross(normal,tangent)
        slope=(hair_edge(a+.004)-hair_edge(a-.004))/(.008*along)
        clearance=(z-hair_edge(a))/sqrt(1+slope*slope)
        if clearance < .055:
            continue
        edge_scale=.68+.32*min(1.,clearance/.28)
        wobble=1+.025*sin(7*a+row)
        whorl(center,tangent,up,normal,distances[-1]/count*.52*edge_scale*wobble,
              .257*edge_scale/wobble,.15*sin(3*a+row*.44))
whorl(np.array((0,.67,70.685)),np.array((1,0,0)),np.array((0,1,0)),
      np.array((0,0,1)),.29,.29,.12)
# The metre datum is shared with the existing cliff and the toe-scale reference.
crest_adjust=70.94-max(p[2] for p in hair_v)
hair_v=[(x,y,z+crest_adjust*max(0.,min(1.,(z-70.0)/.80))) for x,y,z in hair_v]
mesh('Rows of spiral hair bosses',hair_v,hair_f,'hair')

# The source keeps different anatomical parts editable. Only the sculpture is in the GLB.
root=bpy.data.objects.new('Leshan Giant Buddha',None)
surface_collection.objects.link(root)
root['units']='metres'
root['scale_reference']='Four standing player footprints on one great toenail'
root['front']='Blender -Y / glTF +Z'
root['reference']='Original sculpt from Leshan Giant Buddha photographs; no survey mesh.'
for o in objects:
    o.parent=root

def studio():
    world=bpy.data.worlds.new('Overcast daylight')
    scene.world=world; world.use_nodes=True
    world.node_tree.nodes.get('Background').inputs[0].default_value=(.42,.51,.62,1)
    world.node_tree.nodes.get('Background').inputs[1].default_value=.48
    data=bpy.data.lights.new('Soft daylight','SUN');data.energy=2.25;data.angle=.16
    light=bpy.data.objects.new('Soft daylight',data);scene.collection.objects.link(light)
    light.rotation_euler=Vector((- .57,.77,-.86)).to_track_quat('-Z','Y').to_euler()
    data=bpy.data.cameras.new('Sculpture camera')
    cam=bpy.data.objects.new('Sculpture camera',data);scene.collection.objects.link(cam)
    cam.location=(24,-114,42);aim=Vector((0,-1.1,34.5))
    cam.rotation_euler=(aim-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO';cam.data.ortho_scale=86;cam.data.clip_end=450
    scene.camera=cam
    scene.render.engine='CYCLES';scene.cycles.samples=12;scene.cycles.use_denoising=True
    scene.render.resolution_x=760;scene.render.resolution_y=900;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX'
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active;space.clip_end=1100;space.shading.color_type='VERTEX'
                space.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
                space.region_3d.view_distance=118;space.region_3d.view_location=aim
    return cam

studio()
bpy.ops.object.select_all(action='DESELECT')
for o in [root,*objects]:o.select_set(True)
bpy.context.view_layer.objects.active=root
scene.render.image_settings.file_format='PNG'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(NAME+'.blend')),compress=True)
if '--sculpt-only' not in sys.argv:
    runpy.run_path(str(OUT/'package_glb.py'), run_name='__main__')
