"""Build the camp lantern in meters. Blender -Y faces the shelter entrance."""

import argparse
from math import cos, pi, sin, tau
from pathlib import Path
import random
import sys

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
WICK_TIP = -0.420
UP = (0, 0, 1)
FRONT = (0, -1, 0)


def material(name, rgb, metallic=0.0, roughness=0.5, alpha=1.0, emission=None):
    shader = bpy.data.materials.new(name)
    if not shader.node_tree:
        shader.use_nodes = True
    shader.use_backface_culling = True
    shader.diffuse_color = (*rgb, alpha)
    surface = shader.node_tree.nodes.get("Principled BSDF")
    surface.inputs["Base Color"].default_value = (*rgb, 1)
    surface.inputs["Metallic"].default_value = metallic
    surface.inputs["Roughness"].default_value = roughness
    surface.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        shader.surface_render_method = "BLENDED"
    if emission:
        color, strength = emission
        surface.inputs["Emission Color"].default_value = (*color, 1)
        surface.inputs["Emission Strength"].default_value = strength
    return shader


class MeshParts:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.materials = []
        self.face_settings = []

    def face(self, indices, surface, smooth=False):
        if surface not in self.materials:
            self.materials.append(surface)
        self.faces.append(tuple(indices))
        self.face_settings.append((self.materials.index(surface), smooth))

    def polygon(self, points, surface):
        start = len(self.vertices)
        self.vertices.extend(points)
        self.face(range(start, len(self.vertices)), surface)

    def skin(self, rows, surface, caps=False, closed=False, wrapped=True, smooth=True):
        start = len(self.vertices)
        stride = len(rows[0])
        for row in rows:
            self.vertices.extend(row)
        for i in range(len(rows) if closed else len(rows) - 1):
            lower = start + i * stride
            upper = start + ((i + 1) % len(rows)) * stride
            for j in range(stride if wrapped else stride - 1):
                following = (j + 1) % stride
                self.face((lower + j, lower + following, upper + following, upper + j), surface, smooth)
        if caps:
            end = start + (len(rows) - 1) * stride
            self.face(reversed(range(start, start + stride)), surface)
            self.face(range(end, end + stride), surface)

    def object(self, name, origin=(0, 0, 0)):
        mesh = bpy.data.meshes.new(name)
        pivot = Vector(origin)
        mesh.from_pydata([Vector(vertex) - pivot for vertex in self.vertices], [], self.faces)
        for surface in self.materials:
            mesh.materials.append(surface)
        for polygon, (index, smooth) in zip(mesh.polygons, self.face_settings):
            polygon.material_index = index
            polygon.use_smooth = smooth
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.location = pivot
        return obj


def frame(axis, reference=(1, 0, 0)):
    w = Vector(axis).normalized()
    u = Vector(reference) - w.dot(reference) * w
    if u.length < 0.01:
        u = Vector((0, 1, 0)) - w.y * w
    u.normalize()
    return u, w.cross(u), w


def turned(mesh, surface, profile, center=(0, 0, 0), axis=UP, segments=40,
           stretch=(1.0, 1.0), caps=True, closed=False, teeth=0):
    u, v, w = frame(axis)
    center = Vector(center)
    rows = []
    for level, radius in profile:
        row = []
        for index in range(segments):
            angle = tau * index / segments
            serration = (0.94 + 0.06 * cos(teeth * angle)) if teeth else 1
            radial = u * (stretch[0] * cos(angle)) + v * (stretch[1] * sin(angle))
            row.append(center + w * level + radial * (radius * serration))
        rows.append(row)
    mesh.skin(rows, surface, caps=caps, closed=closed)


def rolled_edge(mesh, surface, radius, thickness, center, axis=UP, stretch=(1.0, 1.0)):
    profile = [(thickness * sin(tau * i / 8), radius + thickness * cos(tau * i / 8))
               for i in range(8)]
    turned(mesh, surface, profile, center, axis, stretch=stretch, caps=False, closed=True)


def rounded_path(points, intervals):
    """Sample a Catmull–Rom path through the shaped wire or tube's control points."""
    controls = [Vector(point) for point in points]
    padded = [2 * controls[0] - controls[1], *controls, 2 * controls[-1] - controls[-2]]
    samples = []
    for a, b, c, d in zip(padded, padded[1:], padded[2:], padded[3:]):
        for step in range(intervals):
            t = step / intervals
            samples.append(0.5 * (2*b + (-a+c)*t + (2*a-5*b+4*c-d)*t*t + (-a+3*b-3*c+d)*t*t*t))
    return [*samples, controls[-1]]


def tube(mesh, surface, points, radii, segments=10, intervals=3, guide=(0, 1, 0)):
    points = rounded_path(points, intervals)
    rings = []
    for i, point in enumerate(points):
        tangent = points[min(i+1, len(points)-1)] - points[max(i-1, 0)]
        u, v, _ = frame(tangent, guide)
        rings.append([point + u * (radii[0] * cos(tau*j/segments))
                      + v * (radii[1] * sin(tau*j/segments)) for j in range(segments)])
    mesh.skin(rings, surface, caps=True)


def screw(mesh, steel, soot, center, axis, radius):
    turned(mesh, steel, ((-0.001, radius*0.82), (0, radius), (0.0017, radius*0.83)),
           center, axis, segments=12)
    u, v, w = frame(axis)
    face = Vector(center) + w * 0.00175
    mesh.polygon([face + u*(radius*x) + v*(radius*y)
                  for x, y in ((-0.69,-0.12), (0.69,-0.12), (0.69,0.12), (-0.69,0.12))], soot)


def ceiling_mount(steel, rim, soot):
    mount = MeshParts()
    turned(mount, steel, ((-.011,.027), (-.010,.034), (-.006,.039), (0,.039)))
    rolled_edge(mount, rim, .033, .0014, (0, 0, -.009))
    turned(mount, rim, ((-.025,.007),(-.023,.009),(-.012,.010),(-.010,.014)), segments=16)
    rolled_edge(mount, steel, .0185, .0042, (0, 0, -.039), (1, 0, 0))
    for angle in (0, pi/2, pi, 3*pi/2):
        screw(mount, rim, soot, (.026*cos(angle), .026*sin(angle), -.010), (0, 0, -1), .0037)
    mount.object("Mount")


def fuel_tank(mesh, enamel, rim, brass, oxide, soot):
    stretch = (1.0, .88)
    turned(mesh, enamel, ((-.582,.088),(-.581,.099),(-.578,.105),(-.573,.108),
                          (-.566,.108),(-.558,.106),(-.548,.103),(-.526,.101),
                          (-.508,.099),(-.496,.096),(-.486,.087),(-.477,.072),
                          (-.471,.050),(-.469,.036)), stretch=stretch, segments=56)
    rolled_edge(mesh, rim, .1055, .0027, (0, 0, -.571), stretch=stretch)
    rolled_edge(mesh, oxide, .1020, .0012, (0, 0, -.546), stretch=stretch)

    # The filler plug is threaded through a raised boss on the shoulder.
    plug = (.063, -.052, -.493)
    plug_axis = (.41, -.40, .82)
    turned(mesh, oxide, ((-.006,.018),(.001,.021),(.005,.018)), plug, plug_axis)
    turned(mesh, brass, ((.005,.017),(.008,.022),(.014,.021),(.017,.017)),
           plug, plug_axis, segments=48, teeth=24)
    turned(mesh, oxide, ((.017,.014),(.018,.012)), plug, plug_axis, segments=32)
    screw(mesh, brass, soot, Vector(plug) + Vector(plug_axis).normalized()*.018, plug_axis, .006)

    # Pressed oval badge with a small stamped oak sprig.
    badge = (0, -.0875, -.527)
    turned(mesh, brass, ((-.003,.016),(.001,.017),(.0025,.0148)), badge, FRONT,
           stretch=(1.51,.66), segments=32)
    turned(mesh, oxide, ((.0025,.014),(.0028,.0137)), badge, FRONT,
           stretch=(1.51,.66), segments=32)
    tube(mesh, brass, [(-.011,-.0908,-.531),(-.004,-.0908,-.528),(.003,-.0908,-.526),
                      (.010,-.0908,-.524)], (.0009,.0009), segments=6, intervals=1)
    for x, z in ((-.007,-.529), (0,-.527), (.006,-.525)):
        mesh.polygon(((x-.001,-.0910,z+.002),(x+.003,-.0910,z),
                      (x+.003,-.0910,z+.004),(x-.002,-.0910,z+.006)), brass)


def air_ducts(mesh, enamel, rim, steel, brass, oxide, soot):
    for side in (-1, 1):
        bow = [(side*x,y,z) for x,y,z in ((.081,.011,-.479),(.096,.015,-.458),
               (.113,.019,-.430),(.119,.021,-.401),(.115,.022,-.361),(.104,.021,-.322),
               (.092,.019,-.289),(.078,.016,-.270),(.057,.013,-.260))]
        tube(mesh, enamel, bow, (.016,.0175), segments=16, intervals=4)

        # Flared collars seat the ends of each hollow air tube.
        turned(mesh, rim, ((-.008,.019),(-.003,.020),(.004,.0185),(.008,.0175)),
               (side*.096,.015,-.458), (side*.51,.08,.86), segments=24)
        turned(mesh, rim, ((-.004,.019),(.003,.019),(.008,.0155)),
               (side*.067,.014,-.264), (-side*.84,-.10,.53), segments=24)

        shaft_axis = (side, 0, 0)
        pivot = (side*.099, .014, -.279)
        turned(mesh, steel, ((-.009,.012),(.009,.012),(.014,.010)), pivot, shaft_axis, segments=20)
        turned(mesh, oxide, ((.013,.008),(.017,.008),(.019,.0065)), pivot, shaft_axis, segments=16)
        screw(mesh, brass, soot, (side*.118,.014,-.279), shaft_axis, .0052)


def bail_handle(mesh, steel):
    # The carrying bail passes through the ceiling eye and pivots on the shoulders.
    controls = [(-.115,.014,-.280),(-.124,.014,-.264),(-.123,.013,-.210),
                (-.113,.010,-.133),(-.080,.005,-.084),(-.036,.001,-.060),
                (0,0,-.049),(.036,.001,-.060),(.080,.005,-.084),(.113,.010,-.133),
                (.123,.013,-.210),(.124,.014,-.264),(.115,.014,-.280)]
    tube(mesh, steel, controls, (.0047,.0044), segments=10, intervals=4)


def ventilator(mesh, enamel, rim, steel, brass, oxide, soot):
    turned(mesh, rim, ((-.303,.048),(-.302,.062),(-.297,.067),(-.290,.067),(-.287,.058)))
    rolled_edge(mesh, oxide, .063, .0021, (0, 0, -.298))
    turned(mesh, soot, ((-.291,.039),(-.281,.041),(-.251,.041),(-.248,.038)))

    # Open slots are modeled between pressed flutes, with a dark inner chimney.
    step = tau / 18
    for i in range(18):
        base = i * step
        rows = []
        for z, radius, shift in ((-.290,.056,0),(-.281,.053,0),(-.266,.052,.05),(-.254,.057,.11)):
            rows.append([((radius+flute)*cos(base + step*(fraction+shift)),
                          (radius+flute)*sin(base + step*(fraction+shift)), z)
                         for fraction, flute in ((-.35,0),(-.21,.0017),(0,.003),(.21,.0017),(.35,0))])
        mesh.skin(rows, enamel, wrapped=False)
    turned(mesh, enamel, ((-.258,.055),(-.256,.063),(-.251,.069),(-.246,.069),
                          (-.242,.066),(-.234,.057),(-.226,.043),(-.221,.029),(-.220,.019)))
    rolled_edge(mesh, steel, .0658, .0023, (0, 0, -.250))
    turned(mesh, oxide, ((-.223,.020),(-.219,.019),(-.215,.013),(-.213,.011)), segments=32)
    turned(mesh, brass, ((-.216,.008),(-.211,.008),(-.209,.006)), segments=20)


def burner_and_guard(mesh, enamel, rim, steel, brass, oxide, soot):
    turned(mesh, enamel, ((-.476,.054),(-.469,.064),(-.462,.068),(-.457,.075),
                          (-.450,.076),(-.442,.071),(-.440,.066)))
    rolled_edge(mesh, rim, .074, .0027, (0, 0, -.454))
    turned(mesh, oxide, ((-.446,.062),(-.443,.066),(-.439,.065),(-.436,.058)))
    turned(mesh, brass, ((-.437,.031),(-.431,.034),(-.427,.031),(-.426,.021)))
    turned(mesh, soot, ((-.428,.012),(-.423,.013),(-.421,.009)), stretch=(1.0,.5), segments=20)
    turned(mesh, soot, ((-.423,.010),(-.419,.010),(-.417,.008)), stretch=(1.0,.28), segments=20)

    stem = (-.031,-.060,-.452)
    wheel_axis = (-.28,-.95,.10)
    turned(mesh, brass, ((-.011,.004),(.014,.004),(.018,.006)), stem, wheel_axis, segments=16)
    turned(mesh, oxide, ((.014,.014),(.016,.016),(.020,.015),(.023,.013)),
           stem, wheel_axis, segments=40, teeth=20)
    turned(mesh, brass, ((.022,.010),(.024,.009),(.025,.005)), stem, wheel_axis, segments=20)
    screw(mesh, steel, soot, Vector(stem) + Vector(wheel_axis).normalized()*.024, wheel_axis, .0037)

    # Fine wire guard follows the glass, leaving the face of the flame visible.
    for angle in (pi*.17, pi*.83, pi*1.31, pi*1.69):
        wire = [(radius*cos(angle), radius*sin(angle), level) for radius, level in
                ((.064,-.449),(.077,-.420),(.079,-.391),(.070,-.356),(.055,-.319),(.052,-.301))]
        tube(mesh, steel, wire, (.0025,.0025), segments=8, intervals=3)
    rolled_edge(mesh, steel, .0775, .0021, (0, 0, -.412))
    rolled_edge(mesh, oxide, .0465, .0015, (0, 0, -.304))


def enamel_wear(mesh, aged, exposed, *, cap=False):
    """Small chips along the pressed seams and cap lip, where handling wears paint."""
    rng = random.Random(4131 if cap else 3217)
    seam_z, radius, ellipse = (-.246, .0694, 1.0) if cap else (-.566, .1088, .88)
    for i in range(6 if cap else 15):
        angle = rng.uniform(0, tau)
        width = rng.uniform(.009,.038)
        height = rng.uniform(.0006,.0018)
        z = seam_z + rng.uniform(-.0011,.0023)
        mesh.polygon([(radius*cos(angle+da),ellipse*radius*sin(angle+da),z+dz)
                      for da, dz in ((-width,0),(width*.7,-height),(width,0),(-width*.35,height))],
                     exposed if i % 3 == 0 else aged)


def flame_shape(mesh, surface, profile):
    rows = []
    for height, width, depth, lean in profile:
        rows.append([(lean + width*cos(tau*i/20), depth*sin(tau*i/20), WICK_TIP+height)
                     for i in range(20)])
    mesh.skin(rows, surface, caps=True)


def build():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.scene.name = "Camp Hurricane Lantern"
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.collection.name = "Lantern assembly"
    enamel = material("Blackened petrol enamel", (.051,.102,.095), .30, .49)
    rim = material("Rolled enamel edges", (.077,.131,.119), .40, .39)
    steel = material("Weathered steel wire", (.100,.116,.110), .45, .41)
    brass = material("Hand-worn brass", (.349,.198,.073), .42, .36)
    oxide = material("Tarnished bronze", (.143,.088,.038), .32, .57)
    soot = material("Soot and carbon wick", (.012,.010,.007), .06, .83)
    aged = material("Enamel wear", (.110,.134,.115), .22, .69)

    reservoir = MeshParts()
    ducts = MeshParts()
    handle = MeshParts()
    crown = MeshParts()
    burner = MeshParts()
    fuel_tank(reservoir, enamel, rim, brass, oxide, soot)
    enamel_wear(reservoir, aged, oxide)
    air_ducts(ducts, enamel, rim, steel, brass, oxide, soot)
    bail_handle(handle, steel)
    ventilator(crown, enamel, rim, steel, brass, oxide, soot)
    enamel_wear(crown, aged, oxide, cap=True)
    burner_and_guard(burner, enamel, rim, steel, brass, oxide, soot)
    body = [reservoir.object("Fuel reservoir"), ducts.object("Cold air ducts and hinges", (0, 0, -.368)),
            crown.object("Fluted vent cap", (0, 0, -.256)),
            burner.object("Wick assembly and wire guard", (0, 0, -.440))]
    body.append(handle.object("Bail handle", (0, .014, -.279)))
    ceiling_mount(steel, rim, soot)

    glass = material("Clear smoke-tinted glass", (.52,.63,.61), .03, .22, alpha=.155)
    chimney = MeshParts()
    turned(chimney, glass, ((-.440,.053),(-.432,.060),(-.421,.065),(-.410,.068),
                           (-.399,.069),(-.386,.0685),(-.374,.0655),(-.359,.061),
                           (-.345,.055),(-.334,.050),(-.322,.0465),(-.307,.044),
                           (-.300,.0445),(-.294,.046)), segments=48, caps=False)
    chimney.object("Chimney", (0, 0, -.372))

    amber = material("Amber flame envelope", (.16,.039,.004), roughness=.68, alpha=.46,
                     emission=((1,.225,.018), 1.27))
    gold = material("Ivory flame core", (.36,.246,.105), roughness=.75,
                    emission=((1,.83,.53), 1.65))
    flame = MeshParts()
    flame_shape(flame, amber, ((.001,.006,.003,0),(.007,.013,.006,.001),(.017,.015,.008,.001),
                               (.028,.0135,.0075,.0015),(.040,.010,.006,.003),
                               (.050,.0065,.004,.005),(.059,.0035,.002,.008),(.065,.0004,.0005,.011)))
    flame_shape(flame, gold, ((.002,.0045,.002,0),(.010,.008,.0048,.0005),(.017,.009,.0058,.001),
                              (.025,.0078,.005,.0015),(.033,.0055,.0035,.003),
                              (.042,.0035,.0024,.0045),(.050,.0016,.0011,.006),(.053,.0004,.0004,.007)))
    flame.object("Flame", (0, 0, WICK_TIP))
    return body


def save_source(path):
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type != "VIEW_3D":
                continue
            space = area.spaces.active
            space.shading.type = "MATERIAL"
            space.shading.studio_light = "studio.exr"
            space.overlay.show_overlays = False
            space.clip_start = .008
            space.region_3d.view_rotation = Vector((.34,-1,.10)).to_track_quat("Z", "Y")
            space.region_3d.view_location = (0, 0, -.291)
            space.region_3d.view_distance = 1.20
            space.region_3d.view_perspective = "PERSP"
    path.parent.mkdir(parents=True, exist_ok=True)
    filepaths = bpy.context.preferences.filepaths
    original_versions = filepaths.save_version
    try:
        filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
    finally:
        filepaths.save_version = original_versions


def export_game(path, body):
    # Joining the opaque subassemblies batches faces with matching materials.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in body:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = body[0]
    bpy.ops.object.join()
    body[0].name = "Lantern"
    body[0].data.name = "Lantern"
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB",
                              export_texcoords=False, export_materials="EXPORT",
                              export_cameras=False, export_lights=False, export_animations=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "coop" / "props" / "camp_lantern.glb")
    parser.add_argument("--blend", type=Path, default=ROOT / "art" / "camp_lantern.blend")
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    body = build()
    save_source(args.blend)
    export_game(args.output, body)


if __name__ == "__main__":
    main()
