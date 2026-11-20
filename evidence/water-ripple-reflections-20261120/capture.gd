extends SceneTree

const Terrain = preload("res://terrain.gd")
const Atmosphere = preload("res://atmosphere.gd")
const Lake = preload("res://lake_layout.gd")
const Coast = preload("res://coast_layout.gd")
const INCLUDE := '#include "res://materials/water_rain.gdshaderinc"'
const LAKE_TIME := 92.688612
const COAST_TIME := 90.321148
const LAKE_EYE := Vector3(-10.82, 1.79, -49.1)
const LAKE_AIM := Vector2(1.53035, -0.34935)
const COAST_AIM := Vector2(1.4809, -0.34075)

var view := SubViewport.new()
var terrain := Terrain.new()
var atmosphere := Atmosphere.new()
var camera := Camera3D.new()
var surfaces: Dictionary[MeshInstance3D, ShaderMaterial] = {}
var water_programs := {}
var out := ""
var report := {"checks": [], "errors": [], "shots": {}}
var evidence_directory := ""
var fixed_reflection: ImageTexture

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		quit(2)
		return
	out = args[0]
	evidence_directory = args[2]
	view.size = Vector2i(1280, 720)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(atmosphere)
	view.add_child(terrain)
	terrain.set_process(false)
	view.add_child(camera)
	camera.near = 0.07
	camera.far = 290.0
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 78.0
	camera.make_current()
	pose(LAKE_EYE, LAKE_AIM)
	for chunk: String in ["creek", "crossing", "approach"]:
		var blob := FileAccess.get_file_as_bytes(args[1].path_join(chunk + ".glb"))
		if blob.is_empty():
			quit(3)
			return
		terrain._parse_chunk(chunk, blob)
	check(terrain.loaded.has("creek") and terrain.loaded.has("crossing"), "Actual lake terrain chunks")
	terrain.grove.set_room_time(94.0)
	for mesh: MeshInstance3D in terrain.lake.find_children("*", "MeshInstance3D", true, false):
		var active := mesh.get_active_material(0) as ShaderMaterial
		if active in [terrain.lake.lake_material, terrain.lake.creek_material]:
			surfaces[mesh] = active
	for mesh: MeshInstance3D in terrain.coast.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override == terrain.coast.ocean_shader:
			surfaces[mesh] = terrain.coast.ocean_shader
	check(surfaces.size() == 3, "Lake, creek and ocean meshes identified")
	for variant: String in ["before", "after", "slope-only", "rain-without-rings"]:
		water_programs[variant] = {}
		for shader: String in ["water", "ocean"]:
			water_programs[variant][shader] = load_program(variant, shader)
	if DisplayServer.get_name() == "headless":
		finish()
		return

	var at := Vector2(-85.1, -51.0)
	var coast_eye := Vector3(at.x, Coast.height(at) + 1.67, at.y)
	await comparable("lake-rain", LAKE_EYE, LAKE_AIM, LAKE_TIME, 1.0,
		false, false, ["before", "slope-only", "rain-without-rings", "after"])
	await comparable("coast-rain", coast_eye, COAST_AIM, COAST_TIME, 1.0,
		true, false, ["before", "slope-only", "rain-without-rings", "after"])
	await comparable("lake-weather", LAKE_EYE, LAKE_AIM, LAKE_TIME, 1.0, false, true)
	await comparable("coast-weather", coast_eye, COAST_AIM, COAST_TIME, 1.0, true, true)
	await comparable("lake-distant", LAKE_EYE, Vector2(LAKE_AIM.x, -0.106), LAKE_TIME, 1.0, false, false)
	await comparable("coast-offshore", Vector3(-104.20, 1.65, -56.60), Vector2(1.568, -0.35), COAST_TIME, 1.0, true, false)
	await comparable("lake-clear", LAKE_EYE, LAKE_AIM, 24.0, 0.0, false, false, ["before", "after", "before-repeat"])
	await comparable("coast-clear", coast_eye, COAST_AIM, 24.0, 0.0, true, false)
	await comparable("lake-submerged", Vector3(-17.60, -0.78, -50.0), Vector2(1.53, 0.29), LAKE_TIME, 1.0, false, false)
	await comparable("coast-submerged", Vector3(-95.0, -0.84, -53.0), Vector2(1.48, 0.32), COAST_TIME, 1.0, true, false)
	await comparable("lake-creek-join", Vector3(-8.42, 1.61, -51.63), Vector2(1.72, -0.40), LAKE_TIME, 1.0, false, false)
	await comparable("coast-wash", Vector3(-83.38, Coast.height(Vector2(-83.38, -51.2)) + 1.67, -51.2),
		Vector2(1.383, -0.295), COAST_TIME, 1.0, true, false)
	await comparable("lake-easing", LAKE_EYE, LAKE_AIM, 111.0, 0.42, false, false)
	await comparable("lake-room-phase", LAKE_EYE, LAKE_AIM, LAKE_TIME + 0.19, 1.0, false, false, ["after"])
	terrain.lake.add_impact(Vector3(-14.2, Lake.water_y(), -49.02), 26.44)
	check(terrain.lake.latest_impact_at == 26.44, "Stone impact exists for the dry water comparison")
	await comparable("lake-stone-clear", LAKE_EYE, LAKE_AIM, 27.0, 0.0, false, false)
	finish()

func load_program(variant: String, shader: String) -> Shader:
	if variant == "after":
		var installed := load("res://materials/" + shader + ".gdshader") as Shader
		check(installed != null, "%s %s sources" % [variant, shader])
		return installed
	var original := evidence_directory.path_join("original-" + shader + ".gdshader.txt")
	var code := FileAccess.get_file_as_string(original)
	var common := FileAccess.get_file_as_string(evidence_directory.path_join("original-water_rain.gdshaderinc.txt"))
	var lines := PackedStringArray()
	for line in code.split("\n"):
		if variant != "before" and line.contains("color += rain_drops.z"):
			continue
		if variant == "rain-without-rings" and (line.contains("vec3 rain_drops =") or line.contains("waves += rain_drops.xy")):
			continue
		lines.append(line)
	check(not code.is_empty() and not common.is_empty(), "%s %s sources" % [variant, shader])
	var material := Shader.new()
	material.code = "\n".join(lines).replace(INCLUDE, common)
	return material

func pose(eye: Vector3, look: Vector2) -> void:
	camera.position = eye
	camera.rotation = Vector3(look.y, look.x, 0.0)
	terrain.update_focus(eye)

func comparable(label: String, eye: Vector3, look: Vector2, elapsed: float, rain: float,
		coast: bool, streaks: bool, modes: Array = ["before", "after"]) -> void:
	pose(eye, look)
	var depth := Lake.surface_height(Vector2(eye.x, eye.z)) - eye.y
	var submerged := is_finite(depth) and depth > 0.035
	atmosphere.update_weather(eye, elapsed, rain, false, submerged, depth, 1.0 if coast else 0.0)
	atmosphere.rain.visible = streaks and atmosphere.rain.visible
	terrain.set_wet(rain)
	# Force the new fixed pose/time into the coast material and lake reflection.
	terrain.coast.last_light_time = -INF
	terrain.lake.reflection_updated_at = -1.0
	terrain.update_water(elapsed, rain, {
		"sun_direction": atmosphere.sun_direction, "moon_direction": atmosphere.moon_direction,
		"sun_energy": atmosphere.sun_energy, "sky_zenith": atmosphere.sky_zenith, "sky_horizon": atmosphere.sky_horizon,
		"sun_color": atmosphere.sun_color, "moon_color": atmosphere.moon_color, "cloud_cover": atmosphere.cloud_cover,
		"twilight": atmosphere.twilight, "evening_weight": atmosphere.evening_weight, "underwater": atmosphere.underwater})
	check(atmosphere.underwater == submerged, label + " camera medium")
	check(is_equal_approx(float(terrain.lake.lake_material.get_shader_parameter("water_time")), elapsed), label + " lake clock")
	check(is_equal_approx(float(terrain.coast.ocean_shader.get_shader_parameter("water_time")), elapsed), label + " sea clock")
	fixed_reflection = null
	if terrain.lake.reflection_enabled:
		terrain.lake.reflection.render_target_update_mode = SubViewport.UPDATE_ONCE
		for i in 5:
			await RenderingServer.frame_post_draw
		var reflection := terrain.lake.reflection.get_texture().get_image()
		check(reflection != null and not reflection.is_empty(), label + " frozen live shore reflection")
		if reflection != null and not reflection.is_empty():
			fixed_reflection = ImageTexture.create_from_image(reflection)
	terrain.lake.reflection.render_target_update_mode = SubViewport.UPDATE_DISABLED
	report.shots[label] = {"eye": [eye.x, eye.y, eye.z], "rotation": [look.x, look.y], "clock": elapsed,
		"rain": rain, "underwater": submerged, "water_depth": depth if is_finite(depth) else null, "variants": modes}
	for version: String in modes:
		use_materials("before" if version == "before-repeat" else version)
		for i in 9:
			await RenderingServer.frame_post_draw
		var frame := view.get_texture().get_image()
		check(frame != null and frame.save_png(out.path_join(label + "-" + version + ".png")) == OK, "Captured " + label + " " + version)

func use_materials(version: String) -> void:
	for surface: MeshInstance3D in surfaces:
		var original := surfaces[surface]
		var program := "ocean" if original == terrain.coast.ocean_shader else "water"
		var shader: Shader = water_programs[version][program]
		var material := ShaderMaterial.new()
		material.shader = shader
		for field: Dictionary in original.shader.get_shader_uniform_list():
			var value: Variant = original.get_shader_parameter(field.name)
			if value != null:
				material.set_shader_parameter(field.name, value)
		if original == terrain.lake.lake_material and fixed_reflection != null:
			material.set_shader_parameter("shore_reflection", fixed_reflection)
		surface.material_override = material

func check(ok: bool, description: String) -> void:
	if ok:
		report.checks.append(description)
	else:
		report.errors.append(description)
		push_error(description)

func finish() -> void:
	var stats := FileAccess.open(out.path_join("native-rain-ripple-report.json"), FileAccess.WRITE)
	stats.store_string(JSON.stringify(report, "  ") + "\n")
	stats.close()
	print("WATER_RIPPLES_QA ", report.checks.size(), " passed and ", report.errors.size(), " failed")
	quit(0 if report.errors.is_empty() else 4)
