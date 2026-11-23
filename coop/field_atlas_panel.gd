extends CanvasLayer

const View = preload("res://field_atlas_view.gd")
const ZOOM_IN = preload("res://sounds/atlas-zoom-in.wav")
const ZOOM_OUT = preload("res://sounds/atlas-zoom-out.wav")
const PAPER_TEXT := Color("#efe6cb")
const SOFT_TEXT := Color("#c2c2a1")
const EDGE := Color("#626b51")

signal close_requested
signal travel_requested(site: String)
signal pin_requested(point: Vector2)
signal remove_requested(id: String)

var view := View.new()
var cue := AudioStreamPlayer.new()
var is_open := false
var available := false
var travelling := false
var _browser_audio: JavaScriptObject
var _last_cue := -1000
var _cue_count := 0
var message: Label
var zoom_label: Label
var zoom_in: Button
var zoom_out: Button
var place: Button
var erase: Button

func _ready() -> void:
	layer = 13
	var background := ColorRect.new()
	background.color = Color("#282d22")
	background.mouse_force_pass_scroll_events = false
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	var font := preload("res://fonts/TrailSans.otf").duplicate() as FontFile
	font.fallbacks = [preload("res://fonts/CampHanSupplement.otf"),preload("res://fonts/CampSignCJK.otf")]
	theme.default_font = font
	background.theme = theme
	var margins := MarginContainer.new()
	background.add_child(margins)
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margins.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 14)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 9)
	margins.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	layout.add_child(header)
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", 0)
	header.add_child(title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(title, "鹿鸣湖与东部山地", 27, PAPER_TEXT)
	_label(title, "Cooper  ·  野外图册", 13, SOFT_TEXT)
	var center := _button(header, "定位我", 65)
	center.pressed.connect(view.recenter)
	zoom_out = _button(header, "−", 37)
	zoom_out.pressed.connect(zoom_step.bind(false))
	zoom_label = _label(header, "100%", 13, SOFT_TEXT)
	zoom_label.custom_minimum_size.x = 45
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zoom_in = _button(header, "+", 37)
	zoom_in.pressed.connect(zoom_step.bind(true))
	var close := _button(header, "关闭  M", 81)
	close.pressed.connect(func(): close_requested.emit())
	var map_window := Control.new()
	map_window.clip_contents = true
	map_window.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(map_window)
	view.font = font
	view.mouse_force_pass_scroll_events = false
	map_window.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.landmark_clicked.connect(_travel)
	view.pin_requested.connect(_place_pin)
	view.pin_selected.connect(_select_pin)
	view.zoomed.connect(_play_zoom)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	layout.add_child(footer)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 2)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(detail)
	message = _label(detail, "", 15, PAPER_TEXT)
	message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label(detail, "滚轮 缩放   ·   拖动 查看   ·   右键 标记   ·   数字圆点 队友", 12, SOFT_TEXT)
	place = _button(footer, "放置标记", 88)
	place.toggle_mode = true
	place.toggled.connect(_placing)
	erase = _button(footer, "删除标记", 88)
	erase.pressed.connect(_remove_pin)
	add_child(cue)
	cue.volume_db = -13.0
	if OS.has_feature("web") and bool(JavaScriptBridge.eval("Boolean(window.CooperAudio)", true)):
		_browser_audio = JavaScriptBridge.get_interface("CooperAudio")
		for clip: AudioStreamWAV in [ZOOM_IN, ZOOM_OUT]:
			_browser_audio.register(clip.resource_path.get_file(), clip.mix_rate, Marshalls.raw_to_base64(clip.data))
	set_open(false)

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, title: String, width: float) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(width, 37)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", PAPER_TEXT)
	button.add_theme_stylebox_override("normal", _style(Color("#353d31")))
	button.add_theme_stylebox_override("hover", _style(Color("#53604a")))
	button.add_theme_stylebox_override("pressed", _style(Color("#6a5a3e")))
	button.add_theme_stylebox_override("disabled", _style(Color("#272d24")))
	parent.add_child(button)
	return button

func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = EDGE
	style.set_border_width_all(1)
	return style

func set_open(open: bool) -> void:
	is_open = open
	visible = open
	view.reset_gesture()
	view.mouse_default_cursor_shape = Control.CURSOR_ARROW
	place.set_pressed_no_signal(false)
	erase.hide()
	if open:
		message.text = "点击地标传送" if available else "正在同步房间地图"
	else:
		cue.stop()

func sync(self_id: String, peers: Dictionary, at: Vector2, yaw: float, pins: Dictionary, supported: bool) -> void:
	if available != supported:
		available = supported
		message.text = "点击地标传送" if available else "房间暂未提供地图操作"
		if not available:
			travelling = false
	view.own_id = self_id
	view.own_point = at
	view.own_yaw = yaw
	view.teammates = peers
	view.pins = pins
	if not view.selected_pin.is_empty() and not pins.has(view.selected_pin):
		view.selected_pin = ""
	place.disabled = not available or travelling
	erase.visible = available and not view.selected_pin.is_empty()
	zoom_in.disabled = is_equal_approx(view.target_zoom, View.MAX_ZOOM)
	zoom_out.disabled = is_equal_approx(view.target_zoom, 1.0)
	zoom_label.text = "%d%%" % roundi(view.zoom * 100)
	view.queue_redraw()

func zoom_step(inward: bool) -> void:
	view.zoom_by(1.32 if inward else 1.0 / 1.32, view.size * .5)

func _play_zoom(inward: bool) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_cue < 58:
		return
	var clip: AudioStreamWAV = ZOOM_IN if inward else ZOOM_OUT
	if _browser_audio != null:
		_browser_audio.play(clip.resource_path.get_file(), db_to_linear(cue.volume_db), 1.0, 0.0, 5)
	else:
		cue.stream = clip
		cue.play()
	_last_cue = now
	_cue_count += 1

func _placing(active: bool) -> void:
	view.placing = active
	view.mouse_default_cursor_shape = Control.CURSOR_CROSS if active else Control.CURSOR_ARROW
	message.text = "点击地图放置个人标记" if active else "点击地标传送"

func _travel(site: String) -> void:
	if not available or travelling:
		return
	travelling = true
	message.text = "正在传送"
	travel_requested.emit(site)

func _place_pin(point: Vector2) -> void:
	if not available or travelling:
		return
	place.set_pressed_no_signal(false)
	_placing(false)
	pin_requested.emit(point)

func _select_pin(id: String) -> void:
	view.selected_pin = id
	erase.visible = not id.is_empty()
	message.text = "个人标记" if erase.visible else "点击地标传送"
	view.queue_redraw()

func _remove_pin() -> void:
	if not view.selected_pin.is_empty():
		remove_requested.emit(view.selected_pin)

func reply(action: String, text: String) -> void:
	if action == "travel":
		travelling = false
	if not text.is_empty():
		message.text = text

func observables() -> Dictionary:
	var data := view.observables() if is_open else {}
	data.open = is_open
	data.travelPending = travelling
	data.cues = _cue_count
	if is_open:
		var b := zoom_in.get_global_rect()
		data.zoomInRect = [b.position.x, b.position.y, b.size.x, b.size.y]
		b = zoom_out.get_global_rect()
		data.zoomOutRect = [b.position.x, b.position.y, b.size.x, b.size.y]
		b = erase.get_global_rect()
		data.eraseRect = [b.position.x, b.position.y, b.size.x, b.size.y] if erase.visible else []
		data.status = message.text
	return data
