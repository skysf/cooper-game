extends SceneTree

const Terrain = preload("res://terrain.gd")
const Atmosphere = preload("res://atmosphere.gd")
const WindField = preload("res://vegetation/wind_field.gd")
const Coast = preload("res://coast_layout.gd")
const Lake = preload("res://lake_layout.gd")
const Mines = preload("res://mines_layout.gd")

var view := SubViewport.new()
var terrain := Terrain.new()
var atmosphere := Atmosphere.new()
var camera := Camera3D.new()
var directory := ""
var valid := true
var weather := 1.0
var report: Dictionary = {}

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or not FileAccess.file_exists(args[1]):
		push_error("Supply capture directory and the imported production camp.glb chunk")
		quit(2)
		return
	directory = args[0]
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		quit(3)
		return
	view.size = Vector2i(1280, 720)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(atmosphere)
	view.add_child(terrain)
	terrain.set_process(false)
	view.add_child(camera)
	camera.fov = 63.0
	camera.near = 0.045
	camera.far = 185.0
	camera.make_current()
	terrain._parse_chunk("camp", FileAccess.get_file_as_bytes(args[1]))
	terrain.grove.set_room_time(89.0)
	var pine: Dictionary = terrain.grove.trees.filter(func(t:Dictionary) -> bool: return t.spec.id == "trail-mature")[0]
	var spruce: Dictionary = terrain.grove.trees.filter(func(t:Dictionary) -> bool: return t.spec.id == "trail-spruce")[0]
	verify_tree("pine", pine.model)
	verify_tree("spruce", spruce.model)
	var steady := 77.7
	var peak := 94.5
	aim(Vector3(5.18, 2.28, -69.19), Vector3(2.18, 3.47, -72.63), 69.0)
	storm(89.0)
	atmosphere.rain.hide()
	await pair("pine", steady, peak)
	aim(Vector3(-5.14, 2.18, -76.96), Vector3(-1.55, 3.4, -80.25), 64.0)
	storm(89.0)
	atmosphere.rain.hide()
	await pair("spruce", steady, peak)
	var lod := {}
	for distance in [6.95, 7.5, 8.0, 8.5, 9.05, 16.95, 17.5, 18.0, 18.5, 19.05]:
		aim(Vector3(2.18, 1.7, -72.63 + distance), Vector3(2.18, 3.4, -72.63), 61.0)
		set_flow(89.0)
		var visible := []
		for detail: Node3D in pine.details:
			visible.append(detail.visible)
		lod[str(distance)] = {"active":visible, "blend": [pine.detail_mix.x,pine.detail_mix.y]}
		if distance in [7.5,8.0,8.5,17.5,18.0,18.5]:
			await screenshot("pine-lod-%.1f" % distance, 2)
	assert(lod["8.0"].active == [true,true,false] and lod["18.0"].active == [false,true,true])
	assert(lod["6.95"].active == [true,false,false] and lod["19.05"].active == [false,false,true])
	report["pine_lod_band"] = lod
	var coast_tree_instances := 0
	var coast_crowns := 0
	var coast_ferns := 0
	var grass_nodes: Array[Node3D] = []
	for part: MultiMeshInstance3D in terrain.coast.find_children("*","MultiMeshInstance3D",false,false):
		if part.material_override == terrain.coast.shrub_shader:
			coast_ferns += part.multimesh.instance_count
		elif part.material_override is ShaderMaterial and part.material_override.shader.resource_path.ends_with("lake_canopy.gdshader"):
			if part.material_override.get_shader_parameter("coast_transition"):
				coast_crowns += part.multimesh.instance_count
		elif part.name.begins_with("DuneGrass"):
			grass_nodes.append(part)
		else:
			for i in part.multimesh.mesh.get_surface_count():
				var surface := part.multimesh.mesh.surface_get_material(i) as ShaderMaterial
				if surface != null and surface.get_shader_parameter("coast_transition") == true:
					coast_tree_instances += part.multimesh.instance_count
	var fern := Vector2(-60.75, -43.25)
	var fern_height := Coast.height(fern)
	aim(Vector3(fern.x + 1.85, fern_height + .66, fern.y - .6), Vector3(fern.x, fern_height + .2, fern.y), 58.0)
	storm(89.0)
	atmosphere.rain.hide()
	await pair("coast-fern", steady, peak)
	var coast_tree: Array = Coast.foliage.trees.filter(func(p:Array) -> bool: return p[0] == -69.75 and p[1] == -62.75)[0]
	var x := float(coast_tree[0])
	var z := float(coast_tree[1])
	var y := Coast.height(Vector2(x,z))
	weather = 0.0
	for distance in [35.0,37.0,39.5,42.0,44.0]:
		aim(Vector3(x + distance * .85, y + 2.0, z + distance * .52678),
			Vector3(x, y + 2.5, z), 48.0)
		storm(48.0)
		atmosphere.rain.hide()
		await screenshot("coast-lod-%.1f" % distance, 2)
	weather = 1.0
	report["coast_tree"] = coast_tree
	report["coast_tree_surface_instances"] = coast_tree_instances
	report["coast_canopy_billboards"] = coast_crowns
	report["coast_fern_cards"] = coast_ferns
	report["steady_time"] = steady
	report["gust_time"] = peak
	report["rain_vector"] = []
	var rain_eye := Vector3(-84.1, 2.0, -50.85)
	for yaw in [0.0, PI * 0.5, PI, PI * 1.5]:
		camera.position = rain_eye
		camera.rotation = Vector3(0.0,yaw,0.0)
		terrain.update_focus(camera.position)
		storm(peak)
		var field: Vector4 = atmosphere.streaks.get_shader_parameter("wind_field")
		assert(field.is_equal_approx(WindField.sample(peak, weather)))
		var world := WindField.at_point(field, peak, Vector2(rain_eye.x, rain_eye.z)) * .21
		report.rain_vector.append({"yaw":yaw,"world_at_eye":[world.x,world.y]})
	aim(rain_eye, Vector3(-91.0, 1.4, -57.0), 68.0)
	storm(peak)
	await screenshot("rain-on-wind", 2)
	atmosphere.update_weather(rain_eye,peak,0.0,true)
	assert(not atmosphere.rain.visible)
	atmosphere.update_weather(rain_eye,peak,1.0,true,true,1.0,1.0)
	assert(not atmosphere.rain.visible)

	var seeded := 0
	var above_sea := INF
	var highest := -INF
	var planted := 0
	assert(not grass_nodes.is_empty())
	var seeds: Array = Coast.foliage.get("dunegrass", [])
	var entry: Array = seeds[13]
	var grass_x := float(entry[0])
	var grass_z := float(entry[1])
	var grass_y := Coast.height(Vector2(grass_x,grass_z))
	var eye := Vector3(-86.1, 0.0, -50.50)
	eye.y = Coast.height(Vector2(eye.x,eye.z)) + 1.63
	aim(eye, Vector3(-82.07, grass_y + .12, -50.25), 70.0)
	weather = 0.0
	storm(44.0)
	atmosphere.rain.hide()
	for grass: MultiMeshInstance3D in grass_nodes:
		grass.hide()
		planted += grass.multimesh.instance_count
		for i in grass.multimesh.instance_count:
			var origin := grass.position + grass.multimesh.get_instance_transform(i).origin
			var at := Vector2(origin.x, origin.z)
			var clearance := Coast.height(at) - Lake.water_y()
			above_sea = minf(clearance, above_sea)
			highest = maxf(clearance, highest)
			assert(not Mines.occludes_plant(at))
			assert(is_equal_approx(origin.y + .012, Coast.height(at)))
			assert(clearance > .45)
	for seed: Array in seeds:
		if not Mines.occludes_plant(Vector2(seed[0], seed[1])):
			seeded += 1
	assert(seeded == planted)
	await screenshot("dunegrass-before",9)
	for grass in grass_nodes:
		grass.show()
	await screenshot("dunegrass-after",7)
	aim(Vector3(grass_x - 1.15, grass_y + .60, grass_z - .45),
		Vector3(grass_x, grass_y + .32, grass_z), 53.0)
	await screenshot("dunegrass-close",7)
	weather = 1.0
	storm(89.0)
	atmosphere.rain.hide()
	await pair("dunegrass", steady, peak)
	report["dunegrass"] = {"seeded":seeds.size(),"planted":planted,"batches":grass_nodes.size(),"sample":entry,
		"heights_rel_to_sea": [above_sea, highest], "wide_camera": [eye.x,eye.y,eye.z]}
	var excluded_shrubs: int = Coast.foliage.shrubs.filter(func(p: Array) -> bool:
		return Mines.occludes_plant(Vector2(p[0], p[1]))).size()
	assert(coast_ferns == (Coast.foliage.shrubs.size() - excluded_shrubs) * 3)
	assert(excluded_shrubs == 23)
	report["cave_excluded_shrubs"] = excluded_shrubs
	print("SHORE_WIND_QA " + JSON.stringify(report))
	assert(coast_tree_instances > 0 and coast_crowns == Coast.foliage.trees.size() and coast_ferns > 0)
	quit(0 if valid else 4)

func verify_tree(label: String, model: Node3D) -> void:
	var bark := 0
	var leaves := 0
	var normal := 0
	var roughness := 0
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for i in part.mesh.get_surface_count():
			var material := part.get_active_material(i) as ShaderMaterial
			if material == null:
				continue
			if material.shader.resource_path.ends_with("tree_wood.gdshader"):
				bark += 1
				if material.get_shader_parameter("has_normal_texture"):
					normal += 1
				if material.get_shader_parameter("has_roughness_texture"):
					roughness += 1
			if material.shader.resource_path.ends_with("tree_leaves.gdshader"):
				leaves += 1
	assert(bark > 0 and leaves > 0)
	report[label] = {"bark":bark, "leaves":leaves, "normal_map":normal, "roughness_map":roughness}

func aim(at: Vector3, target: Vector3, fov: float) -> void:
	camera.position = at
	camera.fov = fov
	camera.look_at(target)
	terrain.update_focus(at)

func storm(elapsed: float) -> void:
	var point := Vector2(camera.position.x, camera.position.z)
	atmosphere.update_weather(camera.position, elapsed, weather, true, false,
		Lake.surface_height(point) - camera.position.y, 1.0 if camera.position.x < -60.0 else 0.0)
	terrain.set_wet(weather)
	terrain.update_water(elapsed, weather, {
		"sun_direction": atmosphere.sun_direction, "moon_direction": atmosphere.moon_direction,
		"sun_energy": atmosphere.sun_energy, "sky_zenith": atmosphere.sky_zenith, "sky_horizon": atmosphere.sky_horizon,
		"sun_color": atmosphere.sun_color, "moon_color": atmosphere.moon_color, "cloud_cover": atmosphere.cloud_cover,
		"twilight": atmosphere.twilight, "evening_weight": atmosphere.evening_weight,
		"underwater": atmosphere.underwater
	})

func set_flow(elapsed: float) -> void:
	var wind := WindField.sample(elapsed, weather)
	terrain.grove.set_wind(elapsed, wind)
	terrain.coast.set_wind(elapsed, wind)

func pair(label: String, steady: float, peak: float) -> void:
	set_flow(steady)
	await screenshot(label + "-steady", 7)
	set_flow(peak)
	await screenshot(label + "-gust", 5)

func screenshot(name: String, frames: int) -> void:
	for frame in frames:
		await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	if image == null or image.save_png(directory.path_join(name + ".png")) != OK:
		valid = false
		push_error("Cannot write view: " + name)
