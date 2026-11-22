"""Embed the supplied scan maps in each regional glTF, keeping foliage coverage."""
import io
import json
import struct
import sys
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image
from eastern_rock_mesh import close_shelf, feather_root_edges

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache/world-expansion"
SOURCES = ROOT / "art/scenes_assets"
OUTPUT = ROOT / "art/field_regions"


def decode_exrs(requests):
    folder = CACHE / "linear-maps"
    folder.mkdir(parents=True,exist_ok=True)
    entries = []
    for path,size in requests:
        target = folder / (path.name + f"-{size}.npy")
        if not target.exists() or target.stat().st_mtime < path.stat().st_mtime:
            entries.append([str(path), size, str(target)])
    if entries:
        manifest = folder / "sources.json"
        manifest.write_text(json.dumps(entries))
        subprocess.run([str(ROOT/"scripts/start-blender.sh"),"--background","--factory-startup","--python-exit-code","1",
                        "--python",str(ROOT/"scripts/read-eastern-exr.py"),"--",str(manifest)],check=True)


def sample(path, size):
    if path.suffix.lower() == ".exr":
        linear = CACHE / "linear-maps" / (path.name + f"-{size}.npy")
        if not linear.exists() or linear.stat().st_mtime < path.stat().st_mtime:
            decode_exrs([(path,size)])
        return Image.fromarray(np.load(linear))
    with Image.open(path) as source:
        image = source.copy()
    image.thumbnail((size, size), Image.Resampling.LANCZOS)
    return image


def encode(image, alpha=False):
    stream = io.BytesIO()
    if alpha:
        image.save(stream, "PNG", compress_level=7)
    else:
        image.convert("RGB").save(stream, "JPEG", quality=85, optimize=True)
    return stream.getvalue()


def pack(name):
    raw = (CACHE / (name + "-mesh.glb")).read_bytes()
    n = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20+n])
    binary = bytearray(raw[28+n:28+n+doc["buffers"][0]["byteLength"]])
    book = json.loads((CACHE / (name+"-maps.json")).read_text())
    folder = SOURCES / book["folder"] / "textures"
    decode_exrs({(folder / maps[key], size) for maps in book["materials"].values()
                 for key,size in [("normal",512),("rough",384)] if maps[key] and maps[key].endswith(".exr")})
    doc.update(images=[], textures=[], samplers=[{"magFilter":9729,"minFilter":9987,"wrapS":10497,"wrapT":10497}])
    used = {}
    def texture(key, image, alpha=False):
        if key not in used:
            data = encode(image, alpha)
            binary.extend(bytes(-len(binary) % 4))
            idx = len(doc["bufferViews"])
            doc["bufferViews"].append({"buffer":0,"byteOffset":len(binary),"byteLength":len(data)})
            binary.extend(data)
            i = len(doc["images"])
            doc["images"].append({"name":key,"bufferView":idx,"mimeType":"image/png" if alpha else "image/jpeg"})
            doc["textures"].append({"sampler":0,"source":i})
            used[key] = i
        return {"index":used[key]}
    for mat in doc["materials"]:
        key = mat["name"].removeprefix("field__")
        maps = book["materials"][key]
        color = sample(folder/maps["color"], 1024)
        if maps["alpha"]:
            color = color.convert("RGBA")
            color.putalpha(sample(folder/maps["alpha"], 1024).convert("L").resize(color.size))
        cutout = "A" in color.getbands() and color.getchannel("A").getextrema()[0] < 240
        albedo = texture(key+"_diff",color,cutout)
        pbr = {"baseColorTexture":albedo, "metallicFactor":0, "roughnessFactor":.91}
        mat.clear()
        mat.update(name=key,pbrMetallicRoughness=pbr,doubleSided=True)
        if cutout:
            mat.update(alphaMode="MASK",alphaCutoff=.36)
        if maps["normal"]:
            normal = sample(folder/maps["normal"], 512)
            mat["normalTexture"] = {**texture(maps["normal"],normal),"scale":.76}
        if maps["rough"]:
            rough = sample(folder/maps["rough"], 384).convert("L")
            arm = Image.merge("RGB",(Image.new("L",rough.size,255),rough,Image.new("L",rough.size,0)))
            pbr.update(metallicRoughnessTexture=texture(maps["rough"],arm),roughnessFactor=1)
    if name == "verdant":
        feather_root_edges(doc,binary)
    if name == "namaqua":
        cliff = ROOT / "coop/coast"
        material = {"name": "solid_stratified_rock", "doubleSided": False,
                    "pbrMetallicRoughness": {"baseColorTexture": texture("shelf_returns",sample(cliff/"cliff_color.jpg",1024)),
                                             "metallicFactor": 0, "roughnessFactor": .93},
                    "normalTexture": {**texture("shelf_returns_normal",sample(cliff/"cliff_normal.jpg",512)),"scale":.70}}
        close_shelf(doc, binary, len(doc["materials"]))
        doc["materials"].append(material)
    binary.extend(bytes(-len(binary)%4))
    doc["buffers"][0]["byteLength"] = len(binary)
    js = json.dumps(doc,separators=(",",":")).encode()
    js += b" " * (-len(js)%4)
    header = struct.pack("<4sIII4s",b"glTF",2,28+len(js)+len(binary),len(js),b"JSON")
    (OUTPUT/(name+".glb")).write_bytes(header+js+struct.pack("<I4s",len(binary),b"BIN\0")+binary)
    print(name,len(doc["meshes"]),len(doc["images"]),len(binary),flush=True)


def store_cover():
    ground = ROOT / "coop/east/maps"
    for name in json.loads((ROOT/"coop/east/cover.json").read_text()):
        tiles = [Image.open(CACHE/"cover"/f"{name}-{i}.png").convert("RGBA") for i in range(3)]
        width,height = tiles[0].size
        atlas = Image.new("RGBA",(3*width,height))
        for index,tile in enumerate(tiles):
            atlas.paste(tile,(width*index,0))
        atlas.save(ground/(name+".png"),optimize=True)

if __name__ == "__main__":
    if "--cover-only" in sys.argv:
        store_cover()
        sys.exit(0)
    OUTPUT.mkdir(parents=True,exist_ok=True)
    ground = ROOT / "coop/east/maps"
    ground.mkdir(exist_ok=True)
    for biome, folder, source, resolution in [
            ("loam","verdant_trail","forest_ground_04","2k"),
            ("litter","verdant_trail","forest_leaves_04","4k"),
            ("gravel","namaqualand","gravelly_sand","4k"),
            ("sand","namaqualand","sandy_gravel_02","4k")]:
        for role,channel,ext in [("color","diff","jpg"),("normal","nor_gl","exr")]:
            img = sample(SOURCES/folder/"textures"/f"{source}_{channel}_{resolution}.{ext}",1024)
            (ground/f"{biome}_{role}.jpg").write_bytes(encode(img))
    for biome in ("verdant","namaqua"):
        pack(biome)
