"""Compare physical sole contact in the current and exterior-only gait solver.

Run with Blender background mode. The only output is the optional JSON report.
Neither the source actions nor the models are re-exported.
"""

from math import exp, pi
from pathlib import Path
from statistics import mean
import json
import runpy

import bpy
from mathutils import Quaternion, Vector


ROOT = Path(__file__).resolve().parents[2]
OUTSOLE_MATERIAL = {
    "male": "Turnaround • male",
    "female": "Burnished fiber",
    "male_elite": "Horn ridges",
    "female_elite": "Horn ridges",
}
SIDES = ("L", "R")
SUBDIVISIONS = 240


def exterior_points(body, rest, model, side):
    material, = (i for i, mat in enumerate(body.data.materials)
                 if mat.name == OUTSOLE_MATERIAL[model])
    vertex_indices = {index for face in body.data.polygons if face.material_index == material
                      for index in face.vertices}
    bone = f"foot_{side}"
    group = body.vertex_groups[bone].index
    from_mesh = rest[bone].inverted()
    points = {}
    for index in sorted(vertex_indices):
        vertex = body.data.vertices[index]
        if vertex.co.z > 0.074 or not any(g.group == group and g.weight > 0.6 for g in vertex.groups):
            continue
        assert len(vertex.groups) == 1 and abs(vertex.groups[0].weight - 1.0) < 1e-5
        key = tuple(round(value, 6) for value in vertex.co)
        points.setdefault(key, from_mesh @ vertex.co)
    assert len(points) > 20, (model, side, len(points))
    return list(points.values())


def world_basis(name, phase, length):
    if name in ("TurnLeft", "TurnRight"):
        direction = 1 if name == "TurnLeft" else -1
        return Quaternion((0, 0, 1), direction * pi * phase / 2), Vector((0, 0, 0))
    return Quaternion(), Vector((0, length * phase, 0))


def footprint(values):
    level = min(v.z for v in values)
    weights = [exp(-((v.z - level) / 0.017)**2) for v in values]
    patch = sum((v.xy * weight for v, weight in zip(values, weights)), Vector((0, 0))) / sum(weights)
    return level, patch


def speed_stats(samples):
    values = sorted(samples)
    assert values
    return {"samples": len(values), "mean": mean(values), "p95": values[int(len(values) * 0.95)],
            "max": values[-1]}


def measure(gait, rig, rest, relative, clips, name, soles, outside):
    _, length, frames, duties, _ = gait["STRIDES"].get(name, ("Walk", 0, 30, (0.60, 0.60), None))
    duration = frames / 48.0
    center = {side: rest[f"foot_{side}"].translation +
              gait["contact"](soles[side], rest[f"foot_{side}"].to_quaternion()) for side in SIDES}
    states = {side: [] for side in SIDES}
    hips = []
    for index in range(SUBDIVISIONS + 1):
        phase = index / SUBDIVISIONS
        hip, rotations = gait["pose_frame"](rest, soles, center, clips, name, phase)
        hips.append(hip)
        posed = gait["posed_matrices"](rig, relative, hip, rotations)
        yaw, travel = world_basis(name, phase, length)
        for i, side in enumerate(SIDES):
            matrices = posed[f"foot_{side}"]
            points = [yaw @ (matrices @ point) + travel for point in outside[side]]
            level, patch = footprint(points)
            states[side].append(((phase + 0.5 * i) % 1, level, patch, points))

    output = {}
    for i, side in enumerate(SIDES):
        patch_speeds, marker_speeds, interior = [], [], []
        for a, b in zip(states[side], states[side][1:]):
            if 0.02 <= a[0] < b[0] <= duties[i] - 0.02:
                time = duration / SUBDIVISIONS
                patch_speeds.append((a[2] - b[2]).length / time)
                interior.append(b[1])
                # Compare the same material points that contact the plane in both poses.
                for pa, pb in zip(a[3], b[3]):
                    if max(pa.z - a[1], pb.z - b[1]) <= 0.005:
                        marker_speeds.append((pa.xy - pb.xy).length / time)
        levels = [sample[1] for sample in states[side]]
        output[side] = {"stancePatchMps": speed_stats(patch_speeds), "soleMaterialMps": speed_stats(marker_speeds),
                        "stanceFloorM": [min(interior), max(interior)], "cycleFloorM": [min(levels), max(levels)]}
    return output, hips


def probe(destination):
    gait = runpy.run_path(str(ROOT / "scripts/bake-wild-people-locomotion.py"))
    clips = gait["player_samples"](ROOT)
    output = {"subdivisions": SUBDIVISIONS, "sourceFramesPerSecond": 48, "models": {}}
    for model in gait["MODELS"]:
        bpy.ops.wm.open_mainfile(filepath=str(ROOT / "art" / "wild_man" / f"{model}.blend"))
        rig = gait["scene_rig"]()
        body, = (obj for obj in bpy.context.scene.objects if obj.type == "MESH")
        rest, relative = gait["rest_pose"](rig)
        outside = {side: exterior_points(body, rest, model, side) for side in SIDES}
        legacy = {side: gait["sole_points"](body, rest, side) for side in SIDES}
        model_report = {"soleVertices": {side: [len(legacy[side]), len(outside[side])] for side in SIDES}, "clips": {}}
        for name in (*gait["STRIDES"], "TurnLeft", "TurnRight"):
            current, current_hips = measure(gait, rig, rest, relative, clips, name, legacy, outside)
            revised, revised_hips = measure(gait, rig, rest, relative, clips, name, outside, outside)
            model_report["clips"][name] = {"current": current, "exterior": revised,
                                          "maxHipChangeM": max((a - b).length for a, b in zip(current_hips, revised_hips))}
        output["models"][model] = model_report
    destination.write_text(json.dumps(output, indent=2) + "\n")
    return {"report": str(destination), "models": list(output["models"]), "clipCount": 6}


if __name__ == "__main__":
    import sys

    print(probe(Path(sys.argv[sys.argv.index("--") + 1])))
