"""Sculpt and paint the fitted game mesh in its standing pose, then bake the attack takes."""
from math import exp
from pathlib import Path
import runpy
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "art/characters/locomotion/player_locomotion.blend"


def bell(x, width):
    return exp(-(x / width) ** 2)


def skin_detail(name, position, normal):
    x,y,z = position
    ax = abs(x)
    front, rear = max(0.,normal.y), max(0.,-normal.y)
    outer = max(0., normal.x*(1 if x>0 else -1))
    rise = warm = shade = 0.
    if name == "SkyTorso":
        clavicle = bell(z-1.393+.17*ax,.014)*bell(ax-.091,.075)*front
        pectoral = bell(z-1.276+.11*ax,.055)*bell(ax-.096,.061)*front
        sternum = bell(ax,.018)*bell(z-1.273,.083)*front
        shoulder = bell(ax-.194,.039)*bell(z-1.35,.057)
        scapula = bell(ax-.103,.047)*bell(z-1.326,.065)*rear
        elbow = bell(z-1.142,.035)*bell(ax-.228,.045)
        rise = .0045*clavicle+.0065*pectoral-.0025*sternum+.006*shoulder+.004*scapula+.0022*elbow
        warm = .35*pectoral+.55*elbow
        shade = .62*sternum+.67*bell(z-1.24,.014)*bell(ax-.095,.059)*front+.38*elbow
    elif name == "SkyLegs":
        knee = bell(z-.506,.037)*front
        tendon = bell(z-.46,.035)*front
        calf = bell(z-.326+normal.x*(.020 if x>0 else -.020),.072)*(rear+.40*outer)
        shin = bell(z-.324,.102)*front
        quad = bell(z-.595,.055)*front*(1-.55*outer)
        rise = .0068*knee-.002*tendon+.0062*calf+.0026*shin+.0068*quad
        warm,shade = knee+.18*quad, .63*tendon+.31*calf+.34*bell(z-.48,.032)*rear
    elif name == "SkyFeet":
        ankle = bell(z-.076,.019)*outer
        instep = bell(z-.056,.024)*bell(y-.055,.042)*max(0.,normal.z)
        rise = .0033*ankle+.0025*instep
        warm,shade = .64*ankle+.50*bell(y-.15,.04),.31*instep
    elif name == "SkyHead":
        # Keep the optical frames and the portrait registration. Relief is confined to
        # the face, away from the neck seam, hairline and the fitted bridge of the glasses.
        cheek = bell(ax-.043,.022)*bell(z-1.598,.018)*front
        chin = bell(ax,.032)*bell(z-1.535,.011)*front
        philtrum = bell(ax-.006,.003)*bell(z-1.570,.009)*front
        rise = .0028*cheek+.0022*chin+.0013*philtrum
        warm,shade = .44*cheek,.16*philtrum
    return rise, warm, shade


def hand_detail(p, n, bones, side):
    wrist = bones["hand_"+side].head
    outward = Vector((1 if side=="R" else -1,0,0))
    dorsal = max(0.,n.dot(outward))
    pad = bell((p-wrist).length-.074,.027)
    knuckle = 0.
    tendon = 0.
    for digit in ("index","middle","ring","pinky"):
        base = bones[digit+"_01_"+side].head
        mid = bones[digit+"_02_"+side].head
        knuckle = max(knuckle,bell((p-base).length,.020),.72*bell((p-mid).length,.012))
        start = wrist.lerp(base,.22)
        line = base-start
        along = max(0.,min(1.,(p-start).dot(line)/line.length_squared))
        tendon = max(tendon,bell((p-start-line*along).length,.011)*bell(along-.53,.50))
    return (.0028*knuckle+.0021*tendon)*dorsal, knuckle+.23*pad, .40*pad+.35*tendon


def paint_hands(obj, samples, bones):
    """A dorsal and palmar unwrap share landmarks in the fitted standing hand."""
    mesh = obj.data
    material = mesh.materials[0].copy()
    material.name = "SkyHandsSkin"
    mesh.materials[0] = material
    tree = material.node_tree
    shader = next(n for n in tree.nodes if n.type=="BSDF_PRINCIPLED")
    source = shader.inputs["Base Color"].links[0].from_node.image
    palette = np.array(source.pixels[:]).reshape((source.size[1],source.size[0],4))
    uv = mesh.uv_layers.active
    paint = mesh.color_attributes.active_color
    wrist = bones["hand_R"].head.copy()
    base = np.ones((len(mesh.vertices),3))
    for face in mesh.polygons:
        dorsal = sum(samples[i][1].x * (1 if samples[i][0].x>0 else -1) for i in face.vertices) > 0
        for loop in face.loop_indices:
            idx = mesh.loops[loop].vertex_index
            u,v = uv.data[loop].uv
            base[idx] = palette[min(int(v*source.size[1]),source.size[1]-1),min(int(u*source.size[0]),source.size[0]-1),:3]
            p = samples[idx][0] - wrist
            uv.data[loop].uv = ((min(.998,max(.002,(p.y+.069)/.205)) + int(not dorsal))*.5,
                                 min(.998,max(.002,(p.z+.222)/.277)))
    skin_color = np.median(base,axis=0)
    for i, rgb in enumerate(base):
        tint = np.array(paint.data[i].color[:3])
        paint.data[i].color = (*np.minimum(1.,rgb*tint/skin_color),1.)

    n = 256
    v,u = np.mgrid[0:n,0:2*n]
    dorsal = u<n
    y = (u%n+.5)/n*.205-.069
    z = (v+.5)/n*.277-.222
    noise = np.random.default_rng(1807).standard_normal(y.shape)
    pink = np.zeros_like(y)
    crease = np.zeros_like(y)
    nail = np.zeros_like(y)
    ridge = np.zeros_like(y)
    def gaussian(x,width):
        return np.exp(-np.square(x/width))
    for finger in ("index","middle","ring","pinky","thumb"):
        for j in range(1,4):
            bone = bones[f"{finger}_{j:02d}_R"]
            p = bone.head-wrist
            dy = y-p.y
            width = .010 if finger!="pinky" else .008
            patch = gaussian(dy,width)*gaussian(z-p.z,.012)
            pink += patch*.48
            wrinkle = z-p.z+.0012*np.cos(dy/.004)
            crease += gaussian(dy,width*.85)*(gaussian(wrinkle,.00075)+.48*gaussian(wrinkle+.0024,.0007))
            ridge += np.where(dorsal,patch*.00075,.0001*patch)
        # Locate the nail on the actual distal skin rather than the bone tail.
        group = obj.vertex_groups[f"{finger}_03_R"].index
        points = [samples[q.index][0]-wrist for q in mesh.vertices if any(g.group==group and g.weight>.48 for g in q.groups)]
        if points:
            tip = min(points,key=lambda p:p.z)
            near = [p for p in points if p.z < tip.z+.013]
            cy = sum(p.y for p in near)/len(near)
            r = np.sqrt(((y-cy)/(.0058 if finger!="pinky" else .0047))**2+((z-tip.z-.008)/.0077)**2)
            nail += np.where(dorsal,np.clip((1-r)*9,0,1),0)
            crease += np.where(dorsal,gaussian(r-1.07,.16)*.82,0)
    line = z+.079+.36*y+.005*np.sin((y+.025)*47)
    palm = gaussian(line,.0011)*gaussian(y-.009,.036)
    palm += gaussian(z+.054-.91*y-.003*np.sin(y*77),.0012)*gaussian(y-.001,.031)
    crease = np.clip(crease+np.where(dorsal,0,palm),0,1.5)
    vein = gaussian(y-.013-.18*z-.005*np.sin(z*74),.0027)*gaussian(z+.042,.046)
    vein += gaussian(y+.009+.12*z-.004*np.sin(z*58),.0021)*gaussian(z+.046,.038)
    vein *= dorsal
    grain = .004*np.sin(u*.32+v*.13)*np.sin(v*.48-u*.067)+.003*noise
    value = .977 + grain - .104*crease - .023*vein
    warmth = np.clip(pink,0,1)+.32*(~dorsal)
    rgb = skin_color*np.stack((value-.015*vein,value-.030*warmth-.021*nail,value-.046*warmth-.009*nail),axis=-1)
    relief = ridge+.00039*nail-.00015*crease+.00007*grain/.01
    dv,du = np.gradient(relief,.277/n,.205/n)
    normal = np.stack((-du,-dv,np.ones_like(y)),axis=-1)
    normal /= np.linalg.norm(normal,axis=-1,keepdims=True)

    def packed_texture(name,colors,linear):
        image = bpy.data.images.new(name,width=2*n,height=n,alpha=False)
        image.colorspace_settings.name = "Non-Color" if linear else "sRGB"
        rgba = np.dstack((np.clip(colors,0,1),np.ones_like(y))).astype(np.float32)
        image.pixels.foreach_set(rgba.ravel())
        image.pack()
        node = tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        return node

    albedo = packed_texture("Hand creases and nail beds",rgb,False)
    tint = tree.nodes.new("ShaderNodeVertexColor")
    tint.layer_name = paint.name
    mix = tree.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.
    tree.links.new(albedo.outputs["Color"],mix.inputs[1])
    tree.links.new(tint.outputs["Color"],mix.inputs[2])
    tree.links.new(mix.outputs[0],shader.inputs["Base Color"])
    bumps = packed_texture("Knuckles and palm relief",normal*.5+.5,True)
    normal_map = tree.nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value=.52
    tree.links.new(bumps.outputs["Color"],normal_map.inputs["Color"])
    tree.links.new(normal_map.outputs[0],shader.inputs["Normal"])
    shader.inputs["Roughness"].default_value=.63


def inner_wrists(obj, samples, bones):
    part = obj.copy()
    part.data = obj.data.copy()
    part.name = part.data.name = "SkyInnerWrists"
    bpy.context.collection.objects.link(part)
    keep = {v.index for v in obj.data.vertices if samples[v.index][0].z < .975 and
            any(obj.vertex_groups[g.group].name.startswith(("forearm_","hand_")) and g.weight>.4 for g in v.groups)}
    for i in keep:
        p = samples[i][0]
        side = "R" if p.x>0 else "L"
        forearm = bones["forearm_"+side]
        wrist = bones["hand_"+side].head
        axis = (forearm.head-wrist).normalized()
        along = (p-wrist).dot(axis)
        center = wrist+axis*along
        pull = min(1.,max(0.,(along-.008)/.064))
        inverse = (forearm.matrix @ forearm.bone.matrix_local.inverted()).to_quaternion().inverted()
        part.data.vertices[i].co += inverse @ ((center-p)*(.36*pull))
    editable = bmesh.new()
    editable.from_mesh(part.data)
    bmesh.ops.delete(editable,geom=[v for v in editable.verts if v.index not in keep],context="VERTS")
    editable.to_mesh(part.data)
    editable.free()
    part.data.update()


def sculpt(rig):
    graph = bpy.context.evaluated_depsgraph_get()
    bones = rig.pose.bones
    for name in ("SkyTorso","SkyLegs","SkyFeet","SkyHands","SkyHead"):
        obj = bpy.data.objects[name]
        mesh = obj.data
        evaluated = obj.evaluated_get(graph).to_mesh()
        # Read presented-space landmarks, but displace along the bind-space surface.
        samples = [(v.co.copy(),v.normal.copy()) for v in evaluated.vertices]
        obj.evaluated_get(graph).to_mesh_clear()
        colors = mesh.color_attributes.new(name="Skin undertone",type="BYTE_COLOR",domain="POINT")
        mesh.color_attributes.active_color = colors
        for vertex, (point,normal) in zip(mesh.vertices,samples):
            if name=="SkyHands":
                side = "R" if point.x>0 else "L"
                rise,warm,shade = hand_detail(point,normal,bones,side)
            else:
                rise,warm,shade = skin_detail(name,point,normal)
            vertex.co += vertex.normal * rise
            colors.data[vertex.index].color = (1.-.070*shade,
                 1.-.143*shade-.086*warm,1.-.165*shade-.121*warm,1)
        mesh.update()
        if name=="SkyHands":
            paint_hands(obj,samples,bones)
        if name=="SkyTorso":
            inner_wrists(obj,samples,bones)
    # Multiply vertex paint with the original albedo in Blender and in glTF.
    for name in ("SkySkin","SkyPortrait"):
        mat = bpy.data.materials[name]
        tree = mat.node_tree
        shader = next(n for n in tree.nodes if n.type=="BSDF_PRINCIPLED")
        albedo = shader.inputs["Base Color"].links[0].from_socket
        paint = tree.nodes.new("ShaderNodeVertexColor")
        paint.layer_name = "Skin undertone"
        mix = tree.nodes.new("ShaderNodeMixRGB")
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1
        tree.links.new(albedo,mix.inputs[1])
        tree.links.new(paint.outputs["Color"],mix.inputs[2])
        tree.links.new(mix.outputs[0],shader.inputs["Base Color"])
        shader.inputs["Roughness"].default_value = .63 if name=="SkySkin" else .59


def bake(output):
    assert bpy.app.background
    bpy.ops.wm.open_mainfile(filepath=str(BASE))
    helper = runpy.run_path(str(ROOT/"scripts/bake-wild-people-locomotion.py"))
    melee = runpy.run_path(str(ROOT/"scripts/bake-human-attacks.py"))
    rig = helper["scene_rig"]()
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    stand = bpy.data.actions["Stand"]
    rig.animation_data.action = stand
    rig.animation_data.action_slot = stand.slots[0]
    bpy.context.scene.frame_set(1)
    sculpt(rig)
    melee["build_actions"](rig,helper,player=True)
    rig.animation_data.action = stand
    rig.animation_data.action_slot = stand.slots[0]
    bpy.context.scene.frame_set(1)
    shorts = next(obj for obj in rig.children if obj.type=="MESH" and obj.name.startswith("SkyShorts"))
    placeholder = bpy.data.objects.get("SkyShorts")
    if placeholder is not None and placeholder != shorts:
        placeholder.name = "Imported shorts transform"
    shorts.name = "SkyShorts"
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [rig, *(child for child in rig.children if child.type=="MESH")]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.context.preferences.filepaths.save_version = 0
    output.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output/"sky_field_character.blend"),compress=True)
    rig.animation_data.action = None
    export_clips = {"Stand","Sit",*melee["TAKES"]} - {"Throw"}
    for obj in (rig, shorts.data.shape_keys):
        if obj and obj.animation_data:
            obj.animation_data.action = None
            for track in list(obj.animation_data.nla_tracks):
                if track.name not in export_clips:
                    obj.animation_data.nla_tracks.remove(track)
                else:
                    track.mute = False
    bpy.ops.export_scene.gltf(filepath=str(output/"sky_character.glb"),export_format="GLB",use_selection=True,
        export_animation_mode="NLA_TRACKS",export_force_sampling=True,export_anim_slide_to_zero=True,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_morph_normal=False,
        export_extras=True,export_cameras=False,export_lights=False)


if __name__ == "__main__":
    bake(Path(sys.argv[sys.argv.index("--")+1]).resolve())
