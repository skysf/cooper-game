"""Score paired canvas captures and, on the target Mac, submitted-frame pacing."""

import argparse
import json
import math
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


RESOLUTION = (1280, 720)
EQUIPPED_CHARACTER = (511, 149, 640, 505)
# Coordinates exclude the corner HUD and isolate geometry that must survive a rendering change.
# The two limits are mean and worst 40px tile error on a 0–255 RGB scale.
REGIONS = {
    "forest": [("woods", (230, 125, 1120, 595), 11, 37)],
    "lake": [("shore", (220, 218, 1080, 380), 13, 41),
             ("reflection", (230, 375, 1080, 635), 13, 40)],
    "lamp": [("lantern", (512, 285, 767, 598), 10, 35),
             ("lit-timber", (267, 122, 1070, 550), 12, 41)],
    "dawn": [("horizon", (235, 157, 1080, 477), 13, 40)],
    "storm": [("wet-woods", (235, 170, 1120, 595), 14, 42)],
    "inventory": [("inventory", (337, 154, 1110, 616), 11, 38),
                  ("item-preview", (945, 247, 1130, 449), 10, 35)],
    "equipment": [("equipment", (337, 154, 1110, 616), 11, 38),
                  ("character", EQUIPPED_CHARACTER, 10, 34),
                  ("garment-preview", (892, 217, 1173, 491), 10, 34)],
    # Preserve foreground lakebed on both sides of the centered swim prompt.
    "underwater": [("lakebed", (221, 226, 1080, 540), 13, 40),
                   ("near-lakebed-left", (221, 540, 420, 650), 13, 40),
                   ("near-lakebed-right", (860, 540, 1080, 650), 13, 40)],
}
LUMA = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


def read_image(directory, relative):
    path = directory / Path(relative).name
    with Image.open(path) as image:
        if image.size != RESOLUTION:
            raise ValueError(f"Unexpected image size for {path.name}: {image.size}")
        rgb = image.convert("RGB")
        return np.asarray(rgb, dtype=np.float32), np.asarray(
            rgb.filter(ImageFilter.GaussianBlur(radius=1.6)), dtype=np.float32)


def region(image, bounds):
    x0, y0, x1, y1 = bounds
    return image[y0:y1, x0:x1]


def peak_tile_error(delta):
    return max(float(delta[y:y + 40, x:x + 40].mean())
               for y in range(0, delta.shape[0] - 39, 20)
               for x in range(0, delta.shape[1] - 39, 20))


def luminance_similarity(reference, actual):
    a, b = reference @ LUMA, actual @ LUMA
    am, bm = a.mean(), b.mean()
    covariance = ((a - am) * (b - bm)).mean()
    return float((2 * am * bm + 6.50) * (2 * covariance + 58.52)
                 / ((am ** 2 + bm ** 2 + 6.50) * (a.var() + b.var() + 58.52)))


def heatmap(directory, name, reference, actual):
    delta = np.abs(reference - actual).max(axis=2)
    strength = np.minimum(delta * 4, 255).astype(np.uint8)
    base = (reference @ LUMA * 0.21).astype(np.uint8)
    pixels = np.stack((np.maximum(strength, base), base, base), axis=2)
    file = f"diff-{name}.png"
    Image.fromarray(pixels).save(directory / file)
    return file


def transition_signature(scene, before, after):
    if scene == "lamp":
        bounds = REGIONS[scene][0][1]
        delta = region(after - before, bounds) @ np.array([0.64, 0.29, 0.07])
        return float(np.quantile(np.maximum(delta, 0), 0.92))
    bounds = REGIONS[scene][0][1]
    delta = region(after - before, bounds) @ LUMA
    return float(np.sqrt((delta ** 2).mean()))


def score_visual(directory, scene, reference, actual, issues):
    reference_pixels, reference_blur = read_image(directory, reference["screenshot"])
    actual_pixels, actual_blur = read_image(directory, actual["screenshot"])
    metrics = {"diffImage": heatmap(directory, scene, reference_pixels, actual_pixels), "regions": {}}
    if reference.get("renderer") != actual.get("renderer"):
        issues.append(f"{scene}: reference and candidate rasterizers differ")
    if scene == "underwater":
        try:
            depth_gap = abs(reference["fixedPose"]["y"] - actual["fixedPose"]["y"])
        except (KeyError, TypeError):
            issues.append("underwater: missing fixed camera depth")
        else:
            metrics["cameraDepthDelta"] = depth_gap
            if not math.isfinite(depth_gap) or depth_gap > 0.002:
                issues.append(f"underwater: cameras differ by {depth_gap:.4f} m in depth")
    for name, bounds, average_limit, peak_limit in REGIONS[scene]:
        a, b = region(reference_blur, bounds), region(actual_blur, bounds)
        delta = np.abs(a - b)
        average, peak = float(delta.mean()), peak_tile_error(delta)
        metrics["regions"][name] = {"meanError": average, "peakTileError": peak,
                                    "luminanceSSIM": luminance_similarity(a, b)}
        if average > average_limit or peak > peak_limit:
            issues.append(f"{scene}/{name}: image changed (mean {average:.2f}, strongest tile {peak:.2f})")
        if scene == "lake" and name == "reflection":
            previous_detail = float((a @ LUMA).std())
            actual_detail = float((b @ LUMA).std())
            metrics["regions"][name]["luminanceDeviation"] = {"reference": previous_detail, "actual": actual_detail}
            if previous_detail >= 5 and actual_detail < previous_detail * 0.50:
                issues.append("lake/reflection: the candidate lost the reference reflection contrast")
    if scene in ("lamp", "dawn"):
        baseline_stage, actual_stage = reference.get("transition"), actual.get("transition")
        expected = "repair" if scene == "lamp" else "sunrise"
        if not baseline_stage or not actual_stage or actual_stage.get("type") != expected:
            issues.append(f"{scene}: fixture did not record the {expected} transition")
            return metrics
        _, reference_before = read_image(directory, baseline_stage["beforeScreenshot"])
        _, actual_before = read_image(directory, actual_stage["beforeScreenshot"])
        baseline_delta = transition_signature(scene, reference_before, reference_blur)
        actual_delta = transition_signature(scene, actual_before, actual_blur)
        metrics["transition"] = {"referenceChange": baseline_delta, "actualChange": actual_delta,
                                 "beforeDiffImage": heatmap(directory, scene + "-before", reference_before, actual_before)}
        if baseline_delta < 1.0 or actual_delta < max(1.0, baseline_delta * 0.50):
            issues.append(f"{scene}: visible light transition missing (baseline {baseline_delta:.2f}, actual {actual_delta:.2f})")
    return metrics


def score_frames(run, issues):
    raw = run["frames"]["intervalsMs"]
    if len(raw) < 2 or not all(isinstance(value, (float, int)) and math.isfinite(value) and value > 0 for value in raw):
        raise ValueError("Missing or invalid submitted frame intervals")
    ordered = sorted(raw)
    fps = 1000 * len(raw) / sum(raw)
    p95 = ordered[math.ceil(0.95 * len(raw)) - 1]
    slow = sum(delay > 50 for delay in raw) / len(raw)
    longest_streak = streak = 0
    for delay in raw:
        streak = streak + 1 if delay > 50 else 0
        longest_streak = max(streak, longest_streak)
    if fps < 30 or p95 > 34 or slow > 0.01 or longest_streak > 1 or ordered[-1] > 100:
        issues.append(f"{run['scene']}: {fps:.2f} FPS, P95 {p95:.2f} ms, {slow:.2%} over 50 ms, "
                      f"{longest_streak} consecutive slow frames, worst {ordered[-1]:.2f} ms")
    return {"fps": fps, "p95Ms": p95, "ratioOver50Ms": slow, "consecutiveOver50Ms": longest_streak,
            "maxMs": ordered[-1], "submittedIntervals": len(raw)}


def score_flight(flight, issues, environment):
    if not flight.get("ok") or flight.get("errors"):
        issues.append(f"Flight route failed: {flight.get('error', flight.get('errors'))}")
    gpu = flight.get("gpu", {})
    if (flight.get("headless") or flight.get("tracing") or flight.get("reverseFirstTurn") or
            flight.get("turnDelayMs", 620) != 620 or not flight.get("environment", {}).get("timingEligible") or
            gpu.get("buffer") != list(RESOLUTION) or not re.search(r"Apple M1(?:[,)]|$)", gpu.get("renderer") or "", re.I)):
        environment.append("Flight timing requires a foreground, untraced Apple M1 run at 1280 × 720 with a valid refresh rate")
        return {}
    phases = {}
    for name in ("takeoff", "chase turn", "cockpit turn"):
        try:
            phase = flight["phases"][name]
            frames = phase["submitted"]
            phases[name] = score_frames({"scene": f"flight/{name}", "frames": frames}, issues)
            if name != "takeoff" and ("cameraReverseJumps" not in phase or phase["cameraReverseJumps"]):
                issues.append(f"flight/{name}: reverse camera jump or missing camera samples")
        except (KeyError, ValueError) as error:
            issues.append(f"flight/{name}: missing or invalid WebGL intervals ({error})")
    return phases


def score(directory, report, mode, scenes, require_software, flight=None):
    issues, environment = [], []
    outcome = {"conclusion": "pass", "mode": mode, "issues": issues, "environment": environment, "scenes": {}}
    if report.get("failure"):
        issues.append(f"Capture failed: {report['failure'].get('message', report['failure'])}")
    if mode == "hardware" and (report.get("headless") or report.get("unthrottled") or
                               not report.get("environment", {}).get("timingEligible")):
        environment.append("A foreground, normally throttled browser with a valid blank-tab refresh rate is required")
    runs = {(run["scene"], run["label"]): run for run in report.get("runs", [])}
    for scene in scenes:
        before, after = runs.get((scene, "before")), runs.get((scene, "after"))
        if not before or not after:
            issues.append(f"{scene}: missing baseline or candidate capture")
            continue
        if any(run.get("viewport") != list(RESOLUTION) or run.get("errors") for run in (before, after)):
            issues.append(f"{scene}: invalid canvas size or browser error")
        if scene in ("inventory", "equipment"):
            inventory = after.get("inventory", {})
            bag = inventory.get("bag", {})
            if not inventory.get("open") or bag.get("apple", 0) <= 0 or bag.get("jacket", 0) <= 0:
                issues.append(f"{scene}: the candidate did not open the populated inventory")
            if scene == "equipment" and not inventory.get("equipment"):
                issues.append("equipment: the candidate did not open the equipment tab")
        if require_software and any("swiftshader" not in (run.get("renderer") or "").lower() for run in (before, after)):
            environment.append(f"{scene}: expected the fixed SwiftShader visual reference renderer")
        if mode == "hardware" and any(not run.get("targetM1") or not run.get("hardwareRenderer") or
                                      "apple m1" not in (run.get("renderer") or "").lower() for run in (before, after)):
            environment.append(f"{scene}: the intended Apple M1 hardware GPU was not verified")
        try:
            if scene == "equipment" and before.get("inventory", {}).get("legacyInventory"):
                inventory = after.get("inventory", {})
                pixels, _ = read_image(directory, after["screenshot"])
                detail = float((region(pixels, EQUIPPED_CHARACTER) @ LUMA).std())
                if not inventory.get("equipment") or not inventory.get("open") or detail < 12:
                    issues.append("equipment: candidate interaction or rendered content missing")
                result = {"coverage": "candidate-interaction", "reason": "Reference does not publish equipment controls",
                          "candidateImage": after["screenshot"], "characterLuminanceDeviation": detail}
            else:
                result = score_visual(directory, scene, before, after, issues)
            if mode == "hardware" and not environment:
                result["framePacing"] = score_frames(after, issues)
            outcome["scenes"][scene] = result
        except (KeyError, OSError, ValueError) as error:
            issues.append(f"{scene}: {error}")
    if flight is not None:
        outcome["flight"] = score_flight(flight, issues, environment)
    if environment:
        outcome["conclusion"] = "invalid-environment"
    elif issues:
        outcome["conclusion"] = "fail"
    return outcome


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--mode", choices=("visual", "hardware"), default="visual")
    parser.add_argument("--scenes", default="forest,lake,lamp")
    parser.add_argument("--require-software", action="store_true")
    parser.add_argument("--flight", type=Path, help="Raw flight-web.json from the matching hardware run")
    args = parser.parse_args()
    names = args.scenes.split(",")
    if any(scene not in REGIONS for scene in names):
        parser.error("unknown scene")
    with args.capture.open() as file:
        report = json.load(file)
    if args.flight and args.mode != "hardware":
        parser.error("--flight requires --mode hardware")
    flight = None
    if args.flight:
        try:
            flight = json.loads(args.flight.read_text())
        except (OSError, ValueError) as error:
            flight = {"ok": False, "error": str(error)}
    outcome = score(args.capture.parent, report, args.mode, names, args.require_software, flight)
    (args.capture.parent / "render-score.json").write_text(json.dumps(outcome, indent=2) + "\n")
    print(json.dumps(outcome, indent=2))
    return {"pass": 0, "fail": 1, "invalid-environment": 2}[outcome["conclusion"]]


if __name__ == "__main__":
    raise SystemExit(main())
