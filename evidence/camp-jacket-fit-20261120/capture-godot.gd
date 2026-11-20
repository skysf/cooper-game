extends SceneTree

const Hiker = preload("res://hiker.gd")
const Clothing = preload("res://clothing.gd")
const Preview = preload("res://character_preview.gd")
const Survival = preload("res://survival.gd")
const DT := 1.0 / 60.0
var stage := SubViewport.new()
var camera := Camera3D.new()
var avatar: Hiker
var portrait_light: Environment
var lamps: Array[DirectionalLight3D] = []
var destination := ""
var frames := []

func _initialize() -> void:
	_show.call_deferred()

func _show() -> void:
	destination = OS.get_cmdline_user_args()[0]
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		quit(2)
		return
	stage.size = Vector2i(800,720)
	stage.own_world_3d = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.msaa_3d = Viewport.MSAA_4X
	root.add_child(stage)
	stage.add_child(camera)
	camera.make_current()
	_studio()
	_new_avatar()
	_camera(Vector3(0,0.90,0),Vector3(0.38,0.22,-2.55),2.04)
	await _photo(stage,"stand-full")
	_camera(Vector3(0,1.20,0),Vector3(0.88,0.20,-2.47),0.88)
	await _photo(stage,"stand-front")
	_camera(Vector3(0,1.20,0),Vector3(-0.88,0.39,2.47),0.88)
	await _photo(stage,"stand-back")
	avatar.holding = true
	for i in 15:
		avatar.advance(DT,false)
	_camera(Vector3(0.04,1.192,-0.13),Vector3(1.27,0.36,-2.50),0.95)
	await _photo(stage,"remote-holding")
	_new_avatar()
	_recovery("rise",0.55)
	_camera(Vector3(0,0.86,0.02),Vector3(1.03,0.36,-2.43),1.24)
	await _photo(stage,"recovery-knee")
	_new_avatar()
	_recovery("down",0.90)
	_camera(Vector3(0,0.26,0.32),Vector3(1.5,1.60,-2.19),1.93)
	await _photo(stage,"recovery-down")
	_new_avatar()
	portrait_light.background_color = Color("#222b35")
	portrait_light.ambient_light_color = Color("#b2c7da")
	portrait_light.ambient_light_energy = 0.23
	lamps[0].light_energy = 0.31
	lamps[1].light_energy = 0.17
	_camera(Vector3(0,1.20,0),Vector3(0.88,0.20,-2.47),0.88)
	await _photo(stage,"dark-front")
	_camera(Vector3(0,1.20,0),Vector3(-0.88,0.39,2.47),0.88)
	await _photo(stage,"dark-back")
	portrait_light.ambient_light_color = Color("#dee7eb")
	portrait_light.background_color = Color("#334043")
	portrait_light.ambient_light_energy = 0.66
	lamps[0].light_energy = 0.84
	lamps[1].light_energy = 0.36
	_camera(Vector3(0,0.90,0),Vector3(0.38,0.22,-2.55),2.04)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 55.0
	camera.position = Vector3(0.50,1.70,-7.2)
	camera.look_at(Vector3(0,0.90,0))
	await _photo(stage,"stand-distant")
	avatar.free()
	var drop := Clothing.on_ground("jacket")
	stage.add_child(drop)
	_camera(Vector3(0,0.06,0),Vector3(-0.65,1.20,-1.25),0.69)
	await _photo(stage,"ground")
	drop.free()
	var preview := Preview.new()
	root.add_child(preview)
	preview.update_character(Survival.initial_wear(),false,1)
	preview.view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await _photo(preview.view,"wardrobe")
	preview.update_character({"cap":true,"pants":true},false,1)
	preview.view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await _photo(preview.view,"wardrobe-removed")
	preview.free()
	var report := FileAccess.open(destination.path_join("views.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"frames":frames,"driver":RenderingServer.get_video_adapter_name(),
		"source":FileAccess.get_sha256("res://props/camp_jacket.glb"),
		"runtime":FileAccess.get_sha256("res://hiker.gd")},"  "))
	report.close()
	quit(0 if frames.size() == 12 else 1)

func _new_avatar() -> void:
	if is_instance_valid(avatar):
		avatar.free()
	avatar = Hiker.new()
	stage.add_child(avatar)
	avatar.outfit(2)
	avatar.wear_clothes(Survival.initial_wear())

func _recovery(which: String, at: float) -> void:
	var get_up := which == "rise"
	avatar.set_recovery_state({"health":50.0 if get_up else 0.0,"downAt":-1.0 if get_up else 20.0,
		"revivedAt":20.0 if get_up else -1.0},20.0+at)
	avatar.advance(DT,false)

func _camera(focus: Vector3, offset: Vector3, size: float) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = focus+offset
	camera.look_at(focus)
	camera.size = size
	camera.near = 0.02
	camera.far = 35.0

func _photo(view: SubViewport, name: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	var sample := view.get_texture().get_image()
	if sample != null and sample.save_png(destination.path_join(name+".png")) == OK:
		frames.append(name)
	else:
		push_error("Could not save "+name)

func _studio() -> void:
	var world := WorldEnvironment.new()
	var light := Environment.new()
	portrait_light = light
	light.background_mode = Environment.BG_COLOR
	light.background_color = Color("#334043")
	light.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	light.ambient_light_color = Color("#dee7eb")
	light.ambient_light_energy = 0.66
	world.environment = light
	stage.add_child(world)
	for setting: Array in [[Vector3(-45,-33,0),"#fff5e8",0.84],[Vector3(-25,158,0),"#d8efff",0.36]]:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = setting[0]
		sun.light_color = Color(setting[1])
		sun.light_energy = setting[2]
		stage.add_child(sun)
		lamps.append(sun)
	var floor_node := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(4.6,4.6)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#48524b")
	material.roughness = 0.94
	floor_mesh.material = material
	floor_node.mesh = floor_mesh
	floor_node.position.y = -0.004
	stage.add_child(floor_node)
