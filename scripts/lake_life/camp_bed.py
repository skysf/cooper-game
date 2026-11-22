"""Build a pegged oak rope bed with a flax ticking mattress and a striped wool coverlet."""
from pathlib import Path
from math import sin, cos, pi
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/characters/reed_marsh_study/lakefolk_1700/lakefolk_houseboat.blend"
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = "营地 · 绳编木床"
scene.unit_settings.system = "METRIC"
with bpy.data.libraries.load(str(SOURCE)) as (src, dst):
    dst.images = [name for name in src.images if name in ("木箱外板 · 颜色", "木箱外板 · 法线", "手织亚麻 · 经纱与纬纱")]
def material(name, color, rough=.82):
    m=bpy.data.materials.new(name)
    m.diffuse_color=(*color,1);m.use_nodes=True
    bs=m.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value=(*color,1);bs.inputs["Roughness"].default_value=rough
    return m
oak=material("刨平的旧栎木",(.24,.14,.061)); dark=material("烟熏木楔",(.102,.058,.026))
rope=material("蜡麻床绳",(.34,.207,.093)); flax=material("燕麦色床褥",(.50,.407,.261))
wool=material("茜草染粗呢",(.275,.075,.046)); cream=material("羊毛原色织边",(.54,.415,.237))
blue=material("靛蓝手织细条",(.059,.097,.102)); pillow=material("漂洗亚麻枕",(.64,.565,.422))
for imname,port in [("木箱外板 · 颜色","Base Color"),("木箱外板 · 法线","Normal")]:
    im=bpy.data.images[imname];n=oak.node_tree.nodes.new("ShaderNodeTexImage");n.image=im
    output=n.outputs["Color"]
    if port=="Normal":
        m=oak.node_tree.nodes.new("ShaderNodeNormalMap");m.inputs["Strength"].default_value=.42
        oak.node_tree.links.new(output,m.inputs["Color"]);output=m.outputs[0]
    oak.node_tree.links.new(output,oak.node_tree.nodes.get("Principled BSDF").inputs[port])
def timber(name,loc,size,mat=oak,bevel=.012):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name
    o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    # Cut boards along the grain regardless of the local axis of their length.
    ax=max(range(3),key=lambda i:size[i]);uv=o.data.uv_layers.active
    for poly in o.data.polygons:
        across=max((i for i in range(3) if i!=ax),key=lambda i:1-abs(poly.normal[i]))
        for j in poly.loop_indices:
            v=o.data.vertices[o.data.loops[j].vertex_index].co
            uv.data[j].uv=(v[ax]*.83+.37+loc[1]*.4,v[across]*1.8+.44+loc[0]*.57)
    mod=o.modifiers.new("手刨倒角","BEVEL");mod.width=bevel;mod.segments=2
    o.modifiers.new("平整木面","WEIGHTED_NORMAL");o.data.materials.append(mat)
def cord(name,points,rad,mat):
    cu=bpy.data.curves.new(name,"CURVE");cu.dimensions="3D";cu.bevel_depth=rad;cu.bevel_resolution=1;cu.resolution_u=1
    sp=cu.splines.new("POLY");sp.points.add(len(points)-1)
    for p,co in zip(sp.points,points):p.co=(*co,1)
    o=bpy.data.objects.new(name,cu);scene.collection.objects.link(o);cu.materials.append(mat)
def upholstery(name,hw,y0,y1,z0,rise,material,stripes=False):
    # Closed elliptical cross-sections taper at the ticking's rounded ends.
    v=[];f=[];mats=[];n=28
    ys=sorted(set([i/40 for i in range(41)]+[.070,.081,.095,.105,.131,.153,.180,.193,.207,.219,.835,.849,.867,.89]))
    for t in ys:
        y=y0+(y1-y0)*t;cap=min(1.,t/.085,(1.-t)/.085)
        edge=.875+.125*sin(cap*pi/2)
        for j in range(n):
            a=j*2*pi/n;s,c=sin(a),cos(a);x=hw*edge*((abs(c)**.46)*(1 if c>=0 else -1))
            top=(.5+.5*((abs(s)**.55)*(1 if s>=0 else -1)))
            uneven=.004*sin(21*t+3*x)+.003*cos(13*x+5*t)
            v.append((x,y,z0+rise*(.17+.83*top)*(.72+.28*cap)+uneven))
    for i in range(len(ys)-1):
        t=(ys[i]+ys[i+1])/2
        which=1 if stripes and (.070<t<.081 or .095<t<.105 or .131<t<.153 or .180<t<.193 or .207<t<.219 or .867<t<.89) else 2 if stripes and .835<t<.849 else 0
        for j in range(n):
            f.append((i*n+j,(i+1)*n+j,(i+1)*n+(j+1)%n,i*n+(j+1)%n));mats.append(which)
    f.extend([tuple(range(n)),tuple(reversed(range((len(ys)-1)*n,len(ys)*n)))]);mats.extend([0,0])
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(v,[],f);mesh.update()
    o=bpy.data.objects.new(name,mesh);scene.collection.objects.link(o)
    for m in (material,cream,blue):mesh.materials.append(m)
    for p,k in zip(mesh.polygons,mats):p.material_index=k;p.use_smooth=len(p.vertices)==4
    return o
for x in (-.42,.42):
    timber("榫接长边枨",(x,0,.325),(.067,2.02,.117))
    for y in (-.94,.94):
        h=.70 if y>0 else .485
        timber("落地床柱",(x,y,h/2),(.095,.102,h))
        timber("床柱收口",(x,y,h-.011),(.107,.114,.039),bevel=.015)
        timber("贯穿硬木销",(x+(.051 if x>0 else -.051),y,.331),(.022,.026,.033),dark,.005)
for y in (-.94,.94):timber("榫接横枨",(0,y,.325),(.852,.068,.104))
timber("枕端短靠板",(0,.945,.505),(.816,.049,.173))
for i in range(13):
    y=-.865+i*.14
    cord("横向穿绳", [(-.43,y,.366),(-.29,y,.35),(0,y,.324),(.30,y,.35),(.43,y,.366)],.009,rope)
for i in range(6):
    x=-.32+i*.128
    cord("纵向床绳",[(x,-.95,.363)]+[(x+(.006 if j%2 else -.006),-.865+j*.14,.328+.026*(abs(x)/.32)**2+(.009 if j%2 else -.009)) for j in range(13)]+[(x,.95,.363)],.009,rope)
for x in (-.421,.421):
    for y in [-.81,-.65,-.51,.51,.65,.81]:
        cord("边枨绳扣",[(x+.041*cos(i*2*pi/12),y+.011*i/12,.327+.066*sin(i*2*pi/12)) for i in range(13)],.0085,rope)
upholstery("填草长褥",.397,-.929,.919,.356,.126,flax)
upholstery("手织条纹盖毯",.415,-.917,.35,.431,.083,wool,True)
upholstery("亚麻枕芯",.317,.502,.875,.472,.099,pillow)
for s in (-1,1):
    cord("枕套侧缝",[(s*.294,.53+i*.025,.526+.006*sin(i*.2)) for i in range(13)],.0035,cream)
for j in range(26):
    x=-.37+.74*j/25
    cord("毯尾短流苏",[(x,-.898,.471),(x+.004*sin(j),-.934,.452),(x+.008*cos(j),-.946,.423+.008*sin(j*2))],.0036,cream)
bpy.ops.object.select_all(action="SELECT")
model=list(bpy.context.selected_objects)
# Keep the source editable, but join the evaluated game meshes by material at export.
scene.render.fps=30
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=="VIEW_3D":
            space=area.spaces.active;space.region_3d.view_rotation=Vector((2,-2,1.35)).to_track_quat("Z","Y")
            space.region_3d.view_location=(0,0,.34);space.region_3d.view_distance=3.3
            space.shading.color_type="MATERIAL";space.overlay.show_overlays=False
bpy.context.preferences.filepaths.save_version=0
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/containers_storage/camp_rope_bed.blend"),compress=True)
bpy.context.view_layer.objects.active=model[0];bpy.ops.object.convert(target="MESH")
bpy.ops.object.join();bpy.context.object.name="CampRopeBed"
bpy.ops.export_scene.gltf(filepath=str(ROOT/"coop/props/storage/camp_rope_bed.glb"),export_format="GLB",use_selection=True,export_yup=True)
