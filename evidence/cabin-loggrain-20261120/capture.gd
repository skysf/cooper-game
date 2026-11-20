extends SceneTree

const KIT := "res://props/construction/cabin_kit.json"
const VIEWS := [
	["built", Vector3(.22, 1.80, -.73), Vector3(0.0, 1.60, 3.2), 67.0],
	["inner-log", Vector3(.14, 1.57, -.64), Vector3(1.20, 1.48, .12), 59.0],
	["eaves", Vector3(-2.16, 2.68, 2.36), Vector3(-1.47, 2.73, 1.57), 48.0],
]
var stage := Node3D.new()
var camera := Camera3D.new()
var viewport := SubViewport.new()

func _initialize() -> void:
	run.call_deferred()

func v3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func part(record: Dictionary, position: Vector3, yaw: float) -> void:
	var node := (load(record.model) as PackedScene).instantiate() as Node3D
	stage.add_child(node)
	node.position = position
	node.rotation.y = yaw

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		quit(2)
		return
	var report := {}
	root.add_child(viewport)
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(stage)
	stage.add_child(camera)
	camera.near = .045
	camera.far = 30.0
	camera.make_current()
	var sky := WorldEnvironment.new()
	sky.environment = Environment.new()
	sky.environment.background_mode = Environment.BG_COLOR
	sky.environment.background_color = Color(.29, .34, .39)
	sky.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.environment.ambient_light_color = Color(.88, .93, 1.0)
	sky.environment.ambient_light_energy = .69
	sky.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(sky)
	var daylight := DirectionalLight3D.new()
	daylight.rotation_degrees = Vector3(-43.0, -34.0, 0.0)
	daylight.light_color = Color(1.0, .952, .88)
	daylight.light_energy = 1.26
	daylight.shadow_enabled = true
	daylight.directional_shadow_max_distance = 10.0
	stage.add_child(daylight)
	var reflected := OmniLight3D.new()
	reflected.position = Vector3(.46, 1.79, 1.8)
	reflected.light_color = Color(.95, .91, .83)
	reflected.light_energy = .58
	reflected.omni_range = 4.3
	stage.add_child(reflected)
	var soil := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(44.0, 44.0)
	var soil_material := StandardMaterial3D.new()
	soil_material.albedo_color = Color(.21, .24, .18)
	soil_material.roughness = .9
	plane.material = soil_material
	soil.mesh = plane
	soil.position.y = -.003
	stage.add_child(soil)
	var kit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(KIT))
	part(kit.pieces.cabin_floor, Vector3.ZERO, 0.0)
	for entry: Dictionary in kit.assembly.walls:
		part(kit.pieces[entry.kind], v3(entry.at), float(entry.yaw))
	part(kit.pieces.cabin_roof, v3(kit.assembly.roofAt), 0.0)
	for shot: Array in VIEWS:
		camera.position = shot[1]
		camera.look_at(shot[2])
		camera.fov = shot[3]
		for frame in 4:
			await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image()
		var filename: String = args[0].path_join(shot[0] + ".png")
		var state := pixels.save_png(filename)
		if state != OK:
			push_error("Capture failed for " + filename)
			quit(3)
			return
		report[shot[0]] = filename
	print("CABIN_CAPTURE ", JSON.stringify(report))
	quit()
