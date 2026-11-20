"""Retarget the camp NPC fall and author a braced rise on the equipped player rig."""

from pathlib import Path
import runpy

import bpy
from mathutils import Matrix, Quaternion

DOWN = "Knockout"
UP = "Recover"
FPS = 30


def rig_in_scene():
    rig, = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    assert rig.matrix_world == Matrix.Identity(4), rig.name
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    return rig


def sample(rig, name, phase: float):
    action = bpy.data.actions[name]
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    first, last = action.frame_range
    frame = first + (last - first) * phase
    bpy.context.scene.frame_set(int(frame), subframe=frame % 1.0)
    return {bone.name: bone.matrix.copy() for bone in rig.pose.bones}


def retarget(source, source_start, standing):
    hip_height = standing["hips"].translation.z / source_start["hips"].translation.z
    orientations = {}
    for bone, stand in standing.items():
        if bone in source:
            delta = source[bone].to_quaternion() @ source_start[bone].to_quaternion().inverted()
            orientations[bone] = delta @ stand.to_quaternion()
    shift = (source["hips"].translation - source_start["hips"].translation) * hip_height
    # The planted shoes slow the first part of the collapse before the shoulders
    # come down. Keep the game-space body centred near its rescue marker.
    return standing["hips"].translation + shift, orientations


def eased(value: float) -> float:
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


def blend_pose(first, second, fraction: float, fallback):
    fraction = eased(fraction)
    hip_a, rot_a = first
    hip_b, rot_b = second
    rotations = {
        name: rot_a.get(name, orientation).slerp(rot_b.get(name, orientation), fraction)
        for name, orientation in fallback.items()
    }
    return hip_a.lerp(hip_b, fraction), rotations


def wrapped_pose(matrices, orientations):
    return matrices["hips"].translation, {
        name: matrices[name].to_quaternion() for name in orientations
    }


def lowest_skin(parts):
    world = bpy.context.evaluated_depsgraph_get()
    low = float("inf")
    for obj in parts:
        evaluated = obj.evaluated_get(world)
        mesh = evaluated.to_mesh()
        height = evaluated.matrix_world[2]
        low = min(low, min(
            vertex.co.x * height[0] + vertex.co.y * height[1] + vertex.co.z * height[2] + height[3]
            for vertex in mesh.vertices
        ))
        evaluated.to_mesh_clear()
    return low


def write_take(rig, name, poses, helper, relative, standing_relative, body):
    old = rig.animation_data.nla_tracks.get(name)
    if old is not None:
        previous_take = old.strips[0].action
        rig.animation_data.nla_tracks.remove(old)
        bpy.data.actions.remove(previous_take)
    action = bpy.data.actions.new(name)
    rig.animation_data.action = action
    previous = {}
    heights = []
    for frame, (hip, orientations, contact) in enumerate(poses, start=1):
        matrices = helper["posed_matrices"](rig, standing_relative, hip, orientations)
        helper["key_pose"](rig, matrices, relative, frame, previous)
        rig.animation_data.action_slot = action.slots[0]
        bpy.context.scene.frame_set(frame)
        # Evaluate the real skin before planting the hip track. Head, palms and
        # boots use different support points during the fall and the rise.
        minimum = lowest_skin(body)
        correction = max((.012 - minimum) * contact, .003 - minimum) if contact > 0 else 0.0
        matrices["hips"].translation.z += correction
        if contact > 0:
            # Only the pelvis translation changes. The children's local offsets
            # are already keyed against their parents.
            bone = rig.pose.bones["hips"]
            parent = matrices[bone.parent.name] if bone.parent else Matrix.Identity(4)
            bone.location = ((parent @ relative["hips"]).inverted() @ matrices["hips"]).translation
            bone.keyframe_insert("location", frame=frame, group="hips")
        heights.append(round(minimum + correction, 4))
    rig.animation_data.action = None
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, action)
    track.mute = True
    return heights


def bake(project, output):
    assert bpy.app.background
    project, output = Path(project), Path(output)
    output.mkdir(parents=True, exist_ok=True)
    helper = runpy.run_path(str(project / "scripts/bake-wild-people-locomotion.py"))
    bpy.ops.wm.open_mainfile(filepath=str(project / "art/wild_man/male.blend"))
    npc = rig_in_scene()
    phases = [index / 27 for index in range(28)]
    source = [sample(npc, "Down", phase) for phase in phases]

    bpy.ops.wm.open_mainfile(filepath=str(project / "art/characters/locomotion/player_locomotion.blend"))
    player = rig_in_scene()
    assert bpy.context.scene.render.fps == FPS
    body = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"
            and any(mod.type == "ARMATURE" and mod.object == player for mod in obj.modifiers)]
    assert body
    _, relative = helper["rest_pose"](player)
    standing = sample(player, "Stand", 0)
    standing_relative = {bone.name: standing[bone.parent.name].inverted() @ standing[bone.name]
                         if bone.parent else standing[bone.name] for bone in player.data.bones}
    neutral = {name: matrix.to_quaternion() for name, matrix in standing.items()}
    # Fingers and eyes retain their fitted standing offsets around the shared
    # articulation. Extra NPC grip markers never enter the player rig.
    down = [retarget(matrices, source[0], standing) for matrices in source]
    fall = []
    for (hip, rotation), phase in zip(down, phases):
        hip.y -= .24 * eased(phase / .76)
        fall.append((hip, rotation, eased(phase / .23)))

    seated = wrapped_pose(sample(player, "Sit", 0), neutral)
    braced = wrapped_pose(sample(player, "Land", .34), neutral)
    seated[0].z -= .13
    seated[0].y -= .18
    seated[1]["forearm_L"] = Quaternion((0, 1, 0), -.24) @ seated[1]["forearm_L"]
    seated[1]["upper_arm_L"] = Quaternion((0, 1, 0), -.31) @ seated[1]["upper_arm_L"]
    keys = [(0.0, down[-1]), (.39, seated), (.72, braced), (1.0, wrapped_pose(standing, neutral))]
    recovery = []
    for index in range(37):
        phase = index / 36
        for (start, pose_a), (stop, pose_b) in zip(keys, keys[1:]):
            if phase <= stop:
                hip, rotations = blend_pose(pose_a, pose_b, (phase - start) / (stop - start), neutral)
                recovery.append((hip, rotations, 1.0 - eased((phase - .87) / .13)))
                break
    notes = {}
    for clip, poses in ((DOWN, fall), (UP, recovery)):
        notes[clip] = {
            "frames": len(poses),
            "skinFloor": write_take(player, clip, poses, helper, relative, standing_relative, body)
        }
    sample(player, "Stand", 0)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "player_locomotion.blend"), compress=True)
    player.animation_data.action = None
    for track in player.animation_data.nla_tracks:
        track.mute = track.name not in ("Stand", DOWN, UP)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [player, *body]:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(output / "baked.glb"), export_format="GLB", use_selection=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_force_sampling=True, export_anim_slide_to_zero=True)
    return notes
