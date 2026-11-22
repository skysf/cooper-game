"""Build the metric Rainline cabin kit in an isolated Blender MCP session."""
from __future__ import annotations

from math import atan, cos, pi, sin
from pathlib import Path
import json
import random


PROJECT = Path(__file__).resolve().parents[1]
RUNTIME = PROJECT / "coop/props/construction"
EVIDENCE = PROJECT / "evidence/cabin-kit-20261120"
FLOOR_TOP = 0.18
WALL_TOP = 2.30
INNER_HALF = 1.20
WALL_HALF = 0.12
WALL_AXIS = INNER_HALF + WALL_HALF
CORNER_END = WALL_AXIS + WALL_HALF
DOOR_HALF = 0.52
DOOR_TOP = 2.05
COURSES = [i * (DOOR_TOP / 10) for i in range(11)] + [WALL_TOP]
RIDGE = 1.10
PITCH = atan(0.58)
EAVE = 1.72
ROOF_HALF = 1.61
BEARING_WIDTH = 0.18
BEARING_HEIGHT = 0.28

TOP_FACE = 1 << 3
ALL_FACES = (1 << 6) - 1


def box(lo, hi, faces=TOP_FACE, offset=None, rotation=None):
    result = {"position": list(lo), "size": [b-a for a, b in zip(lo, hi)], "faces": faces}
    if offset is not None:
        result["offset"] = list(offset)
    if rotation is not None:
        result["rotation"] = list(rotation)
    return result


def corners(xs, zs, y=0.0):
    return [[x, y, z] for x in xs for z in zs]


def roof_point(x, y, d, side):
    return (x, RIDGE + cos(PITCH)*y - sin(PITCH)*d,
            side*(cos(PITCH)*d + sin(PITCH)*y))


def wall_volume(kinds, door=False):
    low = -WALL_HALF
    high = WALL_HALF
    if door:
        kinds.extend([
            box((-INNER_HALF, 0.0, low), (-DOOR_HALF, WALL_TOP, high), ALL_FACES),
            box((DOOR_HALF, 0.0, low), (INNER_HALF, WALL_TOP, high), ALL_FACES),
            box((-DOOR_HALF, DOOR_TOP, low), (DOOR_HALF, WALL_TOP, high), ALL_FACES),
        ])
    else:
        kinds.append(box((-INNER_HALF, 0.0, low), (INNER_HALF, WALL_TOP, high), ALL_FACES))
    # The alternating ends are interleaved when each wall faces outward.
    for row, (a, b) in enumerate(zip(COURSES, COURSES[1:])):
        x0, x1 = (INNER_HALF, CORNER_END) if row % 2 == 0 else (-CORNER_END, -INNER_HALF)
        kinds.append(box((x0, a, low), (x1, b, high), ALL_FACES))


def metadata():
    floor = [box((-1.5, 0.101, -1.5), (1.5, FLOOR_TOP, 1.5), ALL_FACES)]
    for x, _, z in corners([-1.12, 1.12], [-1.12, 1.12]):
        floor.append(box((x-.214, 0.0, z-.225), (x+.214, 0.115, z+.225), 0))
    wall, doorway = [], []
    wall_volume(wall)
    wall_volume(doorway, True)
    roof = []
    distance = EAVE / cos(PITCH)
    for side in (-1, 1):
        z = side * WALL_AXIS
        roof.append(box((-1.44, 0.0, z-BEARING_WIDTH/2), (1.44, BEARING_HEIGHT, z+BEARING_WIDTH/2), ALL_FACES))
        roof.append(box(
            (-ROOF_HALF, -0.083, -distance/2), (ROOF_HALF, 0.066, distance/2),
            TOP_FACE, roof_point(0, 0.0, distance/2, side), (PITCH*side, 0.0, 0.0),
        ))
        # Horizontal boxes fill the stepped gable. The sloping halves remain
        # individual oriented boxes so the interior below is physically empty.
        for i in range(6):
            bottom, top = i*0.15, (i+1)*0.15
            reach = min(1.32, (RIDGE-top) / 0.58)
            x = side * WALL_AXIS
            roof.append(box((x-.045, bottom, -reach), (x+.045, top, reach), 0))
    items = {}
    for ident, bounds, shapes, feet, mass in [
        ("cabin_floor", (-1.5, 0, -1.5, 1.5, FLOOR_TOP, 1.5), floor,
         corners([-1.12, 1.12], [-1.12, 1.12]), [0.0, 0.08, 0.0]),
        ("cabin_wall", (-CORNER_END, 0, -WALL_HALF, CORNER_END, WALL_TOP, WALL_HALF), wall,
         corners([-1.08, 1.08], [-0.094, 0.094]), [0.0, 1.10, 0.0]),
        ("cabin_doorway", (-CORNER_END, 0, -WALL_HALF, CORNER_END, WALL_TOP, WALL_HALF), doorway,
         corners([-1.04, 1.04], [-0.094, 0.094]), [0.0, 1.04, 0.0]),
        ("cabin_roof", (-ROOF_HALF, 0, -EAVE-.05, ROOF_HALF, RIDGE+.14, EAVE+.05), roof,
         corners([-1.08, 1.08], [-WALL_AXIS, WALL_AXIS]), [0.0, 0.40, 0.0]),
    ]:
        items[ident] = {"model": "res://props/construction/" + ident + ".glb",
                        "bounds": {k: v for k, v in box(bounds[:3], bounds[3:]).items() if k != "faces"},
                        "colliders": shapes, "feet": feet, "center_of_mass": mass}
    items["cabin_roof"]["anchor"] = [0.0, 0.0, round(WALL_AXIS, 4)]
    return {
        "version": 1, "units": "m", "axes": "Godot XYZ, +Y up, wall exterior +Z",
        "pieces": items,
        "assembly": {
            "floorTop": FLOOR_TOP, "wallHeight": WALL_TOP, "wallClearSpan": 2*INNER_HALF,
            "wallCenterDistance": 2*WALL_AXIS, "doorClear": [2*DOOR_HALF, DOOR_TOP],
            "roofPitch": PITCH, "roofAt": [0.0, FLOOR_TOP+WALL_TOP, 0.0],
            "walls": [
                {"kind":"cabin_doorway","at":[0, FLOOR_TOP, WALL_AXIS],"yaw":0},
                {"kind":"cabin_wall","at":[WALL_AXIS, FLOOR_TOP, 0],"yaw":pi/2},
                {"kind":"cabin_wall","at":[0, FLOOR_TOP, -WALL_AXIS],"yaw":pi},
                {"kind":"cabin_wall","at":[-WALL_AXIS, FLOOR_TOP, 0],"yaw":-pi/2},
            ],
        },
    }


def save_json(path, data):
    def rounded(value):
        if isinstance(value, float):
            return round(value, 6)
        if isinstance(value, dict):
            return {k: rounded(v) for k, v in value.items()}
        if isinstance(value, list):
            return [rounded(x) for x in value]
        return value
    path.write_text(json.dumps(rounded(data), ensure_ascii=False, indent=2) + "\n")


def to_blender(v):
    return v[0], -v[2], v[1]


def studio_texture(name, size, palette, roughness, texture, seed, scratch):
    import bpy
    import numpy as np

    rng = np.random.default_rng(seed)
    u, v = np.meshgrid(np.arange(size, dtype=np.float32)/size, np.arange(size, dtype=np.float32)/size)

    def noise(nx, ny, uu=u, vv=v):
        grid = rng.uniform(-1.0, 1.0, (ny,nx)).astype(np.float32)
        xx, yy = np.mod(uu, 1)*nx, np.mod(vv, 1)*ny
        x, y = xx.astype(int), yy.astype(int)
        a, b = xx-x, yy-y
        a, b = a*a*(3-2*a), b*b*(3-2*b)
        return ((1-b)*((1-a)*grid[y,x]+a*grid[y,(x+1)%nx])
                + b*((1-a)*grid[(y+1)%ny,x]+a*grid[(y+1)%ny,(x+1)%nx]))

    mottling = noise(7, 11)
    if texture == "wood":
        warped = v + .022*noise(4, 7) + .004*noise(15, 26)
        holes = np.zeros_like(v)
        for x, y, spread in [(0.23, 0.29, .066),(.72,.67,.085),(.51,.90,.041)]:
            du, dv = (u-x+.5)%1-.5, (v-y+.5)%1-.5
            r = np.hypot(du*.55,dv*1.9)
            pull = np.exp(-((r/spread)**2))
            warped += .030*np.sign(dv)*pull
            holes += .35*pull + .28*np.exp(-((r/(spread*.25))**2))
        coarse = noise(5, 60, u, warped)
        fiber = noise(19, 280, u, warped)
        bands = np.sin((warped*41 + .32*coarse)*2*pi)
        furrows = np.maximum(0.0, bands)**6
        tone = .070*mottling + .047*coarse + .030*fiber - .035*furrows - .135*holes
        height = .17*coarse + .13*fiber - .06*furrows - .29*holes
    elif texture == "end":
        radius = np.hypot((u-.43)*1.02,v-.52+.022*noise(7,7))
        rings = np.sin((radius*28+.23*mottling)*2*pi)
        theta = np.arctan2(v-.52, u-.43)
        splits = np.maximum(0, np.cos(8*theta-0.35+2*mottling))**19 * np.minimum(1,radius*1.7)
        grain = noise(95,95)
        tone = .05*mottling + .032*rings + .02*grain - .078*splits
        height = .10*rings + .07*grain - .28*splits
    else:
        coarse = noise(26,24)
        fine = noise(168,174)
        veins = np.exp(-np.abs(noise(13,16)+.13*fine)*9)
        tone = .074*mottling + .041*coarse + .032*fine - .034*veins
        height = .25*coarse + .08*fine - .13*veins

    d_v, d_u = np.gradient(height)
    normal = np.stack((-d_u*4.3, -d_v*4.3, np.ones_like(height)), axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    color = np.clip(np.asarray(palette, dtype=np.float32) + tone[:,:,None], 0.02, 0.92)
    color = np.where(color <= .04045, color/12.92, ((color+.055)/1.055)**2.4)

    def make_image(suffix, pixels, data):
        image_name = name + "_" + suffix
        img = bpy.data.images.new(image_name, width=size, height=size, alpha=False)
        img.colorspace_settings.name = "Non-Color" if data else "sRGB"
        rgba = np.ones((size,size,4), dtype=np.float32)
        rgba[:,:,:3] = pixels
        img.pixels.foreach_set(rgba.ravel())
        extension = ".png" if data else ".jpg"
        img.filepath_raw = str(scratch / (image_name + extension))
        img.file_format = "PNG" if data else "JPEG"
        img.save()
        img.pack()
        img.filepath = "//cabin-textures/" + image_name + extension
        return img

    shade = bpy.data.materials.new(name)
    shade.diffuse_color = (*palette,1.0)
    shade.use_nodes = True
    nodes = shade.node_tree.nodes
    links = shade.node_tree.links
    principled = nodes.get("Principled BSDF")
    base = nodes.new("ShaderNodeTexImage")
    base.image = make_image("diff", color, False)
    base.location = (-620,160)
    norm_tex = nodes.new("ShaderNodeTexImage")
    norm_tex.image = make_image("nor_gl", normal*.5+.5, True)
    norm_tex.location = (-620,-125)
    bump = nodes.new("ShaderNodeNormalMap")
    bump.inputs["Strength"].default_value = 0.74
    bump.location = (-315,-125)
    links.new(base.outputs["Color"],principled.inputs["Base Color"])
    links.new(norm_tex.outputs["Color"],bump.inputs["Color"])
    links.new(bump.outputs["Normal"],principled.inputs["Normal"])
    rough = nodes.new("ShaderNodeTexImage")
    values = np.clip(roughness + .085*mottling + .13*tone, 0, 1)
    rough.image = make_image("rough", np.repeat(values[:,:,None],3,axis=2), True)
    rough.location = (-620,-390)
    links.new(rough.outputs["Color"],principled.inputs["Roughness"])
    return shade


def object_mesh(collection, name, vertices, faces, mats, uv, mat_indices, mirror=False, smooth=False):
    import bpy

    mesh = bpy.data.meshes.new(name)
    if mirror:
        faces = [tuple(reversed(f)) for f in faces]
    mesh.from_pydata([to_blender(v) for v in vertices], [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name,mesh)
    collection.objects.link(obj)
    for material in mats:
        mesh.materials.append(material)
    layer = mesh.uv_layers.new(name="Material UV")
    for poly in mesh.polygons:
        poly.use_smooth = smooth
        poly.material_index = mat_indices[poly.index]
        for loop in poly.loop_indices:
            i = mesh.loops[loop].vertex_index
            layer.data[loop].uv = uv(i, poly)
    return obj


def timber(collection, name, start, end, face, head, seed, bevel=.007, transform=None,
           mirror=False, rough=.002, taper=0.0, stations=5):
    """A lengthwise chamfered timber with real bevel and slightly hewn edges."""
    rng = random.Random(seed)
    x0,y0,z0 = start
    x1,y1,z1 = end
    bevel = min(bevel, (x1-x0)*.18, (y1-y0)*.27, (z1-z0)*.27)
    uv_offset = (rng.random(),rng.random())
    parts = [0.0,bevel/(x1-x0)] + [i/stations for i in range(1,stations)] + [1-bevel/(x1-x0),1.]
    raw = []
    for index, t in enumerate(parts):
        inset = bevel*.43 if index in (0,len(parts)-1) else 0.0
        top = y1 - inset - (1.0-t)*taper
        bottom = y0 + inset
        left, right = z0+inset,z1-inset
        section = [(bottom+bevel,left),(top-bevel,left),(top,left+bevel),(top,right-bevel),
                   (top-bevel,right),(bottom+bevel,right),(bottom,right-bevel),(bottom,left+bevel)]
        raw += [(x0+(x1-x0)*t,
                 min(top,max(bottom,y+rng.uniform(-rough,rough))),
                 min(right,max(left,z+rng.uniform(-rough,rough))))
                for y,z in section]
    faces = [tuple(reversed(range(8)))]
    for r in range(len(parts)-1):
        i,j = r*8,(r+1)*8
        faces.extend((i+n,i+(n+1)%8,j+(n+1)%8,j+n) for n in range(8))
    faces.append(tuple((len(parts)-1)*8+i for i in range(8)))
    indices = [1] + [0]*(len(faces)-2) + [1]

    def uv(i, face_poly):
        x,y,z = raw[i]
        if face_poly.material_index == 1:
            return (.5+(y-(y0+y1)*.5)*2.8, .5+(z-(z0+z1)*.5)*2.8)
        side = (face_poly.index-1)%8
        across = z if side in (1,2,3,5,6,7) else y
        return (x/1.36 + uv_offset[0], across/0.58 + uv_offset[1])

    vertices = raw if transform is None else [transform(*v) for v in raw]
    return object_mesh(collection,name,vertices,faces,[face,head],uv,indices,mirror)


def stone(collection, name, x, z, y0, y1, rx, rz, mat, seed):
    rng = random.Random(seed)
    verts = []
    phases = [rng.uniform(-0.085,0.085) for _ in range(8)]
    footprint = [rng.uniform(0.84,1.12) for _ in range(8)]
    for j, (ring, y) in enumerate([(0.85,y0),(1.0,y0+(y1-y0)*0.31),(0.88,y1)]):
        for i in range(8):
            a = i*pi/4 + phases[i]
            lift = 0 if j==0 else -rng.uniform(0,0.011)
            verts.append((x+cos(a)*rx*ring*footprint[i],y+lift,z+sin(a)*rz*ring*footprint[i]))
    faces = [tuple(range(8))]
    for base in (0,8):
        faces.extend((base+i,base+8+i,base+8+(i+1)%8,base+(i+1)%8) for i in range(8))
    faces.append(tuple(reversed([16+i for i in range(8)])))

    def uv(i, poly):
        a,b,c = verts[i]
        if poly.index in (0,17):
            return (a*1.7,c*1.7)
        sector = (poly.index-1)%8
        return ((a if sector in [1,2,5,6] else c)*1.75,b*2.6)
    return object_mesh(collection,name,verts,faces,[mat],uv,[0]*len(faces))


def floor_details(collection, materials):
    hewn,end,deck,_,_,slate = materials
    seed = 600
    for x, _, z in corners([-1.12,1.12],[-1.12,1.12]):
        stone(collection,"Dry stone footing",x,z,0.0,.059,.206,.211,slate,seed)
        stone(collection,"Bearing stone",x+.013,z-.007,.054,.119,.171,.182,slate,seed+7)
        seed += 13
    for z in (-1.396,1.396):
        timber(collection,"Weathered rim sill",(-1.5,.103,z-.104),(1.5,.151,z+.104),
               hewn,end,seed,rough=.0015)
        seed += 1
    for z in (-1.10,0.0,1.10):
        timber(collection,"Under-floor joist",(-1.43,.105,z-.072),(1.43,.146,z+.072),
               hewn,end,seed,bevel=.004)
        seed += 1
    space = 3/14
    for i in range(14):
        begin = -1.5 + i*space
        finish = -1.5 + (i+1)*space
        gap = .0035 + .001*sin(i*1.2)
        timber(collection,"Sawn floor board %02d" % (i+1),
               (-1.5,.144,begin+(gap if i else 0)),(1.5,FLOOR_TOP,finish-(gap if i<13 else 0)),
               deck,end,seed+i,bevel=.0045,rough=.0014,stations=7)


def wall_details(collection, materials, doorway):
    hewn,end,deck,_,clay,_ = materials
    for row,(low,high) in enumerate(zip(COURSES,COURSES[1:])):
        left = -INNER_HALF if row%2==0 else -CORNER_END
        right = CORNER_END if row%2==0 else INNER_HALF
        splits = [(left,-DOOR_HALF-.064),(DOOR_HALF+.064,right)] if doorway and row<10 else [(left,right)]
        for segment,(x0,x1) in enumerate(splits):
            timber(collection,"Hewn log %02d.%d" % (row+1,segment+1),
                   (x0,low+(0.009 if row else 0.0),-WALL_HALF),
                   (x1,high-(0.009 if row<10 else 0.0),WALL_HALF),
                   hewn,end,900+row*11+segment,bevel=.014,rough=.0042,stations=8)
            if row < 10:
                timber(collection,"Infilled log seam",(x0+.003,high-.014,-.104),(x1-.003,high+.012,.104),
                       clay,clay,910+row+segment,bevel=.003,rough=.0027)
    if doorway:
        for side in (-1,1):
            x=side*(DOOR_HALF+.036)
            timber(collection,"Through tenon jamb",(0.0,-WALL_HALF,x-.036),(DOOR_TOP,WALL_HALF,x+.036),
                   deck,end,1382+side,bevel=.0065,rough=.0007,
                   transform=lambda height,depth,width:(width,height,depth))
        timber(collection,"Door lintel",(-DOOR_HALF-.07,DOOR_TOP,-.12),
               (DOOR_HALF+.07,DOOR_TOP+.115,.12),deck,end,1390,bevel=.007,rough=.0005)
        for side in (-1,1):
            for i,y in enumerate((.23,1.05,1.91,2.109)):
                x=side*(DOOR_HALF+.037)
                timber(collection,"Knock-down oak peg",(x-.011,y-.012,.112),(x+.011,y+.012,.12),
                       end,end,1403+side+i,bevel=.0034,rough=.0002,stations=2)


def roof_details(collection, materials):
    hewn,end,_,oak,_,_ = materials
    seed=1740
    rand=random.Random(seed)
    distance=EAVE/cos(PITCH)
    for side in (-1,1):
        eave=side*WALL_AXIS
        timber(collection,"Eave bearing sill",(-1.44,0,eave-BEARING_WIDTH/2),
               (1.44,BEARING_HEIGHT,eave+BEARING_WIDTH/2),hewn,end,seed+side,rough=.0027)
        transform = lambda x,y,d: roof_point(x,y,d,side)
        for x in (-1.38,-.71,0.0,.71,1.38):
            timber(collection,"Exposed rafter",(.02,-.083,x-.041),(distance+.025,-.018,x+.041),
                   hewn,end,seed,bevel=.007,transform=lambda d,y,c:transform(c,y,d),mirror=side>0)
            seed+=1
        for row in range(8):
            d = (row+0.40)*distance/8
            timber(collection,"Shake lath",(-ROOF_HALF,-.031,d-.035),(ROOF_HALF,0.012,d+.035),
                   hewn,end,seed,bevel=.004,transform=transform,mirror=side<0,rough=.0018)
            seed+=1
        for c in range(10):
            tip = distance-.195*c
            if tip < 0.09:
                break
            x=-1.594
            i=0
            while x<1.58:
                width=rand.uniform(.142,.269)
                end_x = 1.594 if x+width>1.51 else x+width
                d1=tip+rand.uniform(-.018,.018)
                d0=max(-.008,d1-rand.uniform(.31,.389))
                lift=rand.uniform(0.0,.012)
                timber(collection,"Riven oak shake %d.%d" % (c+1,i+1),
                       (d0,.016+lift,x),(d1,.057+lift,end_x-.004),
                       oak,end,seed,bevel=.0042,rough=.0033,taper=.020,stations=3,
                       transform=lambda d,y,w:transform(w,y,d),mirror=side>0)
                i+=1
                seed+=1
                x=end_x
        timber(collection,"Riven ridge closure",(-ROOF_HALF,.046,.005),(ROOF_HALF,.104,.119),
               oak,end,seed+side,bevel=.008,transform=transform,mirror=side<0,rough=.0018)
    for side in (-1,1):
        x=side*WALL_AXIS
        for i in range(6):
            low=i*.15
            top=(i+1)*.15
            z=min(1.32, (RIDGE-top)/.58)+.017
            timber(collection,"Gable sawn lap board",(-z,low,x-.043),(z,top+.013,x+.046),
                   hewn,end,1978+i+int(side>0)*60,bevel=.008,rough=.0016,
                   transform=lambda length,height,thickness:(thickness,height,length),mirror=True)


def source_scene(name):
    import bpy

    scene = bpy.data.scenes.new(name)
    scene.use_fake_user = True
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    return scene


def measured_bounds(collection):
    points = [(v.co.x,v.co.z,-v.co.y) for obj in collection.objects for v in obj.data.vertices]
    minimum = [min(p[i] for p in points) for i in range(3)]
    maximum = [max(p[i] for p in points) for i in range(3)]
    return {"position": minimum, "size": [b-a for a,b in zip(minimum, maximum)]}


def export_part(scene, part, scratch, active_scene_only=False):
    import bpy

    bpy.context.window.scene = scene
    temp = bpy.data.collections.new("Export parts")
    scene.collection.children.link(temp)
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    clones = []
    for original in part.objects:
        obj = original.copy()
        obj.data = original.data.copy()
        temp.objects.link(obj)
        obj.select_set(True)
        clones.append(obj)
    bpy.context.view_layer.objects.active = clones[0]
    bpy.ops.object.join()
    merged = bpy.context.view_layer.objects.active
    merged.name = part.name
    merged.data.name = part.name
    bpy.ops.export_scene.gltf(
        filepath=str(scratch / (part.name+".glb")), export_format="GLB",
        use_selection=True, use_active_scene=active_scene_only, export_apply=True, export_animations=False,
        export_tangents=True, export_image_format="AUTO",
    )
    bpy.data.objects.remove(merged, do_unlink=True)
    bpy.data.collections.remove(temp)


def add_instance(scene, part, pos, yaw):
    import bpy

    anchor = bpy.data.objects.new(part.name, None)
    scene.collection.objects.link(anchor)
    anchor.instance_type = "COLLECTION"
    anchor.instance_collection = part
    anchor.location = to_blender(pos)
    anchor.rotation_euler.z = yaw


def studio(scene):
    import bpy
    from mathutils import Vector

    space = bpy.data.collections.new("Review lighting")
    scene.collection.children.link(space)
    backdrop = bpy.data.materials.new("Woodland soil review ground")
    backdrop.use_nodes = True
    backdrop.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (.14,.155,.12,1.)
    floor = bpy.data.meshes.new("Review ground")
    floor.from_pydata([(-200,-200,-.003),(200,-200,-.003),(200,200,-.003),(-200,200,-.003)],[],[(0,1,2,3)])
    plane = bpy.data.objects.new("Review ground",floor)
    space.objects.link(plane)
    plane.data.materials.append(backdrop)
    world = bpy.data.worlds.new("Cool sky and canopy")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs[0].default_value = (.29,.38,.47,1.0)
    background.inputs[1].default_value = .41
    for label, xyz, watts, color, size in [
        ("Sun through trees",(-4,7.0,3.4),1920,(1,.90,.78),4.2),
        ("Open clearing",(5.1,4.0,-4.6),660,(.86,.93,1.0),5.0),
        ("Late sky on shakes",(-1.1,5.0,-6.5),760,(.89,.94,1.0),3.7),
        ("Spill through the doorway",(0,1.65,2.9),40,(1,.94,.83),1.2),
    ]:
        light = bpy.data.lights.new(label,"AREA")
        light.energy = watts
        light.color = color
        light.shape = "DISK"
        light.size = size
        obj = bpy.data.objects.new(label, light)
        space.objects.link(obj)
        obj.location = to_blender(xyz)
        obj.rotation_euler = (Vector(to_blender((0,1.4,0)))-obj.location).to_track_quat("-Z","Y").to_euler()
    camera_data = bpy.data.cameras.new("Assembly view")
    camera = bpy.data.objects.new("Assembly view",camera_data)
    space.objects.link(camera)
    scene.camera = camera
    camera_data.type = "ORTHO"
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 3
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.quality = 92
    scene.view_settings.view_transform = "AgX"
    return camera


def set_view(scene, camera, pos, target, span, width, height):
    from mathutils import Vector

    camera.location = to_blender(pos)
    camera.rotation_euler = (Vector(to_blender(target))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.ortho_scale = span
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100


def render_kit(scene, camera, samples):
    import bpy

    scene.cycles.samples = samples
    bpy.context.window.scene = scene
    views = [
        ("assembly",(6.35,4.7,7.9),(0,1.55,0),6.7,1440,1040),
        ("roof-detail",(4.3,5.3,4.9),(.45,2.94,.08),3.85,1160,900),
        ("joinery-detail",(3.6,2.1,4.3),(.83,1.10,1.34),2.58,1160,900),
    ]
    for label, pos, target, span, width, height in views:
        set_view(scene,camera,pos,target,span,width,height)
        scene.render.filepath = str(EVIDENCE/(label + ".jpg"))
        bpy.ops.render.render(write_still=True)


def build(scratch):
    import bpy

    assert bpy.app.background
    scratch = Path(scratch)
    scratch.mkdir(parents=True,exist_ok=True)
    RUNTIME.mkdir(parents=True,exist_ok=True)
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    prototype = metadata()
    materials = [
        studio_texture(name, size, color, roughness, pattern, seed, scratch)
        for name, size, color, roughness, pattern, seed in [
            ("cabin_hewn_pine",1024,(.466,.351,.238),.79,"wood",309),
            ("cabin_cut_endgrain",768,(.558,.435,.292),.73,"end",311),
            ("cabin_sawn_boards",1024,(.482,.348,.238),.76,"wood",337),
            ("cabin_weathered_oak",1024,(.407,.363,.309),.83,"wood",345),
            ("cabin_chinking_clay",512,(.476,.431,.354),.93,"stone",351),
            ("cabin_fieldstone",768,(.383,.404,.374),.87,"stone",392),
        ]
    ]
    scenes = {}
    parts = {}
    for ident, write in [
        ("cabin_floor",floor_details),
        ("cabin_wall",lambda c,m: wall_details(c,m,False)),
        ("cabin_doorway",lambda c,m: wall_details(c,m,True)),
        ("cabin_roof",roof_details),
    ]:
        scene = source_scene(ident)
        coll = bpy.data.collections.new(ident)
        scene.collection.children.link(coll)
        write(coll,materials)
        prototype["pieces"][ident]["bounds"] = measured_bounds(coll)
        scenes[ident], parts[ident] = scene,coll
        export_part(scene,coll,scratch)

    assembly = source_scene("Assembled cabin")
    add_instance(assembly,parts["cabin_floor"],(0,0,0),0)
    for wall in prototype["assembly"]["walls"]:
        add_instance(assembly,parts[wall["kind"]],wall["at"],wall["yaw"])
    add_instance(assembly,parts["cabin_roof"],prototype["assembly"]["roofAt"],0)
    camera = studio(assembly)
    set_view(assembly,camera,(6.35,4.7,7.9),(0,1.55,0),6.7,1440,1040)
    assembly.render.filepath = "//cabin-assembly.jpg"
    bpy.context.window.scene = assembly
    for scene in list(bpy.data.scenes):
        if scene not in scenes.values() and scene != assembly:
            bpy.data.scenes.remove(scene)
    bpy.data.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(PROJECT/"art/cabin_kit.blend"),compress=True,relative_remap=False)
    save_json(RUNTIME/"cabin_kit.json",prototype)
    return {k: v["bounds"] for k,v in prototype["pieces"].items()}


def prepare_runtime(scratch):
    import runpy

    compress = runpy.run_path(str(PROJECT/"scripts/build-camp-weapons.py"))["compress_model"]
    for ident in metadata()["pieces"]:
        compress(Path(scratch)/(ident+".glb"),RUNTIME/(ident+".glb"))


def render():
    import bpy

    assert bpy.app.background
    scene = bpy.data.scenes["Assembled cabin"]
    render_kit(scene,scene.camera,24)
    return {"assembly":str(EVIDENCE/"assembly.jpg"),"details":str(EVIDENCE/"roof-detail.jpg")}


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--compress",type=Path,required=True)
    options = parser.parse_args()
    prepare_runtime(options.compress)
