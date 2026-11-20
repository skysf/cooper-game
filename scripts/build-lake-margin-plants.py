"""Model young Manchurian hazel and softstem bulrush for Rainline Camp.

Run in Blender's Python. LAKE_PLANT_OUTPUT can redirect the editable source and
runtime assets into an isolated project root.
"""
import math
import os
import random
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector


ROOT = Path(os.environ["LAKE_PLANT_OUTPUT"]) if "LAKE_PLANT_OUTPUT" in os.environ else Path(__file__).resolve().parents[1]
UP = Vector((0.0, 0.0, 1.0))
EAST = Vector((1.0, 0.0, 0.0))
TAU = math.tau
C = math.cos
S = math.sin
ATLAS = {"leaf": (0, 272), "wood": (272, 400), "husk": (400, 512),
         "stalk": (0, 300), "sheath": (300, 384), "spike": (384, 512)}


def horizontal(angle):
    return Vector((C(angle), S(angle), 0.0))


def make_atlas(name, square, hazel):
    pixels = np.ones((square, square, 4), np.float32)
    regions = ("leaf", "wood", "husk") if hazel else ("stalk", "sheath", "spike")
    for region in regions:
        left, right = ATLAS[region]
        x, y = np.meshgrid(np.linspace(0, 1, right - left), np.linspace(0, 1, square))
        speckle = .013 * np.sin(x * 193 + y * 109) + .011 * np.cos(x * 347 - y * 579)
        mottling = .043 * np.sin(x * 18 + y * 10 + np.sin(y * 28)) * np.cos(y * 27 - x * 18)
        if region == "leaf":
            side = abs(x - .5) * 2
            midrib = np.exp(-((x - .5) / .017) ** 2)
            slope = y - (.32 + .14 * y) * side + .066 * side ** 2
            ribs = np.exp(-(np.sin(slope * math.pi * 8.5) / .26) ** 2) * (1 - side * .73)
            finer = np.sin(x * 54 - y * 95 + np.cos(y * 7)) * np.sin(x * 135 + y * 82)
            worn = (np.clip((side - .71) / .29, 0, 1) ** 2 + .42 * y ** 5) * (.22 + .78 * np.sin(y * 19) ** 2)
            base = np.array([.295, .403, .207]) + worn[:, :, None] * [.13, .084, -.022]
            detail = .059 * midrib + .054 * ribs + .009 * finer
        elif region == "wood":
            grain = np.sin(x * 52 + .28 * np.sin(y * 29)) * np.cos(y * 7)
            pores = np.clip(np.sin(y * 143 + x * 49) * np.cos(y * 79 - x * 26) - .70, 0, 1)
            base = np.array([.326, .276, .208]) + y[:, :, None] * [.097, .063, .036]
            detail = .073 * grain + .098 * pores
        elif region == "husk":
            strands = .054 * np.sin(x * 78 + .69 * np.cos(y * 9))
            tips = np.clip((y - .67) * 3.0, 0, 1)
            base = np.array([.568, .473, .247]) + tips[:, :, None] * [.172, .119, .042]
            detail = strands + .055 * np.sin(x * 243 - y * 46) * np.cos(y * 26 + x * 16)
        elif region == "spike":
            scale_rows = np.sin(y * 48 - np.sin(x * TAU * 6))
            base = np.array([.339, .233, .123]) + np.clip(scale_rows, 0, 1)[:, :, None] * [.13, .10, .044]
            detail = .047 * np.sin(x * 37 + y * 59) + .04 * np.sin(x * 131 - y * 175)
        else:
            young = region == "stalk"
            base_color = [.318, .407, .231] if young else [.375, .334, .176]
            base = np.array(base_color) + y[:, :, None] * [.081, .075 if young else .030, .041]
            ribs = np.sin(x * 69 + .19 * np.cos(y * 7))
            detail = .033 * ribs + .021 * np.sin(y * 35 - x * 23)
        pixels[:, left:right, :3] = np.clip(base + (detail + mottling + speckle)[:, :, None], .04, .9)
    image = bpy.data.images.new(name, square, square, alpha=False)
    image.pixels.foreach_set(pixels.ravel())
    image.update()
    image.pack()
    return image


def make_material(name, atlas, preview):
    surface = bpy.data.materials.new(name)
    surface.diffuse_color = (*preview, 1)
    surface.use_nodes = True
    nodes = surface.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = atlas
    tex.location = (-360, 110)
    vertex = nodes.new("ShaderNodeVertexColor")
    vertex.layer_name = "Tissue tint"
    vertex.location = (-360, -110)
    mix = nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1
    mix.location = (-100, 100)
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Metallic"].default_value = 0
    bsdf.inputs["Roughness"].default_value = .82
    links = surface.node_tree.links
    links.new(tex.outputs["Color"], mix.inputs[1])
    links.new(vertex.outputs["Color"], mix.inputs[2])
    links.new(mix.outputs["Color"], bsdf.inputs["Base Color"])
    return surface


class Tissue:
    def __init__(self, label, material):
        self.label = label
        self.material = material
        self.points = []
        self.tones = []
        self.faces = []
        self.uvs = []

    def vertex(self, p, tone):
        self.points.append(tuple(p))
        self.tones.append((*tone, 1))
        return len(self.points) - 1

    def face(self, corners, texture, region):
        self.faces.append(corners)
        left, right = ATLAS[region]
        # Leave a gutter at each edge to avoid pulling colour from an adjacent part.
        self.uvs.append([((left + 2 + (right - left - 4) * u) / 512, .004 + .992 * v) for u, v in texture])

    def tube(self, centers, radii, sides, tone, region, phase=0.0):
        first = len(self.points)
        length = len(centers) - 1
        for i, center in enumerate(centers):
            tangent = (centers[min(i + 1, length)] - centers[max(i - 1, 0)]).normalized()
            reference = UP if abs(tangent.z) < .85 else EAST
            across = tangent.cross(reference).normalized()
            left = tangent.cross(across)
            for side in range(sides):
                angle = phase + TAU * side / sides
                radius = radii[i] * (.95 + .05 * S(angle * 3 + phase * 2 + i * .8))
                point = center + radius * (across * C(angle) + left * S(angle))
                shade = .92 + .08 * C(side / sides * TAU - .8)
                self.vertex(point, tuple(channel * shade for channel in tone))
        for i in range(length):
            for j in range(sides):
                jn = (j + 1) % sides
                a = first + i * sides
                b = a + sides
                self.face((a+j, a+jn, b+jn, b+j),
                          ((j/sides, i/length), ((j+1)/sides, i/length),
                           ((j+1)/sides, (i+1)/length), (j/sides, (i+1)/length)), region)

    def hazel_leaf(self, root, tangent, length, halfwidth, tint, phase):
        tangent = tangent.normalized()
        across = tangent.cross(UP).normalized()
        normal = across.cross(tangent).normalized()
        rings = 11
        start = len(self.points)
        for i in range(rings + 1):
            t = i / rings
            outline = max(.014, S(math.pi * (t ** .81))) ** .89
            serration = (1.0 if i % 2 else .83) * (1 - .16 * t)
            asymmetry = length * .062 * S(math.pi * t) * S(phase)
            for j in range(3):
                side = j - 1
                width = outline * serration * halfwidth * (1.0 + .17 * S(phase + i * .61) * side)
                advance = length * (t + abs(side) * .17 * (1 - t) * (1 - t))
                p = root + tangent * advance + across * (side * width + asymmetry)
                p += normal * (length * (.105 * S(math.pi * t) - .091 * t * t)
                               - abs(side) * width * .28 + width * side * .23 * S(phase))
                self.vertex(p, tuple(channel * (.93 + .07 * S(t * 3.6 + phase + side)) for channel in tint))
        for row in range(rings):
            for side in range(2):
                a = start + 3 * row + side
                b = a + 3
                u = side * .5
                self.face((a, a+1, b+1, b), ((u, row/rings), (u+.5, row/rings),
                                             (u+.5, (row+1)/rings), (u, (row+1)/rings)), "leaf")

    def make_object(self):
        data = bpy.data.meshes.new(self.label + " Mesh")
        data.from_pydata(self.points, [], self.faces)
        data.update()
        data.materials.append(self.material)
        uv = data.uv_layers.new(name="Atlas")
        color = data.color_attributes.new(name="Tissue tint", domain="POINT", type="BYTE_COLOR")
        data.color_attributes.active_color = color
        for polygon, uvs in zip(data.polygons, self.uvs):
            polygon.use_smooth = True
            for i, coords in zip(polygon.loop_indices, uvs):
                uv.data[i].uv = coords
        for cell, tint in zip(color.data, self.tones):
            cell.color = tint
        return bpy.data.objects.new(self.label, data)


def draw_hazel(material):
    rng = random.Random(10864)
    bark = Tissue("Hazel · bark and forks", material)
    leaves = Tissue("Hazel · serrated foliage", material)
    fruit = Tissue("Hazel · bristly fruit husks", material)
    for stem in range(5):
        angle = stem * TAU / 5 + rng.uniform(-.37, .37)
        outward = horizontal(angle)
        base = outward * rng.uniform(.055, .137)
        reach = rng.uniform(.17,.36)
        height = rng.uniform(.95, 1.41)
        twist = horizontal(angle + math.pi * .5) * rng.uniform(.025, .10)
        trunk_tone = (rng.uniform(.69,.96), rng.uniform(.71,.91), rng.uniform(.68,.91))

        def trunk(t):
            return base + UP * (height * t) + outward * (reach * (t ** 1.45)) + twist * S(t * math.pi)

        bark.tube([trunk(i / 6) for i in range(7)],
                  [.024, .021, .016, .013, .008, .0048, .0012], 7, trunk_tone, "wood", angle)
        for branch in range(5):
            fraction = .388 + branch * .126 + rng.uniform(-.068, .068)
            origin = trunk(fraction)
            a = angle + (branch - 2) * .88 + rng.uniform(-.33,.33)
            direction = horizontal(a)
            extent = rng.uniform(.235,.48) * (1 - .41 * fraction)
            rise = rng.uniform(.106,.25)
            elbows = [origin, origin + direction * extent * .36 + UP * (rise * .29),
                      origin + direction * extent * .74 + UP * (rise * .68),
                      origin + direction * extent + UP * rise]
            bark.tube(elbows, [.0078, .0058, .0038, .0015], 5, trunk_tone, "wood", a)
            for bud in range(5):
                j = 1 + int(bud >= 3)
                at = elbows[j].lerp(elbows[j + 1], (.18 + .25 * (bud % 3)) if bud < 4 else .96)
                turn = a + (.96 if bud % 2 else -.80) + rng.uniform(-.35,.35)
                blade_line = horizontal(turn) + UP * rng.uniform(-.33,.57)
                joint = at + blade_line.normalized() * rng.uniform(.011,.026)
                color = (rng.uniform(.66,.98), rng.uniform(.77,.99), rng.uniform(.60,.92))
                if bud == 2 and rng.random() < .29:
                    color = (.99,.88,.53)
                bark.tube([at,joint],[.0018,.00085],4,(.65,.79,.44),"wood",turn)
                leaves.hazel_leaf(joint, blade_line, rng.uniform(.066,.116), rng.uniform(.023,.044), color,
                                  rng.random() * TAU)
            if branch == 3 or (branch == 2 and stem in (0,3)):
                at = elbows[1].lerp(elbows[2], .59)
                for k in range(rng.randrange(2,4)):
                    fruit_dir = horizontal(a + k * 1.7) * .019 - UP * rng.uniform(.020,.038)
                    root = at + fruit_dir * .24
                    centers = [root, root+fruit_dir*.46, root+fruit_dir*.78,
                               root+fruit_dir*1.19, root+fruit_dir*1.49]
                    fruit.tube(centers,[.0039,.009,.0074,.0041,.0046],7,(.88,.91,.70),"husk",a+k)
                    # Tooth-like tips open around the pinched neck of the involucre.
                    head = centers[-1]
                    for tooth in range(5):
                        wing = horizontal(tooth * TAU / 5 + a)
                        near = head + wing * .0040
                        mid = head + wing * .0060 + fruit_dir * .24
                        tip = head + wing * rng.uniform(.007,.011) + fruit_dir * rng.uniform(.36,.57)
                        index = [fruit.vertex(p,(.87,.88,.68)) for p in (near,mid,tip)]
                        fruit.face(index,((.32,.70),(.66,.77),(.52,.99)),"husk")
    return bark, leaves, fruit


def draw_bulrush(material):
    rng = random.Random(81040)
    stems = Tissue("Bulrush · rounded culms", material)
    sheaths = Tissue("Bulrush · basal sheaths and bracts", material)
    seed = Tissue("Bulrush · rust-coloured lateral spikelets", material)

    for stem in range(13):
        angle = stem * 2.399963 + rng.uniform(-.34,.34)
        side = horizontal(angle)
        offset = (.03 + .235 * (stem/12) ** .63)
        at = offset * side
        height = rng.uniform(1.06,1.52)
        size = rng.uniform(.0037,.0079)
        lean = side * rng.uniform(.04,.135)
        tone = (rng.uniform(.68,.92),rng.uniform(.76,.98),rng.uniform(.72,.98))

        def culm(t):
            return at + UP * (height * t) + lean * (t ** 2.16) + horizontal(angle+.9) * (.030 * S(t * math.pi))

        stems.tube([culm(i/9) for i in range(10)], [size * (1-.64*(i/9)**.78) for i in range(10)],
                   6, tone, "stalk", angle)
        sheaths.tube([culm(t) for t in (0.0,.065,.127)], [size*1.22,size*1.05,size*.91],5,
                     (.79,.86,.63),"sheath",angle)
        if stem % 3 == 1:
            continue
        fork = culm(rng.uniform(.911,.953))
        for arm in range(rng.choice((4,5,6))):
            flare = horizontal(angle*.82 + arm*2.399963)
            length = rng.uniform(.018,.071)
            joint = fork + flare * length * .52 + UP * rng.uniform(.007,.022)
            tip = joint + flare * length * .38 + UP * rng.uniform(-.019,.003)
            sheaths.tube([fork,joint,tip], [.0015,.0011,.00065],4,(.82,.80,.63),"sheath",angle)
            end = tip + UP * .002
            for floret in range(rng.choice((1,1,2))):
                direction = (flare * (.50+.19*floret) + UP * (.32-.54*floret)).normalized()
                wide = rng.uniform(.0016,.0029)
                tall = rng.uniform(.0056,.0106)
                seed.tube([end+direction*(t*tall) for t in (0,.32,.71,1)],
                          [.00058,wide,wide*.76,.0004], 5,
                          (rng.uniform(.74,.97),rng.uniform(.70,.93),rng.uniform(.64,.92)),"spike",angle)
                end += flare * .017 - UP * .002
    return stems, sheaths, seed


def export(collection_name, tissue, destination, offset):
    scene = bpy.context.scene
    collection = bpy.data.collections.new(collection_name)
    scene.collection.children.link(collection)
    bpy.ops.object.select_all(action="DESELECT")
    originals = []
    copies = []
    for part in tissue:
        model = part.make_object()
        collection.objects.link(model)
        clone = model.copy()
        clone.data = model.data.copy()
        scene.collection.objects.link(clone)
        clone.select_set(True)
        originals.append(model)
        copies.append(clone)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    model = bpy.context.object
    model.name = collection_name
    model.data.name = collection_name + " Mesh"
    bpy.ops.export_scene.gltf(filepath=str(destination), export_format="GLB", use_selection=True,
                             export_texcoords=True, export_normals=True, export_vertex_color="ACTIVE",
                             export_image_format="AUTO")
    bpy.data.objects.remove(model, do_unlink=True)
    for original in originals:
        original.location.x = offset


def main():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    hazel = make_material("Hazel · leaves, bark, husks", make_atlas("Manchurian hazel atlas",512,True),(.31,.39,.22))
    bulrush = make_material("Bulrush · stems, sheaths, spikelets",
                            make_atlas("Softstem bulrush atlas",512,False),(.39,.45,.27))
    runtime = ROOT / "coop" / "vegetation"
    editable = ROOT / "art" / "vegetation"
    runtime.mkdir(parents=True, exist_ok=True)
    editable.mkdir(parents=True, exist_ok=True)
    export("Manchurian hazel",draw_hazel(hazel),runtime/"lakeside_hazel.glb",0.0)
    export("Softstem bulrush",draw_bulrush(bulrush),runtime/"lakeside_bulrush.glb",1.63)
    scene["Habitat"] = "Corylus mandshurica, woodland margin. Schoenoplectus tabernaemontani, shallow lake shore."
    scene["Season"] = "Late summer and early autumn. Hazel husks, bulrush spikelets, no spring catkins."
    scene["Dimensions"] = "Metres. Export roots at soil contact height. The bulrush is offset in this editing view."
    if bpy.context.screen is not None:
        for area in bpy.context.screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.region_3d.view_distance = 3.4
                area.spaces.active.region_3d.view_location = Vector((.77, 0, .66))
                area.spaces.active.clip_start = .008
                area.spaces.active.shading.color_type = "MATERIAL"
    bpy.ops.wm.save_as_mainfile(filepath=str(editable/"lake_margin_plants.blend"))


main()
