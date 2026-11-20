"""Read the generated coastal triangles and sample the benchmark camera rays."""
from pathlib import Path
import json
import math
import struct

import numpy as np

root = Path.cwd()
asset = root / "coop/coast/headlands.glb"
raw = asset.read_bytes()
length = struct.unpack_from("<I", raw, 12)[0]
doc = json.loads(raw[20:20 + length])
binary = 28 + length


def accessor(index):
    a = doc["accessors"][index]
    v = doc["bufferViews"][a["bufferView"]]
    start = binary + v.get("byteOffset", 0) + a.get("byteOffset", 0)
    count = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    dtype = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[a["componentType"]]
    value = np.frombuffer(raw, offset=start, count=a["count"] * count, dtype=dtype).reshape(-1, count)
    return value.astype("float64") / 255.0 if a.get("normalized") else value


camera = np.array([-85.1, .397693982644341 + 1.67, -51.0])
yaw, pitch, fov = 1.4809, -.34075, 78.0
right = np.array([math.cos(yaw), 0., -math.sin(yaw)])
forward = np.array([-math.sin(yaw)*math.cos(pitch), math.sin(pitch), -math.cos(yaw)*math.cos(pitch)])
up = np.cross(right, forward)
focal = math.tan(math.radians(fov) * .5)
part = []
for mesh in doc["meshes"]:
    for primitive in mesh["primitives"]:
        a = primitive["attributes"]
        pos = accessor(a["POSITION"])
        idx = accessor(primitive["indices"]).reshape(-1, 3)
        points = pos[idx].astype("float64")
        c = points.mean(axis=1)
        near = ((c[:,0] < -84.5) & (c[:,0] > -100) & (abs(c[:,2] + 51.0) < 12.0) & (c[:,1] > -2.7))
        if not near.any():
            continue
        part.append((points[near], accessor(a["NORMAL"])[idx[near]], accessor(a["COLOR_0"])[idx[near]],
                     [mesh["name"]] * int(near.sum())))
tris, normals, colors, names = [np.concatenate(columns) for columns in zip(*part)]
edge1 = tris[:,1] - tris[:,0]
edge2 = tris[:,2] - tris[:,0]
p = camera - tris[:,0]
q = np.cross(p,edge1)
gn = np.cross(edge1,edge2)
gn /= np.linalg.norm(gn,axis=1)[:,None]
gn *= np.sign(gn[:,1])[:,None]


def probe(x,y):
    ray = forward + (2*(x+.5)/1280-1) * focal * right + (1-2*(y+.5)/720) * focal * 720/1280 * up
    s = np.cross(ray,edge2)
    det = (edge1*s).sum(axis=1)
    with np.errstate(divide="ignore",invalid="ignore"):
        u = (p*s).sum(axis=1)/det
        v = (q*ray).sum(axis=1)/det
        t = (edge2*q).sum(axis=1)/det
    candidates = (t>.07) & (u>=0) & (v>=0) & (u+v<=1)
    if not candidates.any():
        return None
    i=np.argmin(np.where(candidates,t,np.inf))
    weight=np.array([1-u[i]-v[i],u[i],v[i]])
    n=(normals[i]*weight[:,None]).sum(axis=0)
    n/=np.linalg.norm(n)
    tone=(colors[i]*weight[:,None]).sum(axis=0)
    blend=abs(n)**5
    blend/=blend.sum()
    return {"pixel":[x,y],"tile":names[i],"xyz":(camera+ray*t[i]).round(4).tolist(),
            "facet_normal":gn[i].round(4).tolist(),"authored_normal":n.round(4).tolist(),
            "sand_green_path_lichen":tone.round(4).tolist(),
            "original_rock_x_y_z_weights":blend.round(4).tolist()}

samples = [probe(x,y) for x,y in [(120,290),(191,170),(205,250),(209,333),(215,390),(234,488),
           (277,200),(282,300),(296,402),(335,435),(365,452),(413,365),(350,567),(660,616)]]
print(json.dumps({"camera_xyz":camera.tolist(),"fov":fov,"samples":samples},indent=2))
