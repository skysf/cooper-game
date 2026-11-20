extends SceneTree

const Atmosphere = preload("res://atmosphere.gd")
const Lake = preload("res://lake_layout.gd")
const Survival = preload("res://survival.gd")
const Storage = preload("res://camp_storage.gd")
const KIT := "res://props/construction/cabin_kit.json"
var viewport := SubViewport.new()
var sky := Atmosphere.new()
var camera := Camera3D.new()
var room := Node3D.new()
var screen_dir := ""
var checks := {}
var site: Vector3
var outside: Vector3
var invalid := false

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		quit(2)
		return
	screen_dir = args[0]
	viewport.size = Vector2i(840,630)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(sky)
	viewport.add_child(camera)
	camera.make_current()
	camera.near = .015
	camera.far = 42.0
	assemble()
	for ore: String in ["coal","iron_ore"]:
		for revision: String in ["baseline","candidate"]:
			await sequence(ore,revision)
	var file := FileAccess.open(screen_dir.path_join("proof.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(checks,"  "))
	file.close()
	quit(3 if invalid else 0)

func assemble() -> void:
	site = Vector3(9.8, Lake.walk_height(Vector2(9.8,-82.2))+.12, -82.2)
	viewport.add_child(room)
	var kit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(KIT))
	model(kit.pieces.cabin_floor.model,room).position = site
	for row: Dictionary in kit.assembly.walls:
		var part := model(kit.pieces[row.kind].model,room)
		part.position = site+v3(row.at)
		part.rotation.y = float(row.yaw)
	model(kit.pieces.cabin_roof.model,room).position = site+v3(kit.assembly.roofAt)
	model("res://props/camp_table.glb",room).position = site+Vector3(-.29,.18,-.37)
	var fill := SpotLight3D.new()
	fill.light_color = Color("#ffe2bc")
	fill.light_energy = 1.55
	fill.spot_range = 4.4
	fill.spot_angle = 52.0
	fill.position = site+Vector3(.09,1.39,1.20)
	room.add_child(fill)
	fill.look_at(site+Vector3(.25,.97,-.18))
	outside = site+Vector3(4.79,-.13,.63)
	var ground := MeshInstance3D.new()
	var coarse := PlaneMesh.new()
	coarse.size = Vector2(12.0,12.0)
	var terrain := StandardMaterial3D.new()
	terrain.albedo_color = Color(.75,.78,.77)
	terrain.albedo_texture = load("res://textures/lake_gravel_diff.jpg")
	terrain.normal_enabled = true
	terrain.normal_texture = load("res://textures/lake_gravel_nor_gl.jpg")
	terrain.normal_scale = .71
	terrain.roughness = .58
	terrain.uv1_scale = Vector3(14.,14.,1.)
	coarse.material = terrain
	ground.mesh = coarse
	viewport.add_child(ground)
	ground.position = outside+Vector3.DOWN*.001

func sequence(ore: String, revision: String) -> void:
	var resource: String = Storage.ITEM_MODELS[ore]
	var used := resource if revision=="candidate" else resource.trim_suffix(".glb")+"-baseline.glb"
	var prop := model(used,viewport)
	var case_name := revision+"-"+ore
	var worktop := site+Vector3(.16,.97,-.18)
	var record := Survival.provision(ore,worktop,"table")
	prop.position = v3(record.at)
	prop.rotation.y = -.29
	aim(worktop+Vector3(.555,.393,.540),worktop+Vector3(0.,.071,0.),36.,false)
	await shot(case_name+"-table")
	aim(worktop+Vector3(-.268,.198,.322),worktop+Vector3(0.,.073,0.),32.,false)
	await shot(case_name+"-arm")
	record = Survival.provision(ore,outside,"ground")
	prop.position = v3(record.at)
	aim(outside+Vector3(.32,.594,.365),outside+Vector3(0.,.061,0.),42.,true)
	await shot(case_name+"-rain")
	var mesh := prop as MeshInstance3D if prop is MeshInstance3D else prop.find_child("*",true,false) as MeshInstance3D
	var bounds := mesh.get_aabb()
	if absf(bounds.position.y)>.00001 or not prop.position.is_equal_approx(outside):
		invalid = true
		push_error("The production model must keep its grounded origin and provision coordinates.")
	checks[case_name] = {"productionPath":resource,"visualMin": arr(bounds.position), "visualSize":arr(bounds.size),
		"tableProvisionPosition":arr(worktop),"groundProvisionPosition": record.at,"sameFileShapeOnBothSurfaces":true}
	prop.free()

func model(path: String, parent: Node) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	parent.add_child(node)
	return node

func aim(active: Vector3,target: Vector3,fov: float, rain: bool) -> void:
	camera.position = active
	camera.look_at(target)
	camera.fov = fov
	sky.update_weather(active,94.5 if rain else 43.0,1.0 if rain else 0.0,false)
	if not rain:
		sky.rain.hide()

func shot(label: String) -> void:
	for i in 7:
		await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.save_png(screen_dir.path_join(label+".png")) != OK:
		invalid = true
		push_error("Could not capture "+label)

func v3(row: Array) -> Vector3:
	return Vector3(float(row[0]),float(row[1]),float(row[2]))
func arr(v: Vector3) -> Array:
	return [v.x,v.y,v.z]
