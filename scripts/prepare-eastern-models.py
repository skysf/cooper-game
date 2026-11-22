"""Extract reusable, measured LOD meshes from the two supplied scene libraries in Blender."""
from pathlib import Path
import bpy
import numpy as np
import bmesh
import json
import re
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache/world-expansion"
SOURCES = ROOT / "art/scenes_assets"
# Runtime name, original object, near triangle budget, typical field height (m).
PACKS = {
    "verdant": ("verdant_trail", [
        ("grove_tree","island_tree_01_a",32400,7.4), ("crooked_tree","island_tree_01_b",28500,5.8),
        ("fallen_trunk","main_dead_tree_trunk",7000,1.65), ("old_stump","dead_tree_trunk_02",4500,1.35),
        ("tangled_roots","root_cluster_01",6500,.73), ("bank_roots","root_cluster_2_04_lod0",1900,.22),
        ("wood_rock","rock_07",4700,1.35), ("broadleaf","shrub_01_c",850,.49),
        ("fern_bush","shrub_03_a",2080,.65), ("underbrush","shrub_02_d",3100,.75),
        ("trail_grass","grass_medium_02_b",780,.32), ("litter","sticks_debris_a",420,.14)]),
    "namaqua": ("namaqualand", [
        ("quiver_tree","quiver_tree_01_LOD0",22100,5.2), ("fork_tree","quiver_tree_02_LOD0",12500,3.0),
        ("granite_tor","namaqualand_boulder_04_LOD0",9400,3.6), ("weathered_rock","namaqualand_boulder_06_LOD0",5900,1.85),
        ("rock_shelf","namaqualand_cliff_02_LOD0",12500,4.8), ("dry_branch","dead_quiver_branch_01",2300,.58),
        ("gazania","flower_gazania_d_LOD1",860,.32), ("gazania_low","flower_gazania_f_LOD1",720,.24),
        ("ursinia","flower_ursinia_b_LOD0",1200,.38), ("blue_flower","flower_heliophila_medium_LOD0",3350,.43),
        ("iceplant","crystalline_iceplant_a_LOD0",1200,.28), ("silver_bush","didelta_spinosa_small_LOD1",1350,.48),
        ("wax_shrub","searsia_lucida_a_LOD0",4100,.86)]),
}


def image_maps(material, folder):
    images = []
    seen = set()
    def visit(tree):
        if tree.name in seen:
            return
        seen.add(tree.name)
        for node in tree.nodes:
            if node.type == "TEX_IMAGE" and node.image:
                path = folder / Path(node.image.filepath).name
                if path.is_file() and path.name not in images:
                    images.append(path.name)
            if node.type == "GROUP" and node.node_tree:
                visit(node.node_tree)
    if material.node_tree:
        visit(material.node_tree)
    stem = re.sub(r"\.\d+$","",material.name).lower()
    def choose(pattern):
        options = [im for im in images if re.search(pattern,im.lower())]
        return next((im for im in options if im.lower().startswith(stem)), options[0] if options else None)
    return {key:choose(pattern) for key,pattern in {
        "color":r"_(diff|col|albedo)", "normal":r"_(nor_gl|norm_gl|gl_norm)", "alpha":r"_alpha", "rough":r"_rough"}.items()}


def realized_tree(obj):
    # These authoring files scatter branch and leaf geometry through Geometry Nodes.
    for mod in obj.modifiers:
        if mod.type != "NODES" or not mod.node_group:
            continue
        group = mod.node_group.copy()
        mod.node_group = group
        target = next(n for n in group.nodes if n.type=="GROUP_OUTPUT" and n.is_active_output)
        geometry = next(s for s in target.inputs if s.type=="GEOMETRY" and s.is_linked)
        source = geometry.links[0].from_socket
        realize = group.nodes.new("GeometryNodeRealizeInstances")
        group.links.new(source,realize.inputs["Geometry"])
        group.links.new(realize.outputs["Geometry"],geometry)


def reduce_mesh(obj, target):
    actual = sum(len(p.vertices)-2 for p in obj.data.polygons)
    if actual > target:
        modifier = obj.modifiers.new("Field LOD","DECIMATE")
        modifier.ratio = min(1.,target/actual)
        modifier.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return sum(len(p.vertices)-2 for p in obj.data.polygons)


def separate_surfaces(mesh):
    """Copy per-corner UVs. A large population of tiny leaves must not exhaust the trunk budget."""
    mesh.calc_loop_triangles()
    count=len(mesh.loop_triangles)
    ids=np.empty(count,dtype="i4")
    triangles=np.empty(count*3,dtype="i4")
    corners=np.empty(count*3,dtype="i4")
    points=np.empty(len(mesh.vertices)*3,dtype="f4")
    uv=np.empty(len(mesh.loops)*2,dtype="f4")
    mesh.loop_triangles.foreach_get("material_index",ids)
    mesh.loop_triangles.foreach_get("vertices",triangles)
    mesh.loop_triangles.foreach_get("loops",corners)
    mesh.vertices.foreach_get("co",points)
    mesh.uv_layers.active.uv.foreach_get("vector",uv)
    for index in np.unique(ids):
        keep=ids==index
        faces=triangles.reshape(-1,3)[keep]
        used,local=np.unique(faces,return_inverse=True)
        part=bpy.data.meshes.new("Surface")
        part.vertices.add(len(used))
        part.vertices.foreach_set("co",points.reshape(-1,3)[used].ravel())
        part.loops.add(faces.size)
        part.loops.foreach_set("vertex_index",local.astype("i4").ravel())
        part.polygons.add(len(faces))
        part.polygons.foreach_set("loop_start",np.arange(0,faces.size,3,dtype="i4"))
        part.polygons.foreach_set("use_smooth",np.ones(len(faces),dtype=bool))
        part.update(calc_edges=True)
        layer=part.uv_layers.new(name="UVMap")
        layer.uv.foreach_set("vector",uv.reshape(-1,2)[corners.reshape(-1,3)[keep]].ravel())
        part.materials.append(mesh.materials[index])
        yield part


def weld_scan(obj,height):
    # Scanned rocks and bark often contain coincident UV seams. Weld coordinates while
    # retaining per-corner UVs so either side of an island simplifies along the same edge.
    bm=bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm,verts=bm.verts,dist=height*.000045)
    bm.to_mesh(obj.data)
    bm.free()


def lod_objects(scene,name,mesh,budget,far_budget,height):
    split=len(mesh.materials)>1
    surfaces=list(separate_surfaces(mesh)) if split else [mesh]
    levels=[[],[]]
    for part in surfaces:
        key=part.materials[0].name
        if name in ("grove_tree","crooked_tree"):
            share=.23 if "leaves" not in key and "branches" not in key else .61 if "leaves" in key else .16
        elif split:
            share=.52 if "leaf" not in key and "twig" not in key else .48
        else:
            share=1.0
        piece=bpy.data.objects.new("Specimen",part)
        scene.collection.objects.link(piece)
        if height>=1.0 and "leaves" not in key and "branches" not in key and "leaf" not in key:
            weld_scan(piece,height)
        reduce_mesh(piece,max(96,int(budget*share)))
        levels[0].append(piece)
        if far_budget:
            far=piece.copy()
            far.data=piece.data.copy()
            scene.collection.objects.link(far)
            reduce_mesh(far,max(100,int(far_budget*share)))
            levels[1].append(far)
    result=[]
    for level,parts in enumerate(levels):
        if not parts:continue
        bpy.ops.object.select_all(action="DESELECT")
        for obj in parts:obj.select_set(True)
        bpy.context.view_layer.objects.active=parts[0]
        if len(parts)>1:bpy.ops.object.join()
        obj=parts[0]
        obj.name=name+("_far" if level else "")
        result.append(obj)
    return result


def extract(pack, folder_name, specs):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    folder = SOURCES/folder_name
    source = next(folder.glob("*.blend"))
    with bpy.data.libraries.load(str(source)) as (available, target):
        names = {}
        for key, base, _, _ in specs:
            aliases = sorted(n for n in available.objects if n==base or re.fullmatch(re.escape(base)+r"\.\d+",n))
            names[key] = aliases[0]
        target.objects = list(names.values())
    originals = {o.name:o for o in target.objects}
    mats, descriptions, exports = {}, {}, []
    for name, _, budget, height in specs:
        original = originals[names[name]]
        scene.collection.objects.link(original)
        realized_tree(original)
        graph = bpy.context.evaluated_depsgraph_get()
        source_mesh = bpy.data.meshes.new_from_object(original.evaluated_get(graph),preserve_all_data_layers=True,depsgraph=graph)
        initial = sum(len(p.vertices)-2 for p in source_mesh.polygons)
        # Preserve authored orientation, remove set dressing translation and put the actual base at zero.
        source_mesh.transform(original.matrix_world.to_3x3().to_4x4())
        verts = [v.co for v in source_mesh.vertices]
        low = Vector([min(v[i] for v in verts) for i in range(3)])
        high = Vector([max(v[i] for v in verts) for i in range(3)])
        base_points = [v for v in verts if v.z < low.z + .024*(high.z-low.z)]
        pivot = Vector((float(np.median([v.x for v in base_points])),float(np.median([v.y for v in base_points])),low.z))
        scale = height/(high.z-low.z)
        source_mesh.transform(Matrix.Scale(scale,4) @ Matrix.Translation(-pivot))
        for i, material in enumerate(list(source_mesh.materials)):
            if material is None:
                continue
            key = re.sub(r"\.\d+$","", material.name).replace(" ","_")
            if key not in mats:
                description = image_maps(material,folder/"textures")
                if not description['color']:
                    raise RuntimeError(f"{name}: missing source color for {key}: {description}")
                mats[key] = bpy.data.materials.new("field__"+key)
                descriptions[key] = description
            source_mesh.materials[i] = mats[key]
        scene.collection.objects.unlink(original)
        far_budget = max(400,int(budget*(.22 if "tree" in name else .16))) if height>=1.15 else 0
        models = lod_objects(scene,name,source_mesh,budget,far_budget,height)
        exports.extend(models)
        dims = (high-low)*scale
        triangles = [sum(len(p.vertices)-2 for p in o.data.polygons) for o in models]
        record = {"source":names[name],"height":height,"width":round(dims.x,3),"depth":round(dims.y,3),
                  "sourceTriangles":initial,"nearTriangles":triangles[0]}
        if len(triangles)>1:record["farTriangles"]=triangles[1]
        manifest[name] = {"pack":pack,**record}
        print("SPECIMEN",name,record,flush=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in exports:o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(CACHE/(pack+"-mesh.glb")),export_format="GLB",use_selection=True,
                              export_animations=False,export_cameras=False,export_lights=False,export_yup=True)
    (CACHE/(pack+"-maps.json")).write_text(json.dumps({"folder":folder_name,"materials":descriptions},indent=2))


if __name__=="__main__":
    assert bpy.app.background
    CACHE.mkdir(exist_ok=True,parents=True)
    manifest = {}
    for pack,(folder,specs) in PACKS.items():extract(pack,folder,specs)
    (ROOT/"coop/east/model_catalog.json").write_text(json.dumps(manifest,indent=2)+"\n")
