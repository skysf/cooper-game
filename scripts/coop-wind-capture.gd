extends SceneTree

const Terrain = preload("res://terrain.gd")
const Atmosphere = preload("res://atmosphere.gd")
const WindField = preload("res://vegetation/wind_field.gd")
const Lake = preload("res://lake_layout.gd")

var view := SubViewport.new()
var terrain := Terrain.new()
var atmosphere := Atmosphere.new()
var camera := Camera3D.new()

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Supply capture directory and the production camp.glb chunk")
		quit(2)
		return
	var directory := args[0]
	var chunk := args[1]
	if not FileAccess.file_exists(chunk) or DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Cannot read production chunk or create capture directory")
		quit(2)
		return

	view.size = Vector2i(1280,720)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(atmosphere)
	view.add_child(terrain)
	terrain.set_process(false)
	view.add_child(camera)
	camera.fov = 78.0
	camera.near = 0.045
	camera.far = 105.0
	camera.position = Vector3(-3.51, 1.70, -84.43)
	camera.look_at(Vector3(-1.85, 2.72, -89.5))
	camera.make_current()
	terrain.update_focus(camera.position)
	terrain._parse_chunk("camp", FileAccess.get_file_as_bytes(chunk))
	terrain.grove.set_room_time(89.0)

	var birch := terrain.grove.find_child("camp-birch", false, false)
	var wood := birch.find_child("birch_bark", true, false) as MeshInstance3D
	var leaves := birch.find_child("birch_foliage", true, false) as MeshInstance3D
	if wood == null or leaves == null or not terrain.loaded.has("camp"):
		push_error("The actual camp chunk or birch surfaces were not found")
		quit(2)
		return
	if wood.get_active_material(0) is not ShaderMaterial or leaves.get_active_material(0) is not ShaderMaterial:
		push_error("The rendered birch did not use the wind shaders")
		quit(2)
		return
	var grass_count := 0
	for item: MultiMeshInstance3D in terrain.loaded["camp"].find_children("*", "MultiMeshInstance3D", true, false):
		if item.material_override == terrain.grass.material:
			grass_count += item.multimesh.instance_count
	if grass_count == 0:
		push_error("The production camp grass is missing")
		quit(2)
		return

	var elapsed := 89.0
	var rain := 1.0
	var point := Vector2(camera.position.x, camera.position.z)
	atmosphere.update_weather(camera.position, elapsed, rain, true, false,
		Lake.surface_height(point) - camera.position.y)
	terrain.set_wet(rain)
	terrain.update_water(elapsed, rain, {
		"sun_direction": atmosphere.sun_direction, "moon_direction": atmosphere.moon_direction,
		"sun_energy": atmosphere.sun_energy, "sky_zenith": atmosphere.sky_zenith, "sky_horizon": atmosphere.sky_horizon,
		"sun_color": atmosphere.sun_color, "moon_color": atmosphere.moon_color, "cloud_cover": atmosphere.cloud_cover,
		"twilight": atmosphere.twilight, "evening_weight": atmosphere.evening_weight,
		"underwater": atmosphere.underwater
	})

	var steady := 75.0
	var peak := 75.0
	for i in 250:
		var t := 75.0 + float(i) * 0.1
		if WindField.sample(t,rain).w < WindField.sample(steady,rain).w:
			steady = t
		if WindField.sample(t,rain).w > WindField.sample(peak,rain).w:
			peak = t
	for item: Array in [["whole-steady", steady], ["whole-gust", peak]]:
		set_flow(item[1],rain)
		await screenshot(directory.path_join(str(item[0]) + ".png"),18)

	# A second view isolates the geometry of the same birch along the branch line.
	var branch_camera := Vector3(-3.38, 3.20, -86.61)
	camera.position = branch_camera
	camera.fov = 58.0
	camera.look_at(Vector3(-1.65, 3.85, -89.50))
	for item: Array in [["crown-steady", steady], ["crown-gust", peak]]:
		set_flow(item[1], rain)
		await screenshot(directory.path_join(str(item[0]) + ".png"),8)
	leaves.hide()
	for item: Array in [["wood-steady",steady],["wood-gust",peak]]:
		set_flow(item[1],rain)
		await screenshot(directory.path_join(str(item[0]) + ".png"),8)
	leaves.show()

	camera.position = Vector3(-3.55, 0.59, -84.84)
	camera.fov = 56.0
	camera.look_at(Vector3(-3.49, 0.24, -85.76))
	for item: Array in [["grass-steady",steady],["grass-gust",peak]]:
		set_flow(item[1], rain)
		await screenshot(directory.path_join(str(item[0]) + ".png"),8)

	camera.position = Vector3(-3.51, 1.70, -84.43)
	camera.fov = 78.0
	camera.look_at(Vector3(-1.85, 2.72, -89.5))
	view.size = Vector2i(800,450)
	for i in 16:
		set_flow(peak - 2.35 + float(i) * 0.28, rain)
		await screenshot(directory.path_join("frame-%02d.png" % i),2)
	var steady_field := WindField.sample(steady,rain)
	var peak_field := WindField.sample(peak,rain)
	print(JSON.stringify({"steady_time":steady, "gust_time":peak, "rain":rain, "grass_instances_in_camp_chunk":grass_count,
		"steady_field":[steady_field.x,steady_field.y,steady_field.z,steady_field.w],
		"gust_field":[peak_field.x,peak_field.y,peak_field.z,peak_field.w],
		"bark_material": wood.get_active_material(0).shader.resource_path,
		"leaf_material": leaves.get_active_material(0).shader.resource_path,
		"grass_material": terrain.grass.material.shader.resource_path}))
	quit()

func set_flow(elapsed: float, rain: float) -> void:
	var wind := WindField.sample(elapsed, rain)
	terrain.grass.material.set_shader_parameter("wind_time", elapsed)
	terrain.grass.material.set_shader_parameter("wind_field", wind)
	terrain.grove.set_wind(elapsed,wind)

func screenshot(path: String, frames: int) -> void:
	for frame in frames:
		await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	if image == null or image.save_png(path) != OK:
		push_error("Could not render "+path)
		quit(2)
