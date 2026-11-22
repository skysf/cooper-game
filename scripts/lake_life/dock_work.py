"""Hand tools for the dock poses. All points are in character space (Blender metres)."""
from math import tau, cos, sin, pi
from mathutils import Vector

def tools_mesh(crew, model):
    p=crew.bones['Work']
    def add(v,f,color):
        model.add(v,f,[((0,0),(0,1),(1,0))]*len(f),[color]*len(v),'Paint',[{'Work':1.}]*len(v))
    def tube(points,r,color,n=6):
        verts=[];faces=[]
        for j,point in enumerate(points):
            d=(points[min(j+1,len(points)-1)]-points[max(0,j-1)]).normalized()
            a=d.cross(Vector((0,1,0)) if abs(d.y)<.88 else Vector((1,0,0))).normalized();b=d.cross(a)
            for k in range(n):
                verts.append(point+r*(a*cos(tau*k/n)+b*sin(tau*k/n)))
                if j:
                    q=(j-1)*n+k;h=(j-1)*n+(k+1)%n
                    faces.extend([(q,h,h+n),(q,h+n,q+n)])
        add(verts,faces,color)
    if not crew.female:
        for j in range(4):
            tube([p+Vector((.096*sin(tau*k/36+j*.09),.014*j+.006*cos(tau*k/36),-.130+.145*cos(tau*k/36+j*.09))) for k in range(37)],.010,(.43+j*.018,.273+j*.012,.130))
        tube([p+Vector(v) for v in ((.01,.02,0),(.03,.02,-.10),(.08,0,-.20),(.116,-.01,-.23),(.13,-.015,-.197))],.008,(.46,.29,.14))
        # The running end crosses the palm pulling in the next coil.
        end=crew.bones['LineEnd']
        verts=[];faces=[];weights=[]
        for k in range(11):
            u=k/10;at=p.lerp(end,u)+Vector((.01,.014,-.125*sin(pi*u)))
            for j in range(6):
                verts.append(at+Vector((.007*cos(tau*j/6),.007*sin(tau*j/6),0)))
                weights.append({'Work':1-u,'LineEnd':u})
                if k:
                    a=(k-1)*6+j;b=(k-1)*6+(j+1)%6
                    faces.extend(((a,b,b+6),(a,b+6,a+6)))
        model.add(verts,faces,[((0,0),(0,1),(1,0))]*len(faces),[(.47,.315,.16)]*len(verts),'Paint',weights)
    else:
        for j in range(7):
            a=j*2.399
            shoot=Vector((.094*cos(a),.055*sin(a),.17+.07*(j%3)/2))
            tube([p+shoot*t for t in (0,.4,.75,1)],.0026,(.134,.212,.076))
            for k in range(2,7):
                h=k/8;q=p+shoot*h
                for side in (-1,1):
                    d=Vector((side*cos(a),side*sin(a),.42))*(.048 if h<.7 else .030)
                    n=Vector((-sin(a),cos(a),0))*.010
                    add([q,q+d*.50+n,q+d,q+d*.50-n,q+d*.48+Vector((0,0,.006))],[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(0,3,2),(0,2,1)],(.16,.29,.114) if j%2 else (.226,.332,.150))
            if j%2==0:
                top=p+shoot
                tube([top-Vector((0,0,.027)),top,top+Vector((0,0,.018))],.010,(.35,.19,.31),5)
