"""Build the Rainline camp iron furnace in a separate Blender scene."""

import math
from math import cos, pi, sin, tau
from pathlib import Path
import random

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ROCK_TEXTURES = ROOT / "coop" / "coast"


def material(name, color, roughness, metallic=0):
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*color, 1)
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return result


def masonry_material(name, shade):
    result = material(name, (0.14 * shade, 0.12 * shade, 0.10 * shade), 0.91)
    tree = result.node_tree
    shader = tree.nodes.get("Principled BSDF")
    for filename, target in [("cliff_color.jpg", "Base Color"), ("cliff_normal.jpg", "Normal")]:
        texture = tree.nodes.new("ShaderNodeTexImage")
        texture.image = bpy.data.images.load(str(ROCK_TEXTURES / filename), check_existing=True)
        texture.image.pack()
        if target == "Normal":
            texture.image.colorspace_settings.name = "Non-Color"
            normal = tree.nodes.new("ShaderNodeNormalMap")
            normal.inputs["Strength"].default_value = 0.63
            tree.links.new(texture.outputs["Color"], normal.inputs["Color"])
            tree.links.new(normal.outputs["Normal"], shader.inputs[target])
        else:
            mix = tree.nodes.new("ShaderNodeMixRGB")
            mix.blend_type = "MULTIPLY"
            mix.inputs[0].default_value = 1.0
            mix.inputs[2].default_value = (shade, shade * .92, shade * .80, 1)
            tree.links.new(texture.outputs["Color"], mix.inputs[1])
            tree.links.new(mix.outputs[0], shader.inputs[target])
    return result


def mesh(collection, name, vertices, faces, surface, bevel=0.0):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    data.materials.append(surface)
    if bevel:
        edge = obj.modifiers.new("Rounded chipped edges", "BEVEL")
        edge.width = bevel
        edge.segments = 2
        normals = obj.modifiers.new("Weighted surface normals", "WEIGHTED_NORMAL")
        normals.keep_sharp = True
    return obj


def ring_block(collection, name, radius, inner, y_scale, bearing, half, bottom, top, surface, rng):
    vertices = []
    origin_u, origin_v = rng.random(), rng.random()
    for z in (bottom, top):
        for r in (radius, inner):
            for a in (bearing - half, bearing, bearing + half):
                rr = r + rng.uniform(-.015, .016)
                zz = z + rng.uniform(-.012, .014) * min(1, z * 14)
                vertices.append((rr * cos(a), y_scale * rr * sin(a), zz))
    faces = [(6,7,1,0), (7,8,2,1), (5,11,10,4), (4,10,9,3), (3,9,6,0), (2,8,11,5),
             (6,9,10,7), (7,10,11,8), (0,1,4,3), (1,2,5,4)]
    stone = mesh(collection, name, vertices, faces, surface, bevel=.017)
    uv = stone.data.uv_layers.new(name="Stone UV")
    # Shared metres-to-texture scale on radial faces, ends and horizontal ledges.
    outward = Vector((cos(bearing), sin(bearing), 0))
    for face in stone.data.polygons:
        if abs(face.normal.z) >= .6:
            u_axis = Vector((-sin(bearing), cos(bearing), 0))
            v_axis = outward
        else:
            u_axis = Vector((-face.normal.y, face.normal.x, 0)).normalized()
            v_axis = Vector((0, 0, 1))
        for loop in face.loop_indices:
            point = stone.data.vertices[stone.data.loops[loop].vertex_index].co
            uv.data[loop].uv = (origin_u + 1.72 * u_axis.dot(point), origin_v + 1.72 * v_axis.dot(point))
    return stone


def lining(collection, surface, name, rings, opening=False):
    segments = 28
    vertices = [(r * cos(i * tau / segments), r * sin(i * tau / segments) * .9, z)
                for z, r in rings for i in range(segments)]
    faces = []
    for row, (z, _) in enumerate(rings[:-1]):
        for i in range(segments):
            angle = (i+.5)*tau/segments
            if opening and .16 <= z < .43 and abs(math.remainder(angle-pi/2,tau)) < .45:
                continue
            next_i = (i+1)%segments
            faces.append((row*segments+i,row*segments+next_i,(row+1)*segments+next_i,(row+1)*segments+i))
    shell = mesh(collection, name, vertices, faces, surface, bevel=.006)
    uv = shell.data.uv_layers.new(name="Stone UV")
    for face in shell.data.polygons:
        section = [i % segments for i in face.vertices]
        at_seam = segments - 1 in section and 0 in section
        for loop in face.loop_indices:
            vertex = shell.data.loops[loop].vertex_index
            row, angle = divmod(vertex, segments)
            angle = segments if at_seam and angle == 0 else angle
            z, radius = rings[row]
            slope = abs(face.normal.z)
            uv.data[loop].uv = (
                angle * 2.0 / segments, (z * (1.0 - slope) + radius * slope) * 2.0)
    return shell


def forged_band(collection, name, surface, radius, height, width):
    rounds = [(height, radius+.016), (height+width, radius+.012),
              (height+width, radius-.012), (height, radius-.012), (height, radius+.016)]
    lining(collection, surface, name, rounds)


def create():
    scene = bpy.data.scenes.new("Rainline fieldstone iron furnace")
    objects = bpy.data.collections.new("Fieldstone furnace")
    scene.collection.children.link(objects)
    rng = random.Random(729014)
    stone = masonry_material("Fieldstone with weathered faces", .84)
    soot = masonry_material("Firebox stone with soot", .37)
    clay = material("Vitrified clay lining", (.094, .050, .032), .86)
    iron = material("Oxidized forged rim", (.074, .058, .047), .66, .82)
    ground = material("Cold firebox", (.035, .026, .02), .97)
    ember = material("Furnace ember", (.16, .053, .018), .79)
    glow = ember.node_tree.nodes.get("Principled BSDF")
    glow.inputs["Emission Color"].default_value = (1.0, .16, .027, 1)
    glow.inputs["Emission Strength"].default_value = 0.0

    courses = [(0., .16, .533, 13), (.14, .31, .497, 13), (.286, .445, .482, 12),
               (.423, .589, .474, 12), (.566, .729, .445, 11), (.705, .865, .402, 10),
               (.842, .987, .366, 10), (.964, 1.096, .352, 9)]
    for course, (bottom, top, radius, count) in enumerate(courses):
        rotation = pi / 2 + (0 if course % 2 else pi/count)
        for i in range(count):
            angle = rotation + i*tau/count
            distance = abs(math.remainder(angle - pi/2, tau))
            if course in (1, 2) and distance < (.44 if course == 1 else .37):
                continue
            outer = radius + rng.uniform(-.017, .018)
            shade = soot if course in (1, 2, 3) and distance < .82 else stone
            ring_block(objects, f"Course {course+1}, stone {i+1}", outer, outer-.138, .9,
                       angle, pi/count-rng.uniform(.012,.039), bottom, top, shade, rng)

    lining(objects, soot, "Recessed mortar and insulated shaft",
           [(.012,.401),(.16,.405),(.30,.372),(.43,.349),(.58,.34),(.72,.32),(.86,.28),(1.088,.249)], opening=True)
    lining(objects, clay, "Open clay-lined top", [(1.09,.307), (1.13,.298), (1.13,.249), (1.095,.23), (.60,.24), (.52,.275)])
    forged_band(objects, "Dark forged waist band", iron, .43, .66, .041)
    forged_band(objects, "Pinned top rim", iron, .315, 1.080, .026)
    lining(objects, ground, "Dark clay base inside hearth", [(.177, .02), (.177, .32), (.228,.334)])
    for i in range(26):
        a = rng.uniform(0, tau)
        radius = rng.uniform(.08, .33)
        height = rng.uniform(.19, .224)
        ring_block(objects, f"Ember bed {i+1:02d}", radius+.052, radius, .91, a,
                   rng.uniform(.07,.17), height, height+rng.uniform(.024,.043),
                   ember if i % 4 == 0 else ground, rng)
    for i in (-1, 0, 1):
        # The sill joins the opening to the ash on the courtyard ground.
        ring_block(objects, f"Firebox sill {i:+d}", .568, .41, .94,
                   pi/2+i*.23, .107, .006, .103, soot, rng)
    return scene, objects


def render(scene, collection, path):
    def target(obj, point):
        obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()

    camera = bpy.data.objects.new("Furnace review camera", bpy.data.cameras.new("Furnace lens"))
    collection.objects.link(camera)
    camera.location = (1.84, 2.45, 1.51)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.78
    target(camera, (0,0,.54))
    scene.camera = camera
    for name, location, energy, size, color in [
        ("Warm side light", (1.3, 2.2, 3.4), 415, 2.7, (1,.86,.72)),
        ("Open sky", (-2.0, .6, 2.3), 330, 2.4, (.72,.84,1)),
    ]:
        data = bpy.data.lights.new(name, "AREA")
        data.energy, data.shape, data.size, data.color = energy, "DISK", size, color
        light = bpy.data.objects.new(name, data)
        collection.objects.link(light)
        light.location = location
        target(light, (0,0,.48))
    scene.world = bpy.data.worlds.new("Furnace studio")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes.get("Background").inputs["Color"].default_value = (.26,.29,.34,1)
    scene.world.node_tree.nodes.get("Background").inputs["Strength"].default_value = .4
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 20
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = 900
    scene.render.image_settings.file_format = "JPEG"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True, scene=scene.name)


def export_existing(output, review=None):
    scene = bpy.context.scene
    collection = scene.collection.children["Fieldstone furnace"]
    if review:
        render(scene, collection, review)
    copies = bpy.data.collections.new("Temporary export mesh")
    scene.collection.children.link(copies)
    bpy.ops.object.select_all(action="DESELECT")
    for original in collection.objects:
        if original.type == "MESH":
            clone = original.copy()
            clone.data = original.data.copy()
            copies.objects.link(clone)
            clone.select_set(True)
            bpy.context.view_layer.objects.active = clone
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    merged = bpy.context.view_layer.objects.active
    merged.name = "Fieldstone iron furnace"
    bpy.ops.export_scene.gltf(filepath=str(output / "iron_furnace.glb"), export_format="GLB", use_selection=True,
                              export_texcoords=True, export_tangents=True, export_animations=False)
    bpy.data.objects.remove(merged, do_unlink=True)
    bpy.data.collections.remove(copies)


def build(output):
    scene, collection = create()
    output.mkdir(parents=True, exist_ok=True)
    bpy.data.libraries.write(str(output / "iron_furnace.blend"), {scene}, compress=True)
    return {"mesh_objects": len(collection.objects), "path": str(output)}


if __name__ == "__main__":
    import sys
    args = sys.argv[sys.argv.index("--")+1:]
    output = Path(args[0])
    if bpy.context.scene.collection.children.get("Fieldstone furnace"):
        export_existing(output, Path(args[1]) if len(args) > 1 else None)
    else:
        build(output)
