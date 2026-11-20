extends SceneTree
## Run in a copy of the project with native Compatibility rendering and a frames directory.
const EAGLE := preload("res://props/camp_eagle.glb")
const LIVE := ["GroundIdle", "PerchIdle", "Takeoff", "Flap", "Glide", "BankLeft", "BankRight", "Dive", "LandGround", "LandPerch"]
const DEATH := {"Fall": 0.9, "Collapse": 0.6, "Dead": 0.1}
var stage := Node3D.new()
var camera := Camera3D.new()
var model: Node3D
var mesh: MeshInstance3D
var rig: Skeleton3D
var animation: AnimationPlayer
var errors: Array[String] = []

func _initialize() -> void:
	_verify.call_deferred()

func _verify() -> void:
	_stage()
	model = EAGLE.instantiate()
	stage.add_child(model)
	animation = model.find_children("*", "AnimationPlayer", true, false)[0]
	rig = model.find_children("*", "Skeleton3D", true, false)[0]
	mesh = model.find_children("*", "MeshInstance3D", true, false)[0]
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var marker := model.find_child("PerchContact", true, false) as Node3D
	assert(marker != null and marker.position.is_equal_approx(Vector3(0.0, 0.008, 0.057)))
	var live := {}
	for clip: String in LIVE:
		var live_clip := animation.get_animation(clip)
		assert(live_clip != null)
		live[clip] = {"length": live_clip.length, "tracks": live_clip.get_track_count(), "loop": live_clip.loop_mode}
	var report := {}
	for clip: String in DEATH:
		var action := animation.get_animation(clip)
		assert(action != null and action.loop_mode == Animation.LOOP_NONE)
		assert(absf(action.length - float(DEATH[clip])) < 0.002)
		var samples := []
		var steps := roundi(action.length * 30)
		for i in range(steps + 1):
			await _pose(clip, action.length * i / float(steps))
			var bounds := _deformed_bounds()
			if bounds.position.y < -0.008:
				errors.append("%s frame %d penetrates the ground at %.4f m" % [clip, i, bounds.position.y])
			samples.append({"time": action.length * i / float(steps), "fold": mesh.get_blend_shape_value(0),
				"bottomM": bounds.position.y, "sizeM": [bounds.size.x, bounds.size.y, bounds.size.z]})
		var final: Dictionary = samples.back()
		if absf(final.bottomM - 0.004) > 0.005 or final.fold < 0.99:
			errors.append("%s did not settle folded and grounded: %s" % [clip, final])
		report[clip] = {"tracks": action.get_track_count(), "samples": samples, "finalBones": _bones()}
	for clip: String in ["Fall", "Collapse"]:
		for bone: String in report.Dead.finalBones:
			var last: Vector3 = report[clip].finalBones[bone]
			var rest: Vector3 = report.Dead.finalBones[bone]
			if last.distance_to(rest) > 0.001:
				errors.append(clip + " ends away from Dead: " + bone)
	if report.Fall.samples[0].fold > 0.02 or report.Collapse.samples[0].fold < 0.99:
		errors.append("Airborne and grounded starts should use the appropriate wing shapes")
	for job: Array in [["live-glide", "Glide", 0.50], ["live-ground", "GroundIdle", 0.10],
			["fall-start", "Fall", 0.12], ["fall-middle", "Fall", 0.39], ["fall-end", "Fall", 0.75],
			["collapse-middle", "Collapse", 0.28], ["dead-side", "Dead", 0.05], ["dead-front", "Dead", 0.05]]:
		_camera(Vector3(-2.0, 1.25, -2.0) if job[0] == "dead-front" else Vector3(2.4, 0.95, -1.15))
		await _pose(job[1], job[2])
		root.get_texture().get_image().save_png("res://frames/" + job[0] + ".png")
	var path := FileAccess.open("res://frames/eagle-poses.json", FileAccess.WRITE)
	path.store_string(JSON.stringify({"live": live, "death": report, "bones": rig.get_bone_count(), "errors": errors}, "  "))
	for error: String in errors:
		push_error(error)
	quit(0 if errors.is_empty() else 1)

func _bones() -> Dictionary:
	var points := {}
	for i in rig.get_bone_count():
		points[rig.get_bone_name(i)] = rig.get_bone_global_pose(i).origin
	return points

func _pose(clip: String, at: float) -> void:
	animation.play(clip)
	animation.seek(at, true)
	animation.pause()
	rig.force_update_all_bone_transforms()
	await process_frame
	await RenderingServer.frame_post_draw

func _deformed_bounds() -> AABB:
	var blended := mesh.bake_mesh_from_current_blend_shape_mix()
	assert(blended != null)
	var skin := mesh.skin
	var transforms: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var bone := rig.find_bone(skin.get_bind_name(bind))
		transforms.append(rig.global_transform * rig.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
	var low := Vector3.INF
	var high := -Vector3.INF
	for surface in mesh.mesh.get_surface_count():
		var morphed := blended.surface_get_arrays(surface)
		var weights_source := mesh.mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = morphed[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = weights_source[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = weights_source[Mesh.ARRAY_WEIGHTS]
		var influences := int(joints.size() / positions.size())
		for i in positions.size():
			var point := Vector3.ZERO
			for j in influences:
				var address := i * influences + j
				if weights[address] > 0.0:
					point += (transforms[joints[address]] * positions[i]) * weights[address]
			low = low.min(point)
			high = high.max(point)
	return AABB(low, high - low)

func _stage() -> void:
	root.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#6c7b69")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#f4eddb")
	environment.ambient_light_energy = 0.57
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	for light_data: Array in [[Vector3(-2.6,3.2,-2.1),0.87],[Vector3(3.0,2.5,1.8),0.37]]:
		var light := DirectionalLight3D.new()
		stage.add_child(light)
		light.position = light_data[0]
		light.look_at(Vector3.ZERO)
		light.light_energy = light_data[1]
		light.shadow_enabled = light.position.z < 0
		light.directional_shadow_max_distance = 7.0
		light.shadow_bias = 0.08
		light.shadow_normal_bias = 0.25
	var floor := MeshInstance3D.new()
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2(50, 50)
	floor.mesh = plane
	floor.position.y = -0.006
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#667056")
	floor.material_override = material
	stage.add_child(floor)
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.56
	_camera(Vector3(2.4, 0.95, -1.15))
	camera.make_current()

func _camera(at: Vector3) -> void:
	camera.position = at
	camera.look_at(Vector3(0, 0.33, 0.04))
