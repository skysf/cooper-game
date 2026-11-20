extends SceneTree

const Terrain = preload("res://terrain.gd")
const Atmosphere = preload("res://atmosphere.gd")
const Rules = preload("res://rules.gd")

var view := SubViewport.new()
var terrain := Terrain.new()
var atmosphere := Atmosphere.new()
var camera := Camera3D.new()
var directory := ""
var report := {}
var valid := true

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		quit(2)
		return
	directory = args[0]
	view.size = Vector2i(1280,720)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(atmosphere)
	view.add_child(terrain)
	terrain.set_process(false)
	view.add_child(camera)
	camera.near = 0.055
	camera.far = 105.0
	camera.make_current()
	aim(Vector3(2.22,.47,-84.18),Vector3(1.82,.07,-80.82),65.0)
	for id in ["camp","approach"]:
		var packet := args[1].path_join(id+".glb")
		if FileAccess.file_exists(packet):
			terrain._parse_chunk(id,FileAccess.get_file_as_bytes(packet))
	check(terrain.loaded.has("camp") and terrain.loaded.has("approach"),"Live camp and approach chunks were loaded")
	terrain.grove.set_room_time(88.0)
	var scope := {"mud":0,"rock":0}
	var maps := {}
	for chunk: Node3D in terrain.loaded.values():
		for surface: MeshInstance3D in chunk.find_children("*","MeshInstance3D",true,false):
			var key := String(surface.name).get_slice("__",0)
			if scope.has(key):
				scope[key] += 1
				var surface_material := surface.material_override as ShaderMaterial
				check(surface_material == terrain.ground_materials[key], "Streamed " + key + " uses its matching shader")
				if not maps.has(key):
					var source: StandardMaterial3D = terrain.materials[key]
					check(surface_material.get_shader_parameter("ground_color") == source.albedo_texture
						and surface_material.get_shader_parameter("ground_normal") == source.normal_texture
						and surface_material.get_shader_parameter("surface_data") == source.roughness_texture,
						"Original color, normal and ARM use the same imported textures")
					maps[key] = [source.albedo_texture.resource_path, source.normal_texture.resource_path,
						source.roughness_texture.resource_path]
	check(scope.mud > 0 and scope.rock > 0,"Actual mud and rock surfaces tested")
	report["scope"] = scope
	report["textures"] = maps

	freeze_light(53.0,0.0)
	set_ground(53.0)
	await shot("trail-dry",12)
	set_ground(94.5)
	await shot("trail-wet-frozen-light",9)
	freeze_light(94.5,1.0)
	set_ground(94.5)
	await shot("trail-storm",10)
	for t in [119.0,128.0,143.0,172.0]:
		set_ground(t)
		await shot("trail-dryout-%d" % int(t),7)

	aim(Vector3(-.88, .82,-77.61),Vector3(-2.489,.48,-76.0),59.0)
	freeze_light(53.0,0.0)
	set_ground(53.0)
	await shot("rock-dry",10)
	set_ground(94.5)
	await shot("rock-wet-frozen-light",8)
	freeze_light(94.5,1.0)
	set_ground(94.5)
	await shot("rock-storm",8)
	report["camera_trail"] = [2.22,.47,-84.18]
	report["camera_rock"] = [-.88,.82,-77.61]
	var stop: float = report["119.0"].materials.mud.retained
	var later: float = report["128.0"].materials.mud.retained
	var late: float = report["143.0"].materials.mud.retained
	check(0.25 < stop and stop > later and later > late and late > 0.0, "Retained moisture dries gradually once the real rain stops")
	check(report["172.0"].materials.mud.retained == 0.0, "The dry phase returns to the original material")
	check(report["119.0"].materials.mud.film == 0.0, "Rain film ends before the soaked ground dries")
	set_ground(128.0)
	check(is_equal_approx(report["128.0"].materials.mud.retained, later), "Seeking to a drying room time is deterministic")
	report["water_scene_included"] = false
	print("GROUND_MOISTURE_QA " + JSON.stringify(report))
	quit(0 if valid else 4)

func aim(at: Vector3, target: Vector3, fov: float) -> void:
	camera.position = at
	camera.fov = fov
	camera.look_at(target)
	terrain.update_focus(at)

func freeze_light(elapsed: float, rain: float) -> void:
	atmosphere.update_weather(camera.position,elapsed,rain,false)
	atmosphere.rain.hide()

func set_ground(elapsed: float) -> void:
	var rain := Rules.rain_at(elapsed)
	terrain.set_wet(rain)
	terrain.update_water(elapsed,rain,{
		"sun_direction":atmosphere.sun_direction,"moon_direction":atmosphere.moon_direction,
		"sun_energy":atmosphere.sun_energy,"sky_zenith":atmosphere.sky_zenith,
		"sky_horizon":atmosphere.sky_horizon,"sun_color":atmosphere.sun_color,"moon_color":atmosphere.moon_color,
		"cloud_cover":atmosphere.cloud_cover,"twilight":atmosphere.twilight,
		"evening_weight":atmosphere.evening_weight,"underwater":atmosphere.underwater})
	var readings := {}
	for key in ["mud","rock"]:
		var material: ShaderMaterial = terrain.ground_materials[key]
		var moisture: Vector2 = material.get_shader_parameter("moisture") if rain > 0.0 or elapsed >= 119.0 else Vector2.ZERO
		readings[key] = {"type":"ShaderMaterial","retained":moisture.x,"film":moisture.y}
	report[str(elapsed)] = {"rain":rain,"materials":readings}

func shot(label: String, frames: int) -> void:
	for frame in frames:
		await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	check(image != null and image.save_png(directory.path_join(label+".png")) == OK,"Saved " + label)

func check(ok: bool, text: String) -> void:
	if not ok:
		valid = false
		push_error(text)
