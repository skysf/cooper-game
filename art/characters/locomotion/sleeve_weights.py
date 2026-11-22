"""Weight the sleeve fabric by its connected surface below each armhole.

Positions are (lateral, height, depth) in metres. The supplied jacket has separate
cuff details and coincident UV-seam vertices. Welding is used for adjacency only.
"""
from collections import defaultdict
from math import dist

def smooth(low, high, value):
    t = max(0.,min(1.,(value-low)/(high-low)))
    return t*t*(3-2*t)

def sleeve_weights(positions, edges):
    vertices, lookup, mapping = [], {}, []
    for point in positions:
        key = tuple(round(float(v),4) for v in point)
        if key not in lookup:
            lookup[key] = len(vertices)
            vertices.append(key)
        mapping.append(lookup[key])
    graph = defaultdict(set)
    for a,b in edges:
        a,b=mapping[a],mapping[b]
        if a!=b:
            graph[a].add(b)
            graph[b].add(a)

    # The underarm opens at ~1.20 m. Below that height a fabric component can
    # belong entirely to one sleeve even where it touches the torso in projection.
    low=set(i for i,p in enumerate(vertices) if p[1] < 1.175)
    fixed={}
    while low:
        stack=[low.pop()]
        group=list(stack)
        while stack:
            i=stack.pop()
            for j in graph[i]:
                if j in low:
                    low.remove(j)
                    group.append(j)
                    stack.append(j)
        mean_x=sum(vertices[i][0] for i in group)/len(group)
        # The hem has a separate narrow facing at 0.167 m. The inner cuff
        # trim begins outside 0.18 m; keep the facing at the pelvis on a high reach.
        is_sleeve=float(abs(mean_x)>.180)
        for i in group:
            fixed[i]=is_sleeve

    weights=[]
    for i,(x,y,z) in enumerate(vertices):
        prior=smooth(.126,.24,abs(x))*(1.-smooth(1.35,1.45,y))
        if y>1.46 or abs(x)<.09:
            fixed[i]=0.
        weights.append(fixed.get(i,prior))

    # Extend pinned sleeve/torso labels across the shoulder with edge-distance
    # weighted relaxation; use a weak anatomical prior for disconnected trim.
    free=[i for i in range(len(vertices)) if i not in fixed]
    neighbors={i:[(j,1./max(.002,dist(vertices[i],vertices[j]))) for j in graph[i]] for i in free}
    prior=weights.copy()
    for _ in range(48):
        updated=weights.copy()
        for i in free:
            edges_i=neighbors[i]
            if edges_i:
                total=sum(w for j,w in edges_i)
                updated[i]=.96*sum(weights[j]*w for j,w in edges_i)/total+.04*prior[i]
        weights=updated
    return [weights[i] for i in mapping]
