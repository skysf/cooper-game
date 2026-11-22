"""Complete the scanned cliff face before packing either of its game LODs."""
import numpy as np


def read_attribute(doc, blob, index):
    info = doc['accessors'][index]
    view = doc['bufferViews'][info['bufferView']]
    dtype = np.dtype({5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}[info['componentType']])
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}[info['type']]
    return np.ndarray((info['count'], width), dtype, blob,
                      offset=view.get('byteOffset', 0) + info.get('byteOffset', 0),
                      strides=(view.get('byteStride', width * dtype.itemsize), dtype.itemsize))


def close_shelf(doc, blob, material):
    def append(values, position=False):
        indices = values.ndim == 1
        data = np.ascontiguousarray(values, dtype='<u4' if indices else '<f4')
        blob.extend(bytes(-len(blob) % 4))
        info = {'bufferView': len(doc['bufferViews']), 'componentType': 5125 if indices else 5126,
                'count': len(data), 'type': 'SCALAR' if indices else 'VEC' + str(data.shape[1])}
        if position:
            info.update(min=data.min(0).tolist(), max=data.max(0).tolist())
        doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': data.nbytes,
                                   'target': 34963 if indices else 34962})
        blob.extend(data.tobytes())
        doc['accessors'].append(info)
        return len(doc['accessors']) - 1

    for node in doc['nodes']:
        if node.get('name') not in ('rock_shelf', 'rock_shelf_far'):
            continue
        prims = doc['meshes'][node['mesh']]['primitives']
        front, = prims
        # The source scan includes coincident coordinates at UV seams. Keep the original
        # front untouched and identify its one physical perimeter in welded coordinates.
        original = read_attribute(doc, blob, front['attributes']['POSITION']).copy()
        faces = read_attribute(doc, blob, front['indices']).copy().reshape(-1, 3)
        _, reps, inverse = np.unique(original.round(4), axis=0, return_index=True, return_inverse=True)
        pts = original[reps]
        faces = inverse.reshape(-1)[faces]
        edges = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
        _, first, counts = np.unique(np.sort(edges, axis=1), axis=0, return_index=True, return_counts=True)
        rim = edges[first[counts == 1]]
        assert len(rim) > 20 and counts.max() == 2
        # The ledge's outwards-facing front is on the positive-Z side of the mesa.
        rear = pts.copy()
        rear[:, 0] = 1.4 + (pts[:, 0] - 1.4) * .89
        rear[:, 1] = pts[:, 1] * .65 - .48
        rear[:, 2] -= 3.25 + .52 * np.cos(pts[:, 0] * .64 + pts[:, 1] * .38)
        middle = (pts + rear) * .5
        middle[:, 1] += .32 * np.sin(pts[:, 1] * .49) + .09 * np.cos(pts[:, 0] * 2.0)
        middle[:, 0] += .12 * np.sin(pts[:, 0] * .46)
        n = len(pts)
        a, b = rim.T
        panels = [faces[:, ::-1] + 2 * n]
        for layer in (0, n):
            panels.extend([np.column_stack([b, a, a + n]) + layer, np.column_stack([b, a + n, b + n]) + layer])
        tri = np.vstack([pts, middle, rear])[np.concatenate(panels)]
        normals = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        length = np.linalg.norm(normals, axis=1)
        keep = length > 1e-9
        tri, normals = tri[keep], normals[keep] / length[keep, None]
        # Project the return faces by their own dominant direction at a fixed metre scale.
        # A cliff atlas has no information about the missing rock behind the scan.
        uv = np.empty((len(tri), 3, 2), np.float32)
        axis = np.argmax(np.abs(normals), axis=1)
        for i, uv_axes in enumerate(([2, 1], [0, 2], [0, 1])):
            uv[axis == i] = tri[axis == i][:, :, uv_axes] * .55
        prims.append({'mode': 4, 'material': material, 'attributes': {
            'POSITION': append(tri.reshape(-1, 3), True), 'NORMAL': append(np.repeat(normals, 3, axis=0)),
            'TEXCOORD_0': append(uv.reshape(-1, 2))}, 'indices': append(np.arange(tri.size // 3))})


def feather_root_edges(doc, blob):
    # Flatten the perimeter of the scanned soil apron. The root relief inside the patch
    # keeps its authored shape, and can now emerge through the slope at any heading.
    for node in doc['nodes']:
        if node.get('name') not in ('bank_roots','tangled_roots'):
            continue
        prim, = doc['meshes'][node['mesh']]['primitives']
        points = read_attribute(doc,blob,prim['attributes']['POSITION'])
        normals = read_attribute(doc,blob,prim['attributes']['NORMAL'])
        indices = read_attribute(doc,blob,prim['indices']).reshape(-1,3)
        _, reps, inv = np.unique(points.round(4),axis=0,return_index=True,return_inverse=True)
        inv = inv.reshape(-1)
        face = inv[indices]
        pairs = np.concatenate([face[:, [0,1]],face[:, [1,2]],face[:, [2,0]]])
        pairs, counts = np.unique(np.sort(pairs,axis=1),axis=0,return_counts=True)
        edge = points[reps[np.unique(pairs[counts==1])]][:,[0,2]]
        xz = points[:,[0,2]]
        distance = np.sqrt(np.min(np.sum((xz[:,None,:]-edge[None,:,:])**2,axis=2),axis=1))
        weight = np.clip(distance/(.13 if node['name']=='bank_roots' else .28),0,1)
        points[:,1] *= weight*weight*(3-2*weight)
        tri = points[indices]
        area = np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0])
        average = np.zeros((len(reps),3))
        for i in range(3): np.add.at(average,face[:,i],area)
        average /= np.maximum(1e-12,np.linalg.norm(average,axis=1))[:,None]
        changed = (weight<1) & (np.linalg.norm(average[inv],axis=1)>.9)
        normals[changed] = average[inv[changed]]
        info=doc['accessors'][prim['attributes']['POSITION']]
        info.update(min=points.min(0).tolist(),max=points.max(0).tolist())
