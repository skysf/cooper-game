extends SceneTree
## Render the production Godot imports and the streamed zones listed by the asset audit.

const Terrain = preload("res://terrain.gd")
const Atmosphere = preload("res://atmosphere.gd")
const Lake = preload("res://lake_layout.gd")
const PlayerMotion = preload("res://player_motion.gd")
const STUDIO := Vector2i(640, 480)
const VIEWS := [Vector3(0.92, 0.52, 1.15), Vector3(-0.92, 0.64, -1.15)]
const POSES := ["Stand", "Idle-loop", "GroundIdle-loop"]
const ZONE_EYES := {
	"backcountry": Vector2(1.1, -113.0), "camp": Vector2(1.9, -85.0),
	"approach": Vector2(0.1, -71.5), "creek": Vector2(-4.2, -60.2),
	"crossing": Vector2(1.6, -40.0), "tower": Vector2(6.3, -19.0),
	"ridge": Vector2(0.2, 0.4),
}

var view := SubViewport.new()
var camera := Camera3D.new()
var destination := ""
var restored := {"assets": [], "zones": [], "failures": []}

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 3:
		push_error("Supply audit inventory JSON, zone directory and destination")
		quit(2)
		return
	destination = arguments[2]
	for folder: String in ["models", "zones"]:
		if DirAccess.make_dir_recursive_absolute(destination.path_join(folder)) != OK:
			push_error("Cannot create the review directory")
			quit(2)
			return
	var inventory: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if inventory is not Dictionary or inventory.get("models", []).is_empty():
		push_error("Invalid or empty asset inventory")
		quit(2)
		return
	view.size = STUDIO
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(camera)
	camera.make_current()
	var studio := _studio()
	for entry: Dictionary in inventory.models:
		await _model(entry.file)
	studio.free()
	await _zones(arguments[1])
	var report := FileAccess.open(destination.path_join("capture.json"), FileAccess.WRITE)
	if report == null:
		push_error("Cannot write capture report")
		quit(2)
		return
	report.store_string(JSON.stringify(restored, "\t") + "\n")
	report.close()
	print("MODEL_REVIEW meshes=%d zones=%d issues=%d" % [restored.assets.size(), restored.zones.size(), restored.failures.size()])
	quit(0 if restored.failures.is_empty() else 3)

func _studio() -> Node3D:
	var stage := Node3D.new()
	view.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#334043")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("#dee7eb")
	world.environment.ambient_light_energy = 0.66
	stage.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -33, 0)
	key.light_color = Color("#fff5e8")
	key.light_energy = 0.84
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 158, 0)
	fill.light_color = Color("#d8efff")
	fill.light_energy = 0.36
	stage.add_child(fill)
	return stage

func _model(file: String) -> void:
	var path := "res://" + file.trim_prefix("coop/")
	var source := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if source == null:
		_failure(file)
		return
	var instance := source.instantiate() as Node3D
	if instance == null:
		_failure(file)
		return
	view.add_child(instance)
	var pose := _pose(instance)
	var parts := instance.find_children("*", "MeshInstance3D", true, false)
	if instance is MeshInstance3D:
		parts.push_front(instance)
	var bounds := AABB()
	var visible_parts := 0
	for item: MeshInstance3D in parts:
		# The game only uses one of these manually selectable meshes at a time.
		if item.name in [&"LOD1", &"LOD2"] or str(item.name).ends_with("Far"):
			item.hide()
		if item.mesh == null or not item.is_visible_in_tree():
			continue
		var box: AABB = item.global_transform * item.get_aabb()
		bounds = box if visible_parts == 0 else bounds.merge(box)
		visible_parts += 1
	if visible_parts == 0 or not bounds.size.is_finite() or bounds.size.length() <= 0.00001:
		_failure(file)
		instance.free()
		return
	var photos := []
	for i in VIEWS.size():
		_framing(bounds, VIEWS[i])
		var photo := "models/%s-%d.jpg" % [file.get_file().get_basename(), i + 1]
		if await _shot(photo):
			photos.append(photo)
	restored.assets.append({"file": file, "viewable_meshes": visible_parts, "pose": pose,
		"bounds_origin": _vec(bounds.position), "bounds_size_m": _vec(bounds.size), "views": photos,
		"glb_sha256": FileAccess.get_sha256(path)})
	instance.free()

func _pose(instance: Node3D) -> String:
	var players := instance.find_children("*", "AnimationPlayer", true, false)
	var sampled := ""
	for player: AnimationPlayer in players:
		player.stop()
		for action: String in POSES:
			if player.has_animation(action):
				player.play(action)
				player.seek(0.12, true)
				player.pause()
				sampled = action
				break
	return sampled

func _framing(bounds: AABB, angle: Vector3) -> void:
	var center := bounds.get_center()
	var span := bounds.size.length()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = center + angle.normalized() * span * 1.28
	camera.look_at(center)
	camera.near = maxf(span * 0.003, 0.0005)
	camera.far = span * 3.0 + 0.03
	var half := bounds.size * 0.5
	var frame_width := camera.basis.x.abs().dot(half) * 2.0
	var frame_height := camera.basis.y.abs().dot(half) * 2.0
	camera.size = maxf(frame_height, frame_width / (float(STUDIO.x) / STUDIO.y)) * 1.12

func _zones(directory: String) -> void:
	view.size = Vector2i(1024, 576)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.near = 0.045
	camera.far = 105.0
	camera.fov = 64.0
	var atmosphere := Atmosphere.new()
	view.add_child(atmosphere)
	var terrain := Terrain.new()
	view.add_child(terrain)
	terrain.set_process(false)
	terrain.grove.set_room_time(25.0)
	for chunk: Dictionary in terrain.chunks:
		var at: Vector2 = ZONE_EYES[chunk.id]
		camera.position = Vector3(at.x, Lake.walk_height(at) + PlayerMotion.WALK_EYE, at.y)
		camera.look_at(camera.position + Vector3(0.22, -0.13, 1.0 if chunk.id == "camp" else -1.0))
		terrain.update_focus(camera.position)
		var packet := FileAccess.get_file_as_bytes(directory.path_join(chunk.id + ".glb"))
		if packet.size() != int(chunk.bytes):
			_failure(chunk.id)
			continue
		terrain._parse_chunk(chunk.id, packet)
		if not terrain.loaded.has(chunk.id):
			_failure(chunk.id)
			continue
		atmosphere.update_weather(camera.position, 25.0, 0.0, false)
		terrain.update_water(25.0, 0.0, {
			"sun_direction": atmosphere.sun_direction, "sun_energy": atmosphere.sun_energy,
			"sky_zenith": atmosphere.sky_zenith, "sky_horizon": atmosphere.sky_horizon,
			"sun_color": atmosphere.sun_color, "underwater": false,
		})
		var photo := "zones/%s.jpg" % chunk.id
		if await _shot(photo):
			restored.zones.append({"id": chunk.id, "camera_m": _vec(camera.position), "view": photo,
				"glb_sha256": FileAccess.get_sha256(directory.path_join(chunk.id + ".glb")),
				"runtime_meshes": terrain.loaded[chunk.id].find_children("*", "MeshInstance3D", true, false).size(),
				"runtime_batches": terrain.loaded[chunk.id].find_children("*", "MultiMeshInstance3D", true, false).size()})

func _shot(file: String) -> bool:
	for frame in 2:
		await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	if image == null or image.save_jpg(destination.path_join(file), 0.9) != OK:
		_failure(file)
		return false
	return true

func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _failure(id: String) -> void:
	restored.failures.append(id)
	push_error("Review capture failed for " + id)
