extends SceneTree
## Run against a copied coop project. The optional --capture needs its renderer.
const People = preload("res://wild_people.gd")
const PeopleScene = preload("res://wild_people_scene.gd")
const Rules = preload("res://rules.gd")
const Lake = preload("res://lake_layout.gd")
const ACTORS := {"male": [1, "male"], "female": [1, "female"],
	"male_elite": [4, "male"], "female_elite": [4, "female"]}
const CASES := [["walk", 1.35, 0.0, 0.0], ["patrol", 0.85, 0.0, 0.0],
	["run", 2.2, 0.0, 0.0], ["limp_left", 1.8, 78.0, 0.0],
	["limp_right", 1.8, 0.0, 78.0]]
const DT := 1.0 / 60.0
var grid: Dictionary
var lane: Vector2
var results := {}
var errors: Array[String] = []
var camera: Camera3D
var capture := false
var baseline := false

func _initialize() -> void:
	_verify.call_deferred()

func _verify() -> void:
	var args := OS.get_cmdline_user_args()
	baseline = "--baseline" in args
	capture = "--capture" in args
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	lane = _lane(Vector2(22.0, -71.0))
	assert(lane != Vector2.INF, "A clear, nearly level woodland lane is required")
	if capture:
		_light_stage()
	var models: Dictionary = ACTORS if not baseline else {"male": ACTORS.male, "female_elite": ACTORS.female_elite}
	for key: String in models:
		var steps := {}
		for scenario: Array in CASES:
			steps[scenario[0]] = await _drive_test(key, models[key], scenario)
		steps.turn_left = await _turn_test(key, models[key], -1.0)
		steps.turn_right = await _turn_test(key, models[key], 1.0)
		results[key] = steps
	print("NPC_STRIDE ", JSON.stringify({"baseline": baseline, "lane": str(lane), "models": results, "errors": errors}))
	quit(0 if errors.is_empty() else 1)

func _lane(hint: Vector2) -> Vector2:
	# The same route is selected on either version, in the actual collision grid.
	for offset_y in range(0, 25):
		for offset_x in range(-22, 22):
			var at := hint + Vector2(offset_x, -offset_y)
			var height := Lake.walk_height(at)
			var clear := true
			for step in range(57):
				for edge: float in [-0.35, 0.0, 0.35]:
					var point := at + Vector2(edge, -step * 0.25)
					clear = clear and Rules.free_at(point, grid) and absf(Lake.walk_height(point) - height) < 0.011
				if not clear:
					break
			if clear and Rules.free_at(at + Vector2(-1.1, 0.0), grid) and Rules.free_at(at + Vector2(1.1, 0.0), grid):
				return at
	return Vector2.INF

func _drive_test(key: String, model: Array, scenario: Array) -> Dictionary:
	var scene := PeopleScene.new()
	root.add_child(scene)
	var motion := People.new()
	var state := People.initial(120.0)
	var npc := People.make_person(key, model[0], model[1], lane, 120.0)
	npc.legL = scenario[2]
	npc.legR = scenario[3]
	npc.weapon = "spear"
	npc.shield = true
	state.people[key] = npc
	var room := {"data": {"elapsed": 120.0}, "people_routes": {}}
	var eye := Vector3(lane.x, 1.65, lane.y)
	var snapshot := People.snapshot(state, "", 120.0)
	scene.sync(snapshot.people, 120.0, DT, eye)
	var actor: Dictionary = scene.actors[key]
	var rig: Skeleton3D = actor.rig
	var mesh := _skin(actor.model)
	var soles := _soles(mesh)
	var slip := {"L": [], "R": []}
	var lift := {"L": 0.0, "R": 0.0}
	var min_clearance := INF
	var previous := {}
	var contacts := 0
	var speeds: Array[float] = []
	var gear_error := 0.0
	for frame in 244:
		var time := 120.0 + frame * DT
		if frame % 6 == 0:
			var before := People.position(npc)
			room.data.elapsed = time
			motion._drive(room, npc, before + Vector2(0, -4), scenario[1], grid, DT * 6.0)
			speeds.append(People.position(npc).distance_to(before) / (DT * 6.0))
			snapshot = People.snapshot(state, "", time)
		scene.sync(snapshot.people, time, DT, eye)
		if frame < 36 or frame % 3 != 0:
			continue
		rig.force_update_all_bone_transforms()
		await process_frame
		await process_frame
		var points := _contact(mesh.skin, rig, soles, actor.root.position.y)
		for side: String in points:
			var contact: Dictionary = points[side]
			min_clearance = minf(min_clearance, contact.height)
			lift[side] = maxf(lift[side], contact.height)
			if contact.height < 0.018:
				contacts += 1
				if previous.has(side) and previous[side].height < 0.018:
					var movement: Vector2 = contact.patch - previous[side].patch
					slip[side].append(movement.length() / (DT * 3.0))
		previous = points
		for item: Array in [[actor.right, "grip_R"], [actor.left, "grip_L"]]:
			var attachment: Node3D = item[0]
			var grip := rig.to_global(rig.get_bone_global_pose(rig.find_bone(item[1])).origin)
			gear_error = maxf(gear_error, attachment.global_position.distance_to(grip))
		if capture and frame in [45, 63, 81, 99] and key in ["male", "female_elite"] and scenario[0] != "patrol":
			await _picture(key + "-" + scenario[0] + "-" + str(frame), actor, false)
	var left := _summary(slip.L)
	var right := _summary(slip.R)
	var report := {"clip": npc.clip, "distance": People.position(npc).distance_to(lane),
		"meanServerMps": _summary(speeds).mean, "left": left, "right": right,
		"contacts": contacts, "footLowestM": min_clearance, "liftM": lift, "gripErrorM": gear_error}
	if not baseline:
		var limit := 0.16 if scenario[0] == "run" else 0.12
		if maxf(left.mean, right.mean) > limit or contacts < 28 or min_clearance < -0.018 or gear_error > 0.002:
			errors.append("%s/%s foot or grip validation: %s" % [key, scenario[0], report])
		if scenario[0] == "limp_left" and not (npc.clip == "LimpLeft" and lift.L < lift.R * 0.75):
			errors.append(key + " left limp does not favor the injured foot")
		if scenario[0] == "limp_right" and not (npc.clip == "Limp" and lift.R < lift.L * 0.75):
			errors.append(key + " right limp does not favor the injured foot")
	scene.queue_free()
	await process_frame
	return report

func _turn_test(key: String, model: Array, side: float) -> Dictionary:
	var scene := PeopleScene.new()
	root.add_child(scene)
	var motion := People.new()
	var state := People.initial(160.0)
	var npc := People.make_person(key, model[0], model[1], lane, 160.0)
	npc.weapon = "spear"
	npc.shield = true
	state.people[key] = npc
	var room := {"data": {"elapsed": 160.0}, "people_routes": {}}
	var goal := lane + Vector2(side * 1.1, 0.0)
	var eye := Vector3(lane.x, 1.65, lane.y)
	var snapshot := People.snapshot(state, "", 160.0)
	scene.sync(snapshot.people, 160.0, DT, eye)
	var actor: Dictionary = scene.actors[key]
	var rig: Skeleton3D = actor.rig
	var max_yaw_step := 0.0
	var max_turn_drift := 0.0
	var turn_yaw := 0.0
	var clips := {}
	var foot_rise := 0.0
	var min_bottom := INF
	var frames := 0
	var mesh := _skin(actor.model)
	var soles := _soles(mesh)
	for frame in 112:
		var time := 160.0 + frame * DT
		if frame % 6 == 0:
			var prev_yaw: float = npc.yaw
			var before := People.position(npc)
			room.data.elapsed = time
			motion._drive(room, npc, goal, 1.35, grid, DT * 6.0)
			var step_yaw := absf(angle_difference(prev_yaw, npc.yaw))
			max_yaw_step = maxf(max_yaw_step, step_yaw)
			if str(npc.clip).begins_with("Turn"):
				turn_yaw += step_yaw
				max_turn_drift = maxf(max_turn_drift, before.distance_to(People.position(npc)))
			snapshot = People.snapshot(state, "", time)
		scene.sync(snapshot.people, time, DT, eye)
		clips[npc.clip] = int(clips.get(npc.clip, 0)) + 1
		if str(npc.clip).begins_with("Turn"):
			rig.force_update_all_bone_transforms()
			await process_frame
			var points := _contact(mesh.skin, rig, soles, actor.root.position.y)
			foot_rise = maxf(foot_rise, maxf(points.L.height, points.R.height))
			min_bottom = minf(min_bottom, minf(points.L.height, points.R.height))
			frames += 1
		if capture and frame in [10, 24, 38] and key in ["male", "female_elite"]:
			await _picture(key + ("-left-" if side < 0.0 else "-right-") + str(frame), actor, true)
	var report := {"clips": clips, "maxTickRadians": max_yaw_step, "turnRadians": turn_yaw,
		"turnDriftM": max_turn_drift, "footRiseM": foot_rise, "footLowestM": min_bottom if frames > 0 else null,
		"distanceRemainingM": People.position(npc).distance_to(goal)}
	if not baseline and (not clips.has("TurnLeft" if side < 0.0 else "TurnRight") or max_yaw_step > 0.36
			or turn_yaw < 1.35 or max_turn_drift > 0.001 or foot_rise < 0.035 or min_bottom < -0.02
			or People.position(npc).distance_to(goal) > 0.14):
		errors.append("%s turn %s: %s" % [key, side, report])
	scene.queue_free()
	await process_frame
	return report

func _skin(model: Node3D) -> MeshInstance3D:
	for item: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if item.skin != null:
			return item
	assert(false, "No skinned mesh")
	return null

func _soles(mesh: MeshInstance3D) -> Dictionary:
	var fields := {"L": [], "R": []}
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var influences := int(joints.size() / positions.size())
		for i in positions.size():
			if positions[i].y > 0.074:
				continue
			for j in influences:
				var k := i * influences + j
				if weights[k] < 0.6:
					continue
				var joint := str(mesh.skin.get_bind_name(joints[k]))
				if joint.begins_with("foot_") or joint.begins_with("toes_"):
					var skin_weights := []
					for blend in influences:
						var entry := i * influences + blend
						if weights[entry] > 0.0:
							skin_weights.append([joints[entry], weights[entry]])
					fields[joint.right(1)].append([positions[i], skin_weights])
	assert(fields.L.size() > 20 and fields.R.size() > 20, "Find real skinned sole vertices")
	return fields

func _contact(skin: Skin, rig: Skeleton3D, soles: Dictionary, floor_y: float) -> Dictionary:
	var matrices: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var bone := rig.find_bone(skin.get_bind_name(bind))
		matrices.append(rig.global_transform * rig.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
	var data := {}
	for side: String in soles:
		var points := PackedVector3Array()
		var bottom := INF
		for vertex: Array in soles[side]:
			var local: Vector3 = vertex[0]
			var point := Vector3.ZERO
			for influence: Array in vertex[1]:
				point += (matrices[influence[0]] * local) * float(influence[1])
			points.append(point)
			bottom = minf(bottom, point.y)
		var patch := Vector2.ZERO
		var total := 0.0
		for point: Vector3 in points:
			var weight := exp(-pow((point.y - bottom) / 0.017, 2.0))
			patch += Vector2(point.x, point.z) * weight
			total += weight
		data[side] = {"height": bottom - floor_y, "patch": patch / total}
	return data

func _summary(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {"samples": 0, "mean": 0.0, "max": 0.0}
	var sum := 0.0
	for sample: float in samples:
		sum += sample
	return {"samples": samples.size(), "mean": sum / samples.size(), "max": samples.max()}

func _light_stage() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#56695d")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("#e8e6d8")
	world.environment.ambient_light_energy = 0.66
	stage.add_child(world)
	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-41, -31, 0)
	lamp.light_energy = 0.90
	lamp.shadow_enabled = true
	stage.add_child(lamp)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4
	stage.add_child(camera)
	camera.make_current()
	var floor := MeshInstance3D.new()
	floor.mesh = PlaneMesh.new()
	floor.mesh.size = Vector2(80, 80)
	floor.position = Vector3(lane.x, Lake.walk_height(lane) - 0.009, lane.y)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#535d40")
	floor.material_override = material
	stage.add_child(floor)

func _picture(name: String, actor: Dictionary, turn: bool) -> void:
	var center: Vector3 = actor.root.position + Vector3.UP * 0.91
	camera.position = center + (Vector3(2.8, 0.5, -2.9) if turn else Vector3(3.5, 0.22, -0.65))
	camera.look_at(center)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://frames/" + name + ".png")
