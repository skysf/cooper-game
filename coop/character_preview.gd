extends TextureRect

const Hiker = preload("res://hiker.gd")
const Survival = preload("res://survival.gd")
const PREVIEW_SIZE := Vector2i(384, 432)

var view := SubViewport.new()
var person := Hiker.new()
var equipment: Dictionary = {}
var equipped_pack := false
var started := false
var dragging := false
var needs_redraw := false
var warmup_build_ms := 0.0
var warmup_draw_ms := 0.0

func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	# Retain the rendered texture across menu visibility and layout changes.
	view.size = PREVIEW_SIZE
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(view)
	texture = view.get_texture()

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#cddedc")
	environment.ambient_light_energy = 0.78
	world.environment = environment
	view.add_child(world)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -26, 0)
	key.light_color = Color("#fff1d8")
	key.light_energy = 0.92
	view.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 140, 0)
	rim.light_color = Color("#b3d3dc")
	rim.light_energy = 0.38
	view.add_child(rim)

	var floor := MeshInstance3D.new()
	var base := CylinderMesh.new()
	base.top_radius = 0.43
	base.bottom_radius = 0.44
	base.height = 0.021
	base.radial_segments = 32
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#1d3030")
	stone.roughness = 0.96
	base.material = stone
	floor.mesh = base
	floor.position.y = -0.0105
	view.add_child(floor)

	view.add_child(person)
	person.rotation.y = PI - 0.22
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 2.10
	view.add_child(camera)
	camera.position = Vector3(0.0, 1.09, 3.5)
	camera.look_at(Vector3(0.0, 0.82, 0.0))
	camera.make_current()

	visibility_changed.connect(_visibility_changed)

func _apply_equipment(worn: Dictionary, wearing_backpack: bool, slot: int) -> void:
	if not started:
		started = true
		person.outfit(slot)
		needs_redraw = true
	person.player_slot = slot
	if equipment != worn or equipped_pack != wearing_backpack:
		equipment = worn.duplicate()
		equipped_pack = wearing_backpack
		person.wear_clothes(equipment)
		person.wear_backpack(equipped_pack)
		needs_redraw = true

func warm_up(worn: Dictionary, wearing_backpack: bool, slot: int) -> void:
	var started_at := Time.get_ticks_usec()
	# Keep all gear nodes resident, including clothing the player has taken off.
	_apply_equipment(Survival.initial_wear(), true, slot)
	_apply_equipment(worn, wearing_backpack, slot)
	warmup_build_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	# Give the loading screen a frame between scene construction and the first GPU submission.
	await get_tree().process_frame
	var draw_started := Time.get_ticks_usec()
	_draw_once()
	await RenderingServer.frame_post_draw
	warmup_draw_ms = (Time.get_ticks_usec() - draw_started) / 1000.0

func update_character(worn: Dictionary, wearing_backpack: bool, slot: int) -> void:
	_apply_equipment(worn, wearing_backpack, slot)
	_draw_if_visible()

func _draw_once() -> void:
	needs_redraw = false
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not RenderingServer.frame_post_draw.is_connected(_finish_draw):
		RenderingServer.frame_post_draw.connect(_finish_draw, CONNECT_ONE_SHOT)

func _finish_draw() -> void:
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _draw_if_visible() -> void:
	if needs_redraw and is_visible_in_tree():
		_draw_once()

func _visibility_changed() -> void:
	if is_visible_in_tree():
		_draw_if_visible()
	else:
		dragging = false
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		needs_redraw = needs_redraw or view.render_target_update_mode == SubViewport.UPDATE_ONCE
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		mouse_default_cursor_shape = Control.CURSOR_MOVE if dragging else Control.CURSOR_DRAG
		accept_event()
	elif event is InputEventMouseMotion and dragging and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		person.rotation.y = wrapf(person.rotation.y + event.relative.x * 0.014, -PI, PI)
		_draw_once()
		accept_event()
