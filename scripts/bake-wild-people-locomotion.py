"""Bake the player gait onto the four NPC sources in a candidate directory.

Run from a background Blender session with runpy, then call bake(project, output).
The existing NPC sources are read-only. Distances match wild_people.gd.
"""

from math import cos, exp, pi, sin, sqrt, tau
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

SIDES = ("L", "R")
CORE = ("hips", "spine", "chest", "upper_chest", "neck", "head")
ARMS = tuple(f"{bone}_{side}" for side in SIDES
             for bone in ("clavicle", "upper_arm", "forearm", "hand"))
LEGS = tuple(f"{bone}_{side}" for side in SIDES
             for bone in ("thigh", "shin", "foot", "toes"))
MAPPED = ("root",) + CORE + ARMS + LEGS
IDENTITY = Quaternion()
FORWARD = Vector((0, 1, 0))
UP = Vector((0, 0, 1))
TURN_RADIANS = pi / 2
STRIDES = {
    "Walk": ("Walk", 1.38, 48, (0.59, 0.59), (0.135, 0.135)),
    "Run": ("Run", 1.92, 36, (0.37, 0.37), (0.186, 0.186)),
    "Limp": ("Walk", 1.04, 54, (0.70, 0.52), (0.13, 0.048)),
    "LimpLeft": ("Walk", 1.04, 54, (0.52, 0.70), (0.048, 0.13)),
}
MODELS = ("male", "female", "male_elite", "female_elite")


def scene_rig():
    rig, = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    assert rig.matrix_world == Matrix.Identity(4), rig.name
    assert set(MAPPED) <= set(rig.pose.bones.keys())
    return rig


def player_samples(project):
    bpy.ops.wm.open_mainfile(filepath=str(project / "art/characters/locomotion/player_locomotion.blend"))
    rig = scene_rig()
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    clips = {}
    for name, intervals in (("Stand", 0), ("Walk", 96), ("Run", 96)):
        action = bpy.data.actions[name]
        rig.animation_data.action = action
        rig.animation_data.action_slot = action.slots[0]
        first, last = action.frame_range
        samples = []
        for i in range(intervals + 1):
            frame = first + (last - first) * i / max(1, intervals)
            bpy.context.scene.frame_set(int(frame), subframe=frame % 1.0)
            samples.append({bone: (rig.pose.bones[bone].matrix.translation.copy(),
                                   rig.pose.bones[bone].matrix.to_quaternion()) for bone in MAPPED})
        clips[name] = samples
    return clips


def sample(samples, phase):
    key = (phase % 1.0) * (len(samples) - 1)
    i = int(key)
    factor = key - i
    return {name: (point.lerp(samples[i + 1][name][0], factor),
                   rotation.slerp(samples[i + 1][name][1], factor))
            for name, (point, rotation) in samples[i].items()}


def rotated_delta(pose, stand, bone):
    return pose[bone][1] @ stand[bone][1].inverted()


def sole_points(body, rest, side):
    bone = f"foot_{side}"
    group = body.vertex_groups[bone].index
    ankle = rest[bone].translation
    local = rest[bone].to_quaternion().inverted()
    points = [local @ (v.co - ankle) for v in body.data.vertices
              if v.co.z < 0.074 and any(g.group == group and g.weight > 0.6 for g in v.groups)]
    assert len(points) > 20, (body.name, bone, len(points))
    return points


def contact(sole, rotation):
    points = [rotation @ point for point in sole]
    floor = min(point.z for point in points)
    weights = [exp(-((point.z - floor) / 0.017)**2) for point in points]
    center = sum((point * weight for point, weight in zip(points, weights)), Vector()) / sum(weights)
    center.z = floor
    return center


def smooth(v):
    return v * v * (3.0 - 2.0 * v)


def stride_contact(phase, duty, length, lift):
    half_reach = duty * length / 2
    if phase < duty:
        return half_reach - phase * length, 0.0
    swing = (phase - duty) / (1.0 - duty)
    # Same stance velocity and Hermite recovery as the player stride.
    tangent = length * (1.0 - duty)
    travel = half_reach * (2 * smooth(swing) - 1) - tangent * (2 * swing**3 - 3 * swing**2 + swing)
    return travel, lift * sin(pi * swing)**1.3


def knee_and_ankle(rest, target, rotations, hip_pos, side, knee_hint):
    thigh, shin, foot = (f"{bone}_{side}" for bone in ("thigh", "shin", "foot"))
    hip_offset = rest[thigh].translation - rest["hips"].translation
    hip_delta = rotations["hips"] @ rest["hips"].to_quaternion().inverted()
    origin = hip_pos + hip_delta @ hip_offset
    solve_limb(rest, rotations, origin, target, (thigh, shin, foot), knee_hint)


def solve_limb(rest, rotations, origin, target, joints, bend_hint):
    first, second, last = joints
    upper = rest[second].translation - rest[first].translation
    lower = rest[last].translation - rest[second].translation
    ulen, llen = upper.length, lower.length
    direction = target - origin
    distance = min(direction.length, ulen + llen - 0.0001)
    direction.normalize()
    knee_dir = bend_hint - direction * direction.dot(bend_hint)
    if knee_dir.length < 0.001:
        knee_dir = FORWARD - direction * direction.y
    knee_dir.normalize()
    along = (distance * distance + ulen * ulen - llen * llen) / (2 * distance)
    knee = origin + direction * along + knee_dir * sqrt(max(0.0, ulen * ulen - along * along))
    ankle = origin + direction * distance
    for name, old_offset, new_offset in ((first, upper, knee - origin), (second, lower, ankle - knee)):
        prior = rotations[name]
        reference = prior @ (rest[name].to_quaternion().inverted() @ old_offset)
        rotations[name] = reference.rotation_difference(new_offset) @ prior


def pose_frame(rest, soles, centers, clips, name, phase):
    stand = clips["Stand"][0]
    turn = 1 if name == "TurnLeft" else -1 if name == "TurnRight" else 0
    player, length, _, duties, lifts = STRIDES.get(name, ("Walk", 0, 30, (0.60, 0.60), (0.105, 0.105)))
    action = sample(clips[player], phase)
    rotations = {bone: rotated_delta(action, stand, bone) @ rest[bone].to_quaternion() for bone in MAPPED}
    for bone in CORE + ARMS:
        if turn or bone in ARMS:
            rotations[bone] = rest[bone].to_quaternion().slerp(rotations[bone], 0.42 if turn else 0.78)
    hip_pos = rest["hips"].translation + (action["hips"][0] - stand["hips"][0]) * (0.60 if turn else 0.91)
    if turn:
        for bone, weight in (("hips", 2), ("spine", 4), ("chest", 8), ("upper_chest", 10), ("neck", 15), ("head", 17)):
            rotations[bone] = Quaternion(UP, turn * weight * pi / 180 * (0.55 + 0.45 * cos(tau * phase))) @ rotations[bone]
    elif name in ("Limp", "LimpLeft"):
        safe_side = 1 if name == "LimpLeft" else -1
        weight = 0.5 + 0.5 * cos(tau * (phase - (0.68 if safe_side > 0 else 0.18)))
        hip_pos.x += 0.035 * safe_side * weight
        hip_pos.z -= 0.014 * weight
        for bone in CORE:
            rotations[bone] = Quaternion(FORWARD, safe_side * 0.075 * weight) @ rotations[bone]
    targets = {}
    knee_hints = {}
    for i, side in enumerate(SIDES):
        u = (phase + 0.5 * i) % 1.0
        duty = duties[i]
        foot, toe, thigh, shin = (f"{bone}_{side}" for bone in ("foot", "toes", "thigh", "shin"))
        # Match the player ankle and knee timing to the NPC support or swing duration.
        source_duty = 0.37 if player == "Run" else 0.59
        source_phase = (u / duty * source_duty if u < duty else
                        source_duty + (u - duty) / (1 - duty) * (1 - source_duty))
        step = sample(clips[player], source_phase - 0.5 * i)
        source_leg = (step[foot][0] - step[thigh][0]).normalized()
        source_knee = step[shin][0] - step[thigh][0]
        knee_hints[side] = (source_knee - source_leg * source_leg.dot(source_knee)).normalized()
        for bone in (thigh, shin, foot, toe):
            rotations[bone] = rotated_delta(step, stand, bone) @ rest[bone].to_quaternion()
        slide, clearance = stride_contact(u, duty, length, lifts[i])
        center = centers[side].copy()
        if turn:
            arc = duty / 2 - u if u < duty else duty * (smooth((u - duty) / (1 - duty)) - 0.5)
            yaw = Quaternion(UP, turn * TURN_RADIANS * arc)
            center = yaw @ center
            for bone in (foot, toe):
                rotations[bone] = yaw @ rest[bone].to_quaternion().slerp(rotations[bone], 0.37)
        else:
            center.y += slide
            if lifts[i] < 0.08:
                for bone in (foot, toe):
                    rotations[bone] = rest[bone].to_quaternion().slerp(rotations[bone], 0.49)
        center.z = 0.004 + clearance
        target = center - contact(soles[side], rotations[foot])
        targets[side] = target
        rest_hip = rest["hips"].translation
        offset = (rotations["hips"] @ rest["hips"].to_quaternion().inverted()) @ (rest[thigh].translation - rest_hip)
        horizontal = target - (hip_pos + offset)
        upper, lower = rest[shin].translation - rest[thigh].translation, rest[foot].translation - rest[shin].translation
        dh = sqrt(max(0.0, (upper.length + lower.length - 0.006)**2 - horizontal.x**2 - horizontal.y**2))
        hip_pos.z = min(hip_pos.z, target.z + dh - offset.z)
    for side in SIDES:
        knee_and_ankle(rest, targets[side], rotations, hip_pos, side, knee_hints[side])
    return hip_pos, rotations


def rest_pose(rig):
    rest = {bone.name: bone.matrix_local.copy() for bone in rig.data.bones}
    relative = {bone.name: rest[bone.parent.name].inverted() @ rest[bone.name] if bone.parent else rest[bone.name]
                for bone in rig.data.bones}
    return rest, relative


def posed_matrices(rig, relative, hip_pos, orientations, positions=None):
    output = {}
    overrides = positions if positions is not None else {}
    for bone in rig.pose.bones:
        name = bone.name
        parent = output[bone.parent.name] if bone.parent else Matrix.Identity(4)
        relative_rest = parent @ relative[name]
        origin = hip_pos if name == "hips" else overrides.get(name, relative_rest.translation)
        rotation = orientations.get(name, relative_rest.to_quaternion())
        output[name] = Matrix.LocRotScale(origin, rotation, None)
    return output


def key_pose(rig, matrices, relative, frame, previous, translate=()):
    translated = ("hips", "root", *translate)
    for bone in rig.pose.bones:
        name = bone.name
        parent = matrices[bone.parent.name] if bone.parent else Matrix.Identity(4)
        local = (parent @ relative[name]).inverted() @ matrices[name]
        rotation = local.to_quaternion()
        if name in previous:
            rotation.make_compatible(previous[name])
        previous[name] = rotation.copy()
        bone.rotation_quaternion = rotation
        bone.keyframe_insert("rotation_quaternion", frame=frame, group=name)
        if name in translated:
            bone.location = local.translation
            bone.keyframe_insert("location", frame=frame, group=name)


def build_actions(rig, clips):
    scene = bpy.context.scene
    assert scene.render.fps == 48
    body, = [obj for obj in scene.objects if obj.type == "MESH"]
    assert body.matrix_world == Matrix.Identity(4), body.name
    rest, relative = rest_pose(rig)
    soles = {side: sole_points(body, rest, side) for side in SIDES}
    centers = {side: rest[f"foot_{side}"].translation + contact(soles[side], rest[f"foot_{side}"].to_quaternion())
               for side in SIDES}
    rig.animation_data.action = None
    for name, intervals in [(name, data[2]) for name, data in STRIDES.items()] + [("TurnLeft", 30), ("TurnRight", 30)]:
        label = name + "-loop"
        old = rig.animation_data.nla_tracks.get(label)
        if old is not None:
            original = old.strips[0].action
            rig.animation_data.nla_tracks.remove(old)
            bpy.data.actions.remove(original)
        action = bpy.data.actions.new(label)
        rig.animation_data.action = action
        previous = {}
        for i in range(intervals + 1):
            hip_pos, orientations = pose_frame(rest, soles, centers, clips, name, i / intervals)
            matrices = posed_matrices(rig, relative, hip_pos, orientations)
            key_pose(rig, matrices, relative, i + 1, previous)
        rig.animation_data.action = None
        track = rig.animation_data.nla_tracks.new()
        track.name = label
        track.strips.new(label, 1, action)
        track.mute = True


def bake(project, output, models=MODELS):
    assert bpy.app.background
    project, output = Path(project), Path(output)
    assert not output.is_relative_to(project / "art") and not output.is_relative_to(project / "coop")
    output.mkdir(parents=True, exist_ok=True)
    clips = player_samples(project)
    for name in models:
        bpy.ops.wm.open_mainfile(filepath=str(project / f"art/wild_man/{name}.blend"))
        rig = scene_rig()
        build_actions(rig, clips)
        rig.animation_data.action = bpy.data.actions["Idle-loop"]
        rig.animation_data.action_slot = rig.animation_data.action.slots[0]
        bpy.context.scene.frame_set(1)
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(output / f"{name}.blend"), compress=True)
        rig.animation_data.action = None
        for track in rig.animation_data.nla_tracks:
            track.mute = False
        bpy.ops.object.select_all(action="DESELECT")
        for obj in bpy.context.scene.objects:
            obj.select_set(True)
        bpy.ops.export_scene.gltf(filepath=str(output / f"{name}.glb"), export_format="GLB", use_selection=True,
                                  export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                                  export_cameras=False, export_lights=False, export_texcoords=True,
                                  export_materials="EXPORT", export_anim_slide_to_zero=True)
    return {"outputs": list(models), "playerSamples": {name: len(samples) for name, samples in clips.items()}}
