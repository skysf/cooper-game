extends SceneTree

const Terrain = preload("res://terrain.gd")
const Atmosphere = preload("res://atmosphere.gd")
const Mines = preload("res://mines_layout.gd")
const MinesScene = preload("res://mines_scene.gd")
const Lake = preload("res://lake_layout.gd")
const PlacementWorld = preload("res://placement_world.gd")
const WindField = preload("res://vegetation/wind_field.gd")

var view := SubViewport.new()
var terrain := Terrain.new()
var atmosphere := Atmosphere.new()
var camera := Camera3D.new()
var folder := ""
var report := {}
var valid := true

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		quit(2)
		return
	folder = args[0]
	view.size = Vector2i(1280, 720)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(atmosphere)
	view.add_child(terrain)
	view.add_child(MinesScene.new())
	terrain.set_process(false)
	view.add_child(camera)
	camera.near = 0.045
	camera.far = 147.0
	camera.make_current()

	aim(Vector3(1.42, 1.66, -90.88), Vector3(1.30, 1.37, -85.55), 70.0)
	for id in ["camp", "approach", "creek"]:
		var packet := args[1].path_join(id + ".glb")
		if FileAccess.file_exists(packet):
			terrain._parse_chunk(id, FileAccess.get_file_as_bytes(packet))
	check(terrain.loaded.has("camp") and terrain.loaded.has("approach"), "Production camp and approach chunks")
	terrain.grove.set_room_time(88.0)
	terrain.set_quest(true,true,true)
	weather(94.5, true)
	check(rows() == 3, "The repaired roof has two wooden slopes and the canvas patch")
	await pair("camp")
	terrain.set_quest(false,false,false)
	weather(94.5, false)
	check(rows() == 0, "The unrepaired legacy shelter allows rain")
	await shot("camp-unrepaired", 6)

	var yaw := 0.48
	var rotation := Basis(Vector3.UP, yaw)
	var center := Vector3(9.8, Lake.walk_height(Vector2(9.8,-82.2)), -82.2)
	var cabin := Node3D.new()
	view.add_child(cabin)
	var kit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://props/construction/cabin_kit.json"))
	instanced_piece(kit, "cabin_floor", cabin, Transform3D(rotation, center))
	for spec: Dictionary in kit.assembly.walls:
		var offset := Mines.vector(spec.at)
		instanced_piece(kit, spec.kind, cabin, Transform3D(Basis(Vector3.UP,yaw + float(spec.yaw)),
			center + rotation * offset))
	var roof_origin := center + rotation * Mines.vector(kit.assembly.roofAt)
	var roof := instanced_piece(kit,"cabin_roof",cabin,Transform3D(rotation,roof_origin))
	var roof_record := {"kind":"cabin_roof","at":[roof_origin.x,roof_origin.y,roof_origin.z],
		"yaw":yaw,"rotation":quaternion_values(rotation.get_rotation_quaternion()),"mode":"ground"}
	aim(center + rotation * Vector3(.22,1.80,-.73),center + rotation * Vector3(0.0,1.60,3.2),67.0)
	atmosphere.set_rain_roofs({"test-roof":roof_record})
	weather(94.5,false)
	check(rows() == 2, "The placed house uses two sloped panels from the cabin kit")
	check(PlacementWorld.pose(roof_record).is_equal_approx(roof.transform), "The visual roof and proxy use the same pose")
	await pair("built")

	# Carry removes a placed occluder before the item takes on the hand pose.
	var held := roof_record.duplicate(true)
	held.mode = "held"
	atmosphere.set_rain_roofs({"test-roof":held})
	roof.hide()
	weather(94.5,false)
	check(rows() == 0, "The carried roof no longer blocks rain at its old position")
	await shot("built-carried",8)

	var shifted := Vector3(5.7, 0.0, 0.65)
	var destination := roof_origin + shifted
	var tilted := Basis.from_euler(Vector3(0.14, 0.73, -0.08))
	var moved := roof_record.duplicate(true)
	moved.at = [destination.x,destination.y,destination.z]
	moved.yaw = 0.73
	moved.rotation = quaternion_values(tilted.get_rotation_quaternion())
	atmosphere.set_rain_roofs({"test-roof":moved})
	roof.transform = PlacementWorld.pose(moved)
	roof.show()
	weather(94.5,false)
	check(rows() == 2, "The moved and tilted roof is repacked")
	await pair("old-site")
	aim(destination + Vector3(0.25,-.83,-.60),destination + Vector3(-1.2,-.72,4.0),72.0)
	weather(94.5,false)
	await pair("tilted")
	atmosphere.set_rain_roofs({})
	roof.queue_free()
	weather(94.5,false)
	check(rows() == 0, "Disassembling removes the rain cover")
	await shot("tilted-removed",7)
	cabin.queue_free()

	for id: String in Mines.data:
		var pose := Mines.pose(id)
		var floor := mine_floor_at(id,1.80)
		var outdoor := mine_floor_at(id,-3.3)
		aim(pose * Vector3(float(floor[2]), float(floor[1])+1.63,1.80),
			pose * Vector3(0.0,float(outdoor[1])+1.20,-5.3), 72.0)
		weather(94.5,false)
		check(rows() >= 20 and rows() <= 120, "Nearby stone shell packed for " + id)
		await pair(id)
		if id == "iron_mine":
			# On the actual open ramp, the rain remains visible. The tunnel itself
			# stays a geometry shadow along the same wind direction.
			aim(pose * Vector3(0.0,float(outdoor[1])+1.63,-3.3),
				pose * Vector3(0.0,float(outdoor[1])+1.20,-6.2), 66.0)
			weather(94.5,false)
			await pair("mine-open-slope")

	aim(Vector3(0.5,1.70,-61.5),Vector3(-1.3,1.52,-48.0),68.0)
	weather(94.5,false)
	check(rows() == 0,"Open forest takes the ordinary precipitation path")
	await pair("open-outside")
	# Keep the optical camera and room time still to isolate motion of the
	# emitter window. The interior drops must retain their screen positions.
	atmosphere.update_weather(camera.position + Vector3(0.56, 0.29, -0.21),94.5,1.0,false)
	await shot("open-shifted-focus",8)
	atmosphere.update_weather(camera.position,94.5 + 1.0 / 60.0,1.0,false)
	await shot("open-next-frame",8)
	check(not weather(94.5,false,0.0),"Dry weather keeps rain hidden")
	atmosphere.update_weather(camera.position,94.5,1.0,false,true,.75)
	check(not atmosphere.rain.visible,"Submerged camera keeps rain hidden")
	print("RAIN_SHELTER_QA " + JSON.stringify(report))
	quit(0 if valid else 4)

func quaternion_values(q: Quaternion) -> Array:
	return [q.x,q.y,q.z,q.w]

func instanced_piece(kit: Dictionary, key: String, root: Node3D, pose: Transform3D) -> Node3D:
	var model: Node3D = (load(kit.pieces[key].model) as PackedScene).instantiate()
	model.transform = pose
	root.add_child(model)
	return model

func mine_floor_at(id: String, depth: float) -> Array:
	var floor: Array = Mines.data[id].floor
	for station: Array in floor:
		if float(station[0]) >= depth:
			return station
	return floor.back()

func aim(at: Vector3, target: Vector3, fov: float) -> void:
	camera.position = at
	camera.fov = fov
	camera.look_at(target)
	terrain.update_focus(at)

func rows() -> int:
	return int(atmosphere.streaks.get_shader_parameter("shelter_rows"))

func weather(elapsed: float, repaired: bool, wet := 1.0) -> bool:
	var eye := camera.position
	var depth := Lake.surface_height(Vector2(eye.x,eye.z)) - eye.y
	atmosphere.update_weather(eye,elapsed,wet,repaired,false,depth,0.9 if eye.x < -60 else 0.0)
	terrain.set_wet(wet)
	terrain.update_water(elapsed,wet,{
		"sun_direction":atmosphere.sun_direction,"moon_direction":atmosphere.moon_direction,
		"sun_energy":atmosphere.sun_energy,"sky_zenith":atmosphere.sky_zenith,
		"sky_horizon":atmosphere.sky_horizon,"sun_color":atmosphere.sun_color,"moon_color":atmosphere.moon_color,
		"cloud_cover":atmosphere.cloud_cover,"twilight":atmosphere.twilight,"evening_weight":atmosphere.evening_weight,
		"underwater":atmosphere.underwater})
	return atmosphere.rain.visible

func pair(label: String) -> void:
	var count := rows()
	var field: Vector4 = atmosphere.streaks.get_shader_parameter("wind_field")
	check(field.is_equal_approx(WindField.sample(94.5,1.0)), "Rain shares the world wind at " + label)
	var slope := WindField.at_point(field,94.5,Vector2(camera.position.x,camera.position.z)) * 0.21
	report[label] = {"cover_boxes":count,"position":[camera.position.x,camera.position.y,camera.position.z],
		"world_rain_slope_at_eye":[slope.x,slope.y]}
	atmosphere.streaks.set_shader_parameter("shelter_rows",0)
	await shot(label+"-no-cover",10)
	atmosphere.streaks.set_shader_parameter("shelter_rows",count)
	await shot(label+"-covered",6)
	atmosphere.rain.hide()
	await shot(label+"-dry-reference",6)
	atmosphere.rain.show()

func shot(name: String, frames: int) -> void:
	for i in frames:
		await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	check(image != null and image.save_png(folder.path_join(name + ".png")) == OK, "Saved " + name)

func check(ok: bool, message: String) -> void:
	if not ok:
		valid = false
		push_error(message)
