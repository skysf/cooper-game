#!/usr/bin/env python3
"""List cooperative-game meshes, texture dependencies and rig metadata without rebuilding."""

import argparse
import hashlib
import json
import os
import re
import runpy
import struct
import subprocess
from collections import defaultdict
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
COOP = ROOT / "coop"
GLB = runpy.run_path(str(ROOT / "skills/game-3d-blender/scripts/inspect_glb.py"))
IMAGE = GLB["Image"]
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".tga", ".hdr", ".exr", ".ktx2", ".svg"}
REF = re.compile(r'["\']res://([^"\'\r\n]+)["\']')
SCENE_IMPORT = ("meshes/generate_lods", "meshes/create_shadow_meshes", "nodes/root_scale",
                "meshes/force_disable_compression", "skins/use_named_skins", "animation/import",
                "animation/fps", "gltf/embedded_image_handling", "gltf/texture_map_mode")
TEXTURE_IMPORT = ("compress/mode", "compress/high_quality", "compress/normal_map",
                  "mipmaps/generate", "process/size_limit")

# Explicit pairings document intended provenance. Availability is always checked on disk.
SOURCES = {
    "headlands": ("scripts/build-coast.py", "coop/coast_layout.json"),
    "sky_character": ("art/characters/sky_character.blend", "art/characters/sky_head_v3.blend",
                      "art/characters/locomotion/player_locomotion.blend"),
    "camp_backpack": ("art/camp_backpack.blend", "scripts/build-camp-backpack.py"),
    "camp_cap": ("art/camp_cap.blend", "scripts/build-camp-clothing.py"),
    "camp_jacket": ("art/camp_jacket.blend", "scripts/build-camp-clothing.py"),
    "camp_pants": ("art/camp_pants.blend", "scripts/build-camp-clothing.py"),
    "camp_boot": ("art/camp_boot.blend", "scripts/build-camp-wearables.py"),
    "camp_helmet": ("art/camp_helmet.blend", "scripts/build-camp-wearables.py"),
    "camp_lantern": ("art/camp_lantern.blend", "scripts/build-camp-lantern.py"),
    "camp_table": ("art/camp_table.blend", "scripts/build-camp-table.py", "scripts/refine-camp-furniture.py"),
    "camp_water_jug": ("art/camp_table.blend", "scripts/build-camp-table.py"),
    "wood_chair": ("art/wood_chair.blend", "scripts/refine-camp-furniture.py"),
    "iron_furnace": ("art/iron_furnace.blend", "scripts/build-iron-furnace.py"),
    "camp_red_spaceship": ("art/vehicles/source/红色科幻飞船.glb", "scripts/build-camp-spaceship.py"),
    "food_apple": ("art/household/GalaApple_01_BLEND/GalaApple_01_BLEND.blend", "scripts/build-camp-household.py"),
    "food_bread": ("art/household/BreadRoll_001_Blend/BreadRoll.blend", "scripts/build-camp-household.py"),
    "table_babushka": ("art/household/Babushka_BLEND/Babushka.blend", "scripts/build-camp-household.py"),
    "table_gnome": ("art/household/StrawberryGardenGnomeFigurine_BLEND/StrawberryGardenGnomeFigurine.blend",
                    "scripts/build-camp-household.py"),
    "material_wood": ("art/camp_materials/material_wood.blend",),
    "material_tarp": ("art/camp_materials/material_tarp.blend",),
    "shore_boulder": ("art/rocks/boulder_01_4k/boulder_01_4k.blend", "scripts/build-camp-stones.py"),
    "grass_medium_01": ("art/vegetation/grass_medium_01_4k/grass_medium_01_4k.blend", "scripts/build-camp-grass.py"),
    "coastal_dunegrass": ("art/vegetation/coastal_dunegrass.blend", "scripts/build-coast-dunegrass.py"),
    "creek_ostrich_fern": ("art/vegetation/creek_ostrich_fern.blend", "scripts/build-creek-ostrich-fern.py"),
    "luming_streamed_crown": ("art/vegetation/luming_streamed_crown.blend", "scripts/build-streamed-crown-pilot.py"),
    "wicker_basket": ("art/containers_storage/wicker_basket_02_4k.blend/wicker_basket_02_4k.blend",),
    "wood_crate": ("art/containers_storage/wooden_crate_01_4k.blend/wooden_crate_01_4k.blend",),
    "military_crate": ("art/containers_storage/wooden_military_crate_4k.blend/wooden_military_crate_4k.blend",),
    "wood_barrel": ("art/containers_storage/wooden_barrels_01_4k.blend/wooden_barrels_01_4k.blend",),
    "wood_barrel_tall": ("art/containers_storage/wooden_barrels_01_4k.blend/wooden_barrels_01_4k.blend",),
    "herb_bundle": ("scripts/build-wild-people-icons.py",),
    "hide": ("dist/ui-mockup/3d/hide/hide.blend",),
    "eagle_feather": ("dist/ui-mockup/3d/eagle/eagle.blend",),
    "eagle_claw": ("dist/ui-mockup/3d/eagle/eagle.blend",),
    "pine_mature_refined": ("art/pine_tree_01_trail.blend", "scripts/build-pine-pilot.py"),
}
for stem in ("cabin_floor", "cabin_wall", "cabin_doorway", "cabin_roof"):
    SOURCES[stem] = ("art/cabin_kit.blend", "scripts/build-cabin-kit.py")
for stem in ("coal", "coal_mine", "coal_seam", "iron_ore", "iron_ingot", "iron_mine", "iron_seam"):
    SOURCES[stem] = ("art/mines/rainline_mines.blend", "scripts/build-camp-mines.py")
for stem in ("lakeside_bulrush", "lakeside_hazel"):
    SOURCES[stem] = ("art/vegetation/lake_margin_plants.blend", "scripts/build-lake-margin-plants.py")
SOURCES["campfire"] = ("dist/ui-mockup/3d/food/food.blend", "coop/materials/campfire.gdshader")
for stem in ("eagle_meat", "dog_meat", "crocodile_meat_raw", "crocodile_meat_grilled", "crocodile_sandwich"):
    SOURCES[stem] = ("dist/ui-mockup/3d/food/food.blend",)
for stem in ("rope", "rope_ladder", "wood_plank", "wicker_strip", "wood_sign"):
    SOURCES[stem] = ("dist/ui-mockup/3d/woodcraft/woodcraft.blend",)
for stem in ("stone_round", "stone_flat", "stone_sharp"):
    SOURCES[stem] = ("art/rocks/rock_moss_set_01_4k/rock_moss_set_01_4k.blend", "scripts/build-camp-stones.py")
for stem, name in (("katana", "antique_katana_01"), ("rifle", "bolt_action_rifle_7_62"), ("pistol", "service_pistol")):
    SOURCES[stem] = (f"art/weapons/source/{name}_4k.blend/{name}_4k.blend", "scripts/build-camp-weapons.py")
ANIMAL_INPUTS = {
    "camp_crocodile": "鳄鱼_3D_hunyuan-3d_v3.1_pro.glb",
    "camp_eagle": "老鹰_3D_hunyuan-3d_v3.1_pro.glb",
    "camp_mastiff": "藏獒_3D_tripo3D_h3_1.glb",
}


def relative(path):
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)


def text_files():
    files = []
    for folder, dirs, names in os.walk(COOP):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        files.extend(Path(folder, name) for name in names)
    return sorted(files)


def import_settings(path, keys):
    sidecar = path.with_name(path.name + ".import")
    if not sidecar.is_file():
        return {}
    fields = dict(re.findall(r"(?m)^([\w/]+)=([^\n]*)$", sidecar.read_text()))
    return {key: fields[key] for key in keys if key in fields}


def add_ref(refs, path, file, line, kind="literal"):
    refs[path].add((file, line, kind))


def scan_references(files):
    refs = defaultdict(set)
    dynamic = []
    for path in files:
        if path.suffix not in {".gd", ".tscn", ".tres", ".json", ".godot", ".gdshader"}:
            continue
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for name in REF.findall(line):
                if "%" in name or "{" in name:
                    dynamic.append({"template": name, "source": relative(path), "line": line_no})
                else:
                    add_ref(refs, name, relative(path), line_no)
    return refs, dynamic


def line_of(path, token):
    return next(index for index, line in enumerate(path.read_text().splitlines(), 1) if token in line)


def collect_dynamic(refs, files, world):
    grove = COOP / "grove.gd"
    stages = re.findall(r'"id":\s*"([^"]+)"', grove.read_text().split("const FINAL_AGE", 1)[0])
    stage_loader = line_of(grove, "%s_%s.glb")
    for spec in world["grove"]["species"].values():
        prefix = spec["modelPrefix"].removeprefix("res://")
        for stage in stages:
            add_ref(refs, f"{prefix}_{stage}.glb", relative(grove), stage_loader,
                    "world.json grove species × growth stage")
    panel = COOP / "camp_storage_panel.gd"
    if panel.exists():
        survival = (COOP / "survival.gd").read_text()
        registry = survival.split("const ITEM_NAMES := {", 1)[1].split("}", 1)[0]
        names = set(re.findall(r'"([a-z0-9_]+)"\s*:', registry))
        recipes = COOP / "camp_storage.gd"
        if recipes.exists():
            names.update(re.findall(r'"kind"\s*:\s*"([a-z0-9_]+)"', recipes.read_text()))
        icon_loader = line_of(panel, "inventory_%s")
        for path in files:
            if path.parent != COOP / "textures" or path.suffix.lower() not in IMAGE_SUFFIXES:
                continue
            if path.stem.removeprefix("inventory_") in names and path.name.startswith("inventory_"):
                add_ref(refs, str(path.relative_to(COOP)), relative(panel),
                        icon_loader, "inventory or recipe icon")


def refs_for(refs, key):
    return [{"source": file, "line": line, "kind": kind}
            for file, line, kind in sorted(refs.get(key, ()))]


def sources_for(path, tracked, streamed=False):
    name = path.stem
    if streamed:
        matches = ("shared/woodland.glb", ".cache/coop-world-source/woodland.glb", "scripts/coop-zones.py")
    elif relative(path).startswith("coop/wild_people/"):
        matches = (f"art/wild_man/{name}.blend", "scripts/build-wild-people.py")
    elif name in ANIMAL_INPUTS:
        matches = (f"art/animals/{name}.blend", f"art/animals/{name}.glb",
                   f"art/animals/source/Animals/{ANIMAL_INPUTS[name]}")
    elif name in SOURCES:
        matches = SOURCES[name]
    elif name.startswith("pine_"):
        matches = ("scripts/prepare-pines.py", "docs/pine-tree.md")
    elif name.startswith(("birch_", "spruce_")):
        matches = ("scripts/build-tree-species.mjs", "scripts/birch-textures.py")
    else:
        matches = ()
    return [{"path": item, "available": (ROOT / item).is_file(), "tracked": item in tracked}
            for item in matches]


def file_sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def web_pack_inventory(path):
    pack_bytes = path.stat().st_size
    with path.open("rb") as pack:
        magic, version, major, _, _, flags, data_start, directory = struct.unpack("<4s5I2Q", pack.read(40))
        if (magic, version, major, flags) != (b"GDPC", 4, 4, 2) or not 40 <= data_start < directory < pack_bytes:
            raise ValueError("Expected an unencrypted Godot 4 Web export with a version 4 pack directory")
        pack.seek(directory)
        count, = struct.unpack("<I", pack.read(4))
        if count > (pack_bytes - pack.tell()) // 40:
            raise ValueError("PCK file count exceeds the available directory")
        entries = []
        for _ in range(count):
            length, = struct.unpack("<I", pack.read(4))
            if not 1 <= length <= pack_bytes - pack.tell() - 36:
                raise ValueError("PCK path length exceeds the available directory")
            name = pack.read(length).rstrip(b"\x00").decode("utf-8")
            offset, size, _, _ = struct.unpack("<2Q16sI", pack.read(36))
            if offset + data_start + size > directory:
                raise ValueError(f"Entry points beyond the PCK data: {name}")
            entries.append({"path": name, "bytes": size})
    texture_groups = {
        "camp_equipment": ("bolt_action_rifle_7_62", "service_pistol", "antique_katana_01"),
        "storage_containers": ("wicker_basket_02", "wooden_crate_01", "wooden_military_crate", "wooden_barrels_01"),
    }
    groups = {}
    for group, names in texture_groups.items():
        size = sum(item["bytes"] for item in entries if item["path"].endswith(".ctex")
                   and any(name in item["path"] for name in names))
        groups[group] = {"stored_texture_bytes": size, "share_of_pck": round(size / pack_bytes, 5)}
    return {"file": relative(path), "sha256": file_sha(path), "bytes": pack_bytes, "entries": len(entries),
            "texture_groups": groups, "largest_entries": sorted(entries, key=lambda entry: entry["bytes"], reverse=True)[:20]}


def texture_uses(material, context=()):
    for key, value in material.items():
        if not isinstance(value, dict):
            continue
        if key.endswith("Texture") and isinstance(value.get("index"), int):
            yield value["index"], ".".join((*context, key))
        else:
            yield from texture_uses(value, (*context, key))


def texture_roles(document):
    roles = defaultdict(set)
    textures = document.get("textures", [])
    for material in document.get("materials", []):
        for index, role in texture_uses(material):
            texture = textures[index]
            image = texture.get("source")
            if image is None:
                image = next((ext["source"] for ext in texture.get("extensions", {}).values() if "source" in ext), None)
            if image is not None:
                roles[image].add(role)
    return roles


def image_file(path):
    result = {"path": relative(path), "exists": path.is_file()}
    if result["exists"]:
        result.update(bytes=path.stat().st_size, godot_import=import_settings(path, TEXTURE_IMPORT))
        if IMAGE:
            try:
                with IMAGE.open(path) as texture:
                    result["dimensions"] = list(texture.size)
            except OSError:
                pass
    return result


def animation_bounds(document, clips):
    accessors = document.get("accessors", [])
    report = []
    for raw, clip in zip(document.get("animations", []), clips):
        inputs = [accessors[sampler["input"]] for sampler in raw["samplers"]]
        entry = dict(clip)
        if inputs and all(track.get("min") and track.get("max") for track in inputs):
            entry["first_key_seconds"] = min(track["min"][0] for track in inputs)
            entry["last_key_seconds"] = max(track["max"][0] for track in inputs)
        report.append(entry)
    return report


def sidecar_textures(path, files):
    # Godot 4 may extract GLB embedded images alongside the model. Prefix matches
    # are candidates, because the imported scene may use only some of those files.
    prefix = path.stem + "_"
    return [image_file(candidate) for candidate in files.get(path.parent, ())
            if candidate.name.startswith(prefix) and candidate.suffix.lower() in IMAGE_SUFFIXES]


def read_model(path, tracked, images_by_parent, streamed=False):
    report = {"file": relative(path), "sources": sources_for(path, tracked, streamed),
              "exists": path.is_file()}
    if not report["exists"]:
        return report
    detail = GLB["inspect_glb"](path)
    with path.open("rb") as stream:
        doc, _ = GLB["read_layout"](stream, detail["bytes"])
    nodes = doc.get("nodes", [])
    meshes = doc.get("meshes", [])
    roles = texture_roles(doc)
    textures = []
    missing_dependencies = []
    for index, (raw, metadata) in enumerate(zip(doc.get("images", []), detail["images"])):
        texture = {**metadata, "uses": sorted(roles[index])}
        uri = raw.get("uri", "")
        if uri.startswith("data:"):
            texture["storage"] = "data_uri"
        elif uri:
            # External URLs and escaped paths are recorded without a network request.
            resolved = (path.parent / unquote(uri)).resolve()
            if resolved.is_relative_to(ROOT) and not re.match(r"^[a-z][a-z0-9+.-]*:", uri, re.I):
                texture["file"] = image_file(resolved)
                if not texture["file"]["exists"]:
                    missing_dependencies.append(relative(resolved))
            else:
                texture["external_uri"] = uri
        else:
            texture["storage"] = "embedded"
        textures.append(texture)
    primitives = [primitive for mesh in meshes for primitive in mesh["primitives"]]
    triangle_counts = [sum(p["triangles"] for p in m["primitives"]) for m in detail["meshes"]]
    file_settings = import_settings(path, SCENE_IMPORT)
    report.update(
        bytes=detail["bytes"], sha256=file_sha(path), triangles=detail["triangles"],
        mesh_instances_triangles=sum(triangle_counts[n["mesh"]] for n in nodes if "mesh" in n),
        mesh_count=len(meshes), surfaces=len(primitives), materials=detail["materials"],
        declared_lod_nodes=[node["name"] for node in nodes if re.fullmatch(r"LOD\d+", node.get("name", ""))],
        mesh_details=[{"name": m["name"], "triangles": triangles,
                       "surfaces": len(m["primitives"])}
                      for m, triangles in zip(detail["meshes"], triangle_counts)],
        surfaces_with_vertex_colors=sum("COLOR_0" in p["attributes"] for p in primitives),
        surfaces_with_normals=sum("NORMAL" in p["attributes"] for p in primitives),
        surfaces_with_uv0=sum("TEXCOORD_0" in p["attributes"] for p in primitives),
        max_morph_targets=max((len(p.get("targets", [])) for p in primitives), default=0),
        textures=textures, missing_dependencies=missing_dependencies,
        extracted_texture_candidates=sidecar_textures(path, images_by_parent),
        godot_import=file_settings,
        skins=[{**skin, "joints_names": [nodes[index].get("name", str(index)) for index in raw["joints"]]}
               for skin, raw in zip(detail["skins"], doc.get("skins", []))],
        animations=animation_bounds(doc, detail["animations"]),
    )
    return report


def tracks_for(path, refs):
    content = path.read_text(encoding="utf-8")
    clips = []
    for part in re.split(r'(?m)^\[sub_resource type="Animation"[^\n]*\]\s*$', content)[1:]:
        name = re.search(r'(?m)^resource_name = "([^"]+)"', part)
        paths = re.findall(r'(?m)^tracks/\d+/path = NodePath\("([^"]+)"\)', part)
        if name:
            clips.append({"name": name[1], "tracks": len(paths),
                          "target_nodes": sorted({track.partition(":")[0] for track in paths}),
                          "target_bones": sorted({track.partition(":")[2] for track in paths if ":" in track})})
    return {"file": relative(path), "references": refs_for(refs, relative(path).removeprefix("coop/")),
            "sha256": file_sha(path), "sources": ["art/characters/locomotion/player_locomotion.blend"], "clips": clips}


def read_all_models(paths, tracked, images, streamed=False):
    rows = []
    for path in paths:
        try:
            rows.append(read_model(path, tracked, images, streamed))
        except (OSError, ValueError, KeyError, IndexError, TypeError) as exc:
            rows.append({"file": relative(path), "exists": path.is_file(), "error": str(exc)})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zones", type=Path, default=ROOT / "dist/coop/zones",
                        help="Built directory containing the seven GLBs streamed by terrain.gd.")
    parser.add_argument("--pck", type=Path, help="Also measure the contents of this Godot 4 Web export.")
    args = parser.parse_args()
    files = text_files()
    tracked = set(subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0"))
    refs, notes = scan_references(files)
    world = json.loads((COOP / "world.json").read_text())
    collect_dynamic(refs, files, world)
    by_parent = defaultdict(list)
    for path in files:
        if path.suffix.lower() in IMAGE_SUFFIXES:
            by_parent[path.parent].append(path)
    models = read_all_models((path for path in files if path.suffix == ".glb"), tracked, by_parent)
    for row in models:
        row["references"] = refs_for(refs, row["file"].removeprefix("coop/"))
    zones = args.zones.absolute()
    streamed = read_all_models((zones / f'{spec["id"]}.glb' for spec in world["chunks"]), tracked, {}, True)
    for item, spec in zip(streamed, world["chunks"]):
        name = spec["id"]
        item.update(id=name, world_manifest_bytes=spec["bytes"], world_z=[spec["lo"], spec["hi"]],
                    web_path=f"/coop/zones/{name}.glb",
                    native_path=f"Contents/Resources/zones/{name}.glb")
    textures = [{**image_file(COOP / name), "references": refs_for(refs, name)}
                for name in sorted(refs) if Path(name).suffix.lower() in IMAGE_SUFFIXES]
    animation_bindings = [tracks_for(path, refs) for path in files if path.suffix == ".tres"
                          and path.parent == COOP / "animations"]
    known_missing = sorted(name for name in refs if Path(name).suffix.lower() in IMAGE_SUFFIXES | {".glb"}
                           and not (COOP / name).is_file())
    errors = [row for row in [*models, *streamed] if row.get("error") or row.get("missing_dependencies")]
    result = {
        "schema": 1,
        "scope": {
            "literal_models": "Exact res:// references in coop scripts and resources, including dictionaries used by load().",
            "grove_models": "coop/world.json species expanded against coop/grove.gd STAGES.",
            "streamed_models": "coop/world.json chunks loaded by coop/terrain.gd; selected directory checked on disk.",
            "zone_directory": relative(zones),
            "global_texture_dependencies": "Direct textures and dynamic inventory icons; GLB texture uses are in each model.",
            "runtime_overrides": {
                "streamed_terrain": "coop/terrain.gd SURFACES replaces materials by mesh name.",
                "grass_instances": "coop/grass.gd applies grass.gdshader and grass_medium_01.png to mesh variants.",
                "shoreline_instances": "coop/coast_scene.gd creates rock, tree and fern batches and assigns terrain/ocean shaders.",
                "lake_geometry": "coop/lake.gd and coop/lake_bed.gd generate water, lake-bed, pondweed and ripple geometry.",
                "rigged_equipment": "coop/hiker.gd attaches or drives boots, hats, garment rigs and backpack; wild_people_scene.gd attaches weapons to grip_R/grip_L.",
            },
            "limits": "Counts are file metadata, not submitted frame triangles. Visibility, skinning, engine LOD, post-import materials and live behaviour need independent runtime checks.",
            "pillow_available": IMAGE is not None,
        },
        "summary": {
            "glbs_in_project": len(models),
            "glbs_with_references": sum(bool(row["references"]) for row in models),
            "streamed_glbs": len(streamed),
            "streamed_glbs_on_disk": sum(item["exists"] for item in streamed),
            "direct_or_dynamic_texture_files": len(textures),
            "glbs_with_skin": sum(bool(row.get("skins")) for row in models),
            "unreferenced_glbs": [row["file"] for row in models if not row["references"]],
            "missing_referenced_paths": known_missing,
            "read_or_dependency_errors": [row["file"] for row in errors],
        },
        "dynamic_templates": notes,
        "models": models,
        "streamed_models": streamed,
        "global_textures": textures,
        "animation_libraries": animation_bindings,
    }
    if args.pck:
        result["web_pck"] = web_pack_inventory(args.pck.absolute())
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
