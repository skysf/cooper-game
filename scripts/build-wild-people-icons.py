"""Render the six inventory thumbnails using the project's prop-lighting setup."""
import bpy
from mathutils import Vector
from math import sin, cos, pi
from pathlib import Path
import tempfile
import runpy
import subprocess

ROOT=Path(__file__).resolve().parents[1]
tmp=Path(tempfile.mkdtemp(prefix="camp-inventory-"))
thumbnail=runpy.run_path(str(ROOT/"scripts/build-camp-backpack.py"))["thumbnail"]


def herb_bundle(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    verts=[]; faces=[]; slots=[]
    def face(v,slot):
        base=len(verts)
        verts.extend(v);faces.append(tuple(range(base,base+len(v))));slots.append(slot)
    def stem(start,end,r,slot):
        axis=(end-start).normalized()
        one=axis.cross(Vector((1,0,0))).normalized()
        two=axis.cross(one)
        for k in range(6):
            a,b=k*pi/3,(k+1)*pi/3
            p,q=(one*cos(a)+two*sin(a))*r,(one*cos(b)+two*sin(b))*r
            face([start+p,start+q,end+q,end+p],slot)
    def leaf(base,direction,w,slot):
        cross=Vector((direction.z,0,-direction.x)).normalized()
        prev=None
        for j in range(9):
            t=j/8
            center=base+direction*t+Vector((0,-.010*sin(t*pi),0))
            width=w*max(.003,sin(t*pi)**.82)*(.83 if j%2 else 1)
            row=[center-cross*width,center+Vector((0,-.005*sin(pi*t),0)),center+cross*width]
            if prev is not None:
                face([prev[0],prev[1],row[1],row[0]],slot)
                face([prev[1],prev[2],row[2],row[1]],slot+1)
            prev=row
        stem(base,base+direction*.75,.0013,4)
    for i in range(7):
        a=i*2.39996
        lower=Vector((.021*cos(a),.012*sin(a),.004*(i%3)))
        tip=Vector((.095*cos(a),.046*sin(a),.205+.053*(.5+.5*sin(2*a))))
        stem(lower,tip,.0035,4)
        for k in range(3):
            for s in [-1,1]:
                origin=lower.lerp(tip,.41+.17*k)
                d=Vector((s*(.056-.010*k)+.020*cos(a),.028*sin(a+k+s),.035+.008*k))
                leaf(origin,d,.018-.002*k,(i+k)%2)
        leaf(tip-Vector((0,0,.031)),Vector((.025*cos(a),.010*sin(a),.063)),.015,1)
    for j in range(5):
        points=[Vector((.033*cos(2*pi*k/18),.022*sin(2*pi*k/18),.045+.004*j+.004*sin(2*pi*k/18))) for k in range(19)]
        for a,b in zip(points,points[1:]): stem(a,b,.0028,3)
    mesh=bpy.data.meshes.new("Tied herb leaves")
    mesh.from_pydata(verts,[],faces)
    ob=bpy.data.objects.new("Camp herb bundle",mesh);bpy.context.collection.objects.link(ob)
    for name,color in [("Dark leaves",(.052,.14,.034)),("Sage leaves",(.16,.29,.074)),
                       ("Sunlit leaves",(.27,.39,.085)),("Plant twine",(.46,.265,.084)),("Stems",(.22,.34,.074))]:
        m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
        bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=.87
        mesh.materials.append(m)
    for f,slot in zip(mesh.polygons,slots): f.material_index=slot
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_animations=False)

herb=tmp/'herb.glb'
herb_bundle(herb)
assets=[
    ('club',ROOT/'coop/wild_people/club.glb',(1.1,3,.70),-32),
    ('spear',ROOT/'coop/wild_people/spear.glb',(.9,3,.65),-38),
    ('shield',ROOT/'coop/wild_people/shield.glb',(1,3,.95),-14),
    ('stone',ROOT/'coop/props/stone_round.glb',(1.4,-2.8,1.4),0),
    ('water',ROOT/'coop/props/camp_water_jug.glb',(1.4,-2.9,1.3),0),
    ('herb',herb,(.6,-3,1.2),-17),
]
# Fill the item slot while preserving the same outline and transparent margins.
resize='''from PIL import Image
import sys
im=Image.open(sys.argv[1]).convert("RGBA")
if sys.argv[4]=="spear":
    box=im.getchannel("A").point(lambda x:255 if x>18 else 0).getbbox()
    x0,y0,x1,y1=box
    im=im.crop((x0,y0,x1,y0+round((y1-y0)*.42)))
im=im.rotate(float(sys.argv[3]),resample=Image.Resampling.BICUBIC,expand=True)
box=im.getchannel("A").point(lambda x:255 if x>18 else 0).getbbox()
im=im.crop(box)
im.thumbnail((230,230),Image.Resampling.LANCZOS)
out=Image.new("RGBA",(256,256))
out.alpha_composite(im,((256-im.width)//2,(256-im.height)//2))
out.save(sys.argv[2],optimize=True)
'''
for key,source,angle,rotation in assets:
    png=tmp/(key+".png")
    thumbnail(source,png,angle,size_px=384)
    subprocess.run(["python3","-c",resize,str(png),str(ROOT/"coop/textures"/("inventory_"+key+".png")),str(rotation),key],check=True)
