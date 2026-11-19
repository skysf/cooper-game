"""The render gate must reject both a local image regression and a hitch sequence."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw


SCORE = Path(__file__).with_name("coop-render-score.py")


class GateTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.directory = Path(self.scratch.name)
        self.capture = self.directory / "render-benchmark.json"
        self.image = Image.new("RGB", (1280, 720), (67, 102, 84))
        draw = ImageDraw.Draw(self.image)
        draw.rectangle((216, 236, 1080, 360), fill=(151, 168, 141))
        self.image.save(self.directory / "before-lake.png")
        self.image.save(self.directory / "after-lake.png")
        self.report = {"environment": {"timingEligible": True}, "runs": []}
        for label in ("before", "after"):
            self.report["runs"].append({"label": label, "scene": "lake", "screenshot": label + "-lake.png",
                                        "viewport": [1280, 720], "targetM1": True, "hardwareRenderer": True,
                                        "renderer": "ANGLE Metal Renderer: Apple M1", "errors": [],
                                        "frames": {"intervalsMs": [1000 / 60] * 240}})

    def check(self, mode, expected_code, flight=None, scene="lake"):
        self.capture.write_text(json.dumps(self.report))
        command = [sys.executable, str(SCORE), str(self.capture), "--mode", mode, "--scenes", scene]
        if flight:
            path = self.directory / "flight-web.json"
            path.write_text(json.dumps(flight))
            command.extend(["--flight", str(path)])
        run = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(run.returncode, expected_code, run.stdout + run.stderr)
        return json.loads((self.directory / "render-score.json").read_text())

    def test_identical_scene_and_stable_frames_pass(self):
        self.assertEqual(self.check("visual", 0)["conclusion"], "pass")
        result = self.check("hardware", 0)
        self.assertAlmostEqual(result["scenes"]["lake"]["framePacing"]["fps"], 60.0)
        self.assertTrue((self.directory / "diff-lake.png").is_file())

    def test_small_local_corruption_fails_the_visual_gate(self):
        ImageDraw.Draw(self.image).rectangle((456, 464, 516, 520), fill=(245, 24, 215))
        self.image.save(self.directory / "after-lake.png")
        result = self.check("visual", 1)
        self.assertIn("lake/reflection", " ".join(result["issues"]))
        self.assertLess(result["scenes"]["lake"]["regions"]["reflection"]["meanError"], 4)

    def test_underwater_requires_equal_depth_and_ignores_the_swim_prompt(self):
        before, after = self.report["runs"]
        for run in (before, after):
            run.update(scene="underwater", fixedPose={"y": -1.78})
        baseline = self.image.copy()
        ImageDraw.Draw(baseline).rectangle((431, 618, 848, 652), fill=(8, 13, 23))
        baseline.save(self.directory / before["screenshot"])
        ImageDraw.Draw(self.image).rectangle((436, 553, 843, 582), fill=(8, 13, 23))
        self.image.save(self.directory / after["screenshot"])
        self.assertEqual(self.check("visual", 0, scene="underwater")["conclusion"], "pass")
        after["fixedPose"]["y"] = -1.64
        mismatch = self.check("visual", 1, scene="underwater")
        self.assertIn("cameras differ by 0.1400 m", " ".join(mismatch["issues"]))
        after["fixedPose"]["y"] = -1.78
        ImageDraw.Draw(self.image).rectangle((232, 553, 300, 622), fill=(245, 24, 215))
        self.image.save(self.directory / after["screenshot"])
        corruption = self.check("visual", 1, scene="underwater")
        self.assertIn("underwater/near-lakebed-left", " ".join(corruption["issues"]))

    def test_consecutive_slow_frames_fail_even_above_30_fps(self):
        self.report["runs"][1]["frames"]["intervalsMs"][100:103] = [52, 57, 54]
        result = self.check("hardware", 1)
        pacing = result["scenes"]["lake"]["framePacing"]
        self.assertGreater(pacing["fps"], 30)
        self.assertEqual(pacing["consecutiveOver50Ms"], 3)

    def test_low_refresh_cannot_be_used_to_certify_hardware(self):
        self.report["environment"]["timingEligible"] = False
        result = self.check("hardware", 2)
        self.assertEqual(result["conclusion"], "invalid-environment")
        self.assertNotIn("framePacing", result["scenes"]["lake"])

    def test_headless_m1_frames_cannot_certify_hardware(self):
        self.report["headless"] = True
        result = self.check("hardware", 2)
        self.assertEqual(result["conclusion"], "invalid-environment")
        self.assertNotIn("framePacing", result["scenes"]["lake"])

    def test_visible_reverse_turn_fails_even_with_stable_timing(self):
        stable = {"intervalsMs": [1000 / 60] * 240}
        flight = {"ok": True, "environment": {"timingEligible": True},
                  "gpu": {"buffer": [1280, 720], "renderer": "Apple M1"},
                  "phases": {"takeoff": {"submitted": stable},
                             "chase turn": {"submitted": stable, "cameraReverseJumps": [{"radians": 0.11}]},
                             "cockpit turn": {"submitted": stable, "cameraReverseJumps": []}}}
        result = self.check("hardware", 1, flight)
        self.assertIn("reverse camera jump", " ".join(result["issues"]))


if __name__ == "__main__":
    unittest.main()
