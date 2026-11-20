"""Rebuild the portable forms of the woodpile and tied supply roll from coop/terrain.gd."""
from math import sin, cos, pi
from pathlib import Path
import runpy
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
ART = Path(__file__).resolve().parent
PROPS = ROOT / "coop/props"
TEXTURES = ROOT / "coop/textures"
TAU = 2*pi
thumbnail = runpy.run_path(str(ROOT / "scripts/build-camp-backpack.py"))["thumbnail"]


def material(name, hex_color):
    rgb = [int(hex_color[n:n+2], 16)/255 for n in (0, 2, 4)]
    rgb = [c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4 for c in rgb]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.diffuse_color = (*rgb,1)
    shader = m.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*rgb,1)
    shader.inputs["Roughness"].default_value = .83
    return m


class Prop:
    def __init__(self):
        self.vertices=[]
        self.faces=[]
        self.uv=[]
        self.slots=[]

    def vertex(self, xyz):
        self.vertices.append(xyz)
        return len(self.vertices)-1

    def face(self, ids, slot, uv=None):
        self.faces.append(ids)
        self.slots.append(slot)
        self.uv.append(uv or [(0,0)]*len(ids))

    def ring(self,x,y,z,r,n,deform,phase=0):
        return [self.vertex((x,y+cos(a)*r*deform(a),z+sin(a)*r*deform(a)))
                for a in (TAU*j/n+phase for j in range(n))]

    def bridge(self,lo,hi,slot,u0=0,u1=1):
        n=len(lo)
        for j in range(n):
            k=(j+1)%n
            self.face([lo[j],lo[k],hi[k],hi[j]],slot,
                      [(j/n,u0),((j+1)/n,u0),((j+1)/n,u1),(j/n,u1)])

    def finish(self,name,materials):
        mesh=bpy.data.meshes.new(name)
        mesh.from_pydata(self.vertices,[],self.faces)
        mesh.update()
        ob=bpy.data.objects.new(name,mesh)
        bpy.context.collection.objects.link(ob)
        for m in materials: mesh.materials.append(m)
        uv=mesh.uv_layers.new(name="Surface")
        for poly,slot,coords in zip(mesh.polygons,self.slots,self.uv):
            poly.material_index=slot
            poly.use_smooth=True
            for li,coord in zip(poly.loop_indices,coords): uv.data[li].uv=coord
        # Center the complete bundle on its footprint and place its lowest vertex at zero.
        mins=[min(v.co[i] for v in mesh.vertices) for i in range(3)]
        maxs=[max(v.co[i] for v in mesh.vertices) for i in range(3)]
        offset=Vector(((mins[0]+maxs[0])/2,(mins[1]+maxs[1])/2,mins[2]))
        for v in mesh.vertices: v.co-=offset
        return ob


def wood():
    bark = material("Creek bark","675039")
    tex=bark.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image=bpy.data.images.load(str(TEXTURES/"bark_diff.jpg"))
    tex.image.pack()
    bark.node_tree.links.new(tex.outputs["Color"],bark.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    mats=[bark,material("Exposed timber","B58A58"),material("Growth rings","946D43")]
    m=Prop()
    for i in range(6):
        # Same four lower and two upper trunks and offsets as the creek landmark.
        y=(-.46+(i%4)*.29+(.15 if i>=4 else 0))*.25
        z=(.16+(.22 if i>=4 else 0))*.25
        x0=-.72*.25; x1=(.83+.06*sin(i))*.25
        radius=.14*.25
        deform=lambda a: 1+.042*sin(3*a+i)+.022*cos(5*a-i)
        rings=[]
        for f,r in [(0,1),(.035,1.015),(.40,.980),(.76,.94),(1,.91)]:
            rings.append(m.ring(x0+(x1-x0)*f,y+.00625*f,z+.005*f,
                                r*radius,18,deform,i*.23))
        for k,(a,b) in enumerate(zip(rings,rings[1:])): m.bridge(a,b,0,k*.7,(k+1)*.7)
        for front in [False,True]:
            outer=rings[-1] if front else list(reversed(rings[0]))
            cx=x1 if front else x0
            cy=y+.00625 if front else y
            cz=z+.005 if front else z
            previous=outer
            for j,r in enumerate([.87,.83,.68,.65,.46,.43,.22,.195]):
                ring=m.ring(cx,cy,cz,radius*(.91 if front else 1)*r,18,deform,i*.23)
                if not front: ring.reverse()
                m.bridge(previous,ring, 0 if j==0 else 2 if j in (3,5,7) else 1)
                previous=ring
            m.face(previous,1)
    return m.finish("Creek wood bundle",mats)


def tarp():
    m=Prop()
    mats=[material("Camp canvas","4D736A"),material("Rolled edge","758B7E"),
          material("Leather ties","62492E"),material("Belt edge","846547")]
    n=40; z=.065
    def deform(a):return 1+.024*sin(3*a)+.018*cos(5*a+.6)
    rings=[]
    for x,r in [(-.163,.059),(-.159,.064),(-.122,.064),(-.104,.060),(-.086,.064),
                (-.036,.066),(.051,.065),(.087,.063),(.102,.060),(.12,.063),(.158,.063),(.162,.059)]:
        rings.append(m.ring(x,0,z,r,n,deform))
    for a,b in zip(rings,rings[1:]): m.bridge(a,b,0)
    m.face(rings[0][::-1],0);m.face(rings[-1],0)
    # The raised hem and spiral make the rolled material legible from either end.
    for side in [-1,1]:
        last=None
        for j in range(81):
            f=j/80; a=TAU*2.15*f
            r=.008+.048*f
            lo=m.vertex((side*.1636,cos(a)*(r-.0013),z+sin(a)*(r-.0013)))
            hi=m.vertex((side*.1636,cos(a)*(r+.0013),z+sin(a)*(r+.0013)))
            pair=[lo,hi]
            if last:m.face([last[0],last[1],hi,lo] if side>0 else [lo,hi,last[1],last[0]],1)
            last=pair
    for x in [-.103,.102]:
        bands=[m.ring(x+d,0,z,r,n,deform) for d,r in [(-.010,.062),(-.009,.064),(-.006,.065),(.006,.065),(.009,.064),(.010,.062)]]
        for j,(a,b) in enumerate(zip(bands,bands[1:])):m.bridge(a,b,3 if j in (0,4) else 2)
    hem=[]
    for j in range(16):
        x=-.158+j*.316/15
        a=.60+.07*sin(3*j/15)
        r=.066
        hem.append([m.vertex((x,cos(a+d)*r,z+sin(a+d)*r)) for d in [-.029,.029]])
    for a,b in zip(hem,hem[1:]):m.face([a[0],a[1],b[1],b[0]],1)
    return m.finish("Tied camp tarp",mats)


for key,make,angle in [("wood",wood,(2.8,-3.3,2.3)),("tarp",tarp,(2.0,-3.0,1.75))]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    ob=make()
    bpy.context.view_layer.objects.active=ob
    ob.select_set(True)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active
                space.overlay.show_overlays=False
                space.shading.color_type='TEXTURE' if key=="wood" else 'MATERIAL'
                space.region_3d.view_distance=.75
                space.region_3d.view_location=(0,0,.05)
                space.region_3d.view_rotation=(-Vector(angle)).to_track_quat('-Z','Y')
    name="material_"+key
    src=ART/(name+".blend"); output=PROPS/(name+".glb")
    bpy.ops.wm.save_as_mainfile(filepath=str(src),compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(src))
    bpy.ops.export_scene.gltf(filepath=str(output),export_format='GLB',export_animations=False)
    thumbnail(output,TEXTURES/("inventory_"+key+".png"),angle,size_px=256)
