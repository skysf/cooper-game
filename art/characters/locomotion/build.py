"""Bake in-place player movement on the existing SkyRig Stand pose (glTF, metres, -Z forward).

Run from the project root. The intermediate character is for import in Blender and
Godot only. export_library.gd extracts just animation tracks for the shipping game.
"""
import json
import math
import struct
import sys
from pathlib import Path

import numpy as np

RIG = Path("coop/props/sky_character.glb")
BOOT = Path("coop/props/camp_boot.glb")
OUTPUT = Path(".cache/player-locomotion/probe/baked.glb")
PI = math.pi
TAU = 2 * PI
SIDES = (("L", -1), ("R", 1))
LIMBS = ("clavicle", "upper_arm", "forearm", "hand", "thigh", "shin", "foot", "toes")
CHANNELS = ["hips", "spine", "chest", "upper_chest", "neck", "head"] + [
    bone + "_" + side for side, _ in SIDES for bone in LIMBS
]
FINGERS = ("thumb","index","middle","ring","pinky")
CHANNELS += [f"{finger}_{joint:02d}_{side}" for side,_ in SIDES for finger in FINGERS for joint in (1,2,3)]
DURATIONS = {"Walk": 1., "Run": .72, "Takeoff": .14, "Air": .60,
             "Land": .22, "Swim": 1.55, "Tread": 1.8}


if "--deck" in sys.argv:
    OUTPUT = Path(".cache/lake-dockwork/poses/baked.glb")
    DURATIONS = {"Crouch":2.7, "CrouchWalk":.86, "Sleep":3.5}

def rotation(axis, degrees):
    a = np.eye(3)[axis]
    t = math.radians(degrees)
    m = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    return np.eye(3) + math.sin(t)*m + (1-math.cos(t))*m@m


def angles(x=0, y=0, z=0):
    return rotation(1, y) @ rotation(2, z) @ rotation(0, x)


def basis(q):
    x, y, z, w = q
    v = np.array([[0., -z, y], [z, 0., -x], [-y, x, 0.]])
    return np.eye(3) + 2*(w*v + v@v)


def quat(m):
    # Select the largest diagonal component to stay well-conditioned near a half turn.
    candidates = np.array([1+m[0,0]-m[1,1]-m[2,2], 1-m[0,0]+m[1,1]-m[2,2],
                           1-m[0,0]-m[1,1]+m[2,2], 1+np.trace(m)])
    i = int(np.argmax(candidates))
    if i == 3:
        q = [m[2,1]-m[1,2], m[0,2]-m[2,0], m[1,0]-m[0,1], candidates[i]]
    else:
        j, k = (i+1)%3, (i+2)%3
        q = np.zeros(4)
        q[i], q[j], q[k], q[3] = candidates[i], m[i,j]+m[j,i], m[i,k]+m[k,i], m[k,j]-m[j,k]
    return np.array(q)/np.linalg.norm(q)


def aligned(a, b):
    a, b = a/np.linalg.norm(a), b/np.linalg.norm(b)
    v = np.cross(a,b)
    k = np.array([[0.,-v[2],v[1]],[v[2],0.,-v[0]],[-v[1],v[0],0.]])
    return np.eye(3) + k + k@k / max(1e-6, 1 + a@b)


def smooth(t):
    return t*t*(3-2*t)


def curve(points, t):
    for a, b in zip(points, points[1:]):
        if t <= b[0]:
            f = smooth((t-a[0])/(b[0]-a[0]))
            return np.asarray(a[1:])*(1-f) + np.asarray(b[1:])*f
    return np.asarray(points[-1][1:])


def read_glb(path):
    raw = path.read_bytes()
    size = struct.unpack_from("<I", raw, 12)[0]
    return json.loads(raw[20:20+size]), bytearray(raw[28+size:])


doc, data = read_glb(RIG)
nodes = doc["nodes"]
names = {n["name"]: i for i,n in enumerate(nodes)}
parents = {c:i for i,n in enumerate(nodes) for c in n.get("children",[])}
base = [dict(n) for n in nodes]
stand = next(a for a in doc["animations"] if a["name"] == "Stand")
for ch in stand["channels"]:
    target = ch["target"]
    if target["path"] not in ("translation", "rotation", "scale"):
        continue
    acc = doc["accessors"][stand["samplers"][ch["sampler"]]["output"]]
    view = doc["bufferViews"][acc["bufferView"]]
    count = int(acc["type"][-1])
    base[target["node"]][target["path"]] = np.frombuffer(
        data, "<f4", count, view.get("byteOffset",0)+acc.get("byteOffset",0)).astype(float).tolist()

def world(i):
    n = base[i]
    m = np.eye(4)
    m[:3,:3] = basis(n.get("rotation",(0,0,0,1))) @ np.diag(n.get("scale",(1,1,1)))
    m[:3,3] = n.get("translation",(0,0,0))
    return world(parents[i]) @ m if i in parents else m

rest = {n:world(i) for n,i in names.items()}
def pos(n):
    return rest[n][:3,3]
def orient(n):
    b = rest[n][:3,:3]
    return b/np.linalg.norm(b,axis=0)


boot_doc, boot_data = read_glb(BOOT)


def boot_positions(name):
    node = next(node for node in boot_doc["nodes"] if node["name"] == name)
    surface, = boot_doc["meshes"][node["mesh"]]["primitives"]
    points = boot_doc["accessors"][surface["attributes"]["POSITION"]]
    view = boot_doc["bufferViews"][points["bufferView"]]
    return np.ndarray((points["count"], 3), dtype="<f4", buffer=boot_data,
                      offset=view.get("byteOffset", 0) + points.get("byteOffset", 0),
                      strides=(view.get("byteStride", 12), 4)).astype(float)


boot_vertices = {"foot_L": boot_positions("BootLeft"), "foot_R": boot_positions("BootRight")}


def sole_height(foot, delta):
    # The boot's base is on the stand floor. Measure the rotated sole about the ankle.
    return float(np.min(boot_vertices[foot] @ delta[1]) - pos(foot)[1] * delta[1, 1])

class Pose:
    def __init__(self):
        self.rot = {}
        self.shift = np.zeros(3)

    def absolute(self, bone, delta):
        self.rot[bone] = delta @ orient(bone)

    def local(self, bone, delta):
        parent = nodes[parents[names[bone]]]["name"]
        self.absolute(bone, self.rot.get(parent, orient(parent)) @ orient(parent).T @ delta)

    def arm(self, side, sign, upper, lower, body):
        for bone, child, direction in (("upper_arm","forearm",upper), ("forearm","hand",lower)):
            name, end = bone+"_"+side, child+"_"+side
            v = np.array([sign*direction[0], direction[1], direction[2]])
            self.absolute(name,body @ aligned(pos(end)-pos(name),v))
        self.local("hand_"+side,np.eye(3))


def stride(p, t, fast, crouch=False, still=False):
    duty, length = (.37, 2.56) if fast else (.59, 1.46)
    wave, sway = math.cos(TAU*t), math.sin(TAU*t)
    shift_y = (-.112 if fast else -.056) - (.028 if fast else .019)*math.sin(2*TAU*t)
    shift_y -= (.025 if fast else .053)*wave**8
    p.shift = np.array([(.021 if fast else .016)*sway,shift_y,0])
    p.absolute("hips",angles(-5 if fast else -2, 5*wave,2.5*sway))
    p.absolute("spine",angles(-8 if fast else -3,1.5*wave,1.2*sway))
    p.absolute("chest",angles(-10 if fast else -3,-3.2*wave,-1.6*sway))
    p.absolute("upper_chest",angles(-9 if fast else -2,-5.3*wave,-2.2*sway))
    p.absolute("neck",angles(-2,-2*wave,-sway))
    p.absolute("head",angles(0,-.8*wave,-.5*sway))
    if crouch:
        length, duty = (0. if still else .83), .63
        # Tuck the hips back and down so a helmet clears the sloping canvas when turning.
        p.shift = np.array([.008*sway,-.725+.010*sway*sway,.131])
        for bone,angle in [("hips",-18),("spine",-35),("chest",-46),("upper_chest",-52),("neck",-32),("head",-13)]:
            p.absolute(bone,angles(angle,1.1*wave,0))
    for index,(side,sign) in enumerate(SIDES):
        u = (t+.5*index)%1
        reach = length*duty/2
        if u < duty:
            v = u/duty
            z = reach*(2*v-1)
            heel = curve([(0,-12),(.17,0),(.65,0),(1,24 if fast else 17)],v)[0]
            clearance = 0.
        else:
            v = (u-duty)/(1-duty)
            # Match the belt speed at toe-off and heel strike.
            tangent = length*(1-duty)
            z = reach*(1-2*smooth(v)) + tangent*(2*v**3-3*v*v+v)
            heel = curve([(0,24 if fast else 17),(.25,31),(.65,-2),(1,-12)],v)[0]
            clearance = (.25 if fast else .15)*math.sin(PI*v)**1.3
        if crouch:
            clearance = 0. if still else clearance*.26
            heel = 0. if still else heel*.24
        foot, shin, thigh = ("foot_"+side,"shin_"+side,"thigh_"+side)
        pitch = rotation(0,heel)
        ankle_y = -sole_height(foot, pitch) + clearance + (.013 if fast else .004)
        hip_rot = p.rot["hips"]@orient("hips").T
        origin = pos("hips")+p.shift + hip_rot@(pos(thigh)-pos("hips"))
        goal_z = z + pos(foot)[2]
        forward, down = -(goal_z-origin[2]), origin[1]-ankle_y
        leg_a, leg_b = pos(shin)-pos(thigh), pos(foot)-pos(shin)
        l1,l2 = np.linalg.norm(leg_a[1:]),np.linalg.norm(leg_b[1:])
        r = min(l1+l2-.0001, math.hypot(forward,down))
        th = math.atan2(forward,down)+math.acos(np.clip((l1*l1+r*r-l2*l2)/(2*l1*r),-1,1))
        bend = math.acos(np.clip((r*r-l1*l1-l2*l2)/(2*l1*l2),-1,1))
        for bone, angle, vector in ((thigh,th,leg_a), (shin,th-bend,leg_b)):
            p.absolute(bone,rotation(0,math.degrees(angle-math.atan2(-vector[2],-vector[1]))))
        p.absolute(foot,pitch)
        p.local("toes_"+side,angles(-max(0,heel)*.53))
        leg_swing = math.cos(TAU*(u-.02))
        p.local("clavicle_"+side,angles(0,sign*2.5*leg_swing, sign*(1.5+leg_swing)))
        p.local("upper_arm_"+side,angles(-(35 if fast else 23)*leg_swing-(16 if fast else 4),0,sign*(7 if fast else 4)))
        p.local("forearm_"+side,angles((66 if fast else 22)-(19 if fast else 10)*leg_swing))
        p.local("hand_"+side,angles(-5,0,sign*4))
        if crouch:
            p.arm(side,sign,(.25,-.72,-.43),(-.08,-.33,-.73),angles(0))

def sleep_pose(p,t):
    breath=math.sin(TAU*t)
    p.absolute("chest",angles(-.7*breath))
    p.absolute("head",angles(7,9,4))
    for side,sg in SIDES:
        p.absolute("thigh_"+side,angles(8 if sg<0 else 3,0,sg*3))
        p.absolute("shin_"+side,angles(-8 if sg<0 else -2))
        p.arm(side,sg,(.23,-.88,-.17),(-.64,-.28,-.38),angles(0))



def jump(p, t, clip):
    # Hip drop, torso, L/R thigh, knees, upper arms and elbows.
    neutral = (0,-2,4,4,-8,-8,0,0,14,14)
    push = (.014,-7,13,-13,-11,-13,41,33,34,33)
    apex = (-.04,-11,43,25,-68,-53,48,37,47,44)
    approach = (-.006,-5,15,12,-22,-21,28,30,32,30)
    compress = (-.15,-17,38,36,-67,-64,32,38,42,36)
    if clip == "Takeoff":
        sequence = [(0,*neutral),(.28,-.055,-10,20,18,-32,-31,-19,-15,18,20),(.76,*push),(1,*apex)]
    elif clip == "Air":
        sequence = [(0,*apex),(.50,-.036,-9,37,22,-58,-45,46,36,42,40),(1,*apex)]
    else:
        sequence = [(0,*approach),(.36,*compress),(.75,-.05,-9,19,18,-29,-28,16,20,28,24),(1,*neutral)]
    y, pitch, lt, rt, lk, rk, la, ra, le, re = curve(sequence,t)
    p.shift[1] = y
    p.absolute("hips",angles(pitch*.45))
    p.absolute("spine",angles(pitch*.7))
    p.absolute("chest",angles(pitch))
    p.absolute("upper_chest",angles(pitch))
    p.absolute("neck",angles(pitch*.4))
    p.absolute("head",angles(pitch*.2))
    for i,(side,s) in enumerate(SIDES):
        a,k,arm,elbow = (rt,rk,ra,re) if i else (lt,lk,la,le)
        p.absolute("thigh_"+side,angles(a))
        p.absolute("shin_"+side,angles(a+k))
        p.absolute("foot_"+side,angles((7 if clip=="Air" else 0)+k*.12))
        p.local("clavicle_"+side,angles(0,0,s*2))
        p.local("upper_arm_"+side,angles(arm,0,s*(18 if clip=="Air" else 11)))
        p.local("forearm_"+side,angles(elbow))
        p.local("hand_"+side,angles(-6))

    if clip == "Land":
        # Place the lower sole on the physical floor through the absorption/recovery.
        lower = []
        for side,_ in SIDES:
            foot = "foot_"+side
            offset = pos("hips")+p.shift
            last = "hips"
            for bone in ("thigh_"+side,"shin_"+side,foot):
                offset = offset + p.rot[last]@orient(last).T@(pos(bone)-pos(last))
                last = bone
            q = p.rot[foot]@orient(foot).T
            lower.append(offset[1] + sole_height(foot, q))
        p.shift[1] -= min(lower)-.003

def water(p,t,travel):
    wave = math.cos(TAU*t)
    pitch = (-66-5*wave) if travel else -7+3*wave
    p.shift = np.array([0, (-.98 if travel else -1.35) + (.025 if travel else .018)*-wave,
                        .65 if travel else .07])
    for bone,d in (("hips",pitch+4),("spine",pitch+2),("chest",pitch),("upper_chest",pitch+2),
                   ("neck",pitch*.63),("head",pitch*.37)):
        p.absolute(bone,angles(d))
    body = angles(pitch+2)
    for idx,(side,s) in enumerate(SIDES):
        u = t if travel else (t+.50*idx)%1
        p.local("clavicle_"+side,angles(0,0,s*(3+3*math.cos(TAU*u))))
        if travel:
            upper = curve([(0,.27,.94,-.20),(.17,.58,.78,-.22),(.38,.95,.10,-.22),
                           (.56,.75,-.31,-.57),(.74,.52,.58,-.58),(.94,.27,.94,-.20),(1,.27,.94,-.20)],u)
            lower = curve([(0,-.24,.96,-.1),(.17,.53,.77,-.35),(.38,.35,.21,-.91),
                           (.56,-.78,.45,-.36),(.74,-.47,.84,-.20),(.94,-.24,.96,-.10),(1,-.24,.96,-.10)],u)
            a,k,roll,toe = curve([(0,0,-8,2,20),(.24,5,-18,4,18),(.55,31,-88,21,-12),
                                  (.69,28,-74,27,-17),(.87,2,-12,10,25),(1,0,-8,2,20)],u)
        else:
            w,v = math.cos(TAU*u),math.sin(TAU*u)
            upper = np.array([.78+.17*w,-.45+.07*v,-.29+.16*v])
            lower = np.array([.55+.28*w,.16+.12*v,-.66+.28*v])
            a,k,roll,toe = 25+14*w,-42-17*v,12+5*v,6+8*w
        p.arm(side,s,upper,lower,body)
        p.absolute("thigh_"+side,body@angles(a,0,s*roll))
        p.absolute("shin_"+side,body@angles(a+k,-s*roll*.55,s*roll*.65))
        p.absolute("foot_"+side,body@angles(a+k+toe,-s*roll,s*roll*.4))
        p.local("toes_"+side,angles(5))

def accessor(values, typ):
    a = np.asarray(values,dtype="<f4")
    data.extend(b"\0"*((-len(data))%4))
    offset=len(data)
    data.extend(a.tobytes())
    doc["bufferViews"].append({"buffer":0,"byteOffset":offset,"byteLength":a.nbytes})
    acc={"bufferView":len(doc["bufferViews"])-1,"componentType":5126,"count":len(a),"type":typ}
    if typ=="SCALAR":
        acc.update(min=[float(a.min())],max=[float(a.max())])
    doc["accessors"].append(acc)
    return len(doc["accessors"])-1

for clip,duration in DURATIONS.items():
    times=np.linspace(0,duration,max(8,round(duration*30))+1)
    time_id=accessor(times,"SCALAR")
    animation={"name":clip,"samplers":[],"channels":[]}
    rotations={b:[] for b in CHANNELS}
    translations=[]
    for time in times:
        t=time/duration
        p=Pose()
        if clip in ("Crouch","CrouchWalk"):
            stride(p,t,False,True,clip=="Crouch")
        elif clip=="Sleep":
            sleep_pose(p,t)
        elif clip in ("Walk","Run"):
            stride(p,t,clip=="Run")
        elif clip in ("Swim","Tread"):
            water(p,t,clip=="Swim")
        else:
            jump(p,t,clip)
        # Relax the previously spread Stand fingers. The light fist in fast travel
        # opens again for sculling and the outsweep, keeping both grip nodes intact.
        curl = {"Walk":20, "Run":39, "Takeoff":18, "Air":17,
                "Land":15, "Swim":4, "Tread":7, "Crouch":16,"CrouchWalk":16,"Sleep":12}[clip]
        for side,sign in SIDES:
            for f,finger in enumerate(FINGERS):
                for joint,factor in ((1,.82),(2,1.),(3,.55)):
                    angle = curl*factor*(.86+.07*f)
                    delta = angles(-angle*.50,sign*angle*.19,-sign*angle*.22) if finger=="thumb" else angles(0,0,-sign*angle)
                    p.local(f"{finger}_{joint:02d}_{side}",delta)
        for bone in CHANNELS:
            parent=nodes[parents[names[bone]]]["name"]
            if bone not in p.rot:
                p.local(bone,np.eye(3))
            q=quat(p.rot.get(parent,orient(parent)).T@p.rot[bone])
            if rotations[bone] and q@rotations[bone][-1]<0:
                q=-q
            rotations[bone].append(q)
        parent=nodes[parents[names["hips"]]]["name"]
        translations.append(base[names["hips"]]["translation"] + np.linalg.solve(rest[parent][:3,:3],p.shift))
    for bone, kind, tracks in [(b,"rotation",rotations[b]) for b in CHANNELS]+[("hips","translation",translations)]:
        animation["channels"].append({"sampler":len(animation["samplers"]),"target":{"node":names[bone],"path":kind}})
        animation["samplers"].append({"input":time_id,"output":accessor(tracks,"VEC4" if kind=="rotation" else "VEC3"),"interpolation":"LINEAR"})
    doc["animations"].append(animation)

doc["buffers"][0]["byteLength"]=len(data)
header=json.dumps(doc,separators=(",",":")).encode()
header+=b" "*((-len(header))%4)
data.extend(b"\0"*((-len(data))%4))
OUTPUT.parent.mkdir(parents=True,exist_ok=True)
OUTPUT.write_bytes(struct.pack("<4sIIII",b"glTF",2,28+len(header)+len(data),len(header),0x4E4F534A)+header
                   +struct.pack("<II",len(data),0x004E4942)+data)
print(OUTPUT,sorted(DURATIONS))
