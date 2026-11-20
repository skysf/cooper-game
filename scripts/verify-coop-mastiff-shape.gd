extends SceneTree
## Run with the Godot renderer in an isolated project. Put the old and new
## assets at res://before/camp_mastiff.glb and res://after/camp_mastiff.glb.
## Create res://frames/ before running. Captures use the same camera and light.
const CLIPS := ["Idle","Walk","Run","Limp","Attack","Eat","Lie-down","Rest","Rise"]
const FEET := ["Fore.Paw.L","Fore.Paw.R","Hind.Paw.L","Hind.Paw.R"]
var scene := Node3D.new()
var camera := Camera3D.new()
var report: Dictionary = {}

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	root.add_child(scene)
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	camera.size = 1.16
	camera.position = Vector3(-3,0.64,0)
	camera.look_at(Vector3(0,0.47,0))
	var lighting := Environment.new()
	lighting.background_mode = Environment.BG_COLOR
	lighting.background_color = Color("#63756d")
	lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	lighting.ambient_light_color = Color("#e8e7de")
	lighting.ambient_light_energy = 0.63
	var world := WorldEnvironment.new()
	world.environment = lighting
	scene.add_child(world)
	for settings: Array in [[Vector3(-2.3,3.8,-4),0.80],[Vector3(2,2,1.6),0.31]]:
		var light := DirectionalLight3D.new()
		scene.add_child(light)
		light.position = settings[0]
		light.look_at(Vector3.ZERO)
		light.light_energy = settings[1]
		light.shadow_enabled = light.position.z < 0
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	floor.mesh = plane
	floor.position.y = -0.005
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#576951")
	floor.material_override = material
	scene.add_child(floor)
	for name: String in ["before","after"]:
		await bench(name)
	var output := FileAccess.open("res://frames/pose-checks.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	quit()

func _feet(mesh: MeshInstance3D) -> Dictionary:
	var surface := mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
	var joints: PackedInt32Array = surface[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = surface[Mesh.ARRAY_WEIGHTS]
	var influences := int(joints.size() / vertices.size())
	var slots: Dictionary = {}
	for foot: String in FEET:
		slots[foot] = PackedInt32Array()
	assert(influences in [4,8])
	for i in vertices.size():
		for k in influences:
			var address := influences * i + k
			if weights[address] < 0.48:
				continue
			var key := str(mesh.skin.get_bind_name(joints[address]))
			if slots.has(key):
				slots[key].append(i)
	for foot: String in FEET:
		assert(slots[foot].size() > 10)
	return slots

func pose(animator: AnimationPlayer, rig: Skeleton3D, clip: String, time: float) -> void:
	animator.play(clip)
	animator.seek(time, true)
	animator.pause()
	rig.force_update_all_bone_transforms()
	await process_frame
	await RenderingServer.frame_post_draw

func collect(mesh: MeshInstance3D, rig: Skeleton3D, slots: Dictionary) -> Dictionary:
	var baked := mesh.bake_mesh_from_current_skeleton_pose()
	var vertices: PackedVector3Array = baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var data := {"ymin":INF}
	for point: Vector3 in vertices:
		data.ymin = minf(float(data.ymin),(mesh.global_transform * point).y)
	for foot: String in FEET:
		var bottom := INF
		for index: int in slots[foot]:
			bottom = minf(bottom,(mesh.global_transform * vertices[index]).y)
		var pivot := (rig.global_transform * rig.get_bone_global_pose(rig.find_bone(foot))).origin
		data[foot] = {"ymin":bottom, "xyz":[pivot.x,pivot.y,pivot.z]}
	return data

func bench(name: String) -> void:
	var model := (load("res://%s/camp_mastiff.glb" % name) as PackedScene).instantiate() as Node3D
	scene.add_child(model)
	var animator: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
	var rig: Skeleton3D = model.find_children("*","Skeleton3D",true,false)[0]
	var mesh: MeshInstance3D = model.find_children("*","MeshInstance3D",true,false)[0]
	var slots := _feet(mesh)
	var data := {"bones":rig.get_bone_count(),"feet_mesh_vertices":{}, "clips":{}}
	for foot: String in FEET:
		data.feet_mesh_vertices[foot] = slots[foot].size()
	var center := Vector3(0.0,0.47,0.0)
	for clip: String in CLIPS:
		assert(animator.has_animation(clip), "missing clip " + clip)
		var action := animator.get_animation(clip)
		var result := {"seconds":action.length,"mode":action.loop_mode,"samples":[]}
		var intervals := maxi(8,ceili(action.length * 30)) if clip in ["Walk","Run","Limp","Lie-down","Rise"] else 22
		for n in intervals + 1:
			var t := action.length * n / float(intervals)
			await pose(animator,rig,clip,t)
			result.samples.append(collect(mesh,rig,slots))
		data.clips[clip] = result
		var direction := Vector3(-3,.17,0)
		var sample_at := {"Idle":.17, "Walk":.28, "Run":.26, "Limp":.46, "Eat":.53,
				"Lie-down":.72, "Rest":1.28, "Rise":.78, "Attack":.35}[clip] as float
		await capture(name+"-"+clip, animator,rig,clip,sample_at,center,direction)
		if clip == "Idle":
			await capture(name+"-front",animator,rig,clip,.17,center,Vector3(0,.32,-3))
	report[name] = data
	scene.remove_child(model)
	model.queue_free()

func capture(label: String, animator: AnimationPlayer, rig: Skeleton3D, clip: String, t: float, center: Vector3, from: Vector3) -> void:
	camera.position = center + from
	camera.look_at(center)
	await pose(animator,rig,clip,t)
	var picture := root.get_texture().get_image()
	assert(picture != null and not picture.is_empty(), "empty capture " + label)
	picture.save_png("res://frames/%s.png" % label)
