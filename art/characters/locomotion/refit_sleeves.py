"""Apply sleeve binding to an already exported camp_jacket.glb without re-encoding geometry or textures."""
import json
import struct
import sys
from pathlib import Path
import numpy as np
from sleeve_weights import smooth, sleeve_weights

src, dst = map(Path,sys.argv[1:])
raw = bytearray(src.read_bytes())
size = struct.unpack_from("<I",raw,12)[0]
doc = json.loads(raw[20:20+size])
offset = 28+size
formats = {5121:"u1",5123:"<u2",5125:"<u4",5126:"<f4"}

def accessor(index):
    a=doc["accessors"][index]
    view=doc["bufferViews"][a["bufferView"]]
    dtype=np.dtype(formats[a["componentType"]])
    n={"SCALAR":1,"VEC3":3,"VEC4":4}[a["type"]]
    return np.ndarray((a["count"],n),dtype,raw,offset+view.get("byteOffset",0)+a.get("byteOffset",0),
                      (view.get("byteStride",n*dtype.itemsize),dtype.itemsize))

skin=doc["skins"][0]["joints"]
joint={doc["nodes"][node]["name"]:i for i,node in enumerate(skin)}
for primitive in doc["meshes"][0]["primitives"]:
    at=primitive["attributes"]
    pos=accessor(at["POSITION"])
    faces=accessor(primitive["indices"]).reshape(-1,3)
    ids,weights=accessor(at["JOINTS_0"]),accessor(at["WEIGHTS_0"])
    edges=((int(f[i]),int(f[(i+1)%3])) for f in faces for i in range(3))
    arm=sleeve_weights(pos,edges)
    for i,(x,y,z) in enumerate(pos):
        side="L" if x<0 else "R"
        lower=arm[i]*(1.-smooth(1.045,1.160,y))
        bindings=sorted([(joint["Root"],1.-arm[i]),(joint["Arm_"+side],arm[i]-lower),
                         (joint["Forearm_"+side],lower)],key=lambda row:-row[1])
        ids[i]=[k for k,w in bindings]+[0]
        weights[i]=[w for k,w in bindings]+[0.]
dst.write_bytes(raw)
