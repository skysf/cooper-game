extends SceneTree

const Atmosphere = preload("res://atmosphere.gd")
const Terrain = preload("res://terrain.gd")
const Rules = preload("res://rules.gd")
const Layout = preload("res://lake_layout.gd")
const WindField = preload("res://vegetation/wind_field.gd")

var view := SubViewport.new()
var terrain := Terrain.new()
var atmosphere := Atmosphere.new()
var camera := Camera3D.new()
var ferns: Variant
var result := {"captures": {}, "checks": [], "errors": []}
var out := ""

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		quit(2)
		return
	out = args[0]
	view.size = Vector2i(1280, 720)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(atmosphere)
	view.add_child(terrain)
	terrain.set_process(false)
	view.add_child(camera)
	camera.near = 0.038
	camera.far = 150.0
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.make_current()
	aim(Vector3(-6.55, 1.67, -60.05), Vector3(-9.62, 0.45, -57.65), 78.0)
	for chunk: String in ["creek", "crossing", "approach"]:
		var part := FileAccess.get_file_as_bytes(args[1].path_join(chunk + ".glb"))
		if part.is_empty():
			quit(3)
			return
		terrain._parse_chunk(chunk, part)
	check(terrain.loaded.has("creek") and terrain.loaded.has("crossing"), "Current generated creek and crossing chunks")

	ferns = terrain.lake.creek_ferns
	var planting: Array = Layout.layout.lakesideVegetation.ostrichFern
	check(terrain.lake.plants.materials.size() == 2, "Original hazel and bulrush materials load")
	if DisplayServer.get_name() == "headless":
		check(ferns.materials.size() == 2, "Both fern materials compile")
		finish()
		return
	verify_scene(planting)
	terrain.grove.set_room_time(101.0)

	weather(51.2, 0.0)
	await toggle_pair("bank")
	aim(Vector3(-6.80, 1.13, -59.33), Vector3(-8.32, 0.48, -58.50), 70.0)
	weather(51.2, 0.0)
	await toggle_pair("mature")
	weather(94.5, 1.0)
	await toggle_pair("rain")

	# Keep the room and rain phase stable while A/B sampling local leaf movement.
	atmosphere.rain.hide()
	for time: float in [77.7, 94.5]:
		var field := WindField.sample(time, 1.0)
		ferns.set_wind(time, field, 1.0)
		var point := Vector2(-8.24, -58.38)
		var flow := WindField.at_point(field, time, point)
		var label := "steady" if time < 80.0 else "gust"
		result[label] = {"time": time, "wind": [flow.x, flow.y], "speed": flow.length()}
		check((ferns.materials[0].get_shader_parameter("wind_field") as Vector4).is_equal_approx(field), "Shared room gust " + label)
		await shot("wind-" + label, 8)

	aim(Vector3(-7.50, 0.37, -58.02), Vector3(-8.25, 0.50, -58.39), 76.0)
	weather(51.2, 0.0)
	await shot("underleaf", 9)
	aim(Vector3(-7.78, 0.66, -58.12), Vector3(-8.20, 0.71, -58.37), 56.0)
	weather(51.2, 0.0)
	await shot("pinna", 9)
	aim(Vector3(-7.88, 0.119, -58.61), Vector3(-8.24, 0.076, -58.38), 70.0)
	weather(51.2, 0.0)
	await shot("crown", 9)
	aim(Vector3(-8.85, 1.67, -49.1), Vector3(-15.4, 0.20, -49.1), 78.0)
	weather(51.2, 0.0)
	await toggle_pair("dock")
	aim(Vector3(-8.10, 1.65, -46.56), Vector3(-10.45, 0.32, -43.95), 76.0)
	weather(51.2, 0.0)
	await toggle_pair("north-bank")
	aim(Vector3(-14.17, -0.153, -44.38), Vector3(-13.0, -0.162, -44.311), 78.0)
	weather(94.5, 1.0)
	check(atmosphere.underwater and terrain.lake.bed.motes.visible, "Underwater atmosphere and particles")
	await toggle_pair("underwater")

	# Same camera in the cross-fade band, including both forced endpoints.
	aim(Vector3(-1.0, 1.76, -51.6), Vector3(-8.24, 0.48, -58.38), 45.0)
	weather(51.2, 0.0)
	await toggle_pair("lod")
	for trial: Array in [["lod-near", Vector4(30, 35, 37, 45)], ["lod-far", Vector4(0.1, 0.2, 22, 29)]]:
		for material: ShaderMaterial in ferns.materials:
			material.set_shader_parameter("distances", trial[1])
		await shot(trial[0], 10)
	for material: ShaderMaterial in ferns.materials:
		material.set_shader_parameter("distances", ferns.DISTANCES)
	aim(Vector3(4.84, 1.76, -48.97), Vector3(-8.24, 0.48, -58.38), 37.0)
	weather(51.2, 0.0)
	await toggle_pair("distant")
	for material: ShaderMaterial in terrain.lake.plants.materials + ferns.materials:
		check((material.get_shader_parameter("wind_field") as Vector4).is_equal_approx(WindField.sample(51.2, 0.0)),
			"All lake plants share the live room wind vector")
	finish()

func verify_scene(planting: Array) -> void:
	var count := Vector2i.ZERO
	var depth_range := Vector2(INF, -INF)
	var draws := Vector2i.ZERO
	var previous := {}
	var beds := {}
	for spec: Array in planting:
		beds[Vector2(spec[0], spec[1]).snapped(Vector2.ONE * 0.001)] = float(spec[5])
	for batch: MultiMeshInstance3D in ferns.find_children("*", "MultiMeshInstance3D", false, false):
		var is_near: bool = batch.material_override.get_shader_parameter("near_mesh")
		var id := 0 if is_near else 1
		draws[id] += 1
		check(batch.layers & terrain.lake.REFLECTION_LAYER != 0, "%s has reflection layer" % batch.name)
		check(batch.visibility_range_end < 33.5 and batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s has bounded visibility" % batch.name)
		for i in batch.multimesh.instance_count:
			var local_root := batch.position + batch.multimesh.get_instance_transform(i).origin
			var xz := Vector2(local_root.x, local_root.z).snapped(Vector2.ONE * 0.001)
			count[id] += 1
			var above_water := local_root.y - Layout.water_y()
			depth_range.x = minf(depth_range.x, above_water)
			depth_range.y = maxf(depth_range.y, above_water)
			check(not is_finite(Layout.surface_height(xz)) and not Layout.on_dock(xz), "Dry root %s" % xz)
			check(beds.has(xz) and is_equal_approx(local_root.y + 0.004, float(beds.get(xz, INF))), "Grounded root %s" % xz)
			if previous.has(xz):
				check(local_root.is_equal_approx(previous[xz]), "Same near and far root %s" % xz)
			else:
				previous[xz] = local_root
	check(count.x == planting.size() and count.x == count.y, "Each surveyed clump has both meshes")
	check(ferns.find_children("*", "CollisionObject3D", true, false).is_empty(), "Fern has no colliders")
	check((ferns.materials[0].get_shader_parameter("fern_atlas") as Texture2D).get_size() == Vector2(512, 512), "One embedded fern atlas")
	var grid := Rules.collision_grid(terrain.world.obstacles)
	var lanes := {}
	for route: Array in [["boardwalk", Vector2(-10.8, -49.16), Vector2(-8.2, -49.16)],
			["wood", Vector2(-8.51, -52.65), Vector2(-6.65, -53.03)],
			["wade", Vector2(-10.72, -54.19), Vector2(-8.23, -54.19)]]:
		var first: Vector2 = route[1]
		var last: Vector2 = route[2]
		var point := first
		for i in range(40):
			if point.distance_to(last) <= 0.11:
				break
			point = Rules.move(point, point.direction_to(last), minf(0.035, point.distance_to(last) / Rules.SPEED), grid, route[0] == "wade")
		lanes[route[0]] = {"distance_to_goal": point.distance_to(last), "point": [point.x, point.y]}
		check(point.distance_to(last) <= 0.11, "%s remains traversable" % route[0])
	result.planting = {"clumps": [count.x, count.y], "batches": [draws.x, draws.y],
		"root_clearance_above_water": [depth_range.x, depth_range.y], "traversal": lanes}

func weather(elapsed: float, rainfall: float) -> void:
	var eye := camera.position
	var surface := Layout.surface_height(Vector2(eye.x, eye.z))
	var depth := surface - eye.y
	atmosphere.update_weather(eye, elapsed, rainfall, true, is_finite(depth) and depth > .035, depth)
	terrain.set_wet(rainfall)
	terrain.update_water(elapsed, rainfall, {
		"sun_direction": atmosphere.sun_direction, "moon_direction": atmosphere.moon_direction,
		"sun_energy": atmosphere.sun_energy, "sky_zenith": atmosphere.sky_zenith,
		"sky_horizon": atmosphere.sky_horizon, "sun_color": atmosphere.sun_color, "moon_color": atmosphere.moon_color,
		"cloud_cover": atmosphere.cloud_cover, "twilight": atmosphere.twilight, "evening_weight": atmosphere.evening_weight,
		"underwater": atmosphere.underwater})

func aim(eye: Vector3, target: Vector3, horizontal_fov: float) -> void:
	camera.position = eye
	camera.fov = horizontal_fov
	camera.look_at(target)
	terrain.update_focus(eye)

func toggle_pair(label: String) -> void:
	ferns.hide()
	await shot(label + "-before", 12)
	ferns.show()
	await shot(label + "-after", 12)

func shot(label: String, frames: int) -> void:
	terrain.lake.reflection.render_target_update_mode = SubViewport.UPDATE_ONCE
	for i in frames:
		await RenderingServer.frame_post_draw
	var render_objects := view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)
	var primitives := view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	var draw_calls := view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	result.captures[label] = {"eye": [camera.position.x, camera.position.y, camera.position.z], "fov": camera.fov,
		"objects": render_objects, "triangles": primitives, "draw_calls": draw_calls}
	var saved := view.get_texture().get_image().save_jpg(out.path_join(label + ".jpg"), 0.96)
	check(saved == OK, "Rendered " + label)

func check(ok: bool, reason: String) -> void:
	if not ok:
		result.errors.append(reason)
		push_error(reason)
	else:
		result.checks.append(reason)

func finish() -> void:
	var file := FileAccess.open(out.path_join("native-render-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  ") + "\n")
	file.close()
	print("FERN_QA ", result.checks.size(), " checks, ", result.errors.size(), " failures")
	quit(0 if result.errors.is_empty() else 4)
