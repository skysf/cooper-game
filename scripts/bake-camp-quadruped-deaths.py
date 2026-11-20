"""Bake the crocodile collapse and mastiff side pose in Blender background MCP."""
from __future__ import annotations

import json
from math import radians, sqrt
from pathlib import Path
import struct

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector


UP = Vector((0, 0, 1))
FORWARD = Vector((0, 1, 0))
BONE_GROUPS = ("Fore.L", "Fore.R", "Hind.L", "Hind.R")
CROC_TIMING = (
    # Phase, weight transfer, pitch, roll, neck, jaw, tail response, lift, torso twist.
    (0.00, 0.00, 0.0, 0.0, 0.0, 0.0, 0.0, 0.000, 0.0),
    (0.14, 0.10, 0.8, -3.4, 1.4, -4.3, -0.3, .017, -2.6),
    (0.32, 0.32, -0.9, -2.5, 0.3, -6.7, 1.0, .005, 2.4),
    (0.58, 0.88, 0.5, 5.1, -3.8, -4.1, -1.1, 0.000, 1.4),
    (0.78, 1.00, 0.2, 3.7, -4.4, -2.2, 0.34, .005, 0.3),
    (1.00, 1.00, 0.1, 3.8, -4.6, -2.6, 0.0, 0.000, 0.0),
)
CROC_FEET = {
    "Fore.L": (-.12, .031, -4.0, 13.0),
    "Fore.R": (.146, -.105, 1.0, -19.0),
    "Hind.L": (-.077, -.108, 2.0, 13.0),
    "Hind.R": (.072, .063, 1.0, -12.0),
}
TAIL_ENDS = (.194, .166, .143, .123, .109, .098, .089)
TAIL_BEND = (7.0, 5.0, 3.0, -3.7, -5.0, -3.2, 0.4)


def pose_state(rig):
    return {b.name:(b.location.copy(), b.rotation_quaternion.copy(), b.scale.copy()) for b in rig.pose.bones}


def apply_pose(rig, pose):
    for bone in rig.pose.bones:
        bone.location, bone.rotation_quaternion, bone.scale = pose[bone.name]
    bpy.context.view_layer.update()


def action(data, clip):
    data.action = clip
    if clip is not None:
        data.action_slot = clip.slots[0]


def sample_source(rig, clip_name, frame):
    action(rig.animation_data, bpy.data.actions[clip_name])
    bpy.context.scene.frame_set(frame)
    pose = pose_state(rig)
    measured = {b.name: (b.matrix.copy(), b.tail.copy()) for b in rig.pose.bones}
    action(rig.animation_data, None)
    return pose, measured


def interpolate_pose(first, second, value):
    return {name:(loc.lerp(second[name][0],value), rot.slerp(second[name][1],value),
                  scale.lerp(second[name][2],value)) for name,(loc,rot,scale) in first.items()}


def values(curve, phase):
    for first, second in zip(curve, curve[1:]):
        if phase <= second[0]:
            t = (phase-first[0])/(second[0]-first[0])
            t = t*t*(3.0-2.0*t)
            return [a+(b-a)*t for a,b in zip(first[1:],second[1:])]
    return curve[-1][1:]


def set_rotation(bone, rotation):
    bone.matrix = Matrix.LocRotScale(bone.head,rotation,bone.matrix.to_scale())
    bpy.context.view_layer.update()


def turn(bone, x=0.0, y=0.0, z=0.0):
    change = Euler(tuple(radians(v) for v in (x,y,z)), "XYZ").to_quaternion()
    set_rotation(bone,change @ bone.matrix.to_quaternion())


def lift_root(root, amount):
    root.location += root.bone.matrix_local.to_quaternion().inverted() @ UP * amount
    bpy.context.view_layer.update()


def align(bone, direction):
    old = bone.matrix.to_quaternion()
    axis = old @ FORWARD
    set_rotation(bone,axis.rotation_difference(direction) @ old)


def point_end(bone, direction, end_z):
    vertical = max(-.95*bone.length,min(.95*bone.length,end_z-bone.head.z))
    along = Vector((direction.x,direction.y,0)).normalized()*sqrt(bone.length**2-vertical**2)
    along.z = vertical
    align(bone,along)


def limb(rig, name):
    family,side = name.split(".")
    return [rig.pose.bones[f"{family}.{part}.{side}"] for part in ("Upper","Lower","Paw")]


def plant(upper, lower, paw, target, final_orientation, elbow_lift=0.0):
    hip = upper.head.copy()
    d = target-hip
    axis = d.normalized()
    a, b = upper.length, lower.length
    reach = min(max(d.length,abs(a-b)+.002),a+b-.002)
    elbow_along = (reach*reach+a*a-b*b)/(2*reach)
    bend = lower.head-hip
    pole = (bend-axis*bend.dot(axis)).normalized()
    if elbow_lift > 0:
        pole = (pole+(UP-axis*UP.dot(axis))*elbow_lift).normalized()
    elbow = hip + axis*elbow_along + pole*sqrt(max(0,a*a-elbow_along*elbow_along))
    align(upper,elbow-hip)
    align(lower,hip+axis*reach-lower.head)
    set_rotation(paw,final_orientation)


def contact_regions(mesh, species):
    groups = {}
    support = (".Paw.",".Lower.") if species=="crocodile" else (".Paw.",)
    bone_groups = {g.index:g.name for g in mesh.vertex_groups if any(key in g.name for key in support)}
    for name in bone_groups.values():
        groups[name]=[]
    groups["torso"],groups["face"],groups["tail"] = [],[],[]
    if species=="crocodile":
        for i in range(7):
            groups[f"tail_section_{i}"] = []
    for v in mesh.data.vertices:
        x,y,z = v.co
        for w in v.groups:
            if w.group in bone_groups and w.weight>.43:
                groups[bone_groups[w.group]].append(v.index)
        if species == "crocodile":
            if -.42<y<.41 and abs(x)<.215 and z<.185:
                groups["torso"].append(v.index)
            if y>.65 and abs(x)<.39:
                groups["face"].append(v.index)
            if y<-.61:
                groups["tail"].append(v.index)
                index = min(6,max(0,int((-y-.449)/.2543)))
                groups[f"tail_section_{index}"].append(v.index)
        else:
            if -.31<y<.235 and abs(x)>.086 and z>.34:
                groups["torso"].append(v.index)
            if y>.294 and z>.62:
                groups["face"].append(v.index)
            if y<-.335 and z>.51:
                groups["tail"].append(v.index)
    return groups


def contacts(mesh, groups):
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    points = [v.co.copy() for v in evaluated.data.vertices]
    bottom = {name:min(points[i].z for i in ids) for name,ids in groups.items()}
    lo, hi = [[fn(co[a] for co in points) for a in range(3)] for fn in (min,max)]
    return {"low":lo,"high":hi,"contacts":bottom}


def ground_chin(rig, mesh, groups, low=.006):
    """Keep the closed lower jaw clear without pulling the torso away from contact."""
    head = rig.pose.bones["Head"]
    for _ in range(2):
        floor = contacts(mesh,groups)["contacts"]["face"]
        if floor >= low:
            break
        turn(head,x=min(9.0,105.0*(low-floor)))


def support_tail(rig, mesh, groups, walking_bones, weight, tail, brace):
    chain=[rig.pose.bones[f"Tail.{i+1:02d}"] for i in range(7)]
    heights,heading=[],[]
    bend=0.0
    for i,bone in enumerate(chain):
        home = walking_bones[bone.name][1].z
        heights.append(home+(TAIL_ENDS[i]-home)*weight+max(0.0,brace*(1-.11*i)))
        bend += TAIL_BEND[i]*weight+tail*(2.2+.77*i)
        heading.append(Quaternion(UP,radians(bend)) @ (bone.tail-bone.head))
    for iteration in range(3):
        for bone, direction, height in zip(chain,heading,heights):
            point_end(bone,direction,height)
        if iteration==2:
            break
        taps=contacts(mesh,groups)["contacts"]
        corrections=[0.0]*7
        for i in range(7):
            rise=max(0.0,.005-taps[f"tail_section_{i}"])*1.15
            corrections[i]=max(corrections[i],rise)
            if i>0:
                corrections[i-1]=max(corrections[i-1],rise)
        if max(corrections)<.0004:
            break
        heights=[h+c for h,c in zip(heights,corrections)]


def crocodile_pose(rig, mesh, groups, walking, walking_bones, basking, basking_bones, phase):
    if phase == 0:
        apply_pose(rig,walking)
        return
    weight,pitch,roll,neck,jaw,tail,brace,twist = values(CROC_TIMING,phase)
    apply_pose(rig,interpolate_pose(walking,basking,weight*.93))
    bones = rig.pose.bones
    root = bones["Root"]
    rest = root.bone.matrix_local.to_quaternion()
    root.location += rest.inverted() @ Vector((.024*weight,.046*weight,brace))
    bpy.context.view_layer.update()
    turn(root,pitch,roll,0)
    turn(bones["Pelvis"],1.6*weight,1.1*weight,-.6*twist)
    turn(bones["Spine"],-.9*weight,.3*weight,twist)
    turn(bones["Chest"],-1.8*weight,0,-.36*twist)
    turn(bones["Neck"],neck,0,1.6*weight)
    turn(bones["Head"],-.32*neck,1.2*weight,.7*tail)
    turn(bones["Jaw"],jaw)

    body = contacts(mesh,groups)["contacts"]["torso"]
    reference = .033*(1.0-weight)+.006*weight+brace
    lift_root(root,max(-.16,min(.16,reference-body)))
    ground_chin(rig,mesh,groups)

    support_tail(rig,mesh,groups,walking_bones,weight,tail,brace)

    targets = {}
    for name in BONE_GROUPS:
        upper, lower, paw = limb(rig,name)
        dx,dy,toe,flare = CROC_FEET[name]
        lag = .14 if name=="Fore.L" else .06 if name=="Hind.R" else .0
        move = min(1.0,max(0.0,(weight-lag)/(1-lag)))
        planted = walking_bones[paw.name][0].translation
        settle = basking_bones[paw.name][0].translation
        at = planted.lerp(settle,move*.44)
        at += Vector((dx*move,dy*move,0.0))
        # The front-left toes bear the last push; the other front foot slips forward
        # a few centimetres and opens out as the shoulders lose support.
        if name=="Fore.R":
            at.y += .053*max(0.0,1-abs(phase-.29)/.24)
        ending = Quaternion(UP,radians(flare*move)) @ Quaternion((1,0,0),radians(toe*move))
        old_orientation = walking_bones[paw.name][0].to_quaternion()
        ending = ending @ old_orientation.slerp(basking_bones[paw.name][0].to_quaternion(),move*.40)
        targets[name]=(at,ending)
        plant(upper,lower,paw,at,ending)

    for _ in range(3):
        region = contacts(mesh,groups)["contacts"]
        for name,(at,ending) in targets.items():
            upper,lower,paw = limb(rig,name)
            desired = .004
            if name=="Fore.L" and phase<.43:
                desired += max(0.,1-abs(phase-.12)/.21)*.013
            at.z += min(.075,max(-.095,desired-region[paw.name]))
            elbow_lift = max(0.0,min(.66,(.004-region[lower.name])*29.0))
            plant(upper,lower,paw,at,ending,elbow_lift)
    bottom = contacts(mesh,groups)["low"][2]
    if bottom < -.002:
        lift_root(root,.002-bottom)


def mastiff_pose(rig, mesh, groups, resting, idle):
    relaxed = {"Fore.Upper.L":.34, "Fore.Lower.L":.52, "Fore.Paw.L":.38,
               "Fore.Upper.R":.17, "Fore.Lower.R":.25, "Fore.Paw.R":.18}
    mixed = {}
    for name,(loc,rot,scale) in resting.items():
        amount = relaxed.get(name,0.0)
        if name.startswith("Hind."):
            amount = .42 if name.endswith(".L") else .27
        mixed[name]=(loc.lerp(idle[name][0],amount),rot.slerp(idle[name][1],amount),scale.copy())
    apply_pose(rig,mixed)
    b = rig.pose.bones
    root = b["Root"]
    pivot = Vector((0.0,-.045,.258))
    laying = Quaternion(FORWARD,radians(81.0)) @ Quaternion((1,0,0),radians(-2.5))
    offset = pivot-laying @ pivot
    root.location += root.bone.matrix_local.to_quaternion().inverted() @ Vector((offset.x+.011,offset.y,0.0))
    bpy.context.view_layer.update()
    set_rotation(root,laying @ root.matrix.to_quaternion())
    turn(b["Pelvis"],2.0,-4.0,-4.0)
    turn(b["Spine"],-1.7,1.8,3.0)
    turn(b["Chest"],1.3,4.5,.5)
    turn(b["Neck"],-22.0,-8.0,1.7)
    turn(b["Head"],-16.0,3.6,-4.0)
    turn(b["Jaw"],1.8)
    for joint,angles in {
        "Fore.Upper.L":(4,3,-6), "Fore.Lower.L":(2,-7,5), "Fore.Paw.L":(-9,-9,-4),
        "Fore.Upper.R":(-3,-8,-10), "Fore.Lower.R":(3,9,9), "Fore.Paw.R":(8,7,-8),
        "Hind.Upper.L":(-8,2,10), "Hind.Lower.L":(1,-9,8), "Hind.Hock.L":(-2,0,-7),
        "Hind.Upper.R":(4,4,-11), "Hind.Lower.R":(5,4,6), "Hind.Paw.R":(12,-3,7),
        "Tail.01":(5,-13,17), "Tail.02":(-6,5,-6),
    }.items():
        turn(b[joint],*angles)
    low = contacts(mesh,groups)["contacts"]["torso"]
    lift_root(root,.009-low)
    upper,lower,paw=limb(rig,"Fore.L")
    relaxed=paw.head+Vector((-.010,.055,0.0))
    relaxed.z=.226
    orientation=Quaternion((0,1,0),radians(-16)) @ paw.matrix.to_quaternion()
    plant(upper,lower,paw,relaxed,orientation)
    hock=b["Hind.Hock.L"]
    hind_point=hock.head+Vector((.012,.024,0.0))
    hind_point.z=.193
    plant(b["Hind.Upper.L"],b["Hind.Lower.L"],hock,hind_point,hock.matrix.to_quaternion())
    point_end(hock,hock.tail-hock.head,.126)
    toe=b["Hind.Paw.L"]
    turn(toe,x=9.0,y=-16.0)
    neck=b["Neck"]
    head=b["Head"]
    head_orientation=head.matrix.to_quaternion()
    cheek = contacts(mesh,groups)["contacts"]["face"]
    neck_end=neck.tail.z-min(.055,max(0.0,cheek-.019))
    point_end(neck,neck.tail-neck.head,neck_end)
    set_rotation(head,head_orientation)
    ground_chin(rig,mesh,groups,.008)
    lowest = contacts(mesh,groups)["low"][2]
    if lowest < .001:
        lift_root(root,.002-lowest)


def insert_pose(rig, frame):
    for bone in rig.pose.bones:
        for property_name in ("location", "rotation_quaternion", "scale"):
            bone.keyframe_insert(data_path=property_name, frame=frame, group=bone.name)


def new_action(rig, name):
    clip = bpy.data.actions.new(name)
    rig.animation_data.action = clip
    return clip


def record(rig, mesh, groups, seconds):
    data = contacts(mesh,groups)
    data["time"] = seconds
    data["root"] = list(rig.pose.bones["Root"].head)
    data["joints"] = {b.name:list(b.head) for b in rig.pose.bones}
    return data


def bake_crocodile(rig, mesh, groups):
    walk,walk_bones = sample_source(rig,"Walk-loop",1)
    idle,idle_bones = sample_source(rig,"Idle-loop",1)
    clip = new_action(rig,"Collapse")
    report = []
    for i in range(28):
        crocodile_pose(rig,mesh,groups,walk,walk_bones,idle,idle_bones,i/27.0)
        insert_pose(rig,i+1)
        report.append(record(rig,mesh,groups,i/30.0))
    result = pose_state(rig)
    action(rig.animation_data,None)
    return clip,result,report


def clean_clip(rig, mesh, groups, still):
    clip = new_action(rig,"Dead")
    apply_pose(rig,still)
    for frame in (1,4):
        insert_pose(rig,frame)
    sample = record(rig,mesh,groups,.1)
    action(rig.animation_data,None)
    return clip,sample


def unpack_glb(path):
    raw = path.read_bytes()
    json_len, chunk = struct.unpack_from("<I4s",raw,12)
    assert chunk == b"JSON"
    data = json.loads(raw[20:20+json_len])
    length,chunk = struct.unpack_from("<I4s",raw,20+json_len)
    assert chunk == b"BIN\0"
    return data,raw[28+json_len:28+json_len+length]


def append_animations(base, candidate, target, names):
    """Keep the mesh, skin, PBR images, and all previously published animation data."""
    doc,base_bin = unpack_glb(base)
    source,animation_bin = unpack_glb(candidate)
    binary = bytearray(base_bin)
    node_lookup = {node["name"]:i for i,node in enumerate(doc["nodes"])}
    assert len(node_lookup)==len(doc["nodes"])
    assert [x["name"] for x in doc["images"]] == [x["name"] for x in source["images"]]
    assert len(doc["skins"])==len(source["skins"])==1
    if max(abs(a-b) for a,b in zip(
        [v for m in doc["meshes"] for p in m["primitives"] for v in
         doc["accessors"][p["attributes"]["POSITION"]]["min"]],
        [v for m in source["meshes"] for p in m["primitives"] for v in
         source["accessors"][p["attributes"]["POSITION"]]["min"]],
    )) > .00001:
        raise ValueError("Candidate is not based on the published mesh")
    accessor_map = {}
    view_map = {}

    def add_accessor(idx):
        if idx in accessor_map:
            return accessor_map[idx]
        access = source["accessors"][idx].copy()
        idx_view = access["bufferView"]
        if idx_view not in view_map:
            view = source["bufferViews"][idx_view].copy()
            start = view.get("byteOffset",0)
            binary.extend(b"\0" * (-len(binary)%4))
            view["byteOffset"] = len(binary)
            binary.extend(animation_bin[start:start+view["byteLength"]])
            view_map[idx_view] = len(doc["bufferViews"])
            doc["bufferViews"].append(view)
        access["bufferView"] = view_map[idx_view]
        accessor_map[idx] = len(doc["accessors"])
        doc["accessors"].append(access)
        return accessor_map[idx]

    for name in names:
        entry = next(a for a in source["animations"] if a["name"]==name)
        for channel in entry["channels"]:
            old = source["nodes"][channel["target"]["node"]]
            mapped = node_lookup[old["name"]]
            dst = doc["nodes"][mapped]
            for prop,default in {"translation":(0,0,0),"rotation":(0,0,0,1),"scale":(1,1,1)}.items():
                side = old.get(prop,default)
                original = dst.get(prop,default)
                if prop=="rotation" and sum(a*b for a,b in zip(side,original))<0:
                    side = [-q for q in side]
                if any(abs(a-b)>.00001 for a,b in zip(side,original)):
                    raise ValueError(f"{old['name']} differs at its {prop}")
            channel["target"]["node"] = mapped
        for sampler in entry["samplers"]:
            for key in ("input","output"):
                sampler[key] = add_accessor(sampler[key])
        doc["animations"].append(entry)
    binary.extend(b"\0" * (-len(binary)%4))
    doc["buffers"][0]["byteLength"] = len(binary)
    meta=json.dumps(doc,separators=(",",":")).encode()
    meta += b" "*(-len(meta)%4)
    with target.open("wb") as stream:
        stream.write(struct.pack("<4sII",b"glTF",2,28+len(meta)+len(binary)))
        stream.write(struct.pack("<I4s",len(meta),b"JSON")+meta)
        stream.write(struct.pack("<I4s",len(binary),b"BIN\0"))
        stream.write(binary)
    assert target.read_bytes()[0:4]==b"glTF"


def bake(species, output, original_glb):
    assert bpy.app.background and bpy.context.scene.render.fps==30
    out=Path(output).resolve()
    original=Path(bpy.data.filepath).resolve()
    stem=f"camp_{species}"
    assert original.stem==stem and original.parent!=out
    out.mkdir(parents=True,exist_ok=True)
    rig=bpy.data.objects[{"crocodile":"Crocodile Rig","mastiff":"Mastiff Rig"}[species]]
    mesh=bpy.data.objects[{"crocodile":"Camp Crocodile","mastiff":"Camp Mastiff"}[species]]
    assert rig.matrix_world==Matrix.Identity(4)==mesh.matrix_world
    tracks = list(rig.animation_data.nla_tracks)
    for track in tracks:
        track.mute=True
    groups=contact_regions(mesh,species)
    clips=[]
    metrics={}
    if species=="crocodile":
        collapse,pose,metrics["Collapse"] = bake_crocodile(rig,mesh,groups)
        clips.append(collapse)
    else:
        rest,_=sample_source(rig,"Rest-loop",18)
        idle,_=sample_source(rig,"Idle-loop",1)
        mastiff_pose(rig,mesh,groups,rest,idle)
        pose=pose_state(rig)
    dead,metrics["Dead"]=clean_clip(rig,mesh,groups,pose)
    clips.append(dead)
    frame=max(strip.frame_end for track in tracks for strip in track.strips)+10
    for clip in clips:
        track=rig.animation_data.nla_tracks.new()
        track.name=clip.name
        strip=track.strips.new(clip.name,int(frame),clip)
        frame=strip.frame_end+9
    for track in tracks:
        track.mute=False
    bpy.context.scene.frame_end=int(frame)-9
    bpy.context.scene.frame_set(bpy.context.scene.frame_start)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(out/(stem+".blend")),compress=True)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    mesh.select_set(True)
    candidate=out/(stem+"-full.glb")
    bpy.ops.export_scene.gltf(filepath=str(candidate),export_format="GLB",use_selection=True,
        export_animations=True,export_animation_mode="NLA_TRACKS",export_force_sampling=True,
        export_anim_slide_to_zero=True,export_cameras=False,export_lights=False)
    append_animations(Path(original_glb),candidate,out/(stem+".glb"),[clip.name for clip in clips])
    candidate.unlink()
    (out/(stem+"-blender.json")).write_text(json.dumps(metrics,indent=2)+"\n")
    samples=metrics.get("Collapse",[]) + [metrics["Dead"]]
    return {"existing":len(tracks),"tracks":[clip.name for clip in clips],
            "samples": [(sample["time"],sample["low"][2],sample["contacts"]) for sample in samples[::max(1,len(samples)//5)]],
            "dead":metrics["Dead"]["contacts"]}


def render(species, output):
    """Render live and baked poses with fixed cameras in the isolated source copy."""
    assert bpy.app.background
    scene = bpy.context.scene
    rig = next(o for o in scene.objects if o.type=="ARMATURE")
    assert bpy.data.actions.get("Dead") is not None
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    out = Path(output).resolve()
    out.mkdir(parents=True,exist_ok=True)
    target = Vector((0,-.48,.19)) if species=="crocodile" else Vector((-.02,-.01,.24))
    camera_data = bpy.data.cameras.new("Pose review")
    camera = bpy.data.objects.new("Pose review",camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 3.83 if species=="crocodile" else 1.37

    world = bpy.data.worlds.new("Overcast shore")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (.48,.55,.62,1.0)
    background.inputs["Strength"].default_value = .45
    for name,at,energy,size,color in (
        ("Shore daylight",(-2.50,3.1,4.2),520,4.6,(1.0,.89,.74)),
        ("Sky fill",(3.0,-1.2,3.2),260,4.0,(.75,.87,1.0)),
    ):
        lamp=bpy.data.lights.new(name,"AREA")
        lamp.energy=energy
        lamp.size=size
        lamp.color=color
        obj=bpy.data.objects.new(name,lamp)
        scene.collection.objects.link(obj)
        obj.location=at
        obj.rotation_euler=(target-obj.location).to_track_quat("-Z","Y").to_euler()
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.002))
    stage = bpy.context.object
    ground = bpy.data.materials.new("Neutral granite-green bank")
    ground.diffuse_color = (.12,.144,.107,1.0)
    ground.use_nodes = True
    shader = ground.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = ground.diffuse_color
    shader.inputs["Roughness"].default_value = .96
    stage.data.materials.append(ground)
    scene.render.engine="CYCLES"
    scene.cycles.samples=15
    scene.cycles.use_denoising=True
    scene.render.resolution_x,scene.render.resolution_y = 992,586
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="JPEG"
    scene.render.image_settings.quality=91
    scene.view_settings.view_transform="AgX"
    camera_main = (-4.3,1.8,1.6) if species=="crocodile" else (-1.62,.79,.69)
    camera_front = (3.3,4.2,2.03) if species=="crocodile" else (1.50,1.02,.54)
    if species=="crocodile":
        jobs = [("stance","Collapse",1,camera_main),("support","Collapse",7,camera_main),
                ("descent","Collapse",15,camera_main),("dead","Dead",2,camera_main),
                ("dead-front","Dead",2,camera_front)]
    else:
        jobs = [("rest","Rest-loop",18,camera_main),("dead","Dead",2,camera_main),
                ("dead-front","Dead",2,camera_front)]
    for token,clip,frame,at in jobs:
        camera.location=at
        camera.rotation_euler=(target-camera.location).to_track_quat("-Z","Y").to_euler()
        action(rig.animation_data,bpy.data.actions[clip])
        scene.frame_set(frame)
        scene.render.filepath=str(out/(token+".jpg"))
        bpy.ops.render.render(write_still=True)
    return [str(out/(p[0]+".jpg")) for p in jobs]
