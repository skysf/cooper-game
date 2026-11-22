"""Bake the spring beds and intersect a horizontal water level with their real triangles."""
import numpy as np


def radius(x, z, site):
    cx, cz = site['water']
    u, v = (x - cx) / 3.0, (z - cz) / 2.25
    a = np.arctan2(v, u)
    return np.hypot(u, v) / (1 + .14*np.sin(3*a + site['yaw']) + .095*np.cos(2*a+.9) + .06*np.sin(5*a+.6))


def height_at(grid, x, z, origin, spacing=1.):
    u = np.clip((x-origin[0])/spacing, 0, grid.shape[1]-1)
    v = np.clip((z-origin[1])/spacing, 0, grid.shape[0]-1)
    i = np.minimum(u.astype(int), grid.shape[1]-2)
    j = np.minimum(v.astype(int), grid.shape[0]-2)
    u, v = u-i, v-j
    a,b,c,d = grid[j,i],grid[j,i+1],grid[j+1,i],grid[j+1,i+1]
    return np.where(u+v<=1, a+(b-a)*u+(c-a)*v, d+(c-d)*(1-u)+(b-d)*(1-v))


def water_mesh(mesh, key, x, z, h, level, site, faces):
    points = np.stack([x,h,z],axis=-1).reshape(-1,3)
    face_points = points[faces]
    # The hillside beyond a bank can also be below water level. Fill only triangles
    # connected through submerged vertices to this particular spring, never those outside it.
    wx,wz=site['water']; start=np.unravel_index(np.argmin((x-wx)**2+(z-wz)**2),x.shape)
    filled=np.zeros(h.shape,bool); todo=[start];filled[start]=True
    while todo:
        j,i=todo.pop()
        for dj,di in ((1,0),(-1,0),(0,1),(0,-1),(1,-1),(-1,1)):
            jj,ii=j+dj,i+di
            if 0<=ii<h.shape[1] and 0<=jj<h.shape[0] and not filled[jj,ii] and h[jj,ii]<level:
                filled[jj,ii]=True;todo.append((jj,ii))
    local=np.any(filled.ravel()[faces],axis=1)
    polygons, indices, colors = [], [], []
    for triangle in face_points[local & (face_points[:,:,1].min(1)<level)]:
        polygon = []
        for a,b in zip(triangle, np.roll(triangle,-1,axis=0)):
            if a[1]<level:
                polygon.append(a)
            if (a[1]<level) != (b[1]<level):
                polygon.append(a+(b-a)*(level-a[1])/(b[1]-a[1]))
        start=len(polygons)
        for px, bed, pz in polygon:
            polygons.append([px,level,pz]); colors.append([min(1,(level-bed)/.5),0,0,1])
        for i in range(1,len(polygon)-1):
            indices.append([start,start+i,start+i+1])
    p=np.asarray(polygons,dtype='f4')
    mesh.mesh('spring_water_'+key, {'POSITION':p,'NORMAL':np.tile(np.float32([0,1,0]),(len(p),1)),
              'TEXCOORD_0':np.ascontiguousarray(p[:,[0,2]]-np.array([wx,wz],dtype='f4')),'COLOR_0':np.uint8(np.clip(colors,0,1)*255)},np.array(indices))
    halves=local.reshape(-1,2).astype(np.uint8)
    return halves[:,0]+2*halves[:,1]
