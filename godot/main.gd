extends Node3D

var config: Dictionary
var weather: Dictionary
var variant: Dictionary
var camera := Camera3D.new()
var world := Environment.new()
var sun := DirectionalLight3D.new()
var rain := MultiMeshInstance3D.new()
var rain_material := ShaderMaterial.new()
var weather_materials: Array[Dictionary] = []
var previous_wet := -1.0
var previous_road := -1.0
var web_controller
var is_web := OS.has_feature("web")
var first_draw := false
var native_clock := 0.0
var native_rain_override := -1
var native_wet := 0.0
var heading := 0.0
var pitch := -0.09
var native_bench := false
var native_label := Label.new()
var native_frames := [[], []]
var native_previous := 0
var native_previous_time := 0.0
var native_zero := 0

func _ready() -> void:
	get_viewport().mesh_lod_threshold = 0.0
	config = JSON.parse_string(FileAccess.get_file_as_string("res://shared/scene.json"))
	weather = config.weather
	variant = weather.storm if "--storm" in OS.get_cmdline_user_args() else weather.base
	var packed := ResourceLoader.load("res://shared/woodland.glb") as PackedScene
	if packed == null:
		push_error("Shared woodland.glb import failed")
		set_process(false)
		return
	var forest := packed.instantiate()
	add_child(forest)
	for item in forest.find_children("*", "MeshInstance3D", true, false):
		var tree_mesh: MeshInstance3D = item
		if tree_mesh.mesh == null:
			continue
		for index in tree_mesh.mesh.get_surface_count():
			var mat := tree_mesh.get_active_material(index) as BaseMaterial3D
			if mat == null:
				continue
			# The glTF file supplies linear COLOR_0 for foliage pigment and contact shade.
			mat.vertex_color_use_as_albedo = true
			if mat.resource_name.to_lower() not in ["mud", "rock"]:
				continue
			if not mat.has_meta("rain_surface"):
				mat.set_meta("rain_surface", true)
				weather_materials.append({"surface": mat, "kind": mat.resource_name.to_lower(), "color": mat.albedo_color, "rough": mat.roughness})
	add_child(camera)
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = config.render.horizontalFov
	camera.near = config.render.near
	camera.far = config.render.far
	camera.current = true
	var first: Array = config.route[0]
	camera.position = Vector3(first[1], config.player.eye, first[2])
	_setup_weather()
	if is_web:
		web_controller = JavaScriptBridge.get_interface("Wood")
	else:
		native_bench = "--bench" in OS.get_cmdline_user_args()
		var overlay := CanvasLayer.new()
		add_child(overlay)
		overlay.add_child(native_label)
		native_label.position = Vector2(20, 18)
		native_label.add_theme_constant_override("outline_size", 5)
		native_label.add_theme_color_override("font_outline_color", Color("#1c2825"))
		native_label.text = "雨后林地   ·   Godot / macOS\n点击进入 · WASD 行走 · R 天气 · Esc 释放"
	RenderingServer.frame_post_draw.connect(_after_draw)

func _rgb(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])

func _setup_weather() -> void:
	var world_node := WorldEnvironment.new()
	world_node.environment = world
	add_child(world_node)
	world.background_mode = Environment.BG_COLOR
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color.WHITE
	world.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	world.fog_enabled = true
	world.fog_mode = Environment.FOG_MODE_DEPTH
	world.fog_density = 1.0
	world.fog_sky_affect = 0.0
	add_child(sun)
	var d: Array = config.sunDirection
	sun.look_at(Vector3(d[0], d[1], d[2]), Vector3.UP)
	sun.shadow_enabled = false
	_setup_rain()
	_weather_blend(0, variant.wetRoad, variant.wetRock, variant.darken)

func _seed(i: int, k: float) -> float:
	return fposmod(sin((i + 1) * k) * 43758.5453, 1.0)

func _setup_rain() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never;
uniform float distance_fallen;
uniform float opacity;
uniform vec4 shelter; // center XZ, half width and depth
varying vec3 world_position;
void vertex() {
	vec3 offset = INSTANCE_CUSTOM.xyz;
	float y = mod(offset.y * 10.0 - distance_fallen, 10.0) - 2.0;
	VERTEX += vec3((offset.x - 0.5) * 16.0 + VERTEX.y * 0.11, y, (offset.z - 0.5) * 16.0);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (all(lessThan(abs(world_position.xz - shelter.xy), shelter.zw)) && world_position.y < 2.7) {
		discard;
	}
	ALBEDO = vec3(0.71, 0.81, 0.86);
	ALPHA = 0.44 * opacity;
}
"""
	rain_material.shader = shader
	var shelter: Dictionary = config.shelter
	rain_material.set_shader_parameter("shelter", Vector4(shelter.x, shelter.z, shelter.width * 0.5, shelter.depth * 0.5))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.18)
	quad.material = rain_material
	var particles := MultiMesh.new()
	particles.transform_format = MultiMesh.TRANSFORM_3D
	particles.use_custom_data = true
	particles.mesh = quad
	particles.instance_count = maxi(weather.storm.drops, weather.base.drops)
	for i in particles.instance_count:
		particles.set_instance_transform(i, Transform3D.IDENTITY)
		particles.set_instance_custom_data(i, Color(_seed(i, 12.9898), _seed(i, 78.233), _seed(i, 37.719), 1.0))
	particles.custom_aabb = AABB(Vector3(-9, -3, -9), Vector3(18, 13, 18))
	rain.multimesh = particles
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)

func _weather_blend(wet: float, wet_road: float, wet_rock: float, darken: float) -> void:
	if wet == previous_wet and previous_road == wet_road:
		return
	previous_wet = wet
	previous_road = wet_road
	var clear: Dictionary = weather.clear
	var cloudy: Dictionary = weather.rain
	world.background_color = _rgb(clear.sky).lerp(_rgb(cloudy.sky), wet)
	world.fog_light_color = _rgb(clear.fog).lerp(_rgb(cloudy.fog), wet)
	world.fog_depth_begin = lerpf(clear.fogNear, cloudy.fogNear, wet)
	world.fog_depth_end = lerpf(clear.fogFar, cloudy.fogFar, wet)
	world.ambient_light_energy = lerpf(clear.ambient, cloudy.ambient, wet)
	sun.light_color = _rgb(clear.sun).lerp(_rgb(cloudy.sun), wet)
	sun.light_energy = lerpf(clear.direct, cloudy.direct, wet)
	for entry in weather_materials:
		var mat: BaseMaterial3D = entry.surface
		var tint: Color = entry.color
		var scale_color := 1.0 - wet * darken
		mat.albedo_color = Color(tint.r * scale_color, tint.g * scale_color, tint.b * scale_color, tint.a)
		mat.roughness = lerpf(entry.rough, wet_road if entry.kind == "mud" else wet_rock, wet)
	rain_material.set_shader_parameter("opacity", wet)
	rain.visible = wet > 0.0

func _process(delta: float) -> void:
	var state
	if is_web:
		if web_controller == null:
			return
		state = web_controller.step()
		if state == null:
			return
	else:
		state = _native_step(delta)
	camera.position = Vector3(state.x, state.y, state.z)
	camera.rotation = Vector3(state.pitch, -state.yaw, 0)
	_weather_blend(state.wet, state.wetRoad, state.wetRock, state.darken)
	rain.position = camera.position
	# The quad spans the camera's horizontal direction at every yaw.
	rain.rotation.y = -state.yaw
	rain.multimesh.visible_instance_count = clampi(int(state.drops), 0, rain.multimesh.instance_count)
	rain_material.set_shader_parameter("distance_fallen", float(state.time) * float(state.speed))

func _after_draw() -> void:
	if is_web:
		if web_controller == null:
			return
		if not first_draw:
			first_draw = true
			web_controller.ready()
		web_controller.frame()
		return
	var now := Time.get_ticks_usec()
	if not first_draw:
		first_draw = true
		native_zero = now
		native_previous = now
		print("NATIVE_READY ", JSON.stringify({"engine_ms": now / 1000.0, "viewport": [get_viewport().size.x, get_viewport().size.y], "adapter": RenderingServer.get_video_adapter_name(), "wet_materials": weather_materials.size()}))
	elif native_bench:
		var phase := int(native_previous_time >= float(weather.switchAt))
		if phase == int(native_clock >= float(weather.switchAt)) and native_previous_time < float(weather.duration):
			native_frames[phase].append((now - native_previous) / 1000.0)
		native_previous = now
		native_previous_time = native_clock
		if native_clock >= float(weather.duration):
			print("NATIVE_RESULT ", JSON.stringify({"clear": _summary(native_frames[0]), "rain": _summary(native_frames[1])}))
			native_bench = false
			get_tree().quit()

func _summary(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {}
	samples.sort()
	return {"frames": samples.size(), "fps": 1000.0 * samples.size() / float(samples.reduce(func(a, b): return a + b, 0.0)), "p95_ms": samples[ceili(samples.size() * 0.95) - 1]}

func _route_at(t: float) -> Vector2:
	var route: Array = config.route
	for i in range(1, route.size()):
		var prev: Array = route[i - 1]
		var next: Array = route[i]
		if t <= next[0]:
			var alpha := clampf((t - prev[0]) / (next[0] - prev[0]), 0, 1)
			return Vector2(lerpf(prev[1], next[1], smoothstep(0.0, 1.0, alpha)), lerpf(prev[2], next[2], alpha))
	var end: Array = route.back()
	return Vector2(end[1], end[2])

func _native_step(delta: float) -> Dictionary:
	var point := Vector2(camera.position.x, camera.position.z)
	if native_bench:
		native_clock = (Time.get_ticks_usec() - native_zero) / 1000000.0 if first_draw else 0.0
		point = _route_at(native_clock)
		var direction := _route_at(minf(native_clock + 0.9, weather.duration)) - _route_at(maxf(0, native_clock - 0.15))
		if direction.length_squared() > 0.0001:
			heading = atan2(direction.x, -direction.y)
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		native_clock += minf(delta, 0.1)
		var keys := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		var motion := keys.normalized().rotated(heading) * float(config.player.speed) * minf(delta, 0.1)
		point = _slide(point, motion)
	var wet_target := float(native_clock >= float(weather.switchAt))
	if native_rain_override >= 0:
		wet_target = native_rain_override
	native_wet = move_toward(native_wet, wet_target, delta / float(weather.transition))
	return {"x": point.x, "y": config.player.eye, "z": point.y, "yaw": heading, "pitch": pitch, "wet": native_wet, "time": native_clock, "drops": variant.drops, "speed": variant.speed, "darken": variant.darken, "wetRoad": variant.wetRoad, "wetRock": variant.wetRock}

func _free_at(point: Vector2) -> bool:
	for obstacle in config.obstacles:
		var clearance: float = obstacle.r + config.player.radius
		if point.distance_squared_to(Vector2(obstacle.x, obstacle.z)) < clearance * clearance:
			return false
	return true

func _slide(point: Vector2, motion: Vector2) -> Vector2:
	var floor_box: Dictionary = config.ground
	var min_corner := Vector2(floor_box.x0 + 1, floor_box.z0 + 1)
	var max_corner := Vector2(floor_box.x0 + (floor_box.columns - 1) * floor_box.step - 1, floor_box.z0 + (floor_box.rows - 1) * floor_box.step - 1)
	var steps := maxi(1, ceili(motion.length() / 0.12))
	for i in steps:
		var next := (point + motion / steps).clamp(min_corner, max_corner)
		if _free_at(Vector2(next.x, point.y)):
			point.x = next.x
		if _free_at(Vector2(point.x, next.y)):
			point.y = next.y
	return point

func _unhandled_input(event: InputEvent) -> void:
	if is_web or native_bench:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		heading += event.relative.x * float(config.player.mouse)
		pitch = clampf(pitch - event.relative.y * float(config.player.mouse), -1.35, 1.35)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_R:
				native_rain_override = 0 if native_wet > 0.5 else 1
