"""Build the seated Leshan landmark in metres. Blender Z is up, the Buddha faces -Y."""
from bisect import bisect_right
from math import atan2, cos, exp, pi, sin, sqrt, tau
from pathlib import Path
import tempfile
import runpy

import bpy
import numpy as np
from mathutils import Vector

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


def tube(name, path, kind, width, depth=None, segments=10, axis=(0,-1,0)):
    """A carved lip or ridge sampled along a surface; endpoints taper into the stone."""
    rings=[]
    for i,p in enumerate(path):
        tangent=(Vector(path[min(i+1,len(path)-1)])-Vector(path[max(0,i-1)])).normalized()
        n=Vector(axis)
        n=(n-tangent*n.dot(tangent)).normalized()
        b=tangent.cross(n).normalized()
        f=.07+.93*max(0.,sin(pi*i/(len(path)-1)))**.52
        ring=[tuple(Vector(p)+n*((depth or width)*f*cos(tau*j/segments))
                    +b*(width*f*sin(tau*j/segments))) for j in range(segments)]
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

# The face is a continuous sculpted surface. Eyebrows and the incised mouth line follow it.
head_rows=[(55.5,.25,.52,1.1),(55.80,2.05,2.32,.81),(56.30,3.25,3.44,.56),
           (57.40,4.11,4.12,.52),(59.35,4.67,4.35,.46),(61.8,5.05,4.56,.49),
           (64.25,5.21,4.57,.54),(66.5,5.15,4.57,.58),(68.15,4.81,4.37,.62),
           (69.55,3.8,3.58,.64),(70.28,2.40,2.32,.66),(70.64,.15,.15,.67)]
hp=Profile(head_rows)
P=.85

def eyelid(ax):
    w=(ax-2.00)/1.44
    return 62.42+.085*w+.10*w*w

def brow(ax):
    t=(ax-.72)/3.05
    return 63.52+.37*sin(pi*max(0,min(1,t)))+.20*(1-t)

def mouth(x):
    return 59.03+.18*(x/1.57)**2+.038*cos(x*3.05)

def face_relief(x,z):
    ax=abs(x)
    d=.47*gau(ax-2.64,1.20)*gau(z-61.06,1.09)
    d-=.40*gau(ax-2.02,1.47)*gau(z-62.62,.68)
    d+=.55*gau(ax-2.04,1.25)*gau(z-brow(ax),.44)
    w=exp(-((ax-2.00)/1.45)**6)
    line=eyelid(ax)
    d+=w*(.24*gau(z-line-.22,.20)+.105*gau(z-line+.30,.25)-.10*gau(z-line,.09))
    d+=1.29*gau(x,.57)*gau(z-62.05,1.47)+.32*gau(x,.86)*gau(z-63.20,1.15)
    d+=1.73*gau(x,.66)*gau(z-60.62,.60)
    d+=.96*gau(ax-.75,.34)*gau(z-60.40,.39)
    d-=.46*gau(ax-.59,.20)*gau(z-60.18,.15)
    d+=.19*gau(ax-.22,.12)*gau(z-59.76,.28)
    d+=.34*gau(x,1.25)*gau(z-59.12,.77)
    mw=exp(-(x/1.62)**6); ml=mouth(x)
    d+=mw*(.35*gau(z-ml-.20,.17)+.39*gau(z-ml+.19,.20)-.16*gau(z-ml,.09))
    d+=.56*gau(x,1.66)*gau(z-57.32,.70)
    d-=.13*gau(ax-(1.26+.36*(60.4-z)),.22)*gau(z-59.74,.90)
    return d

def base_head(a,z):
    rx,ry,cy=hp(z); c=cos(a)
    x=rx*sp(sin(a),P);y=cy-ry*sp(c,P)
    if c>0 and z<67.3:
        y-=face_relief(x,z)*min(1,max(0,(c-.07)/.57))
    return (x,y,z)

def face_y(x,z):
    rx,ry,cy=hp(z)
    s=min(.99999,(abs(x)/rx)**(1/P))
    c=sqrt(1-s*s)
    return cy-ry*c**P-face_relief(x,z)*min(1,max(0,(c-.07)/.57))

zvalues=np.unique(np.r_[np.linspace(55.5,70.64,72),np.linspace(57.9,64.55,95)])
angles=np.arange(178)*tau/178
solid('Face • carved Maitreya',[[base_head(a,z) for a in angles] for z in zvalues],'face')

def pigment_ribbon(name,path,width,kind):
    verts=[]; faces=[]
    for i,(x,z) in enumerate(path):
        t=i/(len(path)-1); h=width(t)
        for dy in (-h,0,h):
            v=z+dy
            verts.append((x,face_y(x,v)-(.025 if dy else .044),v))
        if i:
            k=3*i
            faces.extend([(k-3,k,k+1,k-2),(k-2,k+1,k+2,k-1)])
    # Orient toward camera (-Y) for either traversal direction.
    if path[-1][0]<path[0][0]: faces=[f[::-1] for f in faces]
    return mesh(name,verts,faces,kind)

for sign,side in ((1,'L'),(-1,'R')):
    xp=np.linspace(.66,3.77,63)
    pigment_ribbon('Carved brow '+side,[(sign*x,brow(x)) for x in xp],
                   lambda t:.018+.205*sin(pi*t)**.6*(1.22-.54*t),'brow')
    xp=np.linspace(.64,3.43,57)
    pigment_ribbon('Lowered eye '+side,[(sign*x,eyelid(x)) for x in xp],
                   lambda t:.009+.073*sin(pi*t)**.72,'crease')
    path=[]
    for i in range(27):
        t=i/26
        x=sign*(.40+.42*t);z=60.20+.077*sin(pi*t)
        path.append((x,face_y(x,z)-.035,z))
    tube('Nostril carving '+side,path,'crease',.055,.035,8)

pigment_ribbon('Quiet mouth',[(x,mouth(x)) for x in np.linspace(-1.65,1.65,75)],
               lambda t:.008+.042*sin(pi*t)**.7,'crease')

# Each earlobe has a deep concha and a rolled outer helix, integral to its shell.
for sign,side in ((1,'L'),(-1,'R')):
    prof=Profile([(58.18,.18,.29),(58.58,.52,.49),(59.45,.65,.58),(61.15,.78,.69),
                  (63.30,1.13,.85),(64.78,1.28,.87),(65.40,.84,.63),(65.70,.22,.23)])
    ec=np.array([sign*5.06,-.08,0]); lateral=np.array([sign*.72,.69,0])
    outward=np.array([sign*.69,-.72,0])
    ear=[]
    for z in np.linspace(58.18,65.70,55):
        rx,dep=prof(z); line=[]
        for a in np.arange(56)*tau/56:
            u=cos(a); v=sin(a)
            along=rx*u+.13*(z-61.7)
            lift=dep*v
            if v>0:
                lift+=.34*gau(abs(u)-.77,.15)*gau(z-63,2.4)
                lift-=.52*gau(u+.15,.43)*gau(z-63.18,1.00)
                lift+=.20*gau(u-.12,.15)*gau(z-62.65,1.32)
            pos=ec+lateral*along+outward*lift
            line.append((pos[0],pos[1],z))
        ear.append(line if sign<0 else line[::-1])
    solid('Long earlobe '+side,ear,'face')

def hair_edge(a):
    return 64.75+1.85*cos(a)+.32*cos(2*a)-.27*gau(abs(sin(a))-.77,.10)*max(0,cos(a))

def hair_point(a,t):
    # Follow the same cranium as the forehead. The front hairline rises over the brow.
    z=hair_edge(a)+(70.64-hair_edge(a))*sin(t*pi*.5)
    x,y,z=base_head(a,z)
    return np.array((x+.065*sin(a),y-.065*cos(a),z+.045))

angles=np.arange(94)*tau/94
solid('Hairline and crown',[[tuple(hair_point(a,t)) for a in angles] for t in np.linspace(.0,.999,41)],'hair')
# Many small domed scrolls follow the scalp normal; relief continues over the back of the head.
hair_v=[];hair_f=[]
for row,t in enumerate(np.linspace(.015,.958,15)):
    sample=np.array([hair_point(a,t) for a in np.arange(150)*tau/150])
    length=np.linalg.norm(sample-np.roll(sample,1,axis=0),axis=1).sum()
    count=max(5,round(length/.63))
    for k in range(count):
        a=(k+.5*(row%2))*tau/count
        c=hair_point(a,t)
        lateral=hair_point(a+.005,t)-hair_point(a-.005,t)
        lateral/=np.linalg.norm(lateral)
        up=hair_point(a,min(.999,t+.004))-hair_point(a,max(0,t-.004))
        n=np.cross(lateral,up);n/=np.linalg.norm(n)
        up=np.cross(n,lateral)
        w=length/count*.53
        h=max(.17,min(.36,np.linalg.norm(hair_point(a,min(1,t+.035))-hair_point(a,max(0,t-.035)))*.56))
        rings=[]
        for r in (1.,.84,.62,.39,.18,.035):
            ring=[]
            for j in range(11):
                phase=j*tau/11
                spiral=.025*cos(phase-8.5*r+.25*(row%2))*(1-r*.5)
                bulge=.015+.225*sqrt(max(0,1-r*r))+spiral
                ring.append(tuple(c+lateral*w*r*cos(phase)+up*h*r*sin(phase)+n*bulge))
            rings.append(ring)
        idx=len(hair_v)
        # The underside is buried in the cap.
        hair_v.extend(p for ring in rings for p in ring)
        for b in range(len(rings)-1):
            for j in range(11):
                q=idx+b*11;j2=(j+1)%11
                hair_f.append((q+j,q+j2,q+11+j2,q+11+j))
        hair_f.append(tuple(idx+55+j for j in range(11)))
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
runpy.run_path(str(OUT/'package_glb.py'), run_name='__main__')
