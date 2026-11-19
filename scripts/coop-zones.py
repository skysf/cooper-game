"""Bake independently downloadable chunks from the licensed co-op Woodland GLB."""
import json
import random
import struct
import subprocess
from pathlib import Path
from math import floor

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist/coop/zones"
PROJECT = ROOT / "coop"
TEXTURES = PROJECT / "textures"
MATERIALS = PROJECT / "materials"
SOURCE = ROOT / ".cache/coop-world-source"
GROVE = json.loads((ROOT / "shared/coop-grove.json").read_text())
CHUNKS = [
    ("backcountry", -121, -101), ("camp", -101, -76),
    ("approach", -76, -64), ("creek", -64, -43),
    ("crossing", -43, -29), ("tower", -29, -7), ("ridge", -7, 14)
]
SURFACES = {
    "mud": ("trail", 1024, .85),
    "forest_floor": ("litter", 512, 1.0),
    "bark": ("bark_brown_01", 512, 1.0),
    "rock": ("mossy_rock", 512, .72),
    "wood": ("wood_planks", 512, 1.0)
}
TILED_SURFACES = {"forest_floor", "bark", "rock", "needles", "fern"}
TILE_WIDTH = 12.0


def materials():
    for name, (source, size, roughness) in SURFACES.items():
        resources = []
        for i, channel in enumerate(("diff", "nor_gl", "arm")):
            filename = name + "_" + channel + ".jpg"
            image = Image.open(ROOT / "shared/textures" / (source + "_" + channel + ".jpg")).convert("RGB")
            image.resize((size, size), Image.Resampling.LANCZOS).save(TEXTURES / filename, quality=83, optimize=True)
            resources.append(f'[ext_resource type="Texture2D" path="res://textures/{filename}" id="{i + 1}"]')
        (MATERIALS / (name + ".tres")).write_text(
            '[gd_resource type="StandardMaterial3D" load_steps=4 format=3]\n\n' + '\n'.join(resources)
            + '\n\n[resource]\nvertex_color_use_as_albedo = true\n'
            + f'roughness = {roughness}\nalbedo_texture = ExtResource("1")\n'
            + 'normal_enabled = true\nnormal_scale = 0.76\nnormal_texture = ExtResource("2")\n'
            + 'roughness_texture = ExtResource("3")\nroughness_texture_channel = 1\n'
            + 'ao_enabled = true\nao_light_affect = 0.6\nao_texture = ExtResource("3")\n'
            + 'texture_filter = 5\n')
    for surface, source in (("fern", "fern"), ("needles", "fir")):
        Image.open(ROOT / "shared/textures" / (source + ".png")).resize((256, 256), Image.Resampling.LANCZOS).save(
            TEXTURES / (surface + ".png"), optimize=True)
        (MATERIALS / (surface + ".tres")).write_text(
            '[gd_resource type="StandardMaterial3D" load_steps=2 format=3]\n'
            + f'[ext_resource type="Texture2D" path="res://textures/{surface}.png" id="1"]\n'
            + '[resource]\nvertex_color_use_as_albedo = true\ncull_mode = 2\ntransparency = 2\n'
            + 'alpha_scissor_threshold = 0.35\nalbedo_texture = ExtResource("1")\nroughness = 1.0\n')
    # Tree silhouettes on the far side of a streaming boundary. Each background tree is
    # replaced with its trunk, branches and needles as soon as its chunk is resident.
    rng = random.Random(913)
    card = Image.new("RGBA", (192, 320))
    ink = ImageDraw.Draw(card)
    ink.polygon([(94,319),(99,319),(97,9)], fill=(62,51,38))
    for j in range(64):
        y = 240-j*3.6
        width = 78*(y/240)**.85*rng.uniform(.7,1.0)
        for sign in (-1,1):
            tint = rng.randint(36,61)
            tip = 96+sign*width
            ink.line([(96,y-8),(tip,y+4)],fill=(54,51,36),width=2)
            for k in range(32):
                t=rng.random()
                x=96+(tip-96)*t
                base=y-11+t*9+rng.uniform(-4,4)
                ink.polygon([(x,base-6), (x+sign*rng.uniform(3,12),base+rng.uniform(6,16)),(x-sign*2,base+3)],
                            fill=(int(tint*.79),tint,int(tint*.67),255))
    card.save(TEXTURES / "distant_fir.png", optimize=True)


def source_meshes():
    data=(SOURCE/"woodland.glb").read_bytes()
    size=struct.unpack_from("<I", data, 12)[0]
    doc=json.loads(data[20:20+size])
    binary=memoryview(data)[28+size:]
    def accessor(id_):
        a=doc["accessors"][id_]; view=doc["bufferViews"][a["bufferView"]]
        dtype={5121:"u1",5123:"<u2",5125:"<u4",5126:"<f4"}[a["componentType"]]
        columns={"VEC3":3,"VEC4":4,"VEC2":2,"SCALAR":1}[a["type"]]
        return np.frombuffer(binary, dtype=dtype, count=a["count"]*columns,offset=view["byteOffset"]).reshape(-1,columns)
    for mesh in doc["meshes"]:
        name=mesh["name"]
        if name=="lantern_glass":
            continue
        prim=mesh["primitives"][0]
        attributes={k:accessor(v) for k,v in prim["attributes"].items()}
        triangles=accessor(prim["indices"]).reshape(-1,3)
        if name=="wood":
            # The shelter uses one box per board. Remove six adjacent rafters/boards
            # on the east pitch, leaving a real opening for the players' canvas patch.
            points=attributes["POSITION"].reshape(-1,24,3)
            lo=points.min(axis=1); hi=points.max(axis=1); mid=(lo+hi)*.5
            broken=(mid[:,0]>2.5)&(lo[:,1]>1.9)&(hi[:,1]>3.4)&(hi[:,2]-lo[:,2]<.45)&(abs(mid[:,2]+89.6)<1.14)
            # The A/B mesh also includes the block lamp's wooden cord and cap.
            # The co-op lantern supplies its own mounting hardware.
            old_lamp = np.isclose(mid[:, 0], 2.82) & np.isclose(mid[:, 2], -87.06)
            triangles=triangles[~(broken | old_lamp)[triangles[:,0]//24]]
        t_z=attributes["POSITION"][triangles,2].mean(axis=1)
        yield name,attributes,triangles,t_z


class Chunk:
    def __init__(self):
        self.blob=bytearray()
        self.doc={"asset":{"version":"2.0","generator":"Cooper Forest, CC0"},"scene":0,
                  "scenes":[{"nodes":[]}],"nodes":[],"meshes":[],"accessors":[],"bufferViews":[]}
    def append(self, arr, target, semantic):
        arr=np.ascontiguousarray(arr)
        view=len(self.doc["bufferViews"])
        raw=arr.tobytes()
        self.doc["bufferViews"].append({"buffer":0,"byteOffset":len(self.blob),"byteLength":len(raw),"target":target})
        self.blob.extend(raw)
        self.blob.extend(b'\0'*(-len(self.blob)%4))
        a={"bufferView":view,"count":len(arr),
           "type":{1:"SCALAR",2:"VEC2",3:"VEC3",4:"VEC4"}[arr.shape[1]],
           "componentType":{"uint8":5121,"uint16":5123,"uint32":5125,"float32":5126}[arr.dtype.name]}
        if semantic=="POSITION":
            a.update(min=arr.min(axis=0).tolist(),max=arr.max(axis=0).tolist())
        if semantic=="COLOR_0":
            a["normalized"]=True
        self.doc["accessors"].append(a)
        return len(self.doc["accessors"])-1
    def mesh(self,name,attributes,triangles):
        if not len(triangles):
            return
        vertices, indices=np.unique(triangles.reshape(-1),return_inverse=True)
        attrs={k:self.append(v[vertices],34962,k) for k,v in attributes.items()}
        index_id=self.append(indices.astype("uint16" if len(vertices)<65536 else "uint32").reshape(-1,1),34963,"INDEX")
        i=len(self.doc["meshes"])
        self.doc["meshes"].append({"name":name,"primitives":[{"indices":index_id,"attributes":attrs}]})
        self.doc["nodes"].append({"name":name,"mesh":i})
        self.doc["scenes"][0]["nodes"].append(i)
    def write(self,name):
        self.doc["buffers"]=[{"byteLength":len(self.blob)}]
        js=json.dumps(self.doc,separators=(',',':')).encode()
        js+=b' '*(-len(js)%4)
        header=struct.pack("<4sIII4s",b'glTF',2,28+len(js)+len(self.blob),len(js),b'JSON')
        result=header+js+struct.pack("<I4s",len(self.blob),b'BIN\0')+self.blob
        (OUT/(name+".glb")).write_bytes(result)
        return len(result)


def grass_cells(plants, chunks):
    cells = {chunk["id"]: {} for chunk in chunks}
    for variant, *plant in plants:
        x, _, z = plant[:3]
        chunk = next((chunk for chunk in chunks if chunk["lo"] <= z < chunk["hi"]), None)
        if chunk is None:
            continue
        origin = (floor(x / 12) * 12 + 6, floor(z / 12) * 12 + 6)
        patch = cells[chunk["id"]].setdefault(origin, [[], [], []])
        patch[variant].append(plant)
    return {chunk: [[x, z, variants] for (x, z), variants in patches.items()]
            for chunk, patches in cells.items()}


def main():
    subprocess.run(["node", "scripts/build-scene.mjs", "--coop"], cwd=ROOT, check=True)
    layout = json.loads((SOURCE / "scene.json").read_text())
    for d in (OUT,TEXTURES,MATERIALS):
        d.mkdir(parents=True,exist_ok=True)
    materials()
    chunks=[Chunk() for _ in CHUNKS]
    for name,attrs,tri,z in source_meshes():
        if name in TILED_SURFACES:
            center_x = attrs["POSITION"][tri, 0].mean(axis=1)
            columns = np.floor(center_x / TILE_WIDTH + 0.5).astype(np.int16)
        for chunk,(_,a,b) in zip(chunks,CHUNKS):
            section = (z >= a) & (z < b)
            if name not in TILED_SURFACES:
                chunk.mesh(name, attrs, tri[section])
                continue
            # Keep vertex positions and normals while giving the frustum smaller bounds.
            for column in np.unique(columns[section]):
                chunk.mesh(f"{name}__{column + 10}", attrs, tri[section & (columns == column)])
    manifest=[]
    for chunk,(id_,a,b) in zip(chunks,CHUNKS):
        size=chunk.write(id_)
        manifest.append(dict(id=id_,lo=a,hi=b,bytes=size))
    # Collision and imagery both use the same metre coordinates as the original world.
    world={k:layout[k] for k in ("shelter","player","weather","route","render","sunDirection")}
    rocks = {(item["x"], item["z"]): item for item in layout["objects"] if item["type"] == "rock"}
    obstacles = []
    for item in layout["obstacles"]:
        if item["type"] == "rock":
            rock = rocks[item["x"], item["z"]]
            item = dict(item, height=round(rock["height"]*.94, 4), yaw=rock["yaw"])
        obstacles.append(item)
    water = json.loads((PROJECT / "water_layout.json").read_text())
    for rock in water["boulders"]:
        obstacles.append(dict(type="rock", x=rock["x"], z=rock["z"], r=rock["radius"],
                              flightRadius=round(rock["size"]*.6352, 4), depth=round(rock["size"]*.9145, 4),
                              height=round(rock["size"]*.8819, 4), yaw=-rock["yaw"]))
    # Covers the 1.58 x 0.72 m tabletop without closing the shelter's main aisle.
    for x in (2.65, 3.10, 3.55):
        obstacles.append(dict(type="table", x=x, z=-88.95, r=.35))
    for dx in (-1.35,1.35):
        for dz in (-1.35,1.35):
            obstacles.append(dict(type="tower",x=10.8+dx,z=-15.1+dz,r=.18))
    # Root footprints are fixed across all ages and shared by server and client.
    for tree in GROVE["trees"]:
        obstacles.append(dict(type=tree.get("species", "pine"), x=tree["x"], z=tree["z"], r=tree["radius"]))
    trees=[[o['x'],o['z'],o['height'],o['yaw']] for o in layout["objects"] if o["type"]=="fir"]
    world.update(spawn=[1.9,-85],sites={"wood":[-9,-53],"tarp":[9,-17],"repair":[1.9,-89.6]},
                 obstacles=obstacles,chunks=manifest,trees=trees,grove=GROVE,
                 grass=grass_cells(layout["grass"], manifest))
    (PROJECT/"world.json").write_text(json.dumps(world,separators=(',',':')))
    print("Resident material source bytes:",sum(p.stat().st_size for p in TEXTURES.iterdir() if p.suffix in ('.png','.jpg')))
    print("Ground chunks:",[(c['id'],c['bytes']) for c in manifest])


if __name__=="__main__":
    main()
