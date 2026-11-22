"""Facial controls for the skinned portrait mesh, in the portrait author's metre space."""
from math import sin, pi, sqrt, exp
from mathutils import Vector


def add_face(mesh, rows, rings, face_start, female, portrait_uv):
    controls={name:{} for name in ('MouthOpen','MouthRound','Blink')}
    mesh.face_controls=controls
    def delta(key,i,x=0,y=0,z=0): controls[key][i]=Vector((-x,y,z))
    def xyz(i):
        x,y,z=mesh.verts[i]; return -x,y,z
    def smooth(t):
        t=max(0,min(1,t));return t*t*(3-2*t)
    def row_at(z):return min(range(len(rows)),key=lambda i:abs(rows[i][0]-z))
    crease=row_at(1.542 if female else 1.535); level=rows[crease][0]; sides=len(rings[0]);span=6
    upper=[rings[crease][j%sides] for j in range(-span,span+1)]
    lower=[i if k in (0,2*span) else mesh.v(xyz(i),'head') for k,i in enumerate(upper)]
    copied=dict(zip(upper,lower))
    for j in range(-span,span):
        index=face_start+(crease-1)*sides+j%sides
        mesh.faces[index]=[copied.get(v,v) for v in mesh.faces[index]]
    for k,ring in enumerate(rings):
        for i in ring:
            x,y,z=xyz(i); front=smooth((y+.026)/.108)
            if k<crease:
                # Mandible rotates down and slightly back. The cheeks take up the
                # displacement progressively, while the cheekbones stay still.
                below=smooth((level-z)/.029)
                local=exp(-(x/.030)**4)
                delta('MouthOpen',i,0,-.007*front*below,-front*(.019*below+.022*(1-below)*local))
            if k>crease:
                delta('MouthOpen',i,0,0,.0026*exp(-(x/.029)**4-((z-level)/.011)**2)*front)
            narrow=exp(-((z-level)/.018)**2)*front
            delta('MouthRound',i,-x*.22*narrow,.008*exp(-(x/.035)**4)*narrow,0)
    upper_dark=[]; lower_dark=[]
    for k,(u,l) in enumerate(zip(upper,lower)):
        x,y,z=xyz(u); w=sin(pi*k/(2*span))**.78
        delta('MouthOpen',u,0,.001*w,.0025*w)
        if u!=l: delta('MouthOpen',l,0,-.006*w,-.022*w)
        delta('MouthRound',l,-x*.22,.008*w,0)
        top=mesh.v((x,y-.014*w-.001,z+.001*w),'head');bottom=mesh.v((x,y-.014*w-.001,z-.001*w),'head')
        upper_dark.append(top);lower_dark.append(bottom)
        delta('MouthOpen',top,0,-.006*w,.0015*w);delta('MouthOpen',bottom,0,-.008*w,-.017*w)
        for i in (top,bottom): delta('MouthRound',i,-x*.22,.006*w,0)
    for j in range(2*span):
        for a,b,mat in ((upper,upper_dark,13),(upper_dark,lower_dark,12),(lower_dark,lower,13)):
            mesh.face([a[j],a[j+1],b[j+1],b[j]],mat)
    # A narrow upper dental arch is partly hidden behind the upper lip.
    teeth=[]
    for j in range(3,2*span-2):
        x,y,z=xyz(upper[j]);w=sin(pi*(j-2)/(2*span-4)); pair=[]
        for dz in (.0015,-.0026*w):
            i=mesh.v((x,y-.0067,z+dz),'head');pair.append(i);delta('MouthOpen',i,0,0,.0014*w);delta('MouthRound',i,-x*.16,.005*w,0)
        teeth.append(pair)
    for a,b in zip(teeth,teeth[1:]):mesh.face([a[0],b[0],b[1],a[1]],14)
    def section(z):
        lo=max(i for i,row in enumerate(rows[:-1]) if row[0]<=z)
        return lo,(z-rows[lo][0])/(rows[lo+1][0]-rows[lo][0])

    def facial_point(x,z):
        # Sample the triangulated head (including its sculpted eye sockets).
        # If a lid samples the analytic oval instead, parts of the printed eye
        # can poke through the lid where the original triangles span a crease.
        lo,f=section(z)
        for j in range(-sides//4,sides//4):
            a,b=xyz(rings[lo][j]),xyz(rings[lo][j+1])
            c,d=xyz(rings[lo+1][j]),xyz(rings[lo+1][j+1])
            left=a[0]*(1-f)+c[0]*f;right=b[0]*(1-f)+d[0]*f
            if left<=x<=right:
                diagonal=a[0]*(1-f)+d[0]*f
                if x<=diagonal:
                    return (1-f)*a[1]+f*c[1]+(d[1]-c[1])*(x-left)/(d[0]-c[0])
                return f*d[1]+(1-f)*b[1]-(b[1]-a[1])*(right-x)/(b[0]-a[0])
        raise ValueError("eyelid outside the front of the head")

    def skin_uv(x,z):
        lo,f=section(z)
        uvs=[]
        for row in (lo,lo+1):
            sx=x/rows[row][3]
            uvs.append(portrait_uv(row,sx,sqrt(max(0,1-sx*sx)),True))
        return tuple(v+(w-v)*f for v,w in zip(*uvs))

    for side in (-1,1):
        # Upper and lower lids meet on a shallow curved lash line. Mirror the
        # winding as well as the positions so both eyes receive the same light.
        patches=[]; uv=[]; count=18
        for j in range(count+1):
            t=j/count; arch=sin(pi*t)**.68; x=side*(.007+.057*t)
            mid=1.597+.002*(t-.5)
            top=mid+.0108*arch
            line=mid-.0038*arch
            bottom=mid-.0100*arch
            poses=[(top+.004*arch,top+.004*arch),(top+.0018*arch,(top+line)*.5),
                   (top,line+.00055*arch),(bottom,line-.00055*arch),
                   (bottom-.0023*arch,bottom-.0023*arch)]
            strip=[]; coords=[]
            for row_index,(z,closed) in enumerate(poses):
                rest=facial_point(x,z)-.0035
                i=mesh.v((x,rest,z),'head')
                strip.append(i)
                depth=facial_point(x,closed)+.0014+.0006*arch
                delta('Blink',i,0,depth-rest,closed-z)
                sample=top+.003+.0014*(2-row_index) if row_index<3 else bottom-.001
                coords.append(skin_uv(x,sample))
            # The lash strip must retract with the upper lid at rest. A large
            # polygon across the resting eye would otherwise occlude its iris.
            patches.append(strip);uv.append(coords)
        for j in range(count):
            for r in range(4):
                corners=[(j,r),(j+1,r),(j+1,r+1),(j,r+1)]
                if side>0: corners.reverse()
                mesh.face([patches[k][l] for k,l in corners],2 if r==2 else 0,[uv[k][l] for k,l in corners])



def install(ob, controls):
    basis=ob.shape_key_add(name='Basis')
    for name,offsets in controls.items():
        key=ob.shape_key_add(name=name,from_mix=False)
        for i,offset in offsets.items():
            if offset.length_squared>1e-12:key.data[i].co=basis.data[i].co+offset
