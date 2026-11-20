"""Build two original Leymus mollis clumps in Blender and export the runtime mesh.

Run in Blender's Python. RAINLINE_DUNE_OUTPUT may point to an isolated project root
containing coop/vegetation and art/vegetation.
"""
import math
import os
import random
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector


ROOT = Path(os.environ["RAINLINE_DUNE_OUTPUT"]) if "RAINLINE_DUNE_OUTPUT" in os.environ else Path(__file__).resolve().parents[1]
S = math.sin
C = math.cos
TAU = math.tau


def colors(name, palette, blade=False):
    """Bake the blade ribs, waxy blue-green lamina and weathered edges to a packed map."""
    u, v = np.meshgrid(np.linspace(0, 1, 128, dtype=np.float32),
                       np.linspace(0, 1, 512 if blade else 128, dtype=np.float32))
    bands = np.sin(u * TAU * (6 if blade else 3) + .15 * np.sin(v * TAU * 8))
    texture = .9 + .07 * bands + .038 * np.sin(v * 104 + u * 21) + .022 * np.cos(v * 237 - u * 35)
    low, middle, high = np.array(palette, dtype=np.float32)
    root = np.clip(1 - v * 4.8, 0, 1) ** 2
    tip = np.clip((v - .87 + .014 * np.sin(u * TAU * 3)) * 7.7, 0, 1) ** 2
    color = middle + root[:, :, None] * (low - middle) + tip[:, :, None] * (high - middle)
    if blade:
        rib = np.exp(-((u - .50) / .035) ** 2)
        worn = np.clip((abs(u - .5) - .40) / .10, 0, 1) ** 2
        color += (rib * .09 + worn * .035)[:, :, None]
    else:
        color += (np.sin(v * TAU) ** 2 * .07)[:, :, None]
    result = np.ones((*u.shape, 4), np.float32)
    result[:, :, :3] = np.clip(color * texture[:, :, None], .025, 1)
    image = bpy.data.images.new(name, width=u.shape[1], height=u.shape[0], alpha=False)
    image.pixels.foreach_set(result.ravel())
    image.update()
    image.pack()
    return image


def make_material(label, image, base_color, roughness):
    material = bpy.data.materials.new(label)
    material.diffuse_color = (*base_color, 1)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.label = image.name
    texture.location = (-380, 90)
    attributes = nodes.new("ShaderNodeVertexColor")
    attributes.layer_name = "Plant tone"
    attributes.location = (-380, -110)
    mix = nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    mix.location = (-100, 100)
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = roughness
    links = material.node_tree.links
    links.new(texture.outputs["Color"], mix.inputs[1])
    links.new(attributes.outputs["Color"], mix.inputs[2])
    links.new(mix.outputs["Color"], bsdf.inputs["Base Color"])
    return material


class PlantMesh:
    def __init__(self):
        self.points = []
        self.faces = []
        self.uvs = []
        self.surfaces = []
        self.tones = []

    def vertex(self, point, tone):
        self.points.append(tuple(point))
        self.tones.append((*tone, 1.0))
        return len(self.points) - 1

    def face(self, points, uv, surface):
        self.faces.append(points)
        self.uvs.append(uv)
        self.surfaces.append(surface)

    def blade(self, root, angle, length, width, lift, retreat, tone):
        # A genuinely folded blade with four cross-section strips. Longitudinal
        # curvature starts upright, then arcs outward with a naturally drooped point.
        forward = Vector((C(angle), S(angle), 0))
        side = Vector((-S(angle), C(angle), 0))
        rings = 10 if length > .29 else 6
        columns = (-1, -.55, 0, .55, 1)
        first = len(self.points)
        for level in range(rings + 1):
            t = level / rings
            travel = root + forward * (length * retreat * t ** 1.44)
            travel.z += length * (lift * S(t * 1.98) + .19 * t - .22 * t ** 3)
            travel += side * (length * .066 * S(t ** 1.3 * math.pi))
            curve = (.37 + .63 * min(1.0, t * 5)) * max(.025, (1 - t ** 2.8) ** .80)
            lateral = (side * C(t * .62) + Vector((0, 0, S(t * .62)))).normalized()
            for column in columns:
                offset = lateral * (column * width * curve * .5)
                offset.z += width * curve * (.30 * abs(column) + .084 * column ** 2)
                variation = .92 + .08 * S(t * 4.0 + column * .55)
                self.vertex(travel + offset, tuple(c * variation for c in tone))
        for i in range(rings):
            for j in range(len(columns) - 1):
                a = first + i * len(columns) + j
                b = a + len(columns)
                self.face((a, a + 1, b + 1, b),
                          ((j * .25, i / rings), ((j + 1) * .25, i / rings),
                           ((j + 1) * .25, (i + 1) / rings), (j * .25, (i + 1) / rings)), 0)

    def stalk(self, axis, height, rng, tone):
        first = len(self.points)
        sections, div = 9, 5
        for i in range(sections + 1):
            t = i / sections
            at = axis(height * t)
            radius = .00245 * (1.0 - .62 * t) * rng.uniform(.90, 1.10)
            for j in range(div):
                angle = TAU * j / div
                self.vertex(at + Vector((radius * C(angle), radius * S(angle), 0.0)), tone)
        for i in range(sections):
            for j in range(div):
                a = first + i * div
                b = a + div
                k = (j + 1) % div
                self.face((a + j, a + k, b + k, b + j),
                          ((j / div, i / sections), ((j + 1) / div, i / sections),
                           ((j + 1) / div, (i + 1) / sections), (j / div, (i + 1) / sections)), 0)

    def floret(self, at, angle, height, width, stained):
        # Angular, narrow overlapping glumes lift along the culm in two rows.
        out = Vector((C(angle), S(angle), 0))
        side = Vector((-S(angle), C(angle), 0))
        up = Vector((0, 0, 1))
        basis = [at, at + up * height * .38 + side * width, at + up * height * .77 + side * width * .57,
                 at + up * (height * 1.13) + out * (width * 1.85),
                 at + up * height * .76 - side * width * .53, at + up * height * .33 - side * width,
                 at + up * height * .49 + out * width * 1.5]
        uvs = [(.50, .04), (.12, .34), (.23, .77), (.51, 1), (.77, .75), (.91, .38), (.50, .55)]
        ring = [self.vertex(v, stained) for v in basis]
        for i in range(6):
            j = (i + 1) % 6
            self.face((ring[i], ring[j], ring[6]), (uvs[i], uvs[j], uvs[6]), 1)

    def object(self, name, materials):
        mesh = bpy.data.meshes.new(name + " Mesh")
        mesh.from_pydata(self.points, [], self.faces)
        mesh.update()
        for material in materials:
            mesh.materials.append(material)
        uv = mesh.uv_layers.new(name="Plant UV")
        tone = mesh.color_attributes.new(name="Plant tone", domain="POINT", type="BYTE_COLOR")
        mesh.color_attributes.active_color = tone
        for i, polygon in enumerate(mesh.polygons):
            polygon.material_index = self.surfaces[i]
            polygon.use_smooth = self.surfaces[i] == 0
            for loop, st in zip(polygon.loop_indices, self.uvs[i]):
                uv.data[loop].uv = st
        for color, tint in zip(tone.data, self.tones):
            color.color = tint
        return bpy.data.objects.new(name, mesh)


def draw_clump(name, flowering, materials):
    rng = random.Random(1806 if flowering else 3309)
    leaf = PlantMesh()
    head = PlantMesh()
    stalk = PlantMesh()
    stems = 5 if flowering else 4
    for stem in range(stems):
        radial = TAU * stem / stems + rng.uniform(-.27, .27)
        lean = Vector((C(radial), S(radial), 0))
        spread = rng.uniform(.021, .092)
        base = lean * spread
        culm_height = rng.uniform(.55, .79) if flowering else rng.uniform(.28, .39)
        arc = rng.uniform(.032, .086) if flowering else rng.uniform(.035, .067)

        def culm(z):
            return base + z * Vector((0, 0, 1)) + lean * (arc * (z / culm_height) ** 2)

        stalk.stalk(culm, culm_height, rng, (.71, .80, .65))
        for blade in range(rng.randint(5, 6)):
            angle = radial + rng.uniform(-1.6, 1.6) + (blade % 2) * .32
            ground_shoot = blade < 2
            height = rng.uniform(.009, .065) if ground_shoot else rng.uniform(.069, culm_height * .42)
            length = rng.uniform(.12, .26) if ground_shoot else rng.uniform(.26, .51 if flowering else .40)
            tint = (rng.uniform(.73, .97), rng.uniform(.80, .98), rng.uniform(.81, 1.0))
            if ground_shoot and rng.random() < .29:
                tint = (.99, .84, .67)
            leaf.blade(culm(height), angle, length, rng.uniform(.0098, .0152),
                       rng.uniform(.39, .79), rng.uniform(.44, .83), tint)

        if flowering:
            spike_start = culm_height - rng.uniform(.137, .18)
            nodes = rng.randrange(11, 15)
            phase = rng.uniform(0, TAU)
            for i in range(nodes):
                t = i / (nodes - 1)
                z = spike_start + (culm_height - spike_start) * t
                scale = .58 + .42 * C(t * 1.35)
                angle = phase + (i % 2) * math.pi + i * .055
                for offset in (-.40, .40):
                    width = scale * rng.uniform(.0029, .0051)
                    h = scale * rng.uniform(.011, .021)
                    tint = (rng.uniform(.70, .96), rng.uniform(.65, .91), rng.uniform(.46, .81))
                    head.floret(culm(z), angle + offset, h, width, tint)

    result = [leaf.object(name + " · blades", materials), stalk.object(name + " · culms", materials)]
    if flowering:
        result.append(head.object(name + " · spikes", materials))
    return result


def run():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    blades = colors("Dunegrass wax and parallel ribs", [[.49, .49, .33], [.35, .463, .368], [.56, .51, .30]], True)
    ears = colors("Dunegrass husk", [[.49, .38, .23], [.73, .64, .41], [.88, .76, .56]])
    materials = [make_material("Waxy folded blade", blades, (.31, .445, .314), .78),
                 make_material("Ripening coastal spike", ears, (.73, .64, .41), .88)]
    runtime = []
    for variant, flowering in [("Leafy", False), ("Flowering", True)]:
        authored = bpy.data.collections.new(variant)
        scene.collection.children.link(authored)
        objects = draw_clump(variant, flowering, materials)
        clones = []
        bpy.ops.object.select_all(action="DESELECT")
        for part in objects:
            authored.objects.link(part)
            compiled = part.copy()
            compiled.data = part.data.copy()
            scene.collection.objects.link(compiled)
            compiled.select_set(True)
            clones.append(compiled)
        bpy.context.view_layer.objects.active = clones[0]
        bpy.ops.object.join()
        prepared = bpy.context.object
        prepared.name = variant
        prepared.data.name = variant
        runtime.append(prepared)
        if flowering:
            for part in objects:
                part.location.x = .97
    bpy.ops.object.select_all(action="DESELECT")
    for mesh in runtime:
        mesh.select_set(True)
    dest = ROOT / "coop/vegetation"
    dest.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(dest / "coastal_dunegrass.glb"), export_format="GLB",
                             use_selection=True, export_texcoords=True, export_normals=True,
                             export_vertex_color="ACTIVE", export_image_format="AUTO")
    for mesh in runtime:
        bpy.data.objects.remove(mesh, do_unlink=True)
    scene["Species"] = "滨麦 / Leymus mollis. Original model. Wet-sand-excluding upper beach planting."
    scene["Phenology"] = "Leaf-only shoots and ripening late-summer spikes."
    scene["Scale"] = "Metres. Both runtime roots are at the sand contact. Flowering offset only for this editing view."
    scene["Sources"] = "CAS iPlant, Ishikari municipal museum, Burke Herbarium and MassWildlife."
    for area in bpy.context.screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.region_3d.view_distance = 1.8
            area.spaces.active.region_3d.view_location = Vector((.46, 0.0, .37))
            area.spaces.active.clip_start = .002
            area.spaces.active.shading.color_type = "MATERIAL"
    dest = ROOT / "art/vegetation"
    dest.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(dest / "coastal_dunegrass.blend"))
    print("DUNEGRASS_OUTPUT", ROOT)


run()
