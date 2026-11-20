extends SceneTree
## Run against an imported coop project. --capture saves native frames in its frames directory.
const People = preload("res://wild_people.gd")
const PeopleScene = preload("res://wild_people_scene.gd")
const Rules = preload("res://rules.gd")
const Lake = preload("res://lake_layout.gd")
const DT := 1.0 / 60.0
var grid: Dictionary
var motion := People.new()
var camera: Camera3D
var stage: Node3D
var floor_mesh: MeshInstance3D
var creek_floor: MeshInstance3D
var creek_surface: MeshInstance3D
var render := false
var errors: Array[String] = []
var results := {}

func _initialize() -> void:
	_verify.call_deferred()

func _verify() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	render = "--capture" in OS.get_cmdline_user_args()
	if render:
		_build_capture_stage()
	for setup: Array in [["male",1,"male",false], ["female_elite",4,"female",true]]:
		for clip: String in ["DrawWater", "GatherFruit"]:
			results[setup[0]+"/"+clip] = await _case(setup, clip)
	_exhausted_cases()
	print("COOP_NPC_WORK ", JSON.stringify({"cases":results,"errors":errors}))
	quit(0 if errors.is_empty() else 1)

func _case(setup: Array, clip: String) -> Dictionary:
	var id: String = setup[0]
	var label := id + "/" + clip
	var water := clip == "DrawWater"
	var source: Vector2 = People.WATER if water else People.FOOD
	var intent := "water" if water else "fruit"
	var state := People.initial(210.0)
	var npc := People.make_person(id, setup[1], setup[2], _approach(source), 210.0)
	npc.phase = "companion"
	npc.water = 48.0 if water else 75.0
	npc.hunger = 75.0 if water else 46.0
	npc.weapon = "spear" if setup[3] else ""
	npc.shield = setup[3]
	state.people[id] = npc
	var room := _room(state)
	var scene := PeopleScene.new()
	root.add_child(scene)
	var initial_stock: int = state.resources[intent].stock
	var eye := Vector3(source.x, Lake.walk_height(source) + 1.67, source.y)
	var began := -1.0
	var ended := -1.0
	var first_root := Vector3.ZERO
	var stop_point := Vector2.ZERO
	var first_feet := {}
	var movement_clips := []
	var captures := {}
	var foot_drift := 0.0
	var min_hand := INF
	var max_reach := 0.0
	var min_hips := INF
	var max_grip_gap := 0.0
	var min_back_offset := INF
	var min_turn_alignment := 1.0
	var floor_error := 0.0
	var water_contact := INF
	for step in range(546):
		var elapsed := 210.0 + step * DT
		room.data.elapsed = elapsed
		motion.tick(room, grid, DT)
		if npc.clip not in movement_clips:
			movement_clips.append(npc.clip)
		var snap: Dictionary = People.snapshot(state,"visitor-a",elapsed).people
		var other: Dictionary = People.snapshot(state,"visitor-b",elapsed).people
		_check(snap[id].clip == other[id].clip and snap[id].clipAt == other[id].clipAt, label + " snapshot clock")
		scene.sync(snap,elapsed,DT,eye)
		if npc.clip != clip:
			if began >= 0.0:
				ended = elapsed
				break
			continue
		var a: Dictionary = scene.actors[id]
		var actor_root: Node3D = a.root
		var rig: Skeleton3D = a.rig
		var animator: AnimationPlayer = a.animator
		if began < 0.0:
			began = elapsed
			first_root = actor_root.position
			stop_point = People.position(npc)
			_check(animator.has_animation(clip) and animator.assigned_animation == clip, label + " active game clip")
			_check(absf(animator.get_animation(clip).length - float(People.WORK_SECONDS[clip])) < 0.002, label + " runtime and GLB duration")
			_check(int(state.resources[intent].stock) == initial_stock - 1, label + " consumes one real source item")
		var age := elapsed-began
		if age < 0.24 or step % 3 != 0:
			continue
		rig.force_update_all_bone_transforms()
		await process_frame
		_check(People.position(npc).is_equal_approx(stop_point), label + " authoritative feet stay put")
		var at: Vector3 = _relative(a, "hand_L")
		min_hand = minf(min_hand,at.y)
		max_reach = maxf(max_reach,-at.z)
		min_hips = minf(min_hips,_relative(a,"hips").y)
		var aim := _water_line(source) if water else source
		var expected := stop_point.direction_to(aim)
		var facing := Basis(Vector3.UP,actor_root.rotation.y) * Vector3.FORWARD
		min_turn_alignment = minf(min_turn_alignment,expected.dot(Vector2(facing.x,facing.z)))
		for side: String in ["L","R"]:
			var foot := _relative(a,"foot_"+side)
			if first_feet.has(side):
				foot_drift = maxf(foot_drift,foot.distance_to(first_feet[side]))
			else:
				first_feet[side] = foot
			if setup[3]:
				var attachment: Node3D = a.left if side == "L" else a.right
				var grip := _relative(a,"grip_"+side)
				var joint := actor_root.to_global(grip)
				max_grip_gap = maxf(max_grip_gap,joint.distance_to(attachment.global_position))
				if age > float(People.WORK_SECONDS[clip])*0.39 and age < float(People.WORK_SECONDS[clip])*0.68:
					min_back_offset = minf(min_back_offset, grip.z - _relative(a,"chest").z)
		if render:
			var skin: MeshInstance3D = a.model.find_children("*", "MeshInstance3D", true, false)[0]
			await RenderingServer.frame_post_draw
			var contact := _skin_contact(skin, water)
			floor_error = maxf(floor_error, absf(contact.x))
			water_contact = minf(water_contact, contact.y)
			var phase := age / float(People.WORK_SECONDS[clip])
			for key: Array in [["approach",0.20], ["reach",0.42], ["recover",0.72], ["stand",0.94]]:
				if phase >= key[1] and not captures.has(key[0]):
					captures[key[0]] = true
					await _capture(id+"-"+clip+"-"+key[0],actor_root,water)
	_check(began >= 0.0 and ended > began, label + " begins and finishes from real terrain")
	_check(absf(ended-began-float(People.WORK_SECONDS[clip])) < 0.035, label + " finishes on the room clock")
	_check(foot_drift < 0.028 and min_turn_alignment > 0.82, label + " stable feet face the source")
	_check(floor_error < 0.026, label + " actual soles stay grounded")
	if water and render:
		_check(water_contact < 0.045, label + " left hand reaches the actual creek surface")
	_check(max_grip_gap < 0.015, label + " attached meshes follow animated grip points")
	if setup[3]:
		_check(min_back_offset > 0.125, label + " gear stows behind the torso while reaching")
		for step in 18:
			var elapsed := ended + DT*step
			room.data.elapsed = elapsed
			motion.tick(room,grid,DT)
			scene.sync(People.snapshot(state,"visitor-a",elapsed).people,elapsed,DT,eye)
		var a: Dictionary = scene.actors[id]
		var rig: Skeleton3D = a.rig
		rig.force_update_all_bone_transforms()
		for side: String in ["L","R"]:
			var grip := rig.find_bone("grip_"+side)
			_check(rig.get_bone_pose_position(grip).distance_to(rig.get_bone_rest(grip).origin)<0.02,
				label + " gear returns to the original hand socket")
	_check(min_hand < (0.36 if water else 1.06) and max_reach > 0.24, label + " visible reach")
	_check(maxi(0, initial_stock - int(state.resources[intent].stock)) == 1, label + " work doesn't repeat the debit")
	var retained: Dictionary = People.from_save(JSON.parse_string(JSON.stringify(state)),ended,grid).people[id]
	_check(retained.weapon == npc.weapon and retained.shield == npc.shield, label + " gear records persist")
	scene.queue_free()
	await process_frame
	return {"clips":movement_clips,"seconds":ended-began,"maxFootDriftM":foot_drift,"minimumHandHeightM":min_hand,
		"maxForwardHandM":max_reach,"lowestHipsM":min_hips,"alignment":min_turn_alignment,
		"weaponAnchorErrorM":max_grip_gap,"skinnedFloorErrorM":floor_error if render else null,
		"gearBackOffsetM":min_back_offset if is_finite(min_back_offset) else null,
		"waterContactErrorM":water_contact if is_finite(water_contact) else null,
		"renderedApproachM":first_root.distance_to(Vector3(stop_point.x,first_root.y,stop_point.y))}

func _exhausted_cases() -> void:
	var state := People.initial(240.0)
	var npc := People.make_person("resource-check",0,"male",People.WATER,240.0)
	npc.phase = "companion"
	npc.water = 10.0
	npc.hunger = 70.0
	state.people[npc.id] = npc
	var room := _room(state)
	room.data.elapsed = 240.0
	state.resources.water.stock = 0
	motion.tick(room,grid,DT)
	_check(npc.clip == "Guard" and npc.water <= 10.0,"empty source doesn't play a successful gather")
	state.resources.water.stock = 3
	room.data.elapsed += DT
	motion.tick(room,grid,DT)
	var first: float = npc.clipAt
	_check(npc.clip == "DrawWater" and state.resources.water.stock == 2,"first draw consumes once")
	room.data.elapsed = first + 1.1
	motion.tick(room,grid,DT)
	_check(npc.clipAt == first and state.resources.water.stock == 2,"no second drink during active work")
	room.data.elapsed = first + 1.6
	motion.tick(room,grid,DT)
	_check(npc.clip == "DrawWater" and npc.clipAt > first and state.resources.water.stock == 1,"repeat drink has a new timestamp")
	npc.order = "rest"
	room.data.elapsed += DT
	motion.tick(room,grid,DT)
	_check(npc.clip != "DrawWater","rest order interrupts the work animation")
	var shared := People.initial(260.0)
	shared.resources.water.stock = 1
	for id: String in ["first","second"]:
		var thirsty := People.make_person(id,0,"male",People.WATER,260.0)
		thirsty.phase = "companion"
		thirsty.water = 40.0
		shared.people[id] = thirsty
	var competition := _room(shared)
	competition.data.elapsed = 260.0
	motion.tick(competition,grid,DT)
	_check(shared.resources.water.stock == 0 and shared.people.first.clip == "DrawWater" and shared.people.second.clip == "Guard",
		"two companions share one remaining water draw")

func _room(state: Dictionary) -> Dictionary:
	return {"data":{"wildPeople":state,"elapsed":210.0,"provisions":{},"quest":{"repaired":true}},
		"people_routes":{},"actors":{},"ship":{"pilot":""}}

func _approach(source: Vector2) -> Vector2:
	for shift: Vector2 in [Vector2(1.3,0),Vector2(0,1.3),Vector2(0,-1.3),Vector2(-1.3,0)]:
		if Rules.free_at(source+shift,grid):
			return source+shift
	return source

func _water_line(source: Vector2) -> Vector2:
	var index := (source.y-float(Lake.layout.creek.firstZ))/float(Lake.layout.creek.spacing)
	return Vector2(Lake.creek_sample(index).x,source.y)

func _relative(actor: Dictionary, bone: String) -> Vector3:
	var rig: Skeleton3D = actor.rig
	return actor.root.to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone(bone)).origin))

func _skin_contact(skin: MeshInstance3D, water: bool) -> Vector2:
	var posed := skin.bake_mesh_from_current_skeleton_pose()
	var floor := INF
	var surface := INF
	for i in skin.mesh.get_surface_count():
		var rest: PackedVector3Array = skin.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
		var vertices: PackedVector3Array = posed.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
		for n in rest.size():
			if rest[n].y < 0.07:
				floor = minf(floor, vertices[n].y)
			elif water and rest[n].y > 0.81 and rest[n].y < 1.02 and rest[n].x < -0.24 and vertices[n].y < 0.12:
				var tip := skin.global_transform * vertices[n]
				var creek := Lake.surface_height(Vector2(tip.x,tip.z))
				if is_finite(creek):
					surface = minf(surface, absf(tip.y-creek))
	return Vector2(floor,surface)

func _check(ok: bool, note: String) -> void:
	if not ok and note not in errors:
		errors.append(note)

func _build_capture_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#5b6a55")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#f3e8d6")
	env.ambient_light_energy = 0.62
	world.environment = env
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-43,-27,0)
	light.light_energy = 0.91
	light.shadow_enabled = true
	floor_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(45,45)
	floor_mesh.mesh = plane
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#657458")
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	floor_mesh.material_override = mat
	stage.add_child(floor_mesh)
	creek_floor = MeshInstance3D.new()
	creek_floor.material_override = mat
	creek_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(creek_floor)
	creek_surface = MeshInstance3D.new()
	var pool := PlaneMesh.new()
	pool.size = Vector2(5, 5)
	creek_surface.mesh = pool
	var creek_material := StandardMaterial3D.new()
	creek_material.albedo_color = Color("#608e8c")
	creek_material.roughness = 0.27
	creek_surface.material_override = creek_material
	creek_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(creek_surface)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.38
	stage.add_child(camera)
	camera.make_current()

func _capture(label: String, actor_root: Node3D, water: bool) -> void:
	floor_mesh.visible = not water
	creek_floor.visible = water
	creek_surface.visible = water
	floor_mesh.position = actor_root.position - Vector3.UP*0.008
	if water:
		var midpoint := Vector2(actor_root.position.x,actor_root.position.z)
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		for x in range(-12,12):
			for z in range(-12,12):
				for offset: Vector2 in [Vector2.ZERO,Vector2(0,1),Vector2(1,0),Vector2(1,0),Vector2(0,1),Vector2.ONE]:
					var p := midpoint + (Vector2(x,z)+offset)*0.21
					builder.set_normal(Vector3.UP)
					builder.add_vertex(Vector3(p.x,Lake.walk_height(p)-0.008,p.y))
		creek_floor.mesh = builder.commit()
		creek_surface.position = Vector3(midpoint.x,Lake.water_y(),midpoint.y)
	var center := actor_root.position + Vector3.UP * 0.86
	camera.position = center + actor_root.basis * Vector3(-3.1,0.45,-2.0)
	camera.look_at(center)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://frames/"+label+".png")
