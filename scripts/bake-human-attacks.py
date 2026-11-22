"""Author in-place melee takes on the camp's two rigs. Blender metres, +Y forward."""
from math import radians

import bpy
from mathutils import Matrix, Quaternion, Vector

RIGHT = Vector((1, 0, 0))
FORWARD = Vector((0, 1, 0))
UP = Vector((0, 0, 1))
SIDES = (("L", -1), ("R", 1))
# Wrist positions in character space, from the loaded hand through contact and follow-through.
# X is measured on the striking side. The off hand and elbows each have their own path.
TAKES = {
    "PunchJab":   ("L", (.14, .25, 1.44), (.11, .51, 1.54), (.10, .53, 1.53),  12, -17),
    "PunchCross": ("R", (.20, .22, 1.43), (.04, .54, 1.52), (.01, .54, 1.50), -18,  29),
    "PunchHook":  ("L", (.34, .16, 1.41), (.08, .40, 1.53), (-.10,.37, 1.49),  24, -34),
    "ClubSwing":  ("R", (.31, .06, 1.59), (.13, .42, 1.39), (-.09,.38, 1.19), -25,  33),
    "SpearThrust":("R", (.28,-.04, 1.18), (.15, .49, 1.33), (.13, .52, 1.33), -16,  23),
    "BladeCut":   ("R", (.32, .13, 1.55), (.09, .44, 1.40), (-.16,.34, 1.23), -22,  37),
    "Throw":      ("R", (.27,-.08, 1.59), (.13, .42, 1.57), (-.04,.45, 1.31), -30,  32),
}


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def at(keys, t):
    for (a, x), (b, y) in zip(keys, keys[1:]):
        if t <= b:
            return x + (y - x) * smooth((t - a) / (b - a))
    return keys[-1][1]


def pose_frame(rig, helper, relative, idle, name, t, player):
    side, load, hit, follow, twist_back, twist_out = TAKES[name]
    sign = 1 if side == "R" else -1
    contact = .33 if player else .60
    wind = contact * .62
    finish = contact + (.095 if player else .08)
    recover = .74 if player else .86
    from_guard = player and name.startswith("Punch")
    end_weight = .65 if from_guard else 0.
    ready = at(((0, end_weight), (wind, 1.), (recover, 1.), (1, end_weight)), t)
    drive = at(((0, 0.), (wind, -.26), (contact, 1.), (finish, .96), (recover, .18), (1, 0.)), t)
    yaw = at(((0, 0.), (wind, twist_back), (contact, twist_out*.87),
              (finish, twist_out), (recover, twist_out*.16), (1, 0.)), t)
    hip = idle["hips"].translation + Vector((sign*(.021*ready-.040*drive), .043*drive, -.050*ready+.016*drive))
    rotations = {}
    for bone, turn, lean, roll in (("hips",.46,3,2), ("spine",.67,6,3), ("chest",.86,8,4),
                                   ("upper_chest",1.,9,4), ("neck",.36,5,2), ("head",.13,2,1)):
        rotations[bone] = (Quaternion(UP, radians(yaw*turn))
                           @ Quaternion(FORWARD, radians(sign*roll*drive))
                           @ Quaternion(RIGHT, radians(-lean*drive-2*ready))
                           @ idle[bone].to_quaternion())
    for label, hand_sign in SIDES:
        active = label == side
        shoulder = "clavicle_" + label
        rotations[shoulder] = (Quaternion(UP, radians(yaw*(1.09 if active else .87)))
                               @ Quaternion(FORWARD, radians(-hand_sign*(6 if active else 3)*ready))
                               @ idle[shoulder].to_quaternion())
        # Keep both soles in their fitted standing positions as the pelvis transfers weight.
        hip_origin = hip + rotations["hips"] @ (idle["hips"].to_quaternion().inverted() @
                         (idle["thigh_"+label].translation - idle["hips"].translation))
        joints = tuple(b+"_"+label for b in ("thigh","shin","foot"))
        for b in joints:
            rotations[b] = idle[b].to_quaternion()
        foot = idle[joints[2]].translation
        natural_knee = idle[joints[1]].translation - idle[joints[0]].translation
        axis = (foot-idle[joints[0]].translation).normalized()
        pole = (natural_knee - axis*natural_knee.dot(axis)).normalized()
        if pole.length < .1:
            pole = FORWARD.copy()
        helper["solve_limb"](idle, rotations, hip_origin, foot, joints,
                             pole.lerp(Vector((hand_sign*.20,1,0)), ready*.85))
    mats = helper["posed_matrices"](rig, relative, hip, rotations)
    for label, hand_sign in SIDES:
        active = label == side
        upper, lower, wrist = (b+"_"+label for b in ("upper_arm","forearm","hand"))
        start = idle[wrist].translation
        guard = Vector((hand_sign*.17, .26, 1.42 if label == "L" else 1.40))
        bookend = guard if from_guard else start
        if active:
            point = lambda xyz: Vector((hand_sign*xyz[0],xyz[1],xyz[2]))
            target = at(((0,bookend),(wind,point(load)),(contact,point(hit)),(finish,point(follow)),
                         (recover,guard),(1,bookend)), t)
            if name in ("PunchJab","PunchCross","SpearThrust"):
                length = (idle[lower].translation-idle[upper].translation).length + (start-idle[lower].translation).length
                direction = Vector((-hand_sign*.16,1.,.28 if name!="SpearThrust" else -.03)).normalized()
                extended = mats[upper].translation + direction*(length*.967)
                target = target.lerp(extended,max(0.,drive)**2)
        else:
            cover = Vector((hand_sign*.16,.23,1.46))
            target = at(((0,bookend),(wind,guard),(finish,cover),(recover,guard),(1,bookend)), t)
        rotations[upper], rotations[lower] = idle[upper].to_quaternion(), idle[lower].to_quaternion()
        # Starting pole comes from the fitted arm, so the first/last frames can join a walk or idle.
        upper_pos = idle[upper].translation
        line = (start-upper_pos).normalized()
        elbow = idle[lower].translation-upper_pos
        start_pole = (elbow-line*elbow.dot(line)).normalized()
        pole = Vector((hand_sign*(1.20 if name=="PunchHook" and active else .62), -.47, -.85))
        helper["solve_limb"](idle, rotations, mats[upper].translation, target,
                             (upper,lower,wrist), start_pole.lerp(pole, ready))
        # Transport the hand with the forearm. A slight pronation differentiates a fist and a grip.
        fore_delta = rotations[lower] @ idle[lower].to_quaternion().inverted()
        hand_rotation = fore_delta @ idle[wrist].to_quaternion()
        if name.startswith("Punch"):
            twist = (64 if active else 12)*max(0.,drive) + 10*ready
            direction = fore_delta @ (start-idle[lower].translation).normalized()
            hand_rotation = Quaternion(direction, radians(-hand_sign*twist)) @ hand_rotation
        elif player and active:
            carried = hand_rotation @ idle[wrist].to_quaternion().inverted() @ FORWARD
            if name == "SpearThrust":
                wanted = Vector((-.04,1,.09))
            else:
                wanted = at(((0,FORWARD),(wind,Vector((.22,-.48,.88))),
                            (contact,Vector((-.27,.90,.27))),(finish,Vector((-.54,.78,-.35))),(1,FORWARD)),t)
            hand_rotation = Quaternion().slerp(carried.rotation_difference(wanted.normalized()),ready) @ hand_rotation
        rotations[wrist] = hand_rotation
    mats = helper["posed_matrices"](rig, relative, hip, rotations)
    if player:
        # Bend toward the palm in the standing hand's own frame, then carry the closed
        # fingers with the keyed wrist. The thumb folds across the first two fingers.
        for label, hand_sign in SIDES:
            curl = at(((0,end_weight),(wind*.85,1.),(recover,.94),(1,end_weight)),t)
            for finger in ("index","middle","ring","pinky","thumb"):
                # In the fitted hand's coordinate frame, X points from the palm
                # toward the back of the hand, Y toward the index and Z upward.
                directions = ((-.94,.01,-.31),(-.22,0,.98),(.87,0,.49))
                if finger == "thumb":
                    directions = ((-.42,.15,-.90),(-.43,-.62,-.65),(.13,-.96,-.25))
                carried = mats["hand_"+label].to_quaternion() @ idle["hand_"+label].to_quaternion().inverted()
                for j, (x,y,z) in enumerate(directions,1):
                    bone = f"{finger}_{j:02d}_{label}"
                    parent = rig.pose.bones[bone].parent.name
                    orient = idle[bone].to_quaternion()
                    tangent = (idle[f"{finger}_{j+1:02d}_{label}"].translation - idle[bone].translation).normalized() if j < 3 else orient @ FORWARD
                    bent = tangent.rotation_difference(Vector((hand_sign*x,y,z)).normalized()) @ orient
                    rotation = carried @ orient.slerp(bent,curl)
                    mats[bone] = Matrix.LocRotScale((mats[parent] @ relative[bone]).translation, rotation, None)
    else:
        # Equipment is attached to real grip bones. Orient its long axis on the
        # shaft/edge and keep the oval shield facing forward as the arm comes up.
        if name in ("SpearThrust","ClubSwing"):
            direction = (Vector((-.04,1,.09)) if name=="SpearThrust" else
                         at(((0,UP),(wind,Vector((.22,-.60,.83))),(contact,Vector((-.42,.86,.22))),
                             (finish,Vector((-.59,.72,-.38))),(1,UP)),t))
            g = "grip_R"
            base = idle[g].to_quaternion()
            desired = (base @ FORWARD).rotation_difference(direction.normalized()) @ base
            mats[g] = Matrix.LocRotScale(mats[g].translation,
                    mats[g].to_quaternion().slerp(desired,ready),None)
        g = "grip_L"
        mats[g] = Matrix.LocRotScale(mats[g].translation, mats[g].to_quaternion().slerp(idle[g].to_quaternion(),ready*.95), None)
    return mats


def build_actions(rig, helper, player=False):
    tracks = rig.animation_data.nla_tracks
    for track in tracks:
        track.mute = True
    idle_name = "Stand" if player else "Idle-loop"
    rig.animation_data.action = bpy.data.actions[idle_name]
    rig.animation_data.action_slot = rig.animation_data.action.slots[0]
    bpy.context.scene.frame_set(1)
    idle = {bone.name:bone.matrix.copy() for bone in rig.pose.bones}
    _, bind_relative = helper["rest_pose"](rig)
    relative = {b.name:idle[b.parent.name].inverted() @ idle[b.name] if b.parent else idle[b.name] for b in rig.pose.bones}
    for name in TAKES:
        if name == ("Throw" if player else "BladeCut"):
            continue
        rig.animation_data.action = None
        old = tracks.get(name)
        if old:
            action = old.strips[0].action
            tracks.remove(old)
            bpy.data.actions.remove(action)
        action = bpy.data.actions.new(name)
        rig.animation_data.action = action
        previous = {}
        frames = 20 if player else 53   # 0.667s at 30 fps / 1.104s at 48 fps.
        for frame in range(frames+1):
            mats = pose_frame(rig, helper, relative, idle, name, frame/frames, player)
            helper["key_pose"](rig, mats, bind_relative, frame+1, previous)
        rig.animation_data.action = None
        track = tracks.new()
        track.name = name
        track.strips.new(name,1,action)
        track.mute = True
