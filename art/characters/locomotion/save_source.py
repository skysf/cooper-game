"""Open the generated rig and preserve its editable actions in a Blender source file."""
import pathlib
import sys
import bpy

src, dst = (pathlib.Path(p).resolve() for p in sys.argv[sys.argv.index("--")+1:])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=str(src))
for action in bpy.data.actions:
    action.use_fake_user = True
    print("Editable action", action.name, tuple(action.frame_range))
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(dst),compress=True)
