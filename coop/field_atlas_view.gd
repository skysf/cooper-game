extends Control

const Atlas = preload("res://field_atlas.gd")
const PAPER = preload("res://coast/field_atlas.webp")
const INK := Color("#343d2f")
const CREAM := Color("#f4e9c9")
const FLAG := Color("#9a4e32")
const TEAM := [Color("#2c7372"), Color("#395e83"), Color("#685b87"), Color("#3c7953")]
const MAX_ZOOM := 5.5

signal zoomed(inward: bool)
signal landmark_clicked(site: String)
signal pin_requested(point: Vector2)
signal pin_selected(id: String)

var font: Font
var own_id := ""
var own_point := Vector2.ZERO
var own_yaw := 0.0
var teammates: Dictionary = {}
var pins: Dictionary = {}
var selected_pin := ""
var placing := false
var center := (Atlas.MIN_CORNER + Atlas.MAX_CORNER) * 0.5
var zoom := 1.0
var target_zoom := 1.0
var _zoom_anchor := Vector2.ZERO
var _anchor_world := Vector2.ZERO
var _mouse_down := Vector2.ZERO
var _pressed := false
var _dragging := false
var _hovered := ""

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_exited.connect(func():
		_hovered = ""
		queue_redraw())
	resized.connect(func():
		center = _clamp_center(center)
		queue_redraw())
	set_process(false)

func reset_gesture() -> void:
	_pressed = false
	_dragging = false
	placing = false
	selected_pin = ""
	_hovered = ""
	target_zoom = zoom
	set_process(false)
	queue_redraw()

func _fit() -> float:
	return maxf(.001, minf(size.x / Atlas.EXTENT.x, size.y / Atlas.EXTENT.y))

func _project(point: Vector2) -> Vector2:
	return size * .5 + (point - center) * (_fit() * zoom)

func _unproject(point: Vector2) -> Vector2:
	return center + (point - size * .5) / (_fit() * zoom)

func _clamp_center(point: Vector2) -> Vector2:
	var margin := (size * .5 / (_fit() * zoom)).min(Atlas.EXTENT * .5)
	return point.clamp(Atlas.MIN_CORNER + margin, Atlas.MAX_CORNER - margin)

func recenter() -> void:
	target_zoom = zoom
	set_process(false)
	center = _clamp_center(own_point)
	queue_redraw()

func zoom_by(factor: float, at: Vector2) -> void:
	var next := clampf(target_zoom * factor, 1.0, MAX_ZOOM)
	if is_equal_approx(next, target_zoom):
		return
	_anchor_world = _unproject(at)
	_zoom_anchor = at
	zoomed.emit(next > target_zoom)
	target_zoom = next
	set_process(true)

func _process(delta: float) -> void:
	zoom = lerpf(zoom, target_zoom, 1.0 - exp(-delta * 22.0))
	if absf(target_zoom - zoom) < 0.002:
		zoom = target_zoom
		set_process(false)
	center = _clamp_center(_anchor_world - (_zoom_anchor - size * .5) / (_fit() * zoom))
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		zoom_by(event.factor, event.position)
		accept_event()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var ticks := clampf(event.factor, .25, 2.0) if event.factor > 0.0 else 1.0
			zoom_by(pow(1.25, ticks if event.button_index == MOUSE_BUTTON_WHEEL_UP else -ticks), event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_down = event.position
				_pressed = true
				_dragging = false
			elif _pressed:
				_pressed = false
				if not _dragging and Rect2(Vector2.ZERO, size).has_point(event.position):
					_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_add_pin(event.position)
		accept_event()
	elif event is InputEventMouseMotion:
		if _pressed and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_dragging = _dragging or event.position.distance_to(_mouse_down) > 5.0
			if _dragging:
				target_zoom = zoom
				set_process(false)
				center = _clamp_center(center - event.relative / (_fit() * zoom))
		else:
			_pressed = false
		_hovered = _landmark_at(event.position)
		mouse_default_cursor_shape = Control.CURSOR_DRAG if _pressed and _dragging else \
			(Control.CURSOR_CROSS if placing else Control.CURSOR_POINTING_HAND if not _hovered.is_empty() else Control.CURSOR_ARROW)
		queue_redraw()
		accept_event()

func _add_pin(at: Vector2) -> void:
	var point := _unproject(at)
	if Atlas.contains(point):
		pin_requested.emit(point)

func _click(at: Vector2) -> void:
	if placing:
		_add_pin(at)
		return
	for id: String in pins:
		if at.distance_to(_project(Atlas.read_point(pins[id]))) <= 12.0:
			pin_selected.emit(id)
			return
	var site := _landmark_at(at)
	if not site.is_empty():
		landmark_clicked.emit(site)
	else:
		pin_selected.emit("")

func _label_rect(site: String) -> Rect2:
	var pad := Vector2(4, 3)
	var label: String = Atlas.LANDMARKS[site].name
	var label_size := Vector2(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, 17) + pad * 2
	var point := _project(Atlas.LANDMARKS[site].at)
	var lower := point + Vector2(-label_size.x * .5, 15)
	if site == "ridge":
		lower.y = point.y - label_size.y - 15
	elif site in ["lake", "tower"]:
		lower = point - Vector2(label_size.x + 15, label_size.y * .5)
	return Rect2(lower, label_size)

func _landmark_at(at: Vector2) -> String:
	if font == null:
		return ""
	var nearest := ""
	var distance := 16.0
	for site: String in Atlas.LANDMARKS:
		var d := _project(Atlas.LANDMARKS[site].at).distance_to(at)
		if d <= distance:
			nearest = site
			distance = d
	if nearest.is_empty():
		for site: String in Atlas.LANDMARKS:
			if _label_rect(site).has_point(at):
				return site
	return nearest

func _team_positions() -> Dictionary:
	var occupied: Array[Vector2] = [_project(own_point)]
	var result := {}
	for id: String in teammates:
		if id == own_id:
			continue
		var peer: Dictionary = teammates[id]
		var at := _project(Vector2(peer.x, peer.z))
		var marker := at
		for other in occupied:
			if marker.distance_to(other) < 19.0:
				marker = at + Vector2.from_angle(float(peer.slot) * 1.53) * 23.0
				break
		occupied.append(marker)
		result[id] = {"point": at, "marker": marker, "slot": int(peer.slot)}
	return result

func _draw() -> void:
	if font == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#c2c6a5"))
	draw_texture_rect(PAPER, Rect2(_project(Atlas.MIN_CORNER), Atlas.EXTENT * (_fit() * zoom)), false)
	var sea := _project(Vector2(-244, -92))
	draw_string(font, sea, "外 海", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#53665a"))
	for site: String in Atlas.LANDMARKS:
		_draw_landmark(site)
	for id: String in pins:
		var point := _project(Atlas.read_point(pins[id]))
		draw_circle(point, 11, CREAM, true, -1, true)
		draw_circle(point, 9, FLAG if id == selected_pin else Color("#744b3a"), true, -1, true)
		_flag(point, CREAM)
	var own := _project(own_point)
	for marker: Dictionary in _team_positions().values():
		var at: Vector2 = marker.marker
		var color: Color = TEAM[posmod(int(marker.slot) - 1, TEAM.size())]
		if at != marker.point:
			draw_line(marker.point, at, color, 1.4, true)
		draw_circle(at, 10, CREAM, true, -1, true)
		draw_circle(at, 8, color, true, -1, true)
		draw_string(font, at + Vector2(-4, 4.6), str(marker.slot), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	draw_circle(own, 11.0, CREAM, true, -1, true)
	var arrow := PackedVector2Array()
	for point: Vector2 in [Vector2(0, -8), Vector2(5.5, 6), Vector2(0, 3.0), Vector2(-5.5, 6)]:
		arrow.append(own + point.rotated(-own_yaw))
	draw_colored_polygon(arrow, Color("#174546"))
	_draw_scale()

func _draw_landmark(site: String) -> void:
	var at := _project(Atlas.LANDMARKS[site].at)
	if not Rect2(Vector2.ZERO, size).grow(90.0).has_point(at):
		return
	var active := site == _hovered and not placing
	var marker_ink := CREAM if active else INK
	draw_circle(at, 12, INK, true, -1, true)
	draw_circle(at, 11, FLAG if active else CREAM, true, -1, true)
	match site:
		"camp":
			draw_polyline(PackedVector2Array([at + Vector2(-6, -1), at + Vector2(0, -6), at + Vector2(6, -1)]), marker_ink, 1.5, true)
			draw_rect(Rect2(at + Vector2(-4, -1), Vector2(8, 6)), marker_ink, false, 1.3)
		"lake":
			for dy in [-4, 0, 4]:
				draw_polyline(PackedVector2Array([at + Vector2(-6, dy), at + Vector2(-3, dy - 1), at + Vector2(1, dy + 1), at + Vector2(6, dy)]), marker_ink, 1.4, true)
		"ridge":
			draw_polyline(PackedVector2Array([at + Vector2(-7, 5), at + Vector2(-1, -6), at + Vector2(2, 0),
				at + Vector2(4, -3), at + Vector2(7, 5)]), marker_ink, 1.4, true)
		"beach":
			_flag(at, marker_ink)
		"island":
			draw_polyline(PackedVector2Array([at + Vector2(-5, 2), at + Vector2(0, -6), at + Vector2(5, 2), at + Vector2(-5, 2)]), marker_ink, 1.5, true)
			draw_line(at + Vector2(0, 2), at + Vector2(0, 6), marker_ink, 1.4, true)
		"tower":
			for dx in [-4, 4]:
				draw_line(at + Vector2(dx, -5), at + Vector2(dx, 5), marker_ink, 1.4, true)
			draw_line(at + Vector2(-6, -3), at + Vector2(6, -3), marker_ink, 1.4, true)
			draw_line(at + Vector2(-4, 2), at + Vector2(4, 2), marker_ink, 1.4, true)
	var label := _label_rect(site)
	draw_rect(label, Color("#ded8afe9") if not active else Color("#f6e9c4"))
	draw_string(font, label.position + Vector2(4, 16), Atlas.LANDMARKS[site].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)

func _flag(at: Vector2, color: Color) -> void:
	draw_line(at + Vector2(-3, 6), at + Vector2(-3, -6), color, 1.5, true)
	draw_polyline(PackedVector2Array([at + Vector2(-3, -5), at + Vector2(5, -4), at + Vector2(2, 0),
		at + Vector2(-3, -1)]), color, 1.3, true)

func _draw_scale() -> void:
	var north := Vector2(28, 43)
	draw_string(font, north + Vector2(-8, -15), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)
	draw_colored_polygon(PackedVector2Array([north + Vector2(0, -9), north + Vector2(6, 9),
		north + Vector2(0, 5), north + Vector2(-6, 9)]), INK)
	var metres := 50 if _fit() * zoom < 4.5 else 20 if _fit() * zoom < 10.0 else 10
	var from := Vector2(23, size.y - 28)
	var to := from + Vector2(float(metres) * _fit() * zoom, 0)
	draw_line(from, to, INK, 1.4, true)
	for end: Vector2 in [from, to]:
		draw_line(end, end + Vector2(0, -5), INK, 1.4, true)
	draw_string(font, from + Vector2(0, 16), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
	draw_string(font, to + Vector2(-20, 16), "%d 米" % metres, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)

func _screen_point(at: Vector2) -> Array:
	return [at.x + global_position.x, at.y + global_position.y]

func observables() -> Dictionary:
	var sites := {}
	for site: String in Atlas.LANDMARKS:
		sites[site] = _screen_point(_project(Atlas.LANDMARKS[site].at))
	var marks := {}
	for id: String in pins:
		marks[id] = _screen_point(_project(Atlas.read_point(pins[id])))
	var members := {}
	for id: String in teammates:
		if id != own_id:
			members[id] = [teammates[id].x, teammates[id].z]
	return {"zoom": zoom, "targetZoom": target_zoom, "sites": sites, "pins": marks, "team": members,
		"selectedPin": selected_pin, "placing": placing, "me": _screen_point(_project(own_point)),
		"viewRect": [global_position.x, global_position.y, size.x, size.y]}
