"""Extend the visible watershed beyond the playable terrain and stitch its shared edges."""
import json

import numpy as np

from eastern_springs import height_at


def smooth(t):
    t = np.clip(t, 0., 1.)
    return t*t*(3.-2.*t)


def land_noise(x, z):
    i,j = np.floor(x).astype('int64'),np.floor(z).astype('int64')
    u,v = smooth(x-i),smooth(z-j)
    def corner(a,b):
        n = (a*374761393+b*668265263) & 0xffffffff
        n = ((n^(n>>13))*1274126177) & 0xffffffff
        return (n^(n>>16))/4294967295.
    return (corner(i,j)*(1-u)+corner(i+1,j)*u)*(1-v)+(corner(i,j+1)*(1-u)+corner(i+1,j+1)*u)*v


def foothills(x, z, distance):
    # Three irregular ridge lines, with lower spurs and saddles between the crests.
    along = .89*x + .46*z
    across = z - .17*x + 29*np.sin(x*.014) + 13*np.sin(along*.037)
    ridge = np.maximum.reduce([
        (32+13*np.sin(along*.023))*np.exp(-((across-88)/38)**2),
        (72+24*np.cos(along*.018))*np.exp(-((across-234-22*np.sin(x*.024))/56)**2),
        (79+25*np.sin(along*.012))*np.exp(-((across+305-38*np.cos(x*.017))/69)**2),
    ])
    east_range = (72+25*np.cos(z*.022))*np.exp(-((x-565-42*np.sin(z*.018))/62)**2)
    rolling = 15 + 9*np.sin(along*.032) + 8*np.cos(across*.043) + 5*np.sin(x*.047-z*.021)
    highlands = np.maximum(ridge, east_range)
    folds = land_noise(x*.024,z*.024)
    spurs = 1.-abs(2.*land_noise(x*.034+folds*1.2,z*.039)-1.)
    relief = (folds-.48)*19 + (spurs-.6)*16 + (land_noise(x*.075,z*.075)-.5)*8
    height = rolling*.78 + highlands*(.62+.34*folds) + relief + 8*smooth((distance-50)/200)
    coast = smooth((x+139+9*np.sin(z*.021))/50)
    return -5.0 + (height+5.0)*coast


def bake_horizon(mesh, root, elevation, region):
    coast = json.loads((root/'coop/coast_layout.json').read_text())
    seabed = np.fromfile(root/'coop/coast/elevation.bin','<f4').reshape(coast['cells'][1]+1,-1)
    east_bounds = (30, region['origin'][0]+region['cells'][0], region['origin'][1],
                   region['origin'][1]+region['cells'][1])
    cx, cz = coast['origin']
    spacing = coast['spacing']
    coast_bounds = (cx,cx+coast['cells'][0]*spacing,cz,cz+coast['cells'][1]*spacing)
    bounds = [east_bounds, (-30,30,-226,119), coast_bounds]
    steps = [1., 1., spacing]
    xs = np.unique([*range(-318,1135,10), *(v for b in bounds for v in b[:2])])
    zs = np.unique([*range(-935,866,10), *(v for b in bounds for v in b[2:])])
    mx, mz = np.meshgrid((xs[1:]+xs[:-1])/2, (zs[1:]+zs[:-1])/2)
    existing = np.full(mx.shape,-1)
    for k,(left,right,near,far) in enumerate(bounds):
        existing[(mx>left)&(mx<right)&(mz>near)&(mz<far)] = k
    vertices, ids, faces = [], {}, []

    def vertex(x, z):
        if (x,z) not in ids:
            ids[x,z] = len(vertices)
            vertices.append((x,z))
        return ids[x,z]

    for j,i in zip(*np.where(existing<0)):
        xa,xb,za,zb = xs[i],xs[i+1],zs[j],zs[j+1]
        corners = [(xa,za),(xa,zb),(xb,zb),(xb,za)]
        rim = []
        for k,(dj,di) in enumerate([(0,-1),(1,0),(0,1),(-1,0)]):
            a,b = corners[k],corners[(k+1)%4]
            rim.append(vertex(*a))
            nj,ni = j+dj,i+di
            if not (0<=nj<existing.shape[0] and 0<=ni<existing.shape[1]):
                continue
            owner = existing[nj,ni]
            if owner<0:
                continue
            # A coarse edge reproduces every boundary vertex of its fine neighbour.
            axis = int(a[0]==b[0])
            start = bounds[owner][2*axis]
            step = steps[owner]
            lo,hi = sorted([a[axis],b[axis]])
            knots = start + np.arange(np.floor((lo-start)/step)+1,np.ceil((hi-start)/step))*step
            for value in knots if a[axis]<b[axis] else knots[::-1]:
                rim.append(vertex(a[0],value) if axis else vertex(value,a[1]))
        if len(rim)==4:
            faces.extend([(rim[0],rim[1],rim[3]),(rim[3],rim[1],rim[2])])
        else:
            mid = vertex((xa+xb)*.5,(za+zb)*.5)
            faces.extend((mid,v,rim[(n+1)%len(rim)]) for n,v in enumerate(rim))

    x,z = np.asarray(vertices).T
    distances = np.array([np.hypot(x-np.clip(x,l,r),z-np.clip(z,n,f)) for l,r,n,f in bounds])
    heights = [height_at(elevation,x,z,region['origin']), -.12*(1-smooth((x-16)/14)),
               height_at(seabed,x,z,coast['origin'],spacing)]
    weights = 1./(.001+distances)**2
    border = np.average(heights,axis=0,weights=weights)
    distance = distances.min(axis=0)
    blend = smooth(distance/48)
    y = border*(1-blend) + foothills(x,z,distance)*blend
    p = np.column_stack((x,y,z))
    f = np.asarray(faces)
    normals = np.zeros_like(p)
    face_normals = np.cross(p[f[:,1]]-p[f[:,0]],p[f[:,2]]-p[f[:,0]])
    for k in range(3):
        np.add.at(normals,f[:,k],face_normals)
    normals /= np.linalg.norm(normals,axis=1)[:,None]
    dry = smooth((x-110+8*np.sin(z*.065))/57)
    cover = smooth(distance/40)
    scrub = .62*land_noise(x*.032,z*.032)+.38*land_noise(x*.083,z*.083)
    stone = smooth((1-normals[:,1]+.16*scrub-.04)/.30)
    colors = np.column_stack((dry,scrub*cover,stone*cover,np.zeros_like(x)))
    mesh.mesh('watershed_horizon',{'POSITION':p.astype('f4'),'NORMAL':normals.astype('f4'),
              'COLOR_0':np.uint8(colors*255),'TEXCOORD_0':np.column_stack((x,z)).astype('f4')/3.4,
              'TEXCOORD_1':np.column_stack(((x+4)*.5,-cover)).astype('f4')},f)
