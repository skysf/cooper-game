"""Export the game jacket and save its fitted, editable scene in a fresh folder."""
from pathlib import Path
import runpy
import sys

import bpy

ROOT = Path(__file__).resolve().parents[2]


def build(output):
    output = Path(output).resolve()
    if any((output / name).exists() for name in ("camp_jacket.blend", "camp_jacket.glb")):
        raise ValueError("Use a fresh candidate output directory")
    output.mkdir(parents=True, exist_ok=True)
    export = runpy.run_path(str(ROOT / "scripts/build-camp-clothing.py"))["export"]
    export("jacket", output)
    bpy.context.scene["fit_source"] = "art/camp_jacket.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "camp_jacket.blend"), compress=True)


if __name__ == "__main__":
    build(sys.argv[sys.argv.index("--") + 1])
