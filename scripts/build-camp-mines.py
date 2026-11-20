"""Make Rainline's walk-in mine assets with Blender's background MCP."""
from __future__ import annotations

from math import cos, pi, sin, tau
from pathlib import Path
import json
import random
import runpy
import struct


PROJECT = Path(__file__).resolve().parents[1]
LAYOUT = runpy.run_path(str(PROJECT / "scripts/build-mine-layout.py"))
ASSET = runpy.run_path(str(PROJECT / "scripts/build-cabin-kit.py"))
IRON = runpy.run_path(str(PROJECT / "scripts/refine-camp-iron-vein.py"))
PICKUPS = runpy.run_path(str(PROJECT / "scripts/refine-mine-pickups.py"))
RUNTIME = PROJECT / "coop/props/mines"
SOURCE = PROJECT / "art/mines"
EVIDENCE = PROJECT / "evidence/mines-20261120"
SHARED = {
    "cliff_color": "coast/cliff_color.jpg",
    "cliff_normal": "coast/cliff_normal.jpg",
    "seaside_color": "coast/seaside_color.jpg",
    "seaside_normal": "coast/seaside_normal.jpg",
    "lake_gravel_diff": "textures/lake_gravel_diff.jpg",
    "lake_gravel_nor_gl": "textures/lake_gravel_nor_gl.jpg",
    "wood_diff": "textures/wood_diff.jpg",
    "wood_nor_gl": "textures/wood_nor_gl.jpg",
}
SOURCE_BLEND = SOURCE / "rainline_mines.blend"
LANTERN_SCALE = 0.52
BAIL_CENTER_Y = -0.049
HANGER_OFFSET_Y = 0.002
WICK_CENTER_Y = -0.392
LIGHT_INSET = 0.16


def surface(name, color, rough, metallic=0.0, emission=0.0):
    import bpy

    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color,1)
    p = mat.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color,1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Emission Color"].default_value = (*color,1)
    p.inputs["Emission Strength"].default_value = emission
    return mat


def reused_surface(label, color, normal, roughness, strength):
    import bpy

    mat = surface(label,(.35,.26,.19),roughness)
    graph = mat.node_tree
    p = graph.nodes.get("Principled BSDF")
    nodes = []
    for key,index in ((color,0),(normal,1)):
        tex = graph.nodes.new("ShaderNodeTexImage")
        tex.location = (-510,200-300*index)
        img = bpy.data.images.get(key)
        if img is None:
            img = bpy.data.images.load(str(PROJECT / "coop" / SHARED[key]))
            img.name = key
            if index == 1:
                img.colorspace_settings.name = "Non-Color"
            img.pack()
        tex.image = img
        nodes.append(tex)
    graph.links.new(nodes[0].outputs["Color"],p.inputs["Base Color"])
    n = graph.nodes.new("ShaderNodeNormalMap")
    n.location = (-260,-100)
    n.inputs["Strength"].default_value = strength
    graph.links.new(nodes[1].outputs["Color"],n.inputs["Color"])
    graph.links.new(n.outputs["Normal"],p.inputs["Normal"])
    return mat


def material_library(scratch):
    common = {
        "cliff": reused_surface("Weathered Rainline cliff", "cliff_color", "cliff_normal", .87, .94),
        "dark": reused_surface("Fissured bedrock", "seaside_color", "seaside_normal", .89, .80),
        "gravel": reused_surface("Compact trail gravel", "lake_gravel_diff", "lake_gravel_nor_gl", .95, .85),
        "wood": reused_surface("Weathered mine timbers", "wood_diff", "wood_nor_gl", .86, .82),
        "metal": surface("Rusted lantern and brace iron",(.063,.040,.029),.52,.73),
    }
    for name, size, palette, rough, seed, metal in (
        ("coal_matte",512,(.071,.080,.092),.69,221,.02),
        ("coal_fracture",512,(.100,.107,.113),.48,430,.04),
        ("oxide",512,(.526,.276,.117),.72,121,.015),
        ("hematite",512,(.224,.161,.128),.53,308,.17),
        ("cast_iron",512,(.341,.379,.409),.48,497,.75),
        ("iron_cold_edge",448,(.445,.474,.478),.35,524,.80),
    ):
        mat = ASSET["studio_texture"](name,size,palette,rough,"stone",seed,scratch)
        mat.node_tree.nodes.get("Principled BSDF").inputs["Metallic"].default_value = metal
        common[name] = mat
    return common


def mesh(collection, name, points, faces, materials, indices, scale=1.0):
    def uv(i, poly):
        x,y,z = points[i]
        nx,nz,ny = (abs(v) for v in poly.normal)
        if ny >= nx and ny >= nz:
            return (x*scale,z*scale)
        if nx > nz:
            return (z*scale, y*scale)
        return (x*scale,y*scale)

    return ASSET["object_mesh"](collection,name,points,faces,materials,uv,indices)


def lane(collection, entry, mat):
    m = LAYOUT
    points, faces = [], []
    # Center of the rendered surface follows the exact OBB top at each station.
    # Jagged edges extend into the rock and down to the existing ground.
    rng = random.Random(951)
    height = m["CoastHeight"]()
    for z,y,x,w in entry["floor"]:
        left, right = x-w-.035, x+w+.035
        row = [left, x-w*.52, x, x+w*.52, right]
        for j,v in enumerate(row):
            d = rng.uniform(-.017,.012) if j in (1,3) else 0.0
            points.append((v,y+d,z))
        for v,sign in [(left,-1),(right,1)]:
            extension = .16 + rng.uniform(0,.15)
            v += sign*extension
            skirt_y = min(y-.16,m["height_at"](height,entry,v,z)-.018)
            points.append((v,skirt_y,z))
    for i in range(len(entry["floor"])-1):
        a, b = i*7,(i+1)*7
        for j in range(4):
            faces.append((a+j,b+j,b+j+1,a+j+1))
        faces += [(a+5,b+5,b,a),(a+4,b+4,b+6,a+6)]
    mesh(collection,"Continuous gravel tread and earthen skirts",points,faces,[mat],[0]*len(faces),.61)


def trail_grade(collection,entry,mats):
    m = LAYOUT
    rng = random.Random(708)
    coast = m["CoastHeight"]()
    samples = entry["footpath"]
    points,faces,indices=[],[],[]
    for i,(x,y,z,w) in enumerate(samples):
        left,right = samples[max(0,i-1)],samples[min(i+1,len(samples)-1)]
        direction = (right[2]-left[2],0.,left[0]-right[0])
        dx,_,dz = m["unit"](direction)
        profile = []
        for t in (-2,-1,0,1,2):
            sx,sz = x+dx*w*t*.5,z+dz*w*t*.5
            tipped = y
            if abs(t)==1:
                tipped += rng.uniform(-.012,.008)
            profile.append((sx,tipped,sz))
        for sign in (-1,1):
            edge = profile[0] if sign < 0 else profile[-1]
            under = m["height_at"](coast,entry,edge[0],edge[2])
            flare = .22 + .65*max(0,y-under)+rng.uniform(.005,.064)
            ax,az = x+dx*sign*(w+flare),z+dz*sign*(w+flare)
            raw = m["height_at"](coast,entry,ax,az)-.019
            profile.append((ax,min(raw,y-.045),az))
        points.extend(profile)
        if i>0:
            a,b=(i-1)*7,i*7
            faces.extend((a+j,b+j,b+j+1,a+j+1) for j in range(4))
            faces += [(a+5,b+5,b,a),(a+4,b+4,b+6,a+6)]
            indices += [0,0,0,0,1,1]
    mesh(collection,"Climbing footpath and tapered soil shoulders",points,faces,
         [mats["gravel"],mats["dark"]],indices,.73)


def bedrock(collection, entry, mats, seed):
    m = LAYOUT
    rng = random.Random(seed)
    heights = m["CoastHeight"]()
    sections = [m["WALL_SECTIONS"][0]]
    for a,b in zip(m["WALL_SECTIONS"],m["WALL_SECTIONS"][1:]):
        for j in range(1,4):
            sections.append(a+(b-a)*j/3)
    inner, outside = [], []
    for z in sections:
        ring = m["ring"](entry,entry["floor"],z)
        fy,cx,w = m["floor_at"](entry["floor"],z)
        scale = 1.+.045*sin(z*2.7+seed) + .04*cos(z*1.9)
        stride = ((.8+.38*sin(z*1.70+seed))*(.86+.14*cos(z*.34)))
        for i,v in enumerate(ring):
            for step in range(2 if i<len(ring)-1 else 1):
                t = step*.5
                a,b = v,ring[min(i+1,len(ring)-1)]
                x,y,_ = [p+(q-p)*t for p,q in zip(a,b)]
                cross = (x-cx)/w
                span = z + rng.uniform(-.105,.105)
                h = y - fy
                x_spall = (1 if cross>0 else -1)*rng.uniform(-.058,.085)
                y_spall = rng.uniform(-.054,.061)
                inner.append((x+x_spall,y+y_spall,span))
                # Outer shell grades into the existing hillside. Broad benches are
                # broken into slab faces by varying shelf/face offsets separately.
                outer_x = cx + cross * (w+.48+stride*.60)*scale + rng.uniform(-.12,.12)
                outer_z = z + rng.uniform(-.22,.23)
                outer_rise = 1.10+.29*sin(z*.68+seed+.50)
                outer_y = fy + h*scale + outer_rise*max(0.0,1.0-abs(cross))**.59
                outer_y += .14*sin(z*2.9+i*.73)+rng.uniform(-.16,.14)
                if h < -.36 or (abs(cross)>.91 and h<.4):
                    outer_y = min(outer_y,m["height_at"](heights,entry,outer_x,z)-.18)
                outside.append((outer_x,outer_y,outer_z))

    count = len(inner)//len(sections)
    inner_wall = None
    for points,label,winding in [(inner,"Interior fractured rock",1),(outside,"Rock outcrop and outer ledges",-1)]:
        faces,indices = [],[]
        for i in range(len(sections)-1):
            a,b=i*count,(i+1)*count
            for j in range(count-1):
                quad = (a+j,a+j+1,b+j+1,b+j)
                pair = ((quad[0],quad[1],quad[3]),(quad[1],quad[2],quad[3])) if (i+j)%2 else (
                    quad[:3],(quad[0],quad[2],quad[3]))
                faces.extend([f[::winding] for f in pair])
                material = int(winding==1 and (j<1 or j>=count-2))
                indices.extend([material,material])
        surface = mesh(collection,label,points,faces,[mats["cliff"],mats["dark"]],indices,.58)
        if winding == 1:
            inner_wall = surface

    for start in (0,len(inner)-count):
        # There is an annular lip at the mouth. Its center stays entirely open.
        # Only the terminal cross-section gets a solid fill.
        a, b = inner[start:start+count],outside[start:start+count]
        points = a+b
        faces = [(i,i+count,i+count+1,i+1) for i in range(count-1)]
        if start:
            y,x,_ = m["floor_at"](entry["floor"],m["BACK"])
            points += [(x,y+.86,m["BACK"]-.10),(x,y+1.12,m["BACK"]+.32)]
            faces += [(2*count,i,(i+1)%count) for i in range(count)]
            faces += [(2*count+1,count+(i+1)%count,count+i) for i in range(count)]
        else:
            faces = [tuple(reversed(face)) for face in faces]
        mesh(collection, "Closed gallery end" if start else "Open entrance rim",
             points,faces,[mats["cliff"],mats["dark"]],
             [0]*len(faces),.57)
    return inner_wall


def shard(collection, name, center, scales, mats, rng, texture_scale=4, angle=None):
    n = rng.randrange(8,12)
    phase = rng.uniform(0,tau) if angle is None else angle
    points = []
    for y,girth in ((-.46,.76),(-.16,1.0),(.20,.90),(.47,.57)):
        for k in range(n):
            a = phase+k*tau/n+rng.uniform(-.10,.10)
            xx = cos(a)*girth*rng.uniform(.85,1.10) + .13*y
            zz = sin(a)*girth*rng.uniform(.85,1.10) - .18*y
            yy = y+rng.uniform(-.075,.075)
            points.append((center[0]+xx*scales[0],center[1]+yy*scales[1],center[2]+zz*scales[2]))
    faces = [tuple(range(n)),tuple(reversed(range(3*n,4*n)))]
    for i in range(3):
        for j in range(n):
            k=(j+1)%n
            a,b,c,d=(i*n+j,i*n+k,(i+1)*n+k,(i+1)*n+j)
            faces.extend(((a,c,b),(a,d,c)))
    return mesh(collection,name,points,faces,mats,
                [rng.randrange(len(mats)) for _ in faces],texture_scale)


def exterior_details(collection, entry, mats, seed):
    rng = random.Random(seed)
    height = LAYOUT["CoastHeight"]()
    for i, z in enumerate((-.22,.88,1.95,2.90,4.16,5.23,6.47,7.78,9.02,10.08,11.04)):
        y,cx,w = LAYOUT["floor_at"](entry["floor"],z)
        for sign in (-1,1):
            x = cx+sign*(w+.37+rng.uniform(.06,.40))
            ground = LAYOUT["height_at"](height,entry,x,z)
            size = (.52+rng.uniform(0,.25),.82+rng.uniform(.11,.64),rng.uniform(.52,.86))
            at = (x,ground+.52*size[1],z)
            shard(collection,"Spalled exterior block %d %d" % (i,sign),at,size,
                  [mats["cliff"]],rng,.64)
    # Low gravel never closes the collision trace or projects above the toes.
    for j in range(58):
        z = rng.uniform(-2.28,10.95)
        y,cx,w = LAYOUT["floor_at"](entry["floor"],z)
        sx = rng.choice((-1,1))
        x = cx+sx*w*rng.uniform(.75,1.04)
        radius = rng.uniform(.026,.16)
        shard(collection,"Scree %02d" % j,(x,y+.014,z),(radius,radius*.42,radius*.68),
              [mats["cliff"],mats["dark"],mats["gravel"]],rng,2.6)


def timber(collection,name,start,end,section,mats,seed):
    x,y,z = start
    vertical = end[1] > y
    length = end[1]-y if vertical else end[0]-x
    half, depth = section[0]*.5,section[1]*.5

    def turn(a,b,c):
        return (x-b,y+a,z+c) if vertical else (x+a,y+b,z+c)

    return ASSET["timber"](collection,name,(0,-half,-depth),(length,half,depth),
                            *mats,seed,bevel=.012,transform=turn)


def mine_frames_and_anchors(collection, entry, mats, seed):
    import bpy
    from mathutils import Vector

    def tube(name,start,end,a,b,material,n=10):
        pos = Vector(ASSET["to_blender"](start))
        finish = Vector(ASSET["to_blender"](end))
        axis = finish-pos
        bpy.ops.mesh.primitive_cone_add(vertices=n,radius1=a,radius2=b,depth=axis.length,
                                       location=(pos+finish)*.5)
        obj = bpy.context.object
        obj.name = name
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = Vector((0,0,1)).rotation_difference(axis.normalized())
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        collection.objects.link(obj)
        for old in list(obj.users_collection):
            if old != collection:
                old.objects.unlink(obj)
        obj.data.materials.append(material)
        return obj

    for i,frame in enumerate(entry["frames"]):
        x,y,z = frame["at"]
        gap, beam = frame["halfGap"],frame["beamY"]
        woods = [mats["wood"],mats["wood"]]
        for sign in (-1,1):
            at = x+sign*gap
            timber(collection,f"Frame {i+1} foot", (at,y-.18,z),(at,beam+.035,z),(.16,.178),woods,seed+i*8+sign)
            for h in (1,):
                knot = y+h*2.21
                tube("Brace nail head",(at,knot,z-.091),(at,knot,z-.102),.023,.023,mats["metal"],8)
        timber(collection,f"Frame {i+1} lintel",(x-gap-.13,beam,z),(x+gap+.13,beam,z),
               (.17,.19),woods,seed+i*31)

    for lamp in entry["lamps"]:
        x,y,z=lamp["at"]
        side=lamp_side(entry,lamp)
        anchor_y=y-.007
        tube("Lantern anchor",(x,anchor_y,z),(x+side*.40,anchor_y,z),.014,.014,mats["metal"],7)


def lamp_side(entry, lamp):
    x,_,z=lamp["at"]
    _,center,_=LAYOUT["floor_at"](entry["floor"],z)
    return 1 if x>center else -1


def import_hurricane_lantern():
    import bpy

    with bpy.data.libraries.load(str(PROJECT/"art/camp_lantern.blend"),link=False) as (source, target):
        target.collections=["Lantern assembly"]
    collection=target.collections[0]
    collection.name="Mine hurricane lantern • excluded from gallery GLB"
    bpy.data.objects.remove(collection.objects["Mount"],do_unlink=True)
    return collection


def mount_hurricane_lanterns(scene, entry, collection):
    import bpy

    lift=HANGER_OFFSET_Y-BAIL_CENTER_Y*LANTERN_SCALE
    for i,lamp in enumerate(entry["lamps"]):
        x,y,z=lamp["at"]
        side=lamp_side(entry,lamp)
        mount=bpy.data.objects.new(f"Hurricane lantern {i+1}",None)
        scene.collection.objects.link(mount)
        mount.instance_type="COLLECTION"
        mount.instance_collection=collection
        mount.location=ASSET["to_blender"]((x,y+lift,z))
        mount.rotation_euler.z=-side*pi/2
        mount.scale=(LANTERN_SCALE,)*3


def preview_lamp_pose(entry, lamp):
    x,y,z=lamp["at"]
    side=lamp_side(entry,lamp)
    lift=HANGER_OFFSET_Y+(WICK_CENTER_Y-BAIL_CENTER_Y)*LANTERN_SCALE
    return (x-side*LIGHT_INSET,y+lift,z)


def coal_seam(collection, entry, mats, seed):
    rng = random.Random(seed)
    side = -1
    gather_x,gather_y,gather_z = entry["gather"]
    choice = [mats["coal_matte"],mats["coal_fracture"]]

    def wall(y,z):
        depth = gather_z+side*z
        fy,cx,w = LAYOUT["floor_at"](entry["floor"],depth)
        _,_,crown = LAYOUT["weft"](entry,depth)
        high = (gather_y+y-fy)/crown
        shoulder = min(1,max(0,(high-.71)/.9))
        return (cx-gather_x)*side+w*(1-.11*shoulder)

    for variant,j in enumerate((-.145,.026,.153)):
        pts = []
        for i in range(27):
            z = -1.10+i*(2.17/26)
            wave = .081*sin(z*3.45+seed) + .145*z
            taper = max(.16,1-abs(z/1.14)**3)
            half = (.21 if variant==1 else .095)*taper
            for sign in (-1,1):
                y = j+wave+sign*half+rng.uniform(-.023,.027)
                x = wall(y,z)-.128 - rng.uniform(-.024,.031)
                pts.append((x,y,z))
        faces = [(i,i+3,i+1) for i in range(0,len(pts)-2,2)]
        faces.extend((i,i+2,i+3) for i in range(0,len(pts)-2,2))
        mesh(collection,"Mineral vein exposed band",pts,faces,choice,
             [int(rng.random()<.20) for _ in faces],2.8)
    for i in range(33):
        z=rng.uniform(-.99,.99)
        y=rng.uniform(-.235,.25)+.137*z
        x=wall(y,z)-rng.uniform(.047,.10)
        shard(collection,f"Vein cleavage {i+1}",(x,y,z),
              (rng.uniform(.065,.126),rng.uniform(.078,.179),rng.uniform(.063,.156)),
              choice,rng,7.0)


def pickup(collection, item, mats):
    rng = random.Random({"coal":22,"iron_ore":414,"iron_ingot":721}[item])
    if item=="iron_ingot":
        points = []
        # Slightly narrower top with cast draft and actual rounded edges.
        for w,d,y,corner in [(.145,.071,0.,.013),(.151,.076,.007,.014),
                             (.137,.067,.039,.012),(.127,.058,.051,.012)]:
            order = [(-w+corner,-d),(-w,-d+corner),(-w,d-corner),(-w+corner,d),
                     (w-corner,d),(w,d-corner),(w,-d+corner),(w-corner,-d)]
            for i,(x,z) in enumerate(order):
                points.append((x,y+rng.uniform(-.0018,.0018) if y else 0.,z))
        faces, indices = [tuple(reversed(range(8)))], [0]
        for a in range(0,24,8):
            for i in range(8):
                j=(i+1)%8
                faces.append((a+i,a+j,a+8+j,a+8+i))
                indices.append(int(a==16 or (a==0 and i%3==0)))
        points.append((-.021,.050,.010))
        for i in range(8):
            faces.append((32,24+i,24+(i+1)%8))
            indices.append(0)
        mesh(collection,"Draft cast iron ingot",points,faces,[mats["cast_iron"],mats["iron_cold_edge"]],indices,4.9)
        for i in range(11):
            x,z=rng.uniform(-.099,.105),rng.uniform(-.047,.045)
            r=rng.uniform(.0012,.0028)
            phi=rng.uniform(0,tau)
            xy=[(x,.0514,z)]+[(x+cos(phi+k*tau/6)*r,.052,z+sin(phi+k*tau/6)*r) for k in range(6)]
            faces=[(0,(k+1)%6+1,k+1) for k in range(6)]
            mesh(collection,"Cast pinholes",xy,faces,[mats["hematite"]],[0]*6,15.0)
        return

    mineral = [mats["coal_matte"],mats["coal_fracture"]] if item=="coal" else [mats["oxide"],mats["oxide"],mats["hematite"]]
    sizes = (.104,.134,.083) if item=="coal" else (.100,.147,.080)
    shard(collection,"Hand mineral chunk",(0,.073,0),sizes,mineral,rng,5.7)
    clefts = [(-.056,.053,.039),(.036,.076,-.045),(.052,.035,.040),(-.013,.109,.016)]
    for i,at in enumerate(clefts):
        shard(collection,f"Interlocked mineral flake {i+1}",at,
              (rng.uniform(.025,.052),rng.uniform(.038,.061),rng.uniform(.031,.044)),
              mineral,rng,9.7)
    bottom = min(v.co.z for o in collection.objects for v in o.data.vertices)
    for obj in collection.objects:
        for vertex in obj.data.vertices:
            vertex.co.z -= bottom


def normalize_shared_images(source, target):
    """Keep common coast and mineral maps as shared runtime resources."""
    all_bytes = source.read_bytes()
    json_len = struct.unpack_from("<I",all_bytes,12)[0]
    root = json.loads(all_bytes[20:20+json_len])
    bin_data = memoryview(all_bytes)[28+json_len:]
    shared = set()
    maps = target.parent/"maps"
    maps.mkdir(exist_ok=True)
    for img in root.get("images",[]):
        image_id = img["name"]
        view_id = img.pop("bufferView")
        shared.add(view_id)
        if image_id in SHARED:
            img["uri"] = "../../"+SHARED[image_id]
        else:
            suffix = ".jpg" if img["mimeType"] == "image/jpeg" else ".png"
            path = maps/(image_id+suffix)
            view = root["bufferViews"][view_id]
            start = view.get("byteOffset",0)
            path.write_bytes(bin_data[start:start+view["byteLength"]])
            img["uri"] = path.relative_to(target.parent).as_posix()
        img.pop("mimeType",None)

    output = bytearray()
    views, mapping = [],{}
    for i,view in enumerate(root["bufferViews"]):
        if i in shared:
            continue
        output += b'\0'*(-len(output)%4)
        start = view.get("byteOffset",0)
        mapping[i] = len(views)
        view["byteOffset"] = len(output)
        output += bin_data[start:start+view["byteLength"]]
        views.append(view)
    root["bufferViews"] = views
    for row in root["accessors"] + root.get("images",[]):
        if "bufferView" in row:
            row["bufferView"] = mapping[row["bufferView"]]
    output += b'\0'*(-len(output)%4)
    root["buffers"][0]["byteLength"] = len(output)
    doc = json.dumps(root,separators=(",",":")).encode()
    doc += b' '*(-len(doc)%4)
    with target.open("wb") as stream:
        stream.write(struct.pack("<4sII",b"glTF",2,28+len(doc)+len(output)))
        stream.write(struct.pack("<I4s",len(doc),b"JSON")+doc)
        stream.write(struct.pack("<I4s",len(output),b"BIN\0"))
        stream.write(output)


def setup_view(scene, camera_at, target, width, height, lens=29):
    import bpy
    from mathutils import Vector

    cam = scene.camera
    if cam is None:
        cam = bpy.data.objects.new("Mine camera",bpy.data.cameras.new("Mine camera"))
        scene.collection.objects.link(cam)
        scene.camera = cam
    cam.location = ASSET["to_blender"](camera_at)
    cam.rotation_euler = (Vector(ASSET["to_blender"](target))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type = "PERSP"
    cam.data.lens = lens
    cam.data.clip_start = .018
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 20
    scene.cycles.use_denoising = True
    scene.view_settings.view_transform = "AgX"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.quality = 91
    return cam


def light(scene,name,kind,at,strength,color,size,look=None):
    import bpy
    from mathutils import Vector

    data = bpy.data.lights.new(name,kind)
    data.energy=strength
    data.color=color
    if kind=="POINT":
        data.shadow_soft_size = size
    if kind=="AREA":
        data.size=size
    if kind=="SUN":
        data.angle=size
    obj=bpy.data.objects.new(name,data)
    scene.collection.objects.link(obj)
    obj.location=ASSET["to_blender"](at)
    if look is not None:
        obj.rotation_euler=(Vector(ASSET["to_blender"](look))-obj.location).to_track_quat("-Z","Y").to_euler()


def world_light(scene, name, energy):
    import bpy
    scene.world=bpy.data.worlds.new(name)
    scene.world.use_nodes=True
    sky=scene.world.node_tree.nodes.get("Background")
    sky.inputs["Color"].default_value=(.40,.53,.71,1)
    sky.inputs["Strength"].default_value=energy


def actual_terrain_reference(scene, entry, mats):
    import bpy

    collection=bpy.data.collections.new("Coast height reference • excluded from GLB")
    scene.collection.children.link(collection)
    h=LAYOUT["CoastHeight"]()
    points,faces=[],[]
    n=47
    for j in range(n):
        z=-12.+j*.69
        for i in range(n):
            x=(i-(n-1)*.5)*.69
            y=LAYOUT["height_at"](h,entry,x,z)
            points.append((x,y,z))
    for j in range(n-1):
        for i in range(n-1):
            a=j*n+i
            faces.append((a,a+n,a+n+1,a+1))
    mesh(collection,"Real coastline height samples",points,faces,[mats["dark"]],
         [0]*len(faces),.37)


def gallery_studio(scene, entry, mats):
    world_light(scene,"Cool coastal daylight",.20)
    light(scene,"High coastal sun","SUN",(-8,13,-9),1.5,(1.,.88,.72),.08,(0,0,3))
    light(scene,"Mouth daylight","AREA",(1.8,3.1,-4.5),165,(.71,.84,1.),5.8,(0,1.2,4))
    for i,model in enumerate(entry["lamps"]):
        light(scene,f"Oil pool {i+1}","POINT",preview_lamp_pose(entry,model),
              23 if i else 18,(1.,.81,.64),.12)
    actual_terrain_reference(scene,entry,mats)


def pickup_studio(scene):
    world_light(scene,"Neutral pickup lighting",.37)
    light(scene,"Broad key","AREA",(-.25,.45,-.28),20,(1.,.94,.83),.29,(0,.04,0))
    light(scene,"Cool edge","AREA",(.09,.31,.28),18,(.62,.79,1.),.26,(0,.045,0))
    light(scene,"Soft fill","AREA",(.38,.20,-.05),7,(.84,.92,1.),.32,(0,.04,0))
    cam=setup_view(scene,(.38,.35,-.43),(0,.052,0),384,384,55)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = .35 if scene.name == "iron_ingot" else .286
    scene.render.film_transparent = True
    scene.render.image_settings.file_format="PNG"
    scene.render.image_settings.color_mode="RGBA"
    scene.cycles.samples=24


def add_collection(scene,name):
    import bpy
    collection = bpy.data.collections.new(name)
    scene.collection.children.link(collection)
    return collection


def place_collection(scene, collection, at, yaw):
    ASSET["add_instance"](scene,collection,at,yaw)


def build(scratch):
    import bpy

    assert bpy.app.background
    scratch = Path(scratch)
    RUNTIME.mkdir(parents=True,exist_ok=True)
    SOURCE.mkdir(parents=True,exist_ok=True)
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    scratch.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    mats = material_library(scratch)
    lantern=import_hurricane_lantern()
    data=LAYOUT["manifest"]()
    scenes, parts = {}, {}
    for ident,entry in data["mines"].items():
        mineral=ident.split("_")[0]
        key=f"{mineral}_seam"
        scene=ASSET["source_scene"](key)
        parts[key]=add_collection(scene,key)
        scenes[key]=scene
        scene=ASSET["source_scene"](ident)
        bpy.context.window.scene=scene
        parts[ident] = collection = add_collection(scene,ident)
        lane(collection,entry,mats["gravel"])
        trail_grade(collection,entry,mats)
        seed=504 if mineral=="coal" else 699
        wall=bedrock(collection,entry,mats,seed)
        if mineral=="coal":
            coal_seam(parts[key],entry,mats,721)
        else:
            IRON["deposit"](parts[key],wall,entry,scratch,ASSET["object_mesh"])
        exterior_details(collection,entry,mats,seed)
        mine_frames_and_anchors(collection,entry,mats,seed)
        mount_hurricane_lanterns(scene,entry,lantern)
        place_collection(scene,parts[key],entry["seam"]["at"],entry["seam"]["yaw"])
        gallery_studio(scene,entry,mats)
        setup_view(scene,(3.35,2.58,-5.7),(0,1.10,1.65),1250,850,31)
        scenes[ident]=scene
    for ident in ("coal","iron_ore","iron_ingot"):
        scene=ASSET["source_scene"](ident)
        parts[ident]=add_collection(scene,ident)
        pickup(parts[ident],ident,mats)
        if ident in PICKUPS["ITEMS"]:
            PICKUPS["apply_material"](scene,parts[ident],ident,scratch)
        pickup_studio(scene)
        scenes[ident]=scene
    for ident,part in parts.items():
        ASSET["export_part"](scenes[ident],part,scratch)
        normalize_shared_images(scratch/(ident+".glb"),RUNTIME/(ident+".glb"))
    bpy.context.window.scene=scenes["coal_mine"]
    for scene in list(bpy.data.scenes):
        if scene not in scenes.values():
            bpy.data.scenes.remove(scene)
    bpy.data.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_BLEND),compress=True,relative_remap=False)
    LAYOUT["write"](data)
    return {ident: {"objects":len(coll.objects), "bytes":(RUNTIME/(ident+".glb")).stat().st_size}
            for ident,coll in parts.items()}


def render(preview="all"):
    import bpy

    assert bpy.app.background
    for ident,entry in LAYOUT["manifest"]()["mines"].items():
        if preview not in ("all",ident,"galleries"):
            continue
        scene=bpy.data.scenes[ident]
        bpy.context.window.scene=scene
        for label, at, aim, lens in (
            ("entrance",(3.52,2.83,-7.25),(-.14,1.34,1.63),33),
            ("interior",(0,LAYOUT["floor_at"](entry["floor"],4.72)[0]+1.58,4.72),
             (entry["gather"][0]*.66,entry["gather"][1]+.18,entry["gather"][2]),25),
        ):
            setup_view(scene,at,aim,1152,768,lens)
            scene.render.filepath=str(EVIDENCE/f"{ident}-{label}.jpg")
            bpy.ops.render.render(write_still=True)
    if preview in ("all","pickups"):
        for ident in ("coal","iron_ore","iron_ingot"):
            scene=bpy.data.scenes[ident]
            bpy.context.window.scene=scene
            scene.render.filepath=str(RUNTIME/f"inventory_{ident}.png")
            bpy.ops.render.render(write_still=True)
    return str(EVIDENCE)
