"""Build the camp NPCs from the three supplied turnarounds. Run with project Blender."""
import bpy
import math
import random
import subprocess
import tempfile
from pathlib import Path
from math import sin, cos, pi, exp, radians
from mathutils import Vector, Quaternion

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art/wild_man"
OUT = ROOT / "coop/wild_people"
REFERENCE = ART / "source_images"
CACHE = Path(tempfile.mkdtemp(prefix="camp-people-art-"))
TAU = 2 * pi
IMAGES = {"male": "普通野人男性.png", "female": "普通野人女性.png", "elite": "高级野人.png"}
for key, filename in IMAGES.items():
    subprocess.run(["python3", str(ROOT/"scripts/prepare-wild-people-atlas.py"),
                    str(REFERENCE / filename), str(CACHE / (key + ".jpg"))], check=True)


def point(x, y, z):
    """Author in portrait coords: screen-right, toward the camera, up."""
    return Vector((-x, y, z))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.context.scene.render.fps = 48


def material(name, color, metallic=0, texture=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    p = mat.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = .79 if not metallic else .43
    p.inputs["Metallic"].default_value = metallic
    if texture:
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(str(CACHE / (texture + ".jpg")), check_existing=True)
        node.image.pack()
        mat.node_tree.links.new(node.outputs["Color"], p.inputs["Base Color"])
    return mat


class Surface:
    """Indexed geometry assembler. UVs are per corner so projections can have seams."""
    def __init__(self, name, mats):
        self.name, self.mats = name, mats
        self.verts, self.weights, self.faces, self.uvs, self.indices = [], [], [], [], []

    def v(self, p, weight=None):
        self.verts.append(point(*p))
        self.weights.append({weight: 1} if isinstance(weight, str) else (weight or {}))
        return len(self.verts) - 1

    def face(self, ids, mat, uvs=None):
        self.faces.append(ids)
        self.indices.append(mat)
        self.uvs.append(uvs or [(0, 0)] * len(ids))

    def finish(self, rig=None):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.verts, [], self.faces)
        mesh.update()
        ob = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(ob)
        for mat in self.mats:
            mesh.materials.append(mat)
        layer = mesh.uv_layers.new(name="ReferenceAtlas")
        for i, face in enumerate(mesh.polygons):
            use_skin=rig is not None and self.indices[i]==1
            face.material_index = 0 if use_skin else self.indices[i]
            face.use_smooth = True
            for loop, (u, v) in zip(face.loop_indices, self.uvs[i]):
                if use_skin:
                    vertex=self.verts[mesh.loops[loop].vertex_index]
                    x,y,z=vertex
                    if z>1.39 and abs(x)<.096:
                        u=47+min(1,max(-1,x/.064))*39
                        v=229+min(1,max(0,(1.50-z)/.09))*79
                    else:
                        u=48+34*math.sin(x*13+y*19)
                        v=11+min(1,max(0,z/1.51))*181
                atlas=(2048,1024) if rig and face.material_index==0 else (1376,768)
                layer.data[loop].uv = (u / atlas[0], 1 - v / atlas[1])
        if rig:
            ob.parent = rig
            mod = ob.modifiers.new("Character deformation", "ARMATURE")
            mod.object = rig
            groups = {}
            for i, weights in enumerate(self.weights):
                for bone, w in weights.items():
                    if bone not in groups:
                        groups[bone] = ob.vertex_groups.new(name=bone)
                    groups[bone].add([i], w, 'REPLACE')
        return ob


def mix_weights(height, stops):
    """Smooth through joints while keeping rigid accessory endpoints."""
    if height <= stops[0][0]:
        return stops[0][1]
    for (a, n), (b, m) in zip(stops, stops[1:]):
        if height < b:
            t = (height-a)/(b-a)
            if n == m:
                return n
            return {n: 1-t, m: t}
    return stops[-1][1]


def loft(surface, rows, sides, mat, weights, uv, shaping=None, center_uv=None):
    """Horizontal ellipse sections (height, x center, depth center, radius x, radius depth)."""
    rings = []
    for i, (z, x, y, rx, ry) in enumerate(rows):
        ring = []
        for j in range(sides):
            a = TAU * j/sides
            s, c = sin(a), cos(a)
            pos = (x+rx*s, y+ry*c, z)
            if shaping:
                pos = shaping(pos, i, a)
            ring.append(surface.v(pos, weights(pos, i, a) if callable(weights) else weights))
        rings.append(ring)
    def vertex_uv(i, j, front, use_center=False):
        mapper=center_uv if use_center else uv
        return mapper(i, sin(TAU*j/sides), cos(TAU*j/sides), front) if mapper else (0, 0)
    for i in range(len(rows)-1):
        for j in range(sides):
            k = (j+1) % sides
            front = cos(TAU*(j+.5)/sides) >= 0
            corners = [(i,j),(i,k),(i+1,k),(i+1,j)]
            use_center=center_uv is not None and cos(TAU*(j+.5)/sides)>.82
            surface.face([rings[r][c] for r,c in corners], mat, [vertex_uv(r,c,front,use_center) for r,c in corners])
    # End caps face opposite directions. Choosing radial UVs avoids smearing hairlines.
    for i, reverse in [(0, True), (len(rows)-1, False)]:
        seq = list(range(sides))[::-1] if reverse else list(range(sides))
        surface.face([rings[i][j] for j in seq], mat, [vertex_uv(i,j,True) for j in seq])


def tube(mesh, pts, radii, sides, mat, bone=None):
    """Taper a faceted strand along a polyline with a transported cross-section."""
    rings = []
    last_axis = None
    for i,p in enumerate(pts):
        tangent = Vector(pts[min(i+1,len(pts)-1)]) - Vector(pts[max(0,i-1)])
        tangent.normalize()
        axis = last_axis or Vector((0,1,0))
        axis = axis - tangent * axis.dot(tangent)
        if axis.length < .05:
            axis = tangent.cross(Vector((1,0,0)))
        axis.normalize()
        last_axis = axis
        other = tangent.cross(axis).normalized()
        ring=[]
        for j in range(sides):
            a = TAU*j/sides
            r = radii[i]
            if not isinstance(r, tuple):
                r=(r,r)
            v = Vector(p)+axis*(r[0]*cos(a))+other*(r[1]*sin(a))
            ring.append(mesh.v(v, bone(v) if callable(bone) else bone))
        rings.append(ring)
    for i in range(len(rings)-1):
        for j in range(sides):
            # axis,other,tangent forms a RH frame in author's (left-handed) space
            k=(j+1)%sides
            mesh.face([rings[i][k],rings[i][j],rings[i+1][j],rings[i+1][k]],mat)
    mesh.face(rings[0],mat)
    mesh.face(rings[-1][::-1],mat)


def oval(mesh, center, radius, mat, bone, n=9, lat=6):
    x,y,z=center
    rx,ry,rz=radius
    rows=[]
    for i in range(lat+1):
        t=-pi/2+pi*i/lat
        rows.append((z+rz*sin(t),x,y,rx*max(.014,cos(t)),ry*max(.014,cos(t))))
    loft(mesh, rows,n,mat,bone,None)


def ring(mesh,x,y,z,rx,ry,rz,mat,bone):
    pts=[(x+rx*sin(TAU*i/14),y,z+rz*cos(TAU*i/14)) for i in range(15)]
    tube(mesh,pts,[ry]*len(pts),5,mat,bone)


def skin_axis(z):
    return mix_weights(z,[(.86,"hips"),(1.01,"spine"),(1.17,"chest"),(1.36,"upper_chest"),(1.45,"upper_chest")])


def bone_table(female):
    shoulder=.174 if female else .199
    d={"root":(None,(0,0,0),(0,0,.09)),
       "hips":("root",(0,0,.91),(0,0,1.02)), "spine":("hips",(0,0,1.02),(0,0,1.14)),
       "chest":("spine",(0,0,1.14),(0,0,1.29)), "upper_chest":("chest",(0,0,1.29),(0,0,1.44)),
       "neck":("upper_chest",(0,0,1.44),(0,0,1.505)), "head":("neck",(0,0,1.505),(0,0,1.73))}
    for sign,s in [(1,"L"),(-1,"R")]:
        def p(x,y,z): return (x*sign,y,z)
        finger_x=shoulder+.076
        chain=[("clavicle","upper_chest",(.025,0,1.412),(shoulder,0,1.40)),
               ("upper_arm","clavicle",(shoulder,0,1.40),(shoulder+.049,0,1.144)),
               ("forearm","upper_arm",(shoulder+.049,0,1.144),(finger_x,.023,.925)),
               ("hand","forearm",(finger_x,.023,.925),(finger_x,.038,.836)),
               ("grip","hand",(finger_x-.014,.053,.868),(finger_x-.014,.053,.92)),
               ("thigh","hips",(.085,0,.89),(.091,.013,.49)),
               ("shin","thigh",(.091,.013,.49),(.10,-.008,.105)),
               ("foot","shin",(.10,-.008,.105),(.10,.11,.045)),("toes","foot",(.10,.11,.045),(.10,.187,.033))]
        for n,parent,a,b in chain:
            d[n+"_"+s]=(parent if parent in ["hips","upper_chest"] else parent+"_"+s,p(*a),p(*b))
    return d


def armature(female):
    data=bpy.data.armatures.new("CampHuman")
    rig=bpy.data.objects.new("CampHuman",data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name,(parent,head,tail) in bone_table(female).items():
        b=data.edit_bones.new(name)
        b.head=point(*head)
        b.tail=point(*tail)
        if parent: b.parent=data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    return rig


def person_materials(key):
    return [material("Turnaround • "+key,(.35,.2,.11),texture=key),
            material("Warm skin",(.265,.119,.065) if key=="female" else (.205,.090,.055)),
            material("Deep umber",(.019,.010,.007)),
            material("Burnished fiber",(.38,.235,.086)),
            material("Palm green",(.120,.15,.046)),
            material("Ivory shell",(.78,.61,.36)),
            material("Iron oxide",(.46,.085,.030)),
            material("Antique brass",(.36,.23,.085),.67),
            material("Dark fiber",(.048,.029,.017)),
            material("Mask and fleece",(.08,.06,.04),texture="elite"),
            material("Horn patina",(.088,.092,.069),.25),
            material("Horn ridges",(.058,.055,.036),.25)]


def body(mesh, fem, elite=False):
    # Project reference front and back onto hand-shaped sections at the matching landmark.
    front,back=(579,1190) if fem else (577,1170)
    profile=[(.82,.134,.098,0,401,405),(.88,.156,.113,-.009,376,379),(.96,.151,.105,-.005,350,360),
             (1.04,.131,.090,0,325,341),(1.12,.133,.098,.003,296,319),(1.19,.151,.105,.006,271,300),
             (1.25,.166,.113,.008,252,272),(1.30,.177,.113,.008,234,250),
             (1.36,.176,.096,0,209,220),(1.404,.159,.080,-.003,193,201),
             (1.435,.108,.066,0,178,187),(1.455,.057,.057,0,168,176)]
    if not fem:
        profile=[(z,rx*(1.1 if z>1.16 else 1),ry,dy,yp+8,yb+8) for z,rx,ry,dy,yp,yb in profile]
    rows=[(z,0,dy,rx,ry) for z,rx,ry,dy,yp,yb in profile]
    def torso_shape(pos,i,a):
        x,y,z=pos
        amp=.028 if fem else .013
        y+=max(cos(a),0)**2*amp*exp(-((z-1.28)/.052)**2)*(1-exp(-(x/.025)**2))
        return x,y,z
    def torso_uv(i,s,c,f):
        z=profile[i][0]
        u=1390+(math.asin(max(-1,min(1,s)))/pi+.5)*180
        return u,(10 if f else 246)+(1.455-z)/.635*224
    def torso_center(i,s,c,f):
        span=[48,50,49,45,45,54,58,62,62,46,26,15][i]
        yp=([404,378,351,326,295,272,251,228,203,179,165,153] if fem else
            [409,384,359,337,309,282,265,246,228,209,194,185])[i]
        return front+s*span,yp
    if not elite:
        loft(mesh,rows,36,0,lambda p,i,a:skin_axis(p[2]),torso_uv,torso_shape,torso_center)
    # The reference close-ups resolve the face paint, eyes, lips and nose ring.
    neck=[(1.40,0,-.003,.051,.052),(1.47,0,0,.057,.057),(1.51,0,.009,.060,.061),(1.54,0,.008,.06,.059)]
    loft(mesh,neck,20,1,lambda p,i,a:mix_weights(p[2],[(1.4,"upper_chest"),(1.46,"neck"),(1.53,"head")]),
         lambda i,s,c,f: ((front if f else back)+(1 if f else -1)*s*16,(182 if fem else 190)-i*8))
    head=[(1.485,.024,.037,.030),(1.497,.047,.055,.020),(1.516,.061,.069,.013),
          (1.535,.073,.079,.006),(1.555,.078,.086,.001),(1.577,.082,.091,0),
          (1.596,.084,.092,0),(1.617,.083,.093,-.001),(1.639,.080,.091,-.004),
          (1.664,.078,.087,-.006),(1.688,.067,.077,-.008),(1.708,.047,.058,-.008),(1.717,.013,.021,-.01)]
    rows=[(z,0,dy,rx,ry) for z,rx,ry,dy in head]
    def head_uv(i,s,c,f):
        z=head[i][0]
        u=1390+(math.asin(max(-1,min(1,s)))/pi+.5)*240
        return u,(483 if f else 747)+(1.717-z)/.232*248
    def face_surface(p,i,a):
        x,y,z=p
        if cos(a)>0:
            nose=.027*exp(-(x/.015)**2-((z-1.566)/.018)**2)+.012*exp(-(x/.011)**2-((z-1.59)/.034)**2)
            lip=.008*exp(-(x/.031)**2-((z-1.542)/.009)**2)
            cheek=.007*exp(-((abs(x)-.046)/.018)**2-((z-1.575)/.025)**2)
            brow=.006*exp(-((z-1.62)/.012)**2)-.009*exp(-((abs(x)-.034)/.018)**2-((z-1.599)/.010)**2)
            y+=(nose+lip+cheek+brow)*cos(a)**2
        return x,y,z
    def portrait_uv(i,s,c,f):
        data=([(255,320,15),(258,314,37),(263,301,56),(264,279,72),(267,248,78),(269,224,82),
               (267,184,82),(260,159,87),(255,147,89),(249,112,84),(241,87,70),(235,66,45),(232,59,15)] if fem else
              [(224,426,15),(224,417,47),(222,396,66),(222,365,83),(225,333,94),(222,305,96),
               (221,262,94),(219,244,94),(216,220,92),(214,196,90),(212,164,78),(212,141,56),(212,127,19)])
        cx,cy,w=data[i]
        return (cx-abs(s)*w if fem else cx+s*w),cy
    loft(mesh,rows,60,0,"head",head_uv,face_surface,portrait_uv)
    for side,suffix in [(1,"L"),(-1,"R")]:
        oval(mesh,(side*.080,.001,1.573),(.011,.021,.024),1,"head")
        ring(mesh,side*.086,.003,1.544,.009,.0024,.012,7 if fem else 5,"head")
        arm(mesh,fem,side,suffix,elite)
        leg(mesh,fem,side,suffix)


def arm(mesh,fem,side,suffix,elite):
    shoulder=.174 if fem else .199
    # Index profile in meters follows palm, wrist taper, radius, elbow and deltoid.
    profile=[(.852,.076,.028,.020,.039),(.89,.076,.034,.024,.033),(.925,.076,.023,.024,.023),
             (.965,.072,.027,.027,.021),(1.04,.064,.036,.034,.013),(1.105,.053,.038,.041,.004),
             (1.145,.049,.033,.036,0),(1.205,.043,.041,.042,-.002),(1.27,.034,.047,.049,0),
             (1.34,.020,.053,.053,0),(1.39,.003,.056,.055,0),(1.423,-.038,.064,.052,0),(1.44,-.081,.046,.037,0)]
    rows=[(z,side*(shoulder+off),y,rx*(.90 if fem else 1),ry) for z,off,rx,ry,y in profile]
    upper,fore,hand=[n+"_"+suffix for n in ["upper_arm","forearm","hand"]]
    weights=lambda p,i,a:mix_weights(p[2],[(.905,hand),(.948,fore),(1.112,fore),(1.178,upper),(1.44,upper)])
    def shoulder_weights(p,i,a):
        if i>=10 and not elite:
            return mix_weights(p[2],[(1.389,upper),(1.438,"clavicle_"+suffix)])
        return weights(p,i,a)
    loft(mesh,rows[:5] if elite else rows,18,1,shoulder_weights,None)
    if not elite:
        # Paint wraps around the arm rather than reprojecting the white between
        # the male reference's bent elbow and his spear.
        for z,off,rx,ry in [(1.270,.034,.047,.049),(1.258,.036,.047,.049),(1.045,.064,.036,.035)]:
            r=(.90 if fem else 1)
            chip=[(z,side*(shoulder+off),.004,rx*r+.0014,ry+.0014),
                  (z+.004,side*(shoulder+off),.004,rx*r+.0015,ry+.0016)]
            loft(mesh,chip,24,6 if fem else 8,upper if z>1.15 else fore,None)
    # Curled fingers wrap each side of an open 32 mm grip.
    cx=shoulder+.076
    for j in range(4):
        z=.884-.0115*j
        pts=[(side*(cx+.016),.041,z),(side*(cx+.017),.059,z-.004),
             (side*(cx+.005),.072,z-.005),(side*(cx-.013),.073,z-.006)]
        tube(mesh,pts,[.009,.008,.007,.005],7,1,hand)
    tube(mesh,[(side*(cx-.018),.031,.893),(side*(cx-.029),.047,.882),(side*(cx-.026),.066,.872)],
         [.011,.010,.007],7,1,hand)
    for k in range(3):
        z=.947+k*.006
        loft(mesh,[(z,side*(cx-.003),.021,.027,.028),(z+.004,side*(cx-.003),.021,.027,.028)],14,
             7 if fem else (3 if k%2 else 8),fore,None)


def leg(mesh,fem,side,suffix):
    sections=[(.075,.100,.000,.033,.037),(.129,.100,-.010,.033,.036),(.185,.100,-.015,.034,.041),
              (.255,.099,-.017,.045,.049),(.32,.098,-.016,.054,.056),(.38,.095,-.009,.057,.058),
              (.437,.092,.006,.047,.048),(.49,.091,.010,.050,.057),(.55,.09,.003,.060,.064),
              (.65,.086,-.002,.066,.075),(.78,.085,-.002,.077,.085),(.89,.083,.002,.081,.090),(.924,.082,0,.077,.078)]
    rows=[(z,side*x,y,rx,ry) for z,x,y,rx,ry in sections]
    thigh,shin,foot=[n+"_"+suffix for n in ["thigh","shin","foot"]]
    weights=lambda p,i,a:mix_weights(p[2],[(.075,foot),(.14,shin),(.456,shin),(.526,thigh),(.83,thigh),(.938,"hips")])
    loft(mesh,rows,20,1,weights,None)
    for j in range(3):
        zz=.354+j*.014
        loft(mesh,[(zz,side*.096,-.010,.057,.058),(zz+.005,side*.096,-.010,.057,.059)],
             22,6 if fem else 8,shin,None)
    if not fem:
        for j in range(3):
            zz=.120+j*.007
            loft(mesh,[(zz,side*.10,-.008,.035,.039),(zz+.006,side*.10,-.008,.035,.040)],16,4 if j==0 else 3,shin,None)
    # Foot narrows at heel and toes; toe tips are split to read in close-ups.
    cx=side*.10
    footrows=[(.014,cx,.055,.044,.113),(.025,cx,.054,.047,.117),(.042,cx,.050,.049,.109),
              (.058,cx,.033,.046,.093),(.078,cx,.011,.038,.066),(.105,cx,-.005,.032,.041)]
    loft(mesh,footrows,22,1,foot,None)
    for j in range(5):
        oval(mesh,(cx+side*(j-2)*.014,.152-.006*j,.026),(.011-.0008*j,.032-.003*j,.015-.001*j),1,foot,7,4)
    if fem:
        loft(mesh,[(.006,cx,.053,.050,.122),(.015,cx,.053,.051,.123),(.020,cx,.053,.049,.120)],24,3,foot,None)
        for dy in [-.024,.052]:
            pts=[(cx-.044,.069+dy,.025),(cx-.015,.071+dy,.057),(cx+.019,.107+dy,.060),(cx+.043,.106+dy,.03)]
            tube(mesh,pts,[.006]*4,6,4,foot)
        loft(mesh,[(.094,cx,-.002,.036,.040),(.10,cx,-.002,.036,.040)],16,7,foot,None)


def hair(mesh,fem,rng):
    # Contiguous cap under curls/braids; avoid light halos at silhouette boundaries.
    rows=[(1.61,0,-.018,.081,.083),(1.649,0,-.011,.086,.095),(1.692,0,-.011,.081,.091),
          (1.726,0,-.012,.063,.076),(1.741,0,-.014,.032,.043),(1.747,0,-.014,.008,.010)]
    def sweep(p,i,a):
        x,y,z=p
        if i==0: z+=.043*max(cos(a),0)-.050*max(-cos(a),0)
        return x,y,z
    def hair_uv(i,s,c,f):
        if fem: return 158+s*9,112+2*i
        return 183+33*s,86+7*i
    loft(mesh,rows,30,0,"head",hair_uv,sweep)
    if not fem:
        for i in range(150):
            t=TAU*i/1.618034
            h=(i+.5)/150
            spread=(1-h*h)**.5
            cx=.083*spread*sin(t); cy=-.009+.088*spread*cos(t)
            cz=1.656+.100*h+.010*rng.random()
            rx=.019+rng.random()*.008; ry=.021; rz=.017+rng.random()*.008
            rr=[(cz+rz*sin(t),cx,cy,rx*max(.01,cos(t)),ry*max(.01,cos(t))) for t in [-pi/2,-.7,0,.7,pi/2]]
            u=170+rng.randrange(42); v=86+rng.randrange(26)
            loft(mesh,rr,8,0,"head",lambda j,s,c,f:(u+7*s,v+j*2))
        for i in range(3):
            z=1.640+i*.004
            loft(mesh,[(z,0,-.008,.088,.102),(z+.004,0,-.008,.089,.103)],32,
                 [3,6,5][i],"head",None)
    else:
        for i in range(17):
            a=pi*.40+pi*1.20*i/16
            x=.079*sin(a); y=-.009+.084*cos(a)
            l=.15+.135*(.5-.5*cos(a))+.025*rng.random()
            path=[]
            for k in range(12):
                t=k/11
                path.append((x+.011*sin(i+3*t)+.017*sin(a)*sin(pi*t),
                             y-.064*t-.025*sin(pi*t),1.693-l*t))
            tube(mesh,path,[.007*(1-.40*k/11) for k in range(12)],7,2,"head")
            for twist in (0,pi):
                strand=[]
                for k in range(39):
                    u=11*k/38; j=min(10,int(u))
                    v=Vector(path[j]).lerp(Vector(path[j+1]),u-j)
                    radius=.0053*(1-.4*k/38)
                    strand.append((v.x+radius*cos(k*.97+twist),v.y+radius*sin(k*.97+twist),v.z))
                tube(mesh,strand,[.0025]*39,4,8,"head")
            for k in [3,7,10]:
                x1,y1,z1=path[k]
                oval(mesh,(x1,y1,z1),(.008,.008,.008),7 if (i+k)%3==0 else 8,"head",7,4)
        # Braided hairline sweeps from temples over the crown; dark ridges catch the rim light.
        for i in range(-6,7):
            x=i*.0119
            k=max(.1,1-(x/.086)**2)**.5
            pts=[]
            for j in range(20):
                a=-.009+3.11*j/19
                pts.append((x*(1-.04*sin(a)), -.010+.104*k*cos(a),1.648+.105*k*sin(a)))
            tube(mesh,pts,[.0039 if i else .0023]*20,6,2 if i else 8,"head")
            # Fine crossed threads make the crest of each cornrow read at head height.
            for offset in [-1,1]:
                ridge=[(x1+offset*.0019*cos(j*2.8),y1+.0025*cos(j*pi/19),z1+.0025*sin(j*pi/19))
                       for j,(x1,y1,z1) in enumerate(pts)]
                tube(mesh,ridge,[.0017]*20,4,8,"head")
    for i in range(3):
        x=(i-1)*.016
        base=(x+(.038 if fem else 0),-.074,1.600 if fem else 1.731)
        tip=((.069+(i-1)*.039) if fem else x+(i-1)*.028,-.173 if fem else -.087,
             base[2]+(.043 if fem else .103)+.018*(i%2))
        feather(mesh,base,tip, .012 if fem else .016,[3,6,5][i],"head")


def feather(mesh,start,end,width,mat,bone):
    a,b=Vector(start),Vector(end)
    if bone=="head":
        path=[]
        previous=None
        for j in range(9):
            t=j/8
            pt=a.lerp(b,t)+Vector((.004*sin(t*pi),-.004*sin(t*pi),0))
            path.append(pt)
            w=width*max(.015,sin(pi*t)**.76)*(1-.65*t)
            row=[mesh.v((pt.x-w*(.74 if j in (2,5) else 1),pt.y,pt.z),bone),
                 mesh.v((pt.x,pt.y+.0022,pt.z),bone),mesh.v((pt.x+w,pt.y-.001,pt.z),bone)]
            if previous:
                for k in range(2):
                    pigment=8 if j in (2,5) else (5 if j==8 else mat)
                    mesh.face([previous[k],previous[k+1],row[k+1],row[k]],pigment)
            previous=row
        tube(mesh,path,[.0016*(1-.7*j/8) for j in range(9)],5,3,bone)
        return
    mid=a.lerp(b,.52)
    # Faceted lanceolate leaf, front ridge and tapered ends are modeled on both faces.
    sid=Vector((width,0,0))
    v=[mesh.v(v,bone) for v in [a,mid-sid,mid+Vector((0,.004,0)),mid+sid,b,mid+Vector((0,-.002,0))]]
    for f in [(0,1,2),(0,2,3),(1,4,2),(2,4,3),(0,5,1),(0,3,5),(1,5,4),(4,5,3)]:
        mesh.face([v[i] for i in f],mat)


def clothes(mesh,fem,rng):
    front,back=(579,1192) if fem else (582,1172)
    # Hem has irregular slots and a solid woven underskirt for all camera angles.
    zbase=.487 if fem else .493
    rows=[(zbase,0,0,.245,.171),(.58,0,0,.225,.155),(.70,0,0,.203,.145),(.83,0,0,.184,.136),
          (.95,0,0,.167,.126),(1.006,0,0,.145,.115)]
    def skirt_shape(p,i,a):
        x,y,z=p
        flutes=1+.022*cos(29*a)
        return x*flutes,y*flutes,z+(.015*cos(17*a)+.01*sin(27*a) if i==0 else 0)
    def skirt_uv(i,s,c,f):
        ys=([544,510,463,411,369,351] if fem else [564,532,486,431,390,370])
        y=ys[i]
        return ((front if f else back)+(s if f else -s)*rows[i][3]*(332 if fem else 304),y+(.9 if not f else 0))
    def skirt_weight(p,i,a):
        z=p[2]
        s=sin(a)
        t=max(0,min(1,(.966-z)*3.21))
        # The front and back panels span both legs. A front-center vertex follows
        # both thighs during sitting, with a gradual handover across the centerline.
        left=max(0,min(1,.5+1.8*s))
        knee=max(0,min(.70,(.555-z)*7.4))
        return {"thigh_L":t*left*(1-knee),"thigh_R":t*(1-left)*(1-knee),
                "shin_L":t*left*knee,"shin_R":t*(1-left)*knee,"hips":1-t}
    loft(mesh,rows,96,0,skirt_weight,skirt_uv,skirt_shape)
    for j in range(82 if fem else 106):
        a=TAU*j/(82 if fem else 106)+rng.uniform(-.02,.02)
        bottom=(.485+rng.uniform(-.065,.045)) if fem else (.735+rng.uniform(-.065,.056))
        for i,(z,rx,ry,w) in enumerate([(1.00,.151,.121,.012),(.934,.178,.13,.020),
                       ((1+bottom)/2,.188 if not fem else .203,.147,.022 if fem else .027),
                       (bottom,.248 if fem else .218,.172 if fem else .155,.0006)]):
            row=[]
            for k in [-1,0,1]:
                b=a+k*w/rx
                pos=(sin(b)*(rx+.005*(k==0)),cos(b)*(ry+.005*(k==0)),z)
                row.append(mesh.v(pos,skirt_weight(pos,i,a)))
            if i:
                for k in range(2):
                    # Shaded double-sided material handles the fine taper at distance.
                    rx=(550+(j*17)%76) if fem else (525+(j*11)%93)
                    ry=370 if fem else 382
                    uy=[0,9,36,110] if fem else [0,8,24,47]
                    mesh.face([row[k+1],row[k],prev[k],prev[k+1]],0,
                              [(rx+(k+1)*2,ry+uy[i]),(rx+k*2,ry+uy[i]),(rx+k*2,ry+uy[i-1]),(rx+(k+1)*2,ry+uy[i-1])])
            prev=row
    waist=[(.975,0,0,.161,.124),(1.008,0,0,.151,.118),(1.020,0,0,.143,.114)]
    loft(mesh,waist,64,0,"hips",lambda i,s,c,f:((front if f else back)+(s if f else -s)*52,[365,355,348][i] if fem else [382,374,369][i]))
    # Raised collar follows the chest; beads are geometry only where they affect silhouette.
    for strand in range(2):
        pts=[]
        for j in range(33):
            a=TAU*j/32
            x=(.077+.020*strand)*sin(a)
            y=.004+(.086+.015*strand)*cos(a)
            z=1.443-(.102+.062*strand)*max(cos(a),0)**1.6
            if cos(a)>0: y+=.022*max(cos(a),0)
            pts.append((x,y,z))
        tube(mesh,pts,[.0035]*len(pts),5,8,"upper_chest")
        for j in range(0,32,2):
            x,y,z=pts[j]
            oval(mesh,(x,y,z),(.006,.006,.008),[3,8,5][(j+strand)%3],"upper_chest",7,4)
    if not fem:
        for i in range(-3,4):
            x=i*.023
            z=1.295+abs(i)*.014
            y=.126-.006*abs(i)
            tube(mesh,[(x,y,z+.020),(x+.002,y+.005,z+.008),(x+.007,y+.007,z),(x+.015,y+.006,z-.002)],
                 [.004,.005,.003,.0008],6,5,"upper_chest")
        for side,s in [(1,"L"),(-1,"R")]:
            x=side*.230
            for i in range(4):
                feather(mesh,(x+side*.027,-.005,1.304),(x+side*(.082+.017*i),-.05+.026*i,1.342+.015*i),
                        .014,[3,4,8,4][i],"upper_arm_"+s)


def wieldables():
    for name in ["club","spear","shield"]:
        reset()
        mats=[material("Smoked alder",(.16,.073,.029)),material("Worn bark",(.24,.137,.067)),
              material("Plant cord",(.47,.33,.154)),material("Chert",(.14,.13,.099)),
              material("Woven sedge",(.37,.22,.088)),material("Dyed warp",(.22,.11,.054))]
        m=Surface(name.title(),mats)
        if name=="shield":
            # Convex woven body, raised alternating warp and weft, rolled rim and a rear handle.
            rings=[]
            def profile(t,a):
                x=.211*t*sin(a)*(1-.19*abs(cos(a)))
                z=.365*t*cos(a)
                return x,.067+.060*(1-t*t),z
            for i in range(7):
                t=max(.001,i/6)
                row=[m.v(profile(t,TAU*j/48)) for j in range(48)]
                if rings:
                    for j in range(48):
                        k=(j+1)%48
                        m.face([rings[-1][j],row[j],row[k],rings[-1][k]],4)
                rings.append(row)
            rim=[profile(1,TAU*j/48) for j in range(49)]
            tube(m,rim,[.010]*len(rim),7,0)
            # A separate concave back surface meets the rim on all sides.
            rear=[]
            for i in range(7):
                row=[]
                for j in range(48):
                    x,y,z=profile(max(.001,i/6),TAU*j/48)
                    row.append(m.v((x,y-.013,z)))
                if rear:
                    for j in range(48):
                        k=(j+1)%48
                        m.face([rear[-1][k],row[k],row[j],rear[-1][j]],5)
                rear.append(row)
            for j in range(48):
                k=(j+1)%48
                m.face([rings[-1][j],rear[-1][j],rear[-1][k],rings[-1][k]],0)
            for i in range(-19,20):
                z=i*.0177
                h=z/.365
                rx=.211*(1-h*h)**.5*(1-.19*abs(h))
                pts=[]
                for k in range(17):
                    x=rx*(k/8-1)
                    d=h*h+(x/(.211*(1-.19*abs(h))))**2
                    pts.append((x,.070+.060*(1-d),z+.0014*sin(k*pi/2+i)))
                tube(m,pts,[.0032]*17,4,2 if i%4 else 5)
            for i in range(-9,10):
                u=i/10
                pts=[]
                for j in range(19):
                    h=(j/9-1)*(1-u*u)**.5
                    x=.211*u*(1-.19*abs(h))
                    pts.append((x,.070+.060*(1-u*u-h*h),.365*h))
                tube(m,pts,[.0026]*19,4,4)
            tube(m,[(0,.080,-.109),(0,.004,-.08),(0,0,-.04),(0,0,.038),(0,.005,.08),(0,.082,.109)],
                 [.016,.017,.012,.012,.017,.016],10,0)
        else:
            spear=name=="spear"
            levels=([(-.72,.007),(-.695,.019),(-.36,.015),(-.02,.017),(.42,.014),(.83,.014),(.91,.011)]
                    if spear else [(-.175,.014),(-.158,.024),(-.120,.019),(.065,.018),(.21,.025),(.33,.039),(.435,.053),(.494,.040),(.51,.021)])
            rows=[]
            for z,r in levels:
                x=(0 if spear else .032)*(max(z,0)/.51)**2
                rows.append((z,x,0,r,r*(1 if spear else .81)))
            loft(m,rows,13,0,None,None,lambda p,i,a:(p[0]+.001*sin(a*3+i),p[1]+.0015*cos(a*4+i),p[2]))
            for j in range(12):
                z=-.117+j*.012
                r=.0183 if spear else .020
                pts=[(r*sin(TAU*k/13),r*cos(TAU*k/13),z+.010*k/13) for k in range(14)]
                tube(m,pts,[.0028]*14,5,2)
            if spear:
                # An irregular leaf-shaped game prop with a flint ridge and leather collar.
                ids=[m.v(v) for v in [(0,0,.865),(-.030,0,.921),(-.038,0,.970),(0,0,1.084),(.033,0,.971),(.030,0,.923),(0,.014,.966),(0,-.013,.966)]]
                for j in range(6):
                    k=(j+1)%6
                    m.face([ids[k],ids[j],ids[6]],3)
                    m.face([ids[j],ids[k],ids[7]],3)
                for j in range(9):
                    z=.86+j*.007
                    r=.017+.001*cos(j)
                    loft(m,[(z,0,0,r,r),(z+.005,0,0,r,r)],12,2,None,None)
                for side in [-1,1]:
                    feather(m,(0,0,.855),(side*.040,-.01,.720+side*.015),.008,2,None)
        m.finish()
        save(name)


def elite_outfit(mesh,fem,rng):
    # Two fiber layers follow the torso and the upper legs. The raised tufts break the hem silhouette.
    profile=[(.746,.247,.155),(.81,.235,.15),(.94,.226,.146),(1.01,.204,.142),
             (1.10,.207,.153),(1.22,.221,.159),(1.34,.239,.161),(1.402,.240,.144),
             (1.459,.180,.128),(1.489,.105,.100)]
    rows=[(z,0,-.009,rx*(.95 if fem else 1),ry) for z,rx,ry in profile]
    def fur_uv(i,s,c,f):
        return 684+s*(43 if i<4 else 46),[366,345,319,370,356,337,320,312,302,296][i]
    loft(mesh,rows,64,9,lambda p,i,a:skin_axis(p[2]),fur_uv,
         lambda p,i,a:(p[0]*(1+.018*cos(23*a)),p[1]*(1+.018*cos(23*a)),p[2]+(.028*cos(17*a) if i==0 else 0)))
    for side,suffix in [(1,"L"),(-1,"R")]:
        sh=.174 if fem else .199
        rows=[(.946,(sh+.075)*side,.018,.046,.048),(1.05,(sh+.060)*side,.012,.065,.067),
              (1.146,(sh+.049)*side,0,.070,.069),(1.267,(sh+.030)*side,0,.076,.082),
              (1.37,(sh+.01)*side,0,.081,.089),(1.413,sh*side,0,.066,.074)]
        loft(mesh,rows,22,9,lambda p,i,a:mix_weights(p[2],[(1.105,"forearm_"+suffix),(1.177,"upper_arm_"+suffix)]),
             lambda i,s,c,f:(606+s*13,[419,399,373,345,315,297][i]))
    # Shingled locks carry actual shadow and silhouette across the shoulders,
    # coat and sleeves. The color samples come from the uninterrupted black pelt.
    for row,(height,rx,ry) in enumerate([(1.42,.197,.130),(1.36,.232,.157),(1.28,.224,.162),
                                          (1.19,.221,.160),(1.12,.213,.155),(.98,.226,.148),
                                          (.90,.232,.153),(.83,.239,.158)]):
        for j in range(38):
            a=TAU*(j+.5*(row%2))/38+rng.uniform(-.023,.023)
            w=rng.uniform(.014,.022); length=rng.uniform(.080,.143)
            z=height+rng.uniform(-.019,.017)
            dr=rng.uniform(.008,.020)
            ids=[]
            for zz,angle,extra in [(z,a-w/rx,0),(z+.018,a,.002),(z,a+w/rx,0),
                                   (z-.052,a-.007,.013),(z-length,a+.018,dr)]:
                v=(sin(angle)*(rx+extra),-.009+cos(angle)*(ry+extra),zz)
                ids.append(mesh.v(v,skin_axis(zz)))
            u=655+rng.randrange(38); v=304+rng.randrange(35)
            for tri,uvs in [((0,1,3),[(u-5,v),(u,v-5),(u,v+14)]),
                            ((1,2,3),[(u,v-5),(u+5,v),(u,v+14)]),
                            ((0,3,4),[(u-5,v),(u,v+14),(u+2,v+35)]),
                            ((3,2,4),[(u,v+14),(u+5,v),(u+2,v+35)])]:
                mesh.face([ids[k] for k in tri],9,uvs)
    # Mask body has a real eye opening on each side; small facets model bridge, cheeks and chin.
    maskrows=[(1.478,.024,.085),(1.499,.043,.093),(1.527,.063,.100),(1.552,.078,.107),
              (1.573,.079,.115),(1.589,.083,.112),(1.606,.087,.109),(1.627,.091,.101),
              (1.653,.087,.092),(1.673,.063,.081),(1.684,.025,.075)]
    grid=[]
    def maskpoint(z,w,depth,u):
        y=depth*(1-.58*abs(u)**1.7)+.021*exp(-(u/.19)**2-((z-1.565)/.031)**2)
        return w*u,y+.020,z
    for i,(z,w,depth) in enumerate(maskrows):
        row=[]
        for j in range(25):
            u=j/12-1
            zh=z
            if i in (5,6) and 3<=min(j,24-j)<=8:
                amount=sin(pi*(min(j,24-j)-3)/5)
                zh=1.599+(1 if i==6 else -1)*(.001+.010*amount)
            row.append(mesh.v(maskpoint(zh,w,depth,u),"head"))
        grid.append(row)
    for i in range(len(grid)-1):
        for j in range(24):
            if i==5 and (3<=j<8 or 16<=j<21): continue
            uv=[]
            corners=[(i,j),(i,j+1),(i+1,j+1),(i+1,j)]
            for r,col in corners:
                z,w,depth=maskrows[r]
                uv.append((679+(col/12-1)*w*351,284-(z-1.478)*490))
            mesh.face([grid[r][c] for r,c in corners],9,uv)
    for side in [-1,1]:
        lo,hi=(3,8) if side<0 else (16,21)
        contour=[grid[5][j] for j in range(lo,hi+1)]+[grid[6][j] for j in range(hi,lo-1,-1)]
        center=mesh.v((side*.044,.102,1.597),"head")
        for j in range(len(contour)):
            mesh.face([contour[j],contour[(j+1)%len(contour)],center],2)
        # Curved and segmented horns are readable against distant trees.
        pts=[(side*.065,-.003,1.665),(side*.087,-.013,1.697),(side*.103,-.020,1.747),
             (side*.115,-.026,1.797),(side*.124,-.030,1.842),(side*.146,-.024,1.872),
             (side*.177,-.017,1.888),(side*.201,-.006,1.910),(side*.211,.001,1.936)]
        radii=[.039,.034,.029,.025,.022,.018,.012,.007,.001]
        tube(mesh,pts,radii,13,10,"head")
        for j in range(1,len(pts)-1):
            a=Vector(pts[j]); b=Vector(pts[j+1])
            tube(mesh,[a,a.lerp(b,.16)],[radii[j]+.0018,radii[j]+.0006],13,11,"head")
        tube(mesh,[(side*.075,.021,1.626),(side*.108,.022,1.651),(side*.118,.029,1.689)],
             [.021,.012,.001],10,10,"head")
    # Belt and slotted metal bells.
    loft(mesh,[(1.014,0,-.01,.214,.149),(1.054,0,-.01,.211,.148)],36,8,"spine",None)
    for i in range(9):
        a=TAU*i/9
        x,y=.219*sin(a),-.007+.155*cos(a)
        oval(mesh,(x,y,1.030),(.030,.027,.030),7,"spine",12,7)
        tube(mesh,[(x-.014*cos(a),y+.024*cos(a),1.023),(x,y+.029*cos(a),1.022),
                   (x+.014*cos(a),y+.024*cos(a),1.023)],[.0015]*3,4,11,"spine")
    for i in range(90):
        a=TAU*i/90
        x,y=.245*sin(a),-.009+.157*cos(a)
        z=.77+rng.uniform(-.025,.025)
        feather(mesh,(x*.94,y*.92,z+.105),(x*1.02,y*1.02,z-rng.uniform(.01,.060)),.010,11 if i%5==0 else 8,"hips")


def animate(rig):
    # Bending axes are model-space directions transformed to the rest basis of each joint.
    def pair(x=0,y=0,z=0): return (x,y,z)
    actions=[("Idle",48,True),("Walk",28,True),("Run",18,True),("Attack",20,False),
             ("Throw",25,False),("Block",32,True),("Limp",36,True),("LimpLeft",36,True),("Down",24,False),
             ("Captive",56,True),("Rest",62,True),("Guard",48,True)]
    for name,duration,loop in actions:
        duration*=2
        action=bpy.data.actions.new(name+("-loop" if loop else ""))
        rig.animation_data_create()
        rig.animation_data.action=action
        for k in range(9):
            t=k/8
            a=TAU*t
            swing=sin(a)
            lift=(1-cos(a))*.5
            rotations={"chest":pair(1.0+1.2*sin(a)),"head":pair(.7*cos(a),0,1.1*sin(a))}
            dz=0; root_y=0; root_rot=0
            for sign,suffix in [(1,"L"),(-1,"R")]:
                def setp(n,x=0,y=0,z=0): rotations[n+"_"+suffix]=pair(x,y,z)
                setp("upper_arm",3,-sign*3,0);setp("forearm",9)
                if name in ["Walk","Run","Limp","LimpLeft"]:
                    run=name=="Run"; limp=name in ("Limp","LimpLeft")
                    sore_side=1 if name=="LimpLeft" else -1
                    amp=34 if run else 24
                    if limp and sign==sore_side: amp=9
                    v=sign*swing
                    setp("thigh",v*amp+(9 if run else 4))
                    setp("shin",-(7+(36 if run else 26)*max(0,-v)) if not (limp and sign==sore_side) else -22)
                    setp("foot",4+9*max(0,-v))
                    setp("upper_arm",-v*(32 if run else 16),-sign*3)
                    setp("forearm",50 if run else 18)
                    dz=(-.014 if run else -.008)*(1-cos(2*a))-.014
                    if limp: rotations["spine"]=pair(4,-sore_side*7*lift,0)
                if name in ["Guard","Block"]:
                    setp("thigh",10+sign*7);setp("shin",-17);setp("foot",7)
                    setp("upper_arm",32 if sign==1 else 15,-sign*12,sign*3)
                    setp("forearm",(57 if name=="Block" else 25) if sign==1 else 24)
                    # Compensate the left palm's pitch so the shield faces the opponent.
                    setp("hand",(-68 if name=="Block" else -42) if sign==1 else -23)
                    rotations["spine"]=pair(3,0,-8); dz=-.024
                if name=="Attack":
                    strike=sin(pi*t)**2
                    wind=sin(pi*min(1,t*2)) if t<.5 else 0
                    setp("thigh",10+sign*5);setp("shin",-16);dz=-.019
                    setp("upper_arm",(24+51*strike-39*wind) if sign<0 else 22,-sign*(8+12*wind))
                    setp("forearm",32-28*strike+58*wind if sign<0 else 34)
                    setp("hand",-12 if sign<0 else -40)
                    rotations["upper_chest"]=pair(4+8*strike,0,19*wind-14*strike)
                if name=="Throw":
                    wind=sin(pi*min(1,t/.53)) if t<.53 else 0
                    release=sin(pi*max(0,(t-.38)/.62)) if t>.38 else 0
                    setp("upper_arm",19+88*release-39*wind if sign<0 else 26,-sign*(8+42*wind if sign<0 else 12))
                    setp("forearm",18+106*wind if sign<0 else 31)
                    rotations["chest"]=pair(6*release,0,23*wind-19*release)
                if name=="Down":
                    fall=t*t*(3-2*t)
                    root_rot=89*fall
                    setp("thigh",13*fall);setp("shin",-17*fall)
                    setp("upper_arm",5-3*fall,sign*(3+28*fall));setp("forearm",10+(5 if sign<0 else 17)*fall)
                    # Pivot around the hips as the body settles flat on its back.
                    ang=radians(root_rot)
                    dz=.91*(1-cos(ang))-.80*fall
                    root_y=.91*sin(ang)
                if name in ["Captive","Rest"]:
                    setp("thigh",24 if name=="Captive" else 103,sign*(9 if name=="Rest" else 3))
                    setp("shin",-120 if name=="Captive" else -16);setp("foot",12 if name=="Captive" else -69)
                    setp("upper_arm",29 if name=="Captive" else 35,-sign*(18 if name=="Captive" else 4))
                    setp("forearm",50 if name=="Captive" else 22,-sign*(14 if name=="Captive" else 4),-sign*6)
                    rotations["chest"]=pair(-9 if name=="Captive" else -14)
                    rotations["head"]=pair(-9+sin(a),0,2*sin(a))
                    dz=-.435 if name=="Captive" else -.347
            frame=1+round(duration*t)
            for pb in rig.pose.bones:
                deg=rotations.get(pb.name,(0,0,0))
                if pb.name=="root":deg=(root_rot,0,0)
                rest=pb.bone.matrix_local.to_quaternion()
                q=Quaternion((1,0,0),radians(deg[0])) @ Quaternion((0,1,0),radians(deg[1])) @ Quaternion((0,0,1),radians(deg[2]))
                pb.rotation_quaternion=rest.inverted() @ q @ rest
                if pb.name=="root":
                    pb.location=rest.inverted() @ Vector((0,root_y,dz))
                    pb.keyframe_insert("location",frame=frame,group=pb.name)
                pb.keyframe_insert("rotation_quaternion",frame=frame,group=pb.name)
        # Ground the actual deformed skin at all authored contact keys. Down and
        # kneeling use the lowest body/garment point, just as the runtime draws them.
        import numpy as np
        body_object=next(o for o in bpy.context.scene.objects if o.type=="MESH")
        landing_frames=(range(1,duration+2) if name in ("Walk","Run") else [1+round(duration*k/8) for k in range(9)])
        heights=[]
        for frame in landing_frames:
            bpy.context.scene.frame_set(frame)
            dg=bpy.context.evaluated_depsgraph_get()
            e=body_object.evaluated_get(dg)
            xyz=np.empty(len(e.data.vertices)*3,dtype=np.float32)
            e.data.vertices.foreach_get("co",xyz)
            floor=float(xyz[2::3].min())
            pelvis=rig.pose.bones["root"]
            phase=(frame-1)/duration
            step=phase%.5
            crossover=.012*(exp(-((step-.073)/.045)**2)+exp(-((step-.43)/.045)**2)) if name=="Run" else 0
            heights.append((frame,pelvis.location.copy()+pelvis.bone.matrix_local.to_quaternion().inverted() @ Vector((0,0,-floor+.003+crossover))))
        for frame,location in heights:
            pelvis.location=location
            pelvis.keyframe_insert("location",frame=frame,group="root")
        rig.animation_data.action=None
        track=rig.animation_data.nla_tracks.new()
        track.name=action.name
        track.strips.new(action.name,1,action)
        track.mute=True
    for bone in rig.pose.bones:
        bone.matrix_basis.identity()
    rig.animation_data.action=None
    bpy.context.scene.frame_set(1)


def prepare_source_view(animated):
    center=Vector((0,0,.91 if animated else .12))
    eye=center+Vector((.38 if animated else .65,3.6,.27))
    if animated:
        rig=next(o for o in bpy.context.scene.objects if o.type=="ARMATURE")
        rig.animation_data.action=bpy.data.actions.get("Idle-loop")
        bpy.context.scene.frame_end=125
        bpy.context.scene.frame_set(1)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type!="VIEW_3D": continue
            view=area.spaces.active
            view.overlay.show_overlays=False
            view.shading.color_type="TEXTURE"
            view.region_3d.view_rotation=(center-eye).to_track_quat("-Z","Y")
            view.region_3d.view_location=center
            view.region_3d.view_distance=3.0 if animated else 2.3


def save(name,animated=False):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in bpy.context.scene.objects: ob.select_set(True)
    prepare_source_view(animated)
    bpy.ops.wm.save_as_mainfile(filepath=str(ART/(name+".blend")),compress=True)
    if animated:
        rig=next(o for o in bpy.context.scene.objects if o.type=="ARMATURE")
        rig.animation_data.action=None
        for t in rig.animation_data.nla_tracks:t.mute=False
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+".glb")),export_format="GLB",use_selection=True,
        export_animations=animated,export_animation_mode="NLA_TRACKS",export_force_sampling=True,
        export_cameras=False,export_lights=False,export_texcoords=True,export_materials="EXPORT",
        export_anim_slide_to_zero=True)


def character(key,elite):
    reset()
    female=key=="female"
    rng=random.Random(531 if female else 311)
    rig=armature(female)
    m=Surface("Body and regalia",person_materials(key))
    body(m,female,elite)
    if not elite:
        hair(m,female,rng)
        clothes(m,female,rng)
    else:
        # A short hair cap fills the space between the helm and collar.
        helm=[(1.612,0,-.008,.088,.101),(1.645,0,-.008,.091,.104),(1.683,0,-.009,.079,.091),
              (1.714,0,-.01,.055,.064),(1.728,0,-.010,.016,.022)]
        loft(m,helm,32,9,"head",lambda i,s,c,f:(678+s*18,193+i*3))
        elite_outfit(m,female,rng)
        # Dark leggings and leather boots read beneath the winter coat.
        for side,s in [(1,"L"),(-1,"R")]:
            rows=[(.10,side*.10,-.007,.043,.046),(.24,side*.099,-.015,.052,.058),
                  (.36,side*.096,-.010,.067,.067),(.49,side*.091,.010,.061,.068),
                  (.65,side*.086,0,.079,.086),(.79,side*.085,0,.089,.098)]
            loft(m,rows,18,8,lambda p,i,a:mix_weights(p[2],[(.46,"shin_"+s),(.53,"thigh_"+s)]),None)
            loft(m,[(.004,side*.10,.056,.055,.132),(.033,side*.10,.056,.058,.133),
                    (.058,side*.10,.05,.054,.121),(.09,side*.10,.016,.047,.079),(.145,side*.10,-.007,.047,.048)],
                 20,11,"foot_"+s,None)
    ob=m.finish(rig)
    # All costume surfaces use a common armature, with at most two influences per vertex.
    for mat in ob.data.materials: mat.use_backface_culling=False
    animate(rig)
    save(key+("_elite" if elite else ""),animated=True)


if __name__=="__main__":
    import sys
    args=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else ["weapons","male","female","male_elite","female_elite"]
    for asset in args:
        if asset=="weapons": wieldables()
        else: character(asset.split("_")[0],asset.endswith("_elite"))
