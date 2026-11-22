import math
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mesh import smooth
from math import sin, cos, pi, tau

V=Vector
I=Matrix.Identity(4)
def trans(x):return Matrix.Translation(V(x))
def rot(axis,a):return Matrix.Rotation(a,4,axis)
def pivot(p,m):return trans(p)@m@trans(-V(p))
def movement(base,target):return V(base).rotation_difference(V(target)).to_matrix().to_4x4()
def blend(a,b,t):return (1-t)*a+t*b
def clamp(x):return min(1.,max(0.,x))
def keys(points,t):
    for (a,x),(b,y) in zip(points,points[1:]):
        if t<=b:
            f=clamp((t-a)/(b-a));return blend(x,y,f*f*(3-2*f))
    return points[-1][1]


class Crew:
    def __init__(self,female):
        self.female=female;self.side=-1 if female else 1
        self.H=V((.010 if female else -.015,0,1.452 if female else 1.480))
        self.shoulders=[V((s*(.164 if female else .207),.001,1.326 if female else 1.362)) for s in (-1,1)]
        self.elbows=list(map(V,([(-.294,-.033,1.106),(.275,-.010,1.132)] if female else [(-.368,-.032,1.138),(.325,.004,1.116)])))
        self.wrists=list(map(V,([(-.191,-.185,1.128),(.273,-.088,.941)] if female else [(-.417,-.145,1.199),(.309,-.081,.909)])))
        self.grip=V((-.169,-.200,1.136) if female else (-.441,-.155,1.196))
        offset=self.grip-self.wrists[0];self.grips=[self.grip,self.wrists[1]+V((-offset.x,offset.y,offset.z))]
        self.hip=V((0,.02,.94));self.pin=V((self.side*(.61 if female else .63),-.115,.844 if female else .895))
        self.max_stretch=1.
        self.bones={'Static':V((0,0,0)),'Trunk':self.hip,'Head':self.H,'Oar':self.pin}
        self.bones['Work']=V((.15,.14,1.37) if female else (-.19,-.13,1.05))
        if not female:
            self.bones['LineEnd']=self.bones['Work']+V((.045,.013,-.145))
        for i,end in enumerate('LR'):
            self.bones.update({'Upper'+end:self.shoulders[i],'Fore'+end:self.elbows[i],'Hand'+end:self.grips[i]})
    def mirror(self,points):
        return (points-np.asarray(self.grips[0]))*np.array([-1,1,1])+np.asarray(self.grips[1])
    def weights(self,name,p):
        n=name.split(' · ',1)[-1]
        if any(x in n for x in ('握持','屈曲')):return [{'HandL':1.}]*len(p)
        if any(x in n for x in ('前臂','工作衣袖','翻袖口','袖口')):
            side=0 if np.mean(p[:,0])<0 else 1;end='LR'[side];B=self.elbows[side];D=self.wrists[side];A=self.shoulders[side]
            if n.startswith('前臂') or '袖口' in n:return [{'Fore'+end:1.}]*len(p)
            line=np.asarray(D-B);la=np.asarray(B-A)
            proj=(p-np.asarray(B))@line/max(.0001,float(line@line))
            upper=(p-np.asarray(A))@la/float(la@la)
            fore=smooth(-.08,.16,proj)*smooth(.72,1.0,upper)
            root=(1-smooth(.01,.28,upper))*.38
            return [{'Trunk':float(r),'Upper'+end:float((1-r)*(1-f)),'Fore'+end:float((1-r)*f)}for r,f in zip(root,fore)]
        if any(k in n for k in ('头面','耳','眼','睫','眉','鼻','嘴','唇','发','鬓','胡','帽','脸','雀斑','盘髻','领巾结')) and '帽带' not in n:return [{'Head':1.}]*len(p)
        if '帽' in n:return [{'Head':1.}]*len(p)
        if any(k in n for k in ('药篮','柳条','篓','草','籽','浆果','叶脉')):return [{'Trunk':1.}]*len(p)
        a=smooth(.89,1.28,p[:,2])
        return [{'Static':float(1-v),'Trunk':float(v)}for v in a]
    def oar_mesh(self,model):
        sign=self.side
        sections=[(-.87,.021,.019),(-.851,.026,.023),(-.80,.019,.018),(-.45,.018,.018),(-.17,.024,.023),(.06,.028,.025),(.18,.023,.024),(.95,.020,.021),(1.25,.019,.027),(1.43,.017,.051),(1.63,.014,.103),(1.92,.012,.119),(2.14,.010,.105),(2.20,.009,.065),(2.225,.008,.012)]
        def turned(secs,base,direction,sideA,sideB,key,c,bone):
            verts=[];tris=[];uv=[];ns=14
            for i,(l,a,b) in enumerate(secs):
                for k in range(ns):
                    th=tau*k/ns;verts.append(base+direction*l+sideA*(a*cos(th))+sideB*(b*sin(th)))
                    if i:
                        j=(i-1)*ns+k;h=(i-1)*ns+(k+1)%ns
                        for face,tex in [((j,h,h+ns),((secs[i-1][0]*.8,k/ns),(secs[i-1][0]*.8,(k+1)/ns),(l*.8,(k+1)/ns))),((j,h+ns,j+ns),((secs[i-1][0]*.8,k/ns),(l*.8,(k+1)/ns),(l*.8,k/ns)))]:
                            tris.append(face);uv.append(tex)
            for start,rev in ((0,True),((len(secs)-1)*ns,False)):
                for j in range(1,ns-1):tris.append((start,start+j+(1 if rev else 0),start+j+(0 if rev else 1)));uv.append(((0,0),(.1,0),(.1,.1)))
            model.add(verts,tris,uv,[c]*len(verts),key,[{bone:1.}]*len(verts))
        turned(sections,self.pin,V((sign,0,0)),V((0,sign,0)),V((0,0,1)),'Oak',(.93,.99,1),'Oar')
        # Thole riser and iron horns rest against the gunwale, independent of blade rotation.
        for y in (-.046,.046):
            base=self.pin+V((0,y,0));turned([(-.84,.043,.038),(-.70,.044,.041),(-.16,.035,.034),(-.026,.032,.032)],base,V((0,0,1)),V((1,0,0)),V((0,1,0)),'Oak',(.77,.77,.72),'Static')
            turned([(-.069,.016,.016),(-.050,.022,.022),(.051,.014,.014),(.073,.011,.011)],base,V((0,0,1)),V((1,0,0)),V((0,1,0)),'Iron',(.13,.12,.09),'Static')
    def motion(self,clip,t):
        # The feathered blade lifts on recovery. Both hands use two points on this exact same shaft.
        off=.024 if self.female else 0.
        ph=(t+off)%1.
        blend_row=1.;idle=0.
        if clip=='Moored':ph=off;blend_row=0.;idle=sin(t*tau)
        if clip=='CastOff':ph=off;blend_row=float(smooth(0,1,t))
        if clip=='Land':ph=off;blend_row=1-float(smooth(0,1,t))
        sweep=keys([(0,.44),(.08,.42),(.40,-.35),(.49,-.44),(.59,-.41),(.90,.41),(1,.44)],ph)
        dip=keys([(0,.39),(.09,.585),(.38,.585),(.49,.49),(.60,.255),(.88,.235),(1,.39)],ph)
        feather=keys([(0,.04),(.09,.02),(.44,.04),(.60,1.27),(.87,1.29),(1,.04)],ph)
        sweep=blend(-.15+.012*idle,sweep,blend_row);dip=blend(.35+.007*idle,dip,blend_row);feather=blend(1.19,feather,blend_row)
        D=V((self.side*cos(sweep)*cos(dip),sin(sweep)*cos(dip),-sin(dip)))
        O=Quaternion(D,feather).to_matrix().to_4x4()@movement((self.side,0,0),D)
        lean=blend(.012+.008*idle, .132*sweep/.44,blend_row)
        torso=trans((0,-.025*blend_row,-.015*blend_row))@pivot(self.hip,rot('X',lean)@rot('Z',self.side*(-.031+ .072*blend_row*sweep/.44)))
        head=torso@pivot(self.H,rot('Z',self.side*(.24*(1-blend_row)+.055*idle)+.055*sin(tau*ph)*blend_row)@rot('X',-.46*lean))
        result={'Static':I,'Trunk':torso,'Head':head,'Oar':pivot(self.pin,O)}
        result['Work']=I
        if not self.female:result['LineEnd']=I
        # Distinct, hand-authored beats: draw a bight into a coil, or turn a sprig to sort its leaves.
        if clip=='Moored':
            return self.dock_motion(t,result['Oar'])
        for i,end in enumerate('LR'):
            A0=self.shoulders[i];B0=self.elbows[i];W0=self.wrists[i];G=self.grips[i];A=torso@A0
            outer=(i==1)==(self.side>0)
            distance=(.45 if outer else .76) if self.female else (.46 if outer else .81)
            target=self.pin-D*distance
            hand=movement((0,0,1),D*self.side)
            self.pose_arm(result,i,torso,target,hand)
        return result

    def dock_motion(self,t,oar):
        # A settled grip at the rail and a deliberate glance toward the bank separate the work beats.
        beats = ([(0,.12),(.12,.72),(.23,.95),(.33,.84),(.46,1.),(.59,.70),(.73,.84),(.89,0.),(1,.12)]
                 if self.female else [(0,.06),(.10,.68),(.20,.95),(.34,.54),(.46,.95),(.56,.45),(.69,.87),(.83,.29),(.94,0.),(1,.06)])
        lift=keys(beats,t)
        turn=keys([(0,.03),(.18,.34),(.39,.55),(.60,.29),(.78,.50),(.93,.07),(1,.03)],t)
        torso=pivot(self.hip,rot('Z',turn)@rot('X',-.14+.29*lift)@rot('Y',.045*sin(tau*t)))
        glance=keys([(0,.18),(.22,-.15),(.55,-.22),(.76,.50),(.91,.65),(1,.18)],t)
        head=torso@pivot(self.H,rot('Z',glance)@rot('X',-.19-.18*lift))
        out={'Static':I,'Oar':oar,'Trunk':torso,'Head':head}
        home=self.bones['Work']
        if self.female:
            # Retrieve from the near side of her back basket, then strip and inspect the sprig.
            left=V((-.11,-.27,1.05)).lerp(V((-.025,-.33,1.42)),lift)
            work=home.lerp(V((.14,-.29,1.33)),lift)+V((.085*sin(pi*lift),0,.12*sin(pi*lift)))
            tools=rot('Y',-.44*lift)@rot('X',.34*lift)
            pick=keys([(0,0),(.23,1),(.41,.4),(.51,1),(.69,.68),(.82,.35),(1,0)],t)
            left=left.lerp(work+V((-.037,-.008,.077+.047*pick)),pick*.84)
            hands=[left,work]
        else:
            work=home.lerp(V((-.12,-.25,1.34)),lift)
            tools=rot('Y',.36*lift)@rot('Z',.24*lift)
            spread=keys([(0,.15),(.16,.31),(.29,.04),(.42,.31),(.55,.05),(.68,.29),(.83,.09),(1,.15)],t)
            right=V((.17,-.17,1.02)).lerp(work+V((spread+.06,-.016,-.04+.055*sin(4*pi*t))),lift)
            hands=[work,right]
            out['LineEnd']=trans(right-self.bones['LineEnd'])
        out['Work']=trans(work)@tools@trans(-home)
        for i in range(2):
            self.pose_arm(out,i,torso,hands[i],rot('Y',(.18 if i==0 else -.25)*lift))
        return out

    def pose_arm(self,result,i,torso,target,hand):
        end='LR'[i]
        A0=self.shoulders[i];B0=self.elbows[i];W0=self.wrists[i];G=self.grips[i];A=torso@A0
        W=target+(hand.to_3x3()@(W0-G))
        axis=(W-A).normalized();dist=(W-A).length;l=(B0-A0).length;r=(W0-B0).length
        stretch=max(1.,(dist+.0001)/(l+r));self.max_stretch=max(self.max_stretch,stretch)
        l*=stretch;r*=stretch
        pole=V(((-1 if i==0 else 1)*.94,.30,-.54));normal=(pole-axis*pole.dot(axis)).normalized()
        along=min(l,max(-l,(l*l-r*r+dist*dist)/(2*max(.001,dist))))
        B=A+axis*along+normal*math.sqrt(max(0,l*l-along*along))
        def segment(p,q,v,w):
            a=q-p;b=w-v
            old=a.normalized();sc=Matrix.Identity(3)+Matrix([[old[j]*old[k]*(b.length/a.length-1) for k in range(3)] for j in range(3)])
            return trans(v)@movement(a,b)@sc.to_4x4()@trans(-p)
        result['Upper'+end]=segment(A0,B0,A,B);result['Fore'+end]=segment(B0,W0,B,W)
        result['Hand'+end]=trans(target)@hand@trans(-G)


class Sheep:
    def __init__(self):
        self.bones={'Static':V((0,0,.58)),'Neck':V((-.395,0,.758)),'Head':V((-.615,-.022,.95)),'Tail':V((.53,0,.75))}
        for fore,x in [('Fore',-.385),('Hind',.425)]:
            for s,y in [('L',-.143),('R',.143)]:
                self.bones[fore+s]=V((x,y,.58));self.bones[fore+s+'Hoof']=V((x,y,.267))
    def weights(self,name,pos):
        if any(s in name for s in ('眼','耳','鼻','唇','人中','额','冠')):return [{'Head':1.}]*len(pos)
        if '尾' in name:return [{'Tail':1.}]*len(pos)
        out=[]
        for x,y,z in pos:
            if z<.60 and (x<-.22 or x>.26):
                side=('Fore' if x<0 else 'Hind')+('L' if y<0 else 'R')
                w=float(smooth(.60,.39,z));k=float(smooth(.32,.21,z))
                out.append({'Static':1-w,side:w*(1-k),side+'Hoof':w*k})
            else:
                head=float(smooth(-.58,-.70,x))*float(smooth(.64,.82,z));neck=float(smooth(-.32,-.53,x))*float(smooth(.62,.80,z))*(1-head)
                out.append({'Static':1-head-neck,'Neck':neck,'Head':head})
        return out
    def motion(self,clip,t):
        p=t*tau;ground=I;graze=0.;sway=0.
        if clip=='Graze':graze=.83+.13*cos(p);sway=.034*sin(p*2)
        if clip=='Walk':graze=.08+.035*cos(2*p);ground=trans((0,0,.014*(1-cos(2*p))));sway=.015*sin(p)
        if clip=='Alert':graze=-.05+.018*cos(p);sway=.085*sin(p)
        collapse=float(smooth(.04,.92,t)) if clip=='Collapse' else 1. if clip=='Dead' else 0.
        if collapse:
            ground=trans((0,-.08*collapse,-.38*collapse))@pivot((.03,0,.44),rot('X',1.26*collapse))
        neck=ground@pivot(self.bones['Neck'],rot('Y',-graze)@rot('Z',sway))
        head=neck@pivot(self.bones['Head'],rot('Y',-.35*graze)@rot('Z',.035*sin(p) if not collapse else 0))
        out={'Static':ground,'Neck':neck,'Head':head,'Tail':ground@pivot(self.bones['Tail'],rot('X',.16*sin(p*2) if not collapse else 0))}
        for j,key in enumerate(('ForeL','ForeR','HindL','HindR')):
            phase=p+(pi if j in (1,2) else 0)+(.22 if j>1 else 0)
            swing=.29*sin(phase) if clip=='Walk' else 0
            upper=ground@pivot(self.bones[key],rot('Y',swing+.58*collapse))
            out[key]=upper
            bend=.46*max(0,cos(phase))**2 if clip=='Walk' else 0
            out[key+'Hoof']=upper@pivot(self.bones[key+'Hoof'],rot('Y',-bend-.68*collapse))
        return out


def rig_model(obj,weights,design,clips):
    scene=bpy.context.scene
    arm=bpy.data.armatures.new(obj.name+' skeleton');rig=bpy.data.objects.new(obj.name+'Rig',arm);scene.collection.objects.link(rig)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')
    for key,base in design.bones.items():
        b=arm.edit_bones.new(key);b.head=base;b.tail=base+V((0,.08,0))
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.parent=rig;mod=obj.modifiers.new('Skin','ARMATURE');mod.object=rig
    groups={k:obj.vertex_groups.new(name=k)for k in design.bones}
    rigid={k:[]for k in design.bones}
    for i,ww in enumerate(weights):
        ww={k:v for k,v in ww.items() if v>.00001}
        if len(ww)==1:rigid[next(iter(ww))].append(i)
        else:
            total=sum(ww.values())
            for k,w in ww.items():groups[k].add([i],w/total,'REPLACE')
    for key,ids in rigid.items():
        if ids:groups[key].add(ids,1,'REPLACE')
    rig.animation_data_create();scene.render.fps=30
    for label,nframes in clips:
        a=bpy.data.actions.new(label);rig.animation_data.action=a;previous={}
        for frame in sorted(set([0,nframes]+list(range(0,nframes+1,3)))):
            posed=design.motion(label,frame/nframes)
            for name,M in posed.items():
                bone=rig.pose.bones[name];base=design.bones[name]
                loc,q,scale=(trans(-base)@M@trans(base)).decompose()
                if name in previous and q.dot(previous[name])<0:q.negate()
                previous[name]=q.copy();bone.rotation_mode='QUATERNION';bone.location=loc;bone.rotation_quaternion=q;bone.scale=scale
                for channel in ('location','rotation_quaternion','scale'):bone.keyframe_insert(channel,frame=frame+1,group=name)
        rig.animation_data.action=None
        tr=rig.animation_data.nla_tracks.new();tr.name=label;tr.strips.new(label,1,a);tr.mute=True
    for b in rig.pose.bones:b.matrix_basis=I
    return rig
