"""Photograph authored plant clusters from three bearings for low-cost continuous ground cover."""
import bpy
import json
import math
from mathutils import Vector
from pathlib import Path
import random

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"coop/east"
CACHE=ROOT/".cache/world-expansion/cover"
CACHE.mkdir(parents=True,exist_ok=True)
recipes=json.loads((OUT/"cover.json").read_text())
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.render.engine="CYCLES"
scene.cycles.samples=18
scene.cycles.use_denoising=False
scene.cycles.transparent_max_bounces=20
scene.view_settings.view_transform="Standard"
scene.render.film_transparent=True
scene.render.resolution_x=512
scene.render.resolution_y=256
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.render.image_settings.color_mode="RGBA"
scene.world=bpy.data.worlds.new("Neutral skylight")
scene.world.use_nodes=True
background=scene.world.node_tree.nodes.get("Background")
background.inputs[0].default_value=(1,1,1,1)
background.inputs[1].default_value=.85
sun=bpy.data.lights.new("Soft side light","SUN")
sun.energy=1.2
sun.angle=.55
lamp=bpy.data.objects.new("Soft side light",sun)
scene.collection.objects.link(lamp)
lamp.rotation_euler=(.48,-.64,-.45)
cam=bpy.data.cameras.new("Cluster portrait")
camera=bpy.data.objects.new("Cluster portrait",cam)
scene.collection.objects.link(camera)
scene.camera=camera
cam.type="ORTHO"
models={}
needed={model for row in recipes.values() for model in row["sources"]}
for pack in ("verdant","namaqua"):
    bpy.ops.import_scene.gltf(filepath=str(ROOT/"art/field_regions"/(pack+".glb")))
    for obj in list(bpy.context.selected_objects):
        if obj.type=="MESH" and obj.name in needed:
            models[obj.name]=obj.data
        obj.hide_render=True
layout={}
for i,(name,row) in enumerate(recipes.items()):
    layout[name]=[]
    r=random.Random(8387+i)
    cluster=[]
    for k in range(row["count"]):
        key=r.choice(row["sources"])
        obj=bpy.data.objects.new(key+" tuft",models[key])
        scene.collection.objects.link(obj)
        phi=r.random()*math.tau
        radius=r.random()**.55*row["span"]*.255
        obj.location=(radius*math.cos(phi),radius*math.sin(phi),0)
        obj.rotation_euler=(r.uniform(-.09,.09),r.uniform(-.09,.09),r.uniform(-math.pi,math.pi))
        scale=r.uniform(.71,1.20)*(1.36 if name=="sedge_bed" else 1)
        obj.scale=(scale,scale,scale)
        cluster.append(obj)
        # Store the same clump in Godot coordinates for the full geometry at walking distance.
        layout[name].append([key,round(obj.location.x,4),round(-obj.location.y,4),round(obj.rotation_euler.z,4),round(scale,4)])
    cam.ortho_scale=row["span"]
    at=Vector((0,0,row["height"]*.32))
    for k in range(3):
        phi=math.pi*k/3
        camera.location=at+Vector((math.cos(phi)*5,math.sin(phi)*5,1.05))
        camera.rotation_euler=(at-camera.location).to_track_quat("-Z","Y").to_euler()
        scene.render.filepath=str(CACHE/f"{name}-{k}.png")
        bpy.ops.render.render(write_still=True)
    for obj in cluster:
        bpy.data.objects.remove(obj,do_unlink=True)

(OUT/"cover_specimens.json").write_text(json.dumps(layout,separators=(",",":")))
