extends SceneTree

const Terrain = preload("res://terrain.gd")
const Atmosphere = preload("res://atmosphere.gd")
const StorageScene = preload("res://camp_storage_scene.gd")
const Lake = preload("res://lake_layout.gd")

var view := SubViewport.new()
var camera := Camera3D.new()
var terrain := Terrain.new()
var atmosphere := Atmosphere.new()
var props := StorageScene.new()
var folder := ""
var fire_at := Vector3(4.75, 0.0, -82.85)
var records := {}
var passes := 0
var failures := 0

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
	view.add_child(props)
	terrain.set_process(false)
	view.add_child(camera)
	fire_at.y = Lake.walk_height(Vector2(fire_at.x, fire_at.z))
	camera.position = fire_at + Vector3(1.18, 1.0, -1.26)
	camera.look_at(fire_at + Vector3.UP * 0.29)
	camera.fov = 50.0
	camera.make_current()
	terrain.update_focus(camera.position)
	var chunk := FileAccess.get_file_as_bytes(args[1])
	terrain._parse_chunk("camp", chunk)
	_check(terrain.loaded.has("camp"), "Loaded the actual camp terrain")
	records = {"fire": {"at":[fire_at.x, fire_at.y, fire_at.z],"yaw":0.0,
		"kind":"campfire", "mode":"ground", "fuelUntil":120.0}}
	for i in 100:
		_update(97.4, 1.0)
		if props.live.has("fire"):
			break
		await process_frame
	if not props.live.has("fire"):
		quit(3)
		return
	var entry: Dictionary = props.live.fire
	for scene: Array in [["rain", 97.4, 1.0], ["night", 190.0, 0.0]]:
		var elapsed: float = scene[1]
		records.fire.fuelUntil = elapsed + 30.0
		_weather(elapsed, scene[2])
		_update(elapsed, scene[2])
		await _shot(scene[0] + "-current")
		if scene[0] == "rain":
			terrain.grass.set_ground_cover({}, camera.position)
			await _shot("rain-uncovered-ground")
			terrain.grass.set_ground_cover(records, camera.position)
		_show_previous(entry, elapsed)
		await _shot(scene[0] + "-previous")
		props._style_fire_model(entry.model)
		entry.light.position.y = 0.25
		entry.light.light_color = Color("#ffb676")
	_update(190.16, 0.0)
	await _shot("night-next")
	_check(entry.flame.visible and entry.light.visible, "A fueled fire shows moving flame and warm light")
	records.fire.fuelUntil = 192.16
	_update(191.16, 0.0)
	_check(entry.light.light_energy < 0.2 and entry.light.light_energy > 0.0, "Flame and nearby light fade as fuel runs out")
	await _shot("night-embers")
	_update(192.16, 0.0)
	_check(not entry.flame.visible and not entry.light.visible, "Flame and light go out at the room deadline")
	_check(entry.model.visible, "Logs and stones remain after burnout")
	await _shot("night-out")

	props.show_placement("campfire", {"hit":{},"ok":true,"pose":Transform3D(Basis.IDENTITY,fire_at)})
	_check(props.ghost != null and _hidden_surfaces(props.ghost) > 0, "Green campfire preview shows just the constructed shape")
	print("CAMPFIRE_MOTION_QA checks=%d failures=%d" % [passes+failures,failures])
	quit(0 if failures == 0 else 3)

func _weather(elapsed: float, rain: float) -> void:
	atmosphere.update_weather(camera.position, elapsed, rain, false)
	terrain.set_wet(rain)
	terrain.update_water(elapsed, rain, {"sun_direction":atmosphere.sun_direction,
		"sun_energy":atmosphere.sun_energy,"sky_zenith":atmosphere.sky_zenith,
		"sky_horizon":atmosphere.sky_horizon,"sun_color":atmosphere.sun_color})

func _update(elapsed: float, rain: float) -> void:
	terrain.grass.set_ground_cover(records, camera.position)
	props.sync(records, {}, "", camera, true, elapsed, rain)

func _fire_surfaces(model: Node3D) -> Array:
	var result := []
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.push_front(model)
	for item: MeshInstance3D in meshes:
		for surface: int in item.mesh.get_surface_count():
			var material := item.mesh.surface_get_material(surface)
			if material != null and material.resource_name.begins_with("Flame"):
				result.append([item, surface])
	return result

func _show_previous(entry: Dictionary, elapsed: float) -> void:
	entry.flame.hide()
	for surface: Array in _fire_surfaces(entry.model):
		surface[0].set_surface_override_material(surface[1], null)
	entry.light.position.y = 0.28
	entry.light.light_color = Color("#ff9956")
	entry.light.light_energy = 0.80 + sin(elapsed * 11.0) * 0.11 + sin(elapsed * 5.1) * 0.08

func _hidden_surfaces(model: Node3D) -> int:
	var count := 0
	for surface: Array in _fire_surfaces(model):
		if surface[0].get_surface_override_material(surface[1]) == props.hidden_flame:
			count += 1
	return count

func _shot(name: String) -> void:
	for i in 5:
		await RenderingServer.frame_post_draw
	var frame := view.get_texture().get_image()
	_check(frame != null and frame.save_png(folder.path_join(name + ".png")) == OK, "Captured " + name)

func _check(ok: bool, message: String) -> void:
	if ok:
		passes += 1
	else:
		failures += 1
		push_error(message)
