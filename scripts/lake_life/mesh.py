"""Reduce the approved Blender studies into grouped, vertex-painted game surfaces."""
import math
from collections import defaultdict
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector


def smooth(a,b,x):
    t=np.clip((x-a)/(b-a),0,1)
    return t*t*(3-2*t)


def runtime_material(name, texture=None, normals=None, rough=.8, metal=0):
    m=bpy.data.materials.new('Lake '+name)
    m.use_nodes=True
    tree=m.node_tree
    bs=tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=(1,1,1,1)
    bs.inputs['Roughness'].default_value=rough
    bs.inputs['Metallic'].default_value=metal
    def image(source):
        n=tree.nodes.new('ShaderNodeTexImage');n.image=source
        return n
    if texture:
        tree.links.new(image(texture).outputs['Color'],bs.inputs['Base Color'])
    if normals:
        n=tree.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.6
        tree.links.new(image(normals).outputs['Color'],n.inputs['Color'])
        tree.links.new(n.outputs[0],bs.inputs['Normal'])
    return m


def browned_cut(source):
    """Brown the muscle, render the fat, and leave a few uneven marks from the grate."""
    width, height = source.size
    pixels = np.empty((height, width, 4), dtype=np.float32)
    source.pixels.foreach_get(pixels.ravel())
    rgb = np.clip(pixels[:, :, :3], 0, 1)
    display = np.where(rgb <= .0031308, 12.92 * rgb, 1.055 * rgb ** (1 / 2.4) - .055)
    red, green, blue = display.transpose(2, 0, 1)
    lean = smooth(.045, .21, red - green)
    value = .27 * red + .58 * green + .15 * blue
    y, x = np.mgrid[0:height, 0:width] / np.array([height, width])[:, None, None]
    marks = np.abs(np.sin((x + .33 * y + .012 * np.sin(15 * y)) * 20.6))
    char = (1 - smooth(.04, .16, marks)) * (.32 + .32 * np.sin(5.7 * y + 2.8 * x) ** 2)
    char *= smooth(.06, .79, np.sin(9.8 * x - 7.7 * y + .5) * .5 + .5)
    meat = np.stack((.19 + .53 * value, .071 + .36 * value, .022 + .20 * value), axis=-1)
    fat = np.stack((.27 + .64 * value, .15 + .52 * value, .067 + .30 * value), axis=-1)
    browned = (fat * (1 - lean[:, :, None]) + meat * lean[:, :, None]) * (1 - char[:, :, None])
    pixels[:, :, :3] = np.where(browned <= .04045, browned / 12.92, ((browned + .055) / 1.055) ** 2.4)
    image = bpy.data.images.new('羊排 · 炙烤切面', width=width, height=height)
    image.colorspace_settings.name = 'sRGB'
    image.pixels.foreach_set(pixels.ravel())
    image.pack()
    return image


def material_library(cooked=False):
    images=bpy.data.images
    cut=images.get('羊排 · 肌理与脂肪')
    if cut is None:
        source=next((m for m in bpy.data.materials if m.name.startswith('14 ') and m.use_nodes),None)
        if source:
            cut=next((n.image for n in source.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and n.image.colorspace_settings.name!='Non-Color'),None)
    lib={k:runtime_material(k,rough=r,metal=m) for k,r,m in [('Paint',.78,0),('Iron',.49,.63),('Eye',.27,.02),('Cloth',.89,0)]}
    if images.get('木箱外板 · 颜色'):
        lib['Oak']=runtime_material('Oak',images['木箱外板 · 颜色'],images['木箱外板 · 法线'],.73)
        lib['Willow']=runtime_material('Willow',images['柳篮篾面 · 颜色'],images['柳篮篾面 · 法线'],.78)
        # Keep the weave's relief while allowing dyed vertex colours to supply albedo.
        height=images['手织亚麻 · 纱结高度'];w,h=height.size
        val=np.empty(w*h*4,'f');height.pixels.foreach_get(val);z=val.reshape(h,w,4)[::2,::2,0]
        dy,dx=np.gradient(z)
        v=np.stack((-dx*1.05,-dy*1.05,np.ones_like(z)),axis=-1);v/=np.linalg.norm(v,axis=-1)[...,None]
        a=np.ones((*z.shape,4),'f');a[:,:,:3]=v*.5+.5
        im=images.new('Game woven normal',width=z.shape[1],height=z.shape[0]);im.colorspace_settings.name='Non-Color'
        im.pixels.foreach_set(a.ravel());im.pack()
        lib['Cloth']=runtime_material('Homespun',normals=im,rough=.87)
    if cut:
        texture = browned_cut(cut) if cooked else cut
        lib['Meat'] = runtime_material('Roasted lamb' if cooked else 'Lamb cut', texture, rough=.82 if cooked else .65)
    return lib


def family(m,lib):
    n=m.name
    if '栎木' in n and 'Oak' in lib:return 'Oak'
    if '柳篮 ·' in n:return 'Willow'
    if any(s in n for s in ('虹膜','角膜','泪线','眼神光')):return 'Eye'
    if any(s in n for s in ('熟铁','铁件','暗锡','锤纹黄铜')):return 'Iron'
    if any(s in n for s in ('船工 ·','采药人 · 茜','棉麻 ·','衣料 ·','采药人 · 灰','舟篷 ·','亚麻','工作围裙')):return 'Cloth'
    if n.startswith('14 ') and 'Meat' in lib:return 'Meat'
    return 'Paint'


def extracted(o,kind):
    n=o.name
    if o.type not in ('MESH','CURVE'):return False
    if kind=='hull' and any(w in n for w in ('蜡麻双针','铺盖菱纹','毯头流苏','缝脚','篷脚锁线','篷补片缝脚','苗茎','叶脉','拱脚索缠')):return False
    if kind in ('ferryman','herbalist'):
        if any(w in n for w in ('桨柄','桨宽叶','桨缠带','船桨','指甲','日晒雀斑','袖口手针','围裙脚双针','帽边缝针','帽带蜡线','下睑细褶')):return False
        if any(w in n.split(' · ')[-1] for w in ('手掌','手指','拇指')) and not any(w in n for w in ('握持','屈曲')):return False
    return True


def simplify_curve(o):
    old=o.data;cu=bpy.data.curves.new('Game curve','CURVE');cu.dimensions='3D'
    cu.bevel_depth=old.bevel_depth;cu.bevel_resolution=0;cu.resolution_u=1
    for m in old.materials:cu.materials.append(m)
    for i,s in enumerate(old.splines):
        if s.type!='POLY':continue
        if len(old.splines)>70 and i%3:continue
        step=6 if len(s.points)>130 else 3 if len(s.points)>32 else 2 if len(s.points)>12 else 1
        ids=list(range(0,len(s.points),step))
        if ids[-1]!=len(s.points)-1:ids.append(len(s.points)-1)
        if len(ids)<2:continue
        p=cu.splines.new('POLY');p.points.add(len(ids)-1)
        for pt,j in zip(p.points,ids):
            pt.co=s.points[j].co;pt.radius=s.points[j].radius
        p.use_cyclic_u=s.use_cyclic_u
    return cu


def ratio(name,kind,count):
    if count<16:return 1.
    if kind=='wool':return .022
    if kind in ('fleece','shorn'):
        if '连续羊毛被' in name:return .094
        if '体型' in name:return .093 if kind=='shorn' else .053
        if '眼 ·' in name:return .34
        return .18 if count>200 else .55
    if kind in ('lamb','grilled'):return .31 if count>250 else .68
    if any(s in name for s in ('雕塑头面','眼睛','嘴唇')):return .38 if '头面' in name else .53
    if any(s in name for s in ('工作衣袖','短外套','袖口','围裙','褶腰','毡帽','柳编药篮')):return .23
    if any(s in name for s in ('油布篷片','搭接外板','舱底板')):return .26 if count>40 else 1.
    return min(1.,max(9/count,.16 if count>65 else .55))


class Model:
    def __init__(self,name,lib):
        self.name=name;self.lib=lib;self.parts=[];self.weights=[]
        self.geometry=bpy.data.collections.new('Export geometry '+name);bpy.context.scene.collection.children.link(self.geometry)
    def collect(self,objects,frame,kind,weight_function,mirror_grip=None):
        candidates=[];dg=bpy.context.evaluated_depsgraph_get()
        for o in objects:
            if not extracted(o,kind):continue
            if o.type=='CURVE':
                cu=simplify_curve(o)
                if not len(cu.splines):continue
                holder=bpy.data.objects.new('Reduced curve',cu)
                self.geometry.objects.link(holder)
                candidates.append((o,holder,frame@o.matrix_world.copy()));continue
            orig=o.evaluated_get(dg)
            me=bpy.data.meshes.new_from_object(orig,preserve_all_data_layers=True,depsgraph=dg)
            tmp=bpy.data.objects.new('Reduced surface',me);self.geometry.objects.link(tmp)
            r=ratio(o.name,kind,len(me.polygons)*2)
            if r<.995:
                mod=tmp.modifiers.new('Silhouette reduction','DECIMATE');mod.ratio=r;mod.use_collapse_triangulate=True
            candidates.append((o,tmp,frame@o.matrix_world.copy()))
        dg=bpy.context.evaluated_depsgraph_get()
        for src,tmp,xf in candidates:
            evaluated=tmp.evaluated_get(dg);me=evaluated.to_mesh(preserve_all_data_layers=True,depsgraph=dg)
            if not me or not me.polygons or not me.materials:
                evaluated.to_mesh_clear();continue
            me.calc_loop_triangles()
            count=len(me.vertices);p=np.empty(count*3,'f');me.vertices.foreach_get('co',p);p=p.reshape(-1,3)
            matrix=np.asarray(xf);p=p@matrix[:3,:3].T+matrix[:3,3]
            if kind=='herbalist' and any(x in src.name for x in ('采集草叶','草茎','叶脉','伞形草籽','红浆果')) and np.mean(p[:,0])<-.045:
                evaluated.to_mesh_clear();continue
            idx=np.empty(len(me.loop_triangles)*3,'i');me.loop_triangles.foreach_get('vertices',idx);idx=idx.reshape(-1,3)
            loops=np.empty(idx.size,'i');me.loop_triangles.foreach_get('loops',loops);loops=loops.reshape(-1,3)
            mids=np.empty(len(idx),'i');me.loop_triangles.foreach_get('material_index',mids)
            uv=np.zeros((len(me.loops),2),'f')
            layer=me.uv_layers.get('WorkUV') or me.uv_layers.active
            if layer:layer.data.foreach_get('uv',uv.ravel())
            paint=me.color_attributes.get('Pigment') or me.color_attributes.active_color
            colors=None
            if paint and paint.domain=='POINT':
                colors=np.empty((len(paint.data),4),'f');paint.data.foreach_get('color',colors.ravel())
            wear=me.attributes.get('WorkWear');water=me.attributes.get('Waterline')
            def attr(a):
                value=np.zeros(count,'f')
                if a and a.domain=='POINT':a.data.foreach_get('value',value)
                return value
            wear_values=attr(wear);wet=attr(water)
            for i,m in enumerate(me.materials):
                mask=mids==i
                if not np.any(mask):continue
                key=family(m,self.lib);t=idx[mask];l=loops[mask]
                col=np.tile(np.array(m.diffuse_color[:3],dtype='f'),(count,1))
                if key=='Oak':
                    tint=(.40,.69,.70) if '灰蓝' in m.name else (.60,.61,.60) if '焦油' in m.name else (.91,.98,1.03)
                    col[:]=tint;col*=1-.53*wet[:,None]
                elif key in ('Willow','Meat'):
                    col[:]=1
                elif colors is not None:
                    col=colors[:,:3].copy()
                if kind=='grilled' and key!='Meat':
                    col *= np.array((.89,.74,.57))
                if key in ('Paint','Cloth') and colors is None:
                    grain=np.sin(p[:,0]*22+3*np.sin(p[:,2]*17))*np.cos(p[:,1]*27+p[:,2]*16)
                    col*= (.98+.095*grain)[:,None];col*=1-.33*wear_values[:,None]
                compact,inv=np.unique(t.ravel(),return_inverse=True)
                pp=p[compact];faces=inv.reshape(-1,3);tc=uv[l].copy();cs=np.clip(col[compact],0,1)
                weights=weight_function(src.name,pp)
                self.add(pp,faces,tc,cs,key,weights)
                if mirror_grip and any(s in src.name for s in ('握持','屈曲')):
                    pp=mirror_grip(pp);self.add(pp,faces[:,::-1],tc[:,::-1],cs,key,[{'HandR':1.}]*len(pp))
            evaluated.to_mesh_clear()
        for _,tmp,_ in candidates:bpy.data.objects.remove(tmp,do_unlink=True)
    def add(self,p,tris,uv,colors,material,weights):
        self.parts.append((np.asarray(p,'f'),np.asarray(tris,'i'),np.asarray(uv,'f'),np.asarray(colors,'f'),material));self.weights.extend(weights)
    def finish(self):
        coords=[];faces=[];uv=[];cols=[];mis=[];keys=[];offset=0
        for pos,tri,tex,color,key in self.parts:
            if key not in keys:keys.append(key)
            coords.append(pos);faces.append(tri+offset);uv.append(tex.reshape(-1,2));cols.append(color);mis.extend([keys.index(key)]*len(tri));offset+=len(pos)
        co=np.concatenate(coords);tri=np.concatenate(faces)
        me=bpy.data.meshes.new(self.name);me.from_pydata(co.tolist(),[],tri.tolist());me.update()
        for k in keys:me.materials.append(self.lib[k])
        me.polygons.foreach_set('material_index',np.asarray(mis,'i'))
        me.polygons.foreach_set('use_smooth',np.ones(len(tri),dtype=bool))
        tex=me.uv_layers.new(name='UVMap');tex.data.foreach_set('uv',np.concatenate(uv).ravel())
        ca=me.color_attributes.new(name='Albedo',type='BYTE_COLOR',domain='POINT')
        rgba=np.ones((len(co),4),'f');rgba[:,:3]=np.concatenate(cols)
        ca.data.foreach_set('color',rgba.ravel());me.color_attributes.active_color=ca
        ob=bpy.data.objects.new(self.name,me);bpy.context.scene.collection.objects.link(ob)
        return ob
