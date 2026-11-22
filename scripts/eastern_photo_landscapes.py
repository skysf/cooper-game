"""Relief and vegetation placement for the wooded ravine and the terraced roadcut."""
import math
import numpy as np


def ramp(x):
    t=np.clip(x,0,1)
    return t*t*(3-2*t)


def scarp_depth(x,z):
    return -45.0+(x-306)*.16+np.sin((x-289)*.16)-z


def ravine_line(x):
    return np.interp(x,[107,117,136,153],[ -68,-85,-91,-87])


def wooded_cover(x,z):
    return ramp((x-106)/11)*ramp((178-x)/14)*ramp((27-abs(z-ravine_line(x)))/11)


def relief(x,z):
    depth=scarp_depth(x,z)
    extent=ramp((x-280)/11)*ramp((334-x)/11)
    # Two irregular fractured faces with a walkable ledge between them.
    slip=.48*np.sin(x*1.05)+.29*np.sin(x*.38+depth*.7)
    lower=ramp((depth+slip)/2.6)
    upper=ramp((depth-7.2+slip*.72)/2.9)
    cut=extent*(5.2*lower+5.65*upper)*ramp((39-depth)/21)
    cut+=extent*.33*np.sin(x*1.33+depth*.77)*ramp(depth/2)*ramp((16-depth)/4)
    bank=z-ravine_line(x)
    wooded=ramp((x-107)/11)*ramp((153-x)/13)
    # Retain the walking trail down the middle and raise its two green shoulders.
    ridges=2.2*np.exp(-((bank-8.4)/4.6)**2)+3.1*np.exp(-((bank+9.3)/5.5)**2)
    wooded_ridge=8.8*np.exp(-((x-158)/14)**2-((z+99)/10.5)**2)
    return cut+wooded*ridges*ramp((abs(bank)-2.2)/2.5)+wooded_ridge


def plant(put, groups, height_at, rng):
    for x in np.arange(111.0,152.0,1.36):
        center=ravine_line(x)
        for side in (-1,1):
            for band in (3.95,6.3):
                dx=rng.uniform(-.51,.51)
                px=x+dx
                pz=center+side*(band+rng.uniform(-.57,.78))
                size=rng.uniform(.90,1.45)*(1.12 if band>5 else .95)
                kind='vine_drape' if (int(x/4)+side)%3 else 'vine_scramble'
                groups[kind].append([round(px,2),round(float(height_at(px,pz))-.075,3),
                                     round(pz,2),round(rng.uniform(-math.pi,math.pi),3),round(size,3)])
        if int((x-111)/1.36)%3==0:
            put('grove_tree',x,center+rng.choice((-1,1))*rng.uniform(9,14),rng.uniform(.77,1.12),.37)
    # The trail turns before the wooded spur, giving the gap a forested middle distance.
    for x in np.arange(143.,171.,3.5):
        for baseline in (-106.,-99.,-94.):
            put(rng.choice(['grove_tree','crooked_tree']),x+rng.uniform(-1.6,1.6),baseline+rng.uniform(-2.,2.),rng.uniform(.96,1.44),.37)
    for x in np.arange(284.,332.,1.55):
        z=-45+(x-306)*.16+math.sin((x-289)*.16)
        if rng.random()<.67:
            put(rng.choice(['wax_shrub','silver_bush','broadleaf']),x,z-rng.uniform(3.8,6.7),rng.uniform(.57,.97))
        if rng.random()<.55:
            put('wax_shrub',x+rng.uniform(-.6,.6),z+rng.uniform(.4,2.4),rng.uniform(.77,1.22))
        if rng.random()<.68:
            put(rng.choice(['grove_tree','crooked_tree']),x,z-rng.uniform(12,17),rng.uniform(.46,.84),.37)

    for x in np.arange(286.,333.,2.7):
        z=-45+(x-306)*.16+math.sin((x-289)*.16)
        put(rng.choice(['grove_tree','crooked_tree']),x+rng.uniform(-.8,.8),z-rng.uniform(10.8,14.),rng.uniform(.72,1.16),.37)
        if rng.random()<.55:
            put('crooked_tree',x+rng.uniform(-.5,.5),z-rng.uniform(4.0,6.8),rng.uniform(.31,.49),.37)



def add_canopies(groups, rng):
    # Add leaf mass to existing rooted trees on the two photographed ridges.
    # Canopies inherit the position, height and orientation of their own trunk.
    for kind,tree_height,spread in [('grove_tree',7.4,1.40),('crooked_tree',5.8,1.10)]:
        for px,py,pz,yaw,scale in groups[kind]:
            along_cut=281<px<334 and 3.2<scarp_depth(px,pz)<20.
            in_grove=110<px<173 and -113<pz<-79
            if not (along_cut or in_grove): continue
            for index in range(3):
                a=yaw+index*2.09
                radius=(.14 if index==0 else .88)*scale
                height=py+tree_height*scale*(.83 if index==0 else .65)
                groups['leaf_mantle'].append([round(px+radius*math.cos(a),2),round(height,3),
                                               round(pz+radius*math.sin(a),2),round(a,3),round(scale*spread,3)])
    for key in ('vine_drape','vine_scramble'):
        for px,py,pz,yaw,scale in groups[key]:
            if abs(pz-ravine_line(px))>5.3 and rng.random()<.84:
                groups['leaf_mantle'].append([px,round(py+1.02*scale,3),pz,yaw,round(scale*.85,3)])
