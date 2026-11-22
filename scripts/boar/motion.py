"""In-place quadruped motion. Each foot has a stance, swing and two-link leg solve."""
import math
from mathutils import Vector
from rigs import trans, pivot, rot, movement, keys

CLIPS = {"Forage":126, "Walk":30, "Run":18, "Warn":36, "Charge":15,
         "LieDown":39, "Rest":114, "Rise":33, "Collapse":27, "Dead":12}


def blend(a,b,x):
    u = min(1.,max(0.,(x-a)/(b-a)))
    return u*u*(3.-2.*u)


class Boar:
    def __init__(self):
        self.bones = {k:Vector(v) for k,v in {
            'Spine':(.04,0,.55),'Neck':(-.43,0,.74),'Skull':(-.64,-.015,.70),
            'Tail':(.77,.025,.75),'EarL':(-.58,-.17,.82),'EarR':(-.545,.15,.82)}.items()}
        self.legs = {}
        for fore in (True,False):
            for side in (-1,1):
                name=('Fore' if fore else 'Hind')+('L' if side<0 else 'R')
                shift=0 if side<0 else (-.119 if fore else .146)
                y=side*(.182 if fore else .174)
                if fore:
                    joints=[(-.352+shift*.25,.69),(-.35+shift*.65,.408),(-.413+shift*.9,.183),(-.448+shift,.067)]
                else:
                    joints=[(.55+shift*.16,.66),(.443+shift*.5,.431),(.637+shift*.86,.23),(.564+shift,.067)]
                path=[Vector((x,y,z)) for x,z in joints]
                self.legs[name]=path
                for suffix,point in zip(('','Shin','Pastern','Foot'),path):
                    self.bones[name+suffix]=point

    def weights(self,name,point):
        x,y,z=point
        if '耳' in name: return {'EarL' if '近' in name else 'EarR':1.}
        if '尾' in name: return {'Tail':1.}
        if any(s in name for s in ('眼','吻盘','獠牙','磨牙','唇沟','颌下')): return {'Skull':1.}
        name_leg=('Fore' if x<0 else 'Hind')+('L' if y<0 else 'R')
        base,knee,hock,foot=self.legs[name_leg]
        if '蹄' in name:return {name_leg+('Foot' if '偶' in name else 'Pastern'):1.}
        # Follow the hock as it angles backwards. The belly reaches below .30 m
        # between the forelegs; lateral distance alone cannot identify a leg.
        joints=(foot,hock,knee,base)
        centre=base.x
        if z<=foot.z: centre=foot.x
        for low,high in zip(joints,joints[1:]):
            if low.z<=z<=high.z:
                centre=low.x+(high.x-low.x)*(z-low.z)/(high.z-low.z)
                break
        width=.078+.075*blend(.28,.59,z)
        leg=blend(.76,.44,z)*blend(.046,.129,abs(y))*blend(width+.085,width,abs(x-centre))
        head=blend(-.53,-.77,x)*(1-leg)
        neck=blend(-.26,-.60,x)*(1-leg-head)
        sw=blend(knee.z+.06,knee.z-.055,z)
        pas=blend(hock.z+.045,hock.z-.035,z)
        fw=blend(.105,.065,z)
        return {'Spine':1-leg-head-neck,'Neck':neck,'Skull':head,name_leg:leg*(1-sw),
                name_leg+'Shin':leg*sw*(1-pas),name_leg+'Pastern':leg*sw*pas*(1-fw),name_leg+'Foot':leg*sw*pas*fw}

    def motion(self,clip,t):
        p=t*math.tau; sine=math.sin; cosine=math.cos
        moving=clip in ('Walk','Run','Charge')
        fast=clip in ('Run','Charge')
        rest=1. if clip=='Rest' else blend(.06,.95,t) if clip=='LieDown' else 1.-blend(.04,.95,t) if clip=='Rise' else 0.
        dead=1. if clip=='Dead' else blend(.04,.96,t) if clip=='Collapse' else 0.
        pitch=-.045*rest
        bob=.010*sine(p) if clip in ('Forage','Rest') else 0.
        if moving:
            pitch+=(.077 if fast else .018)*sine(p if fast else 2*p)
            bob+=(.074 if fast else .014)*(.5-.5*cosine(p if fast else 2*p))
        brace=keys([(0,0),(.25,.67),(.52,.36),(.82,1.),(1,.87)],t) if clip=='Warn' else .85 if clip=='Charge' else 0.
        torso=trans((0,-.095*dead,bob-.285*rest-.325*dead-.028*brace)) @ pivot(self.bones['Spine'],rot('X',-1.40*dead)@rot('Y',pitch))
        sniff=.68+.16*cosine(p)+.06*sine(3*p) if clip=='Forage' else .045*rest+.22*dead+.32*brace
        neck=torso@pivot(self.bones['Neck'],rot('Y',-sniff)@rot('Z',(.091*sine(p) if clip=='Forage' else .015*sine(p)*(1-dead))))
        skull=neck@pivot(self.bones['Skull'],rot('Y',-.13*sniff+.035*sine(2*p)*(1-dead))@rot('Z',.09*sine(p+.4)*sniff*(1-dead)))
        out={'Spine':torso,'Neck':neck,'Skull':skull,'Tail':torso@pivot(self.bones['Tail'],rot('X',(.19*sine(2*p)+.18*sine(p))*(1-dead))@rot('Y',-.18*brace))}
        for i,ear in enumerate(('EarL','EarR')):
            flick=max(0.,sine(p+i*2))**9
            out[ear]=skull@pivot(self.bones[ear],rot('X',(-1 if i else 1)*(.25*flick-.32*brace)*(1-dead)))
        for i,(name,chain) in enumerate(self.legs.items()):
            a,b,c,d=chain;fore=i<2
            phase=(t+((0.,.55,.52,.03) if not fast else (.02,.16,.59,.72))[i])%1.
            duty=.61 if not fast else .44
            stride=.76 if fast else .67
            if phase<duty:
                xwalk=stride*(phase/duty-.5);lift=0.
            else:
                swing=(phase-duty)/(1-duty)
                xwalk=stride*(.5-blend(0,1,swing))
                lift=(.18 if fast else .092)*sine(swing*math.pi)**1.15
            xoff=xwalk if moving else 0.;zoff=lift if moving else 0.
            if clip=='Warn' and i==0:
                stamp=sine(math.pi*min(1,t/.53))**2
                zoff+=.14*stamp;xoff-=.12*stamp
            toe=d+Vector((xoff+(.16 if fore else -.15)*rest,0,zoff))
            if dead:toe=toe.lerp(torso@d,dead)
            hip=torso@a
            pas_angle=(.80 if fore else -.83)*rest+(.60*sine(phase*math.tau) if moving else 0.)+.72*dead
            hock=toe+(rot('Y',pas_angle).to_3x3()@(c-d))
            delta=hock-hip;length=max(.001,delta.length);axis=delta/length
            l1=(b-a).length;l2=(c-b).length
            along=max(0,min(length,(l1*l1-l2*l2+length*length)/(2*length)))
            pole=Vector((1 if fore else -1,0,0));pole=(pole-axis*pole.dot(axis)).normalized()
            knee=hip+axis*along+pole*math.sqrt(max(0,l1*l1-along*along))
            for suffix,old,new in zip(('','Shin','Pastern'),zip(chain,chain[1:]),((hip,knee),(knee,hock),(hock,toe))):
                start,end=old;u,v=new
                out[name+suffix]=trans(u)@movement(end-start,v-u)@trans(-start)
            out[name+'Foot']=trans(toe-d)@pivot(d,rot('Y',.30*(zoff/.18 if moving else 0)+.38*dead))
        return out
