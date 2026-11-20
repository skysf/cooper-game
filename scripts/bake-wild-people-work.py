"""Bake companion gathering on the existing NPC rig, using its standing pose and limb solver."""

from math import pi, radians
from pathlib import Path
import runpy

import bpy
from mathutils import Quaternion, Vector

WORK = {
    "DrawWater": (72, 0.558, (55, 66, 79, 82, 38, 29), (
        (0.00, 0.00, 0.00, 0.00, 0.00),
        (0.18, 0.48, 0.22, 0.00, 0.88),
        (0.39, 1.00, 1.00, 0.00, 1.00),
        (0.51, 1.00, 1.00, 0.12, 1.00),
        (0.70, 0.84, 1.00, 1.00, 1.00),
        (0.88, 0.44, 0.58, 0.56, 0.85),
        (1.00, 0.00, 0.00, 0.00, 0.00),
    )),
    "GatherFruit": (60, 0.16, (7, 19, 26, 30, 23, 16), (
        (0.00, 0.00, 0.00, 0.00, 0.00),
        (0.18, 0.33, 0.10, 0.00, 0.82),
        (0.44, 1.00, 1.00, 0.00, 1.00),
        (0.56, 0.94, 1.00, 0.18, 1.00),
        (0.76, 0.65, 0.76, 1.00, 1.00),
        (0.89, 0.31, 0.38, 0.75, 0.73),
        (1.00, 0.00, 0.00, 0.00, 0.00),
    )),
}
BODY = ("hips", "spine", "chest", "upper_chest", "neck", "head")
RIGHT = Vector((1, 0, 0))
FORWARD = Vector((0, 1, 0))
UP = Vector((0, 0, 1))


def phase_values(keys, phase):
    for a, b in zip(keys, keys[1:]):
        if phase <= b[0]:
            t = (phase - a[0]) / (b[0] - a[0])
            w = t * t * (3.0 - 2.0 * t)
            return tuple(x + w * (y - x) for x, y in zip(a[1:], b[1:]))
    return keys[-1][1:]


def idle_pose(rig):
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.matrix_basis.identity()
    action = bpy.data.actions["Idle-loop"]
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(1)
    pose = {bone.name: bone.matrix.copy() for bone in rig.pose.bones}
    rig.animation_data.action = None
    return pose


def pose(rig, stride, rest, relative, idle, clip, phase):
    _, drop, torso_angles, keys = WORK[clip]
    lower, reaching, bring_back, stow = phase_values(keys, phase)
    if lower == 0.0:
        return idle
    active_draw = clip == "DrawWater"
    hip = idle["hips"].translation + Vector((0.007, -0.105 if active_draw else 0.035, -drop)) * lower
    rotations = {name: matrix.to_quaternion() for name, matrix in idle.items()}
    for name, degrees in zip(BODY, torso_angles):
        tilt = Quaternion(RIGHT, radians(-lower * degrees + (10 * bring_back if name == "head" else 0)))
        rotations[name] = tilt @ rotations[name]
    for side, sign in (("L", -1), ("R", 1)):
        foot = idle[f"foot_{side}"].translation
        thigh = idle[f"thigh_{side}"].translation
        original_knee = idle[f"shin_{side}"].translation - thigh
        leg_axis = (foot - thigh).normalized()
        hint = (original_knee - leg_axis * leg_axis.dot(original_knee)).normalized()
        stride["knee_and_ankle"](rest, foot, rotations, hip, side, hint.lerp(Vector((sign * 0.27, 1.0, 0.16)), lower))
    positions = {"root": idle["root"].translation}
    skeleton = stride["posed_matrices"](rig, relative, hip, rotations, positions)
    for side, sign in (("L", -1), ("R", 1)):
        upper, elbow, hand = (f"{bone}_{side}" for bone in ("upper_arm", "forearm", "hand"))
        if side == "L":
            goal = Vector((-0.175, 0.51 if active_draw else 0.47, 0.026 if active_draw else 1.03))
            toward = (skeleton["head"].translation + Vector((-0.064, 0.17, 0.01)) if active_draw else
                      skeleton["hips"].translation + Vector((-0.10, 0.24, 0.23)))
            target = idle[hand].translation.lerp(goal.lerp(toward, bring_back), reaching)
            pitch = (-48 if active_draw else -26) * reaching + 62 * bring_back
        else:
            goal = Vector((0.245, 0.29, 0.43 if active_draw else 0.87))
            target = idle[hand].translation.lerp(goal, lower * 0.89)
            pitch = -14 * lower
        if lower > 0.0:
            stride["solve_limb"](rest, rotations, skeleton[upper].translation, target, (upper, elbow, hand),
                                 Vector((sign * 0.70, -0.48, -0.22)))
            rotations[hand] = Quaternion(RIGHT, radians(pitch)) @ rotations[hand]
    skeleton = stride["posed_matrices"](rig, relative, hip, rotations, positions)
    for side, offset in (("R", Vector((0.15, -0.24, 0.11))), ("L", Vector((-0.02, -0.18, 0.11)))):
        grip = f"grip_{side}"
        on_back = skeleton["chest"].translation + offset
        positions[grip] = skeleton[grip].translation.lerp(on_back, stow)
        upright = idle[grip].to_quaternion()
        if side == "R":
            desired_axis = Vector((0.83, -0.32 if active_draw else -0.04, 0.40 if active_draw else 0.70))
            orient = (upright @ FORWARD).rotation_difference(desired_axis) @ upright
        else:
            orient = Quaternion(UP, pi) @ upright
        rotations[grip] = skeleton[grip].to_quaternion().slerp(orient, stow)
    return stride["posed_matrices"](rig, relative, hip, rotations, positions)


def build_actions(rig, stride):
    scene = bpy.context.scene
    assert scene.render.fps == 48
    assert all(track.mute for track in rig.animation_data.nla_tracks)
    idle = idle_pose(rig)
    rest, relative = stride["rest_pose"](rig)
    for name, (frames, _, _, _) in WORK.items():
        old = rig.animation_data.nla_tracks.get(name)
        if old is not None:
            action = old.strips[0].action
            rig.animation_data.nla_tracks.remove(old)
            bpy.data.actions.remove(action)
        action = bpy.data.actions.new(name)
        rig.animation_data.action = action
        previous = {}
        for i in range(frames + 1):
            matrices = pose(rig, stride, rest, relative, idle, name, i / frames)
            stride["key_pose"](rig, matrices, relative, i+1, previous, ("grip_R", "grip_L"))
        rig.animation_data.action = None
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 1, action)
        track.mute = True


def bake(project, output, models):
    assert bpy.app.background
    project, output = Path(project), Path(output)
    assert not output.is_relative_to(project / "art") and not output.is_relative_to(project / "coop")
    output.mkdir(parents=True, exist_ok=True)
    stride = runpy.run_path(str(project / "scripts/bake-wild-people-locomotion.py"))
    for name in models:
        bpy.ops.wm.open_mainfile(filepath=str(project / f"art/wild_man/{name}.blend"))
        rig = stride["scene_rig"]()
        build_actions(rig, stride)
        rig.animation_data.action = bpy.data.actions["Idle-loop"]
        rig.animation_data.action_slot = rig.animation_data.action.slots[0]
        bpy.context.scene.frame_set(1)
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(output / f"{name}.blend"), compress=True)
        rig.animation_data.action = None
        for track in rig.animation_data.nla_tracks:
            track.mute = False
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.export_scene.gltf(filepath=str(output / f"{name}.glb"), export_format="GLB", use_selection=True,
                                  export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                                  export_cameras=False, export_lights=False, export_texcoords=True,
                                  export_materials="EXPORT", export_anim_slide_to_zero=True)
    return {"outputs": list(models), "durationSeconds": {name: values[0] / 48 for name, values in WORK.items()}}
