"""Add falling, collapse and resting poses to the editable camp eagle.

Run in Blender's background MCP with the original camp_eagle.blend open.
Call bake(output_dir). The source on disk is read only.
"""

from math import radians
from pathlib import Path

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

FALL = (
    (0.00, 0, 0, 0, 0.00, 0.00, 0, 0),
    (0.15, -15, -9, -6, 0.12, 0.05, -13, 18),
    (0.38, -56, 27, 8, 0.47, 0.40, 27, -18),
    (0.61, -39, 77, 13, 0.72, 0.72, 9, -11),
    (0.82, -26, 100, 4, 0.95, 0.94, 0, 0),
    (1.00, -21, 91, 0, 1.00, 1.00, 0, 0),
)
COLLAPSE = (
    (0.00, 0, 0, 0, 1.00, 0.00, 0, 0),
    (0.22, -19, 19, -5, 0.87, 0.29, -5, 13),
    (0.51, -27, 67, -6, 0.90, 0.70, 4, -5),
    (0.78, -24, 100, 2, 0.98, 0.96, 0, 0),
    (1.00, -21, 91, 0, 1.00, 1.00, 0, 0),
)
REST_DELTA = {  # Model-space angles before the root rolls onto its side.
    "Chest": (-5, 1, 0), "Neck": (-36, 9, -19), "Head": (-16, 4, -17),
    "Tail": (11, -8, 29),
    "Wing.Shoulder.L": (2, 5, -2), "Wing.Elbow.L": (0, 4, 0),
    "Wing.Shoulder.R": (-3, -7, 0),
    "Thigh.L": (-11, 5, 7), "Shin.L": (19, 0, 2), "Foot.L": (-13, 6, 11),
    "Thigh.R": (8, -8, 4), "Shin.R": (-13, 0, 0), "Foot.R": (11, -4, -8),
}


def rotate(bone, base, axis_angles):
    rest = bone.bone.matrix_local.to_quaternion()
    delta = Euler(tuple(radians(angle) for angle in axis_angles), "XYZ").to_quaternion()
    return (rest.inverted() @ delta @ rest @ base).normalized()


def use_action(data, action):
    data.action = action
    if action is not None:
        data.action_slot = action.slots[0]


def current_pose(rig):
    return {bone.name: (bone.location.copy(), bone.rotation_quaternion.copy()) for bone in rig.pose.bones}


def source_pose(rig, keys, clip, frame):
    use_action(rig.animation_data, bpy.data.actions[clip + ".Skeleton"])
    use_action(keys.animation_data, bpy.data.actions[clip + ".WingFold"])
    bpy.context.scene.frame_set(frame)
    pose = current_pose(rig)
    use_action(rig.animation_data, None)
    use_action(keys.animation_data, None)
    return pose


def rest_pose(rig, folded, glide):
    pose = {}
    for bone in rig.pose.bones:
        name = bone.name
        location, rotation = folded[name]
        if name.startswith(("Thigh.", "Shin.", "Foot.", "Toe.", "Claw.")):
            amount = 0.58 if name.endswith(".L") else 0.78
            rotation = rotation.slerp(glide[name][1], amount)
        elif name == "Pelvis":
            location = location.lerp(glide[name][0], 0.40)
            rotation = rotation.slerp(glide[name][1], 0.42)
        if name.startswith(("Toe.", "Claw.")):
            rotation = rotate(bone, rotation, (-11 if name.startswith("Toe.") else 7, 0, 0))
        if name in REST_DELTA:
            rotation = rotate(bone, rotation, REST_DELTA[name])
        pose[name] = (location, rotation)
    return pose


def curve(table, time):
    for first, second in zip(table, table[1:]):
        if time <= second[0]:
            t = (time - first[0]) / (second[0] - first[0])
            weight = t * t * (3.0 - 2.0 * t)
            return tuple(a + (b - a) * weight for a, b in zip(first[1:], second[1:]))
    return table[-1][1:]


def sample_pose(rig, shape, start, finish, curve_values):
    pitch, roll, yaw, fold, weight, left, right = curve_values
    for bone in rig.pose.bones:
        one, two = start[bone.name], finish[bone.name]
        bone.location = one[0].lerp(two[0], weight)
        bone.rotation_quaternion = one[1].slerp(two[1], weight)
    root = rig.pose.bones["Root"]
    root_rest = root.bone.matrix_local.to_quaternion()
    turn = (Quaternion((0, 0, 1), radians(yaw)) @ Quaternion((1, 0, 0), radians(pitch)) @
            Quaternion((0, 1, 0), radians(roll)))
    root.rotation_quaternion = root_rest.inverted() @ turn @ root_rest @ root.rotation_quaternion
    # Roll around the torso and keep the settled body near the interaction origin.
    center = Vector((0.0, -0.046, 0.352))
    shift = center - turn @ center
    root.location += root_rest.inverted() @ Vector((shift.x + 0.065 * weight, shift.y, 0.0))
    for side, flutter in (("L", left), ("R", right)):
        for joint, strength in (("Shoulder", 1.0), ("Elbow", 0.57), ("Wrist", 0.39)):
            bone = rig.pose.bones[f"Wing.{joint}.{side}"]
            bone.rotation_quaternion = rotate(bone, bone.rotation_quaternion, (0, flutter * strength, 0))
    shape.value = fold


def bounds(mesh):
    bpy.context.view_layer.update()
    deformed = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return [min(v.co[axis] for v in deformed.data.vertices) for axis in range(3)], [max(v.co[axis] for v in deformed.data.vertices) for axis in range(3)]


def bake_action(rig, shape, mesh, start, finish, label, frames, table):
    rig_action = bpy.data.actions.new(label + ".Skeleton")
    shape_action = bpy.data.actions.new(label + ".WingFold")
    rig.animation_data.action = rig_action
    shape.id_data.animation_data.action = shape_action
    root = rig.pose.bones["Root"]
    local_up = root.bone.matrix_local.to_quaternion().inverted() @ Vector((0, 0, 1))
    samples = []
    for i in range(frames + 1):
        phase = i / frames
        if label == "Dead":
            phase = 1.0
        sample_pose(rig, shape, start, finish, curve(table, phase))
        low, _ = bounds(mesh)
        # Keep a fall at the flight reference height before the body reaches the ground.
        bottom = 0.004 + (0.145 * (1.0 - phase)**1.8 if label == "Fall" else 0.0)
        root.location += local_up * (bottom - low[2])
        for bone in rig.pose.bones:
            bone.keyframe_insert(data_path="rotation_quaternion", frame=i + 1, group=bone.name)
            bone.keyframe_insert(data_path="location", frame=i + 1, group=bone.name)
        shape.keyframe_insert(data_path="value", frame=i + 1)
        low, high = bounds(mesh)
        samples.append({"time": i / 30, "fold": shape.value, "min": low, "max": high})
    use_action(rig.animation_data, None)
    use_action(shape.id_data.animation_data, None)
    return rig_action, shape_action, samples


def add_track(animation, name, action, frame):
    track = animation.nla_tracks.new()
    track.name = name
    track.strips.new(name, frame, action)


def bake(output):
    assert bpy.app.background
    assert bpy.context.scene.render.fps == 30
    output = Path(output).resolve()
    assert Path(bpy.data.filepath).resolve().parent != output
    output.mkdir(parents=True, exist_ok=True)
    rig = bpy.data.objects["Eagle Rig"]
    mesh = bpy.data.objects["Camp Eagle"]
    assert rig.matrix_world == mesh.matrix_world == Matrix.Identity(4)
    keys = mesh.data.shape_keys
    shape = keys.key_blocks["Folded wings and tail"]
    for data in (rig.animation_data, keys.animation_data):
        for track in data.nla_tracks:
            track.mute = True
    glide = source_pose(rig, keys, "Glide-loop", 16)
    ground = source_pose(rig, keys, "GroundIdle-loop", 4)
    dead = rest_pose(rig, ground, glide)
    result = {}
    built = []
    for label, intervals, start, sequence in (("Fall", 27, glide, FALL), ("Collapse", 18, ground, COLLAPSE),
                                              ("Dead", 3, ground, COLLAPSE)):
        skeleton, morph, record = bake_action(rig, shape, mesh, start, dead, label, intervals, sequence)
        result[label] = record
        built.append((label, skeleton, morph))
    next_frame = 515
    for label, skeleton, morph in built:
        add_track(rig.animation_data, label, skeleton, next_frame)
        add_track(keys.animation_data, label, morph, next_frame)
        next_frame += round(skeleton.frame_range[1]) + 10
    for data in (rig.animation_data, keys.animation_data):
        for track in data.nla_tracks:
            track.mute = False
    bpy.context.scene.frame_end = next_frame - 11
    bpy.context.scene.frame_set(3)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "camp_eagle.blend"), compress=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(output / "camp_eagle.glb"), export_format="GLB", use_selection=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_cameras=False, export_lights=False, export_materials="EXPORT", export_anim_slide_to_zero=True)
    return result
