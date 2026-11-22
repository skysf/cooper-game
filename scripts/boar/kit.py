"""Hide, wool, leather and tusk fittings for the three camp recipes, in metres."""
import math
import numpy as np
from mathutils import Vector

def rgb(hexcode):
    display=np.asarray(tuple(bytes.fromhex(hexcode)))/255.
    return np.where(display<=.04045,display/12.92,((display+.055)/1.055)**2.4)

class Kit:
    def __init__(self,model):
        self.m=model
    def surface(self,rings,base,pattern=None,close=True):
        rows=len(rings);cols=len(rings[0]);pts=np.asarray(rings)
        faces=[];colors=[]
        for j in range(rows):
            for i in range(cols):
                c=pattern(j,i) if pattern else 1.+.042*math.sin(i*1.34+j*.84)
                colors.append(rgb(base)*c)
                if j+1<rows and (i+1<cols or close):
                    a=j*cols+i;b=j*cols+(i+1)%cols
                    faces.extend(((a,b,b+cols),(a,b+cols,a+cols)))
        # Materials are double sided: both the flesh side at the hem and the rolled lip show.
        uv=[[(pts.reshape(-1,3)[k][0],pts.reshape(-1,3)[k][2]) for k in f] for f in faces]
        self.m.add(pts.reshape(-1,3),faces,uv,colors,'plain',[{}]*(rows*cols))
    def cord(self,path,radii,color,sides=7):
        rings=[];points=[Vector(p) for p in path]
        for i,(p,r) in enumerate(zip(points,radii)):
            n=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
            up=Vector((0,0,1)) if abs(n.z)<.88 else Vector((1,0,0))
            a=n.cross(up).normalized();b=n.cross(a)
            rings.append([p+r*(a*math.cos(k*math.tau/sides)+b*math.sin(k*math.tau/sides)) for k in range(sides)])
        self.surface(rings,color)
    def cloak(self):
        rings=[]
        for j,(width,depth,back,front) in enumerate([(.117,.105,.035,.025),(.203,.119,-.01,-.025),(.265,.148,-.09,-.07),(.272,.169,-.24,-.136),(.258,.17,-.38,-.22)]):
            row=[]
            for i in range(43):
                a=.14+(math.tau-.28)*i/42.
                z=front+(back-front)*(.5-.5*math.cos(a))
                ripple=.008*math.sin(9*a+.2*j)+.004*math.sin(15*a)
                row.append(((width+ripple*j/4)*math.sin(a),-(depth+ripple*j/4)*math.cos(a),z+.008*math.sin(5*a)*j/4))
            rings.append(row)
        self.surface(rings,'695642',lambda j,i:.88+.19*abs(math.sin(i*.51+j*.2))+.15*(j==0),False)
        for i in range(42):
            p=rings[-1][i];self.cord([p,(p[0]+.004*math.sin(i),p[1],p[2]-.012-.018*(i%4)/3)],[.007,.001],'524435',4)
        self.cord([(-.043,-.115,-.022),(0,-.132,-.034),(.046,-.117,-.04)],[.007]*3,'946f46')
        self.cord([(-.041,-.131,-.011),(-.029,-.144,-.043),(-.006,-.147,-.053),(.023,-.139,-.043),(.038,-.130,-.026)],[.007,.009,.008,.005,.0008],'d5be92',10)
    def whistle(self):
        self.cord([(-.044,0,.021),(-.030,0,.014),(-.005,0,.016),(.020,0,.028),(.045,0,.048),(.059,0,.063)],
                  [.009,.015,.017,.015,.009,.002],'d9c397',14)
        for x,z in [(-.029,.014),(-.023,.015)]:
            self.cord([(x,-.016*math.cos(a),z+.016*math.sin(a)) for a in np.linspace(0,math.tau,19)],[.0021]*19,'604a36',5)
        self.cord([(-.011,-.014,.022),(-.007,-.016,.022),(-.002,-.015,.022)],[.001,.004,.001],'3b3027')
        path=[(-.026-.045*math.sin(a),.007*math.sin(2*a),.013-.088*(1-math.cos(a))/2) for a in np.linspace(0,math.tau,36)]
        self.cord(path,[.0026]*len(path),'866643',6)
    def roll(self):
        rings=[]
        for j,x in enumerate(np.linspace(-.25,.25,25)):
            rings.append([(x,(.089+.007*math.sin(j*.65))*math.cos(a),.093+(.092+.004*math.cos(3*a+j*.3))*math.sin(a)) for a in np.linspace(0,math.tau,28,endpoint=False)])
        self.surface(rings,'695643',lambda j,i:.91+.17*math.sin(i*.54)+.04*math.sin(j*.9))
        for sign in (-1,1):
            path=[(sign*.252,r*math.cos(a),.093+r*math.sin(a)) for a,r in zip(np.linspace(0,math.tau*2.65,84),np.linspace(.003,.083,84))]
            self.cord(path,[.010]*len(path),'b5a58b',8)
            for x in [sign*.143,sign*.153]:
                path=[(x,.096*math.cos(a),.093+.096*math.sin(a)) for a in np.linspace(0,math.tau,30)]
                self.cord(path,[.006]*len(path),'916c46')
    def bedding(self):
        rings=[];edges=[]
        for j,y in enumerate(np.linspace(-.92,.92,42)):
            width=.346-.066*(abs(y)/.92)**3+.016*math.sin(y*12)
            base=.045+.008*math.sin(j*.42)
            row=[]
            for i in range(23):
                x=(i/11-1)*width
                z=base+.021*(1-(x/width)**2)+.011*math.sin(j*.59+x*11)
                row.append((x,y,z))
            rings.append(row)
        self.surface(rings,'b6a58a',lambda j,i:.9+.10*math.sin(i*.92+j*.88)+.05*math.sin(j*.24),False)
        for side in (0,-1):
            path=[r[side] for r in rings]
            self.cord(path,[.022]*len(path),'594332',8)
            for j in range(1,41,3):
                x,y,z=path[j];sign=1 if side==-1 else -1
                self.cord([(x-sign*.023,y,z+.004),(x,y+.015,z+.014),(x+sign*.011,y+.026,z)],[.003]*3,'c0aa81',5)
        self.cord([(-.255,-.77,.085),(-.20,-.77,.094),(.20,-.77,.094),(.255,-.77,.085)],[.048,.076,.076,.048],'8b765b',18)
