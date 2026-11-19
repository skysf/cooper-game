extends CanvasLayer

const Rules = preload("res://rules.gd")
const Survival = preload("res://survival.gd")
const CharacterPreview = preload("res://character_preview.gd")
const ITEM_ICONS := {
	"apple": preload("res://textures/inventory_apple.png"),
	"bread": preload("res://textures/inventory_bread.png"),
	"cap": preload("res://textures/inventory_cap.png"),
	"jacket": preload("res://textures/inventory_jacket.png"),
	"pants": preload("res://textures/inventory_pants.png"),
	"backpack": preload("res://textures/inventory_backpack.png"),
}
const EQUIPMENT_SLOTS := {"cap": "头部", "jacket": "上身", "pants": "下身", "backpack": "背部"}
const CATEGORIES := {"all": "全部", "food": "食物", "clothing": "服装"}

signal resume_requested
signal invite_requested
signal backpack_close_requested
signal backpack_action_requested(action: String, item: String)

const INK := Color("#f0eee4")
const MUTED := Color("#aebfbb")
const AMBER := Color("#f1c581")
const DARK := Color("#111a1b")
const PANEL := Color("#172324")
const WELL := Color("#131d1e")
const TILE := Color("#223031")
const EDGE := Color("#3e5250")
const HUD_FILL := Color("#122022ec")
const AREA := {"camp": "林间营地", "creek": "鹿鸣溪谷", "tower": "北坡瞭望塔", "lake": "鹿鸣湖岸"}
const GOALS := {"wood": "溪谷木料", "tarp": "瞭望塔防水布", "repair": "营地木棚"}
const HEADING := ["北", "西北", "西", "西南", "南", "东南", "东", "东北"]
const VITALS := [
	["health", "健康", Color("#ec9f8b")], ["hunger", "饱腹", Color("#e9be83")],
	["water", "水分", Color("#8bced7")], ["mood", "心情", Color("#bacd98")],
]
const GROUND_KEYS := [["WASD", "行走"], ["鼠标", "转向"], ["空格", "跳跃"], ["E", "互动"], ["Q", "目标"], ["V", "视角"]]
const SWIM_KEYS := [["WASD", "游泳"], ["鼠标", "转向"], ["C", "下潜"], ["空格", "上浮"], ["V", "视角"]]
const FLIGHT_KEYS := [["WASD", "飞行"], ["鼠标", "转向"], ["空格", "上升"], ["C", "下降"], ["V", "视角"]]

var base := Control.new()
var field := Control.new()
var strong_font: FontVariation
var stage_gradient: GradientTexture2D
var area_title: Label
var room_line: Label
var room_count: Label
var grove_hint: Label
var sky: Label
var bearing: Label
var bearing_arrow: Label
var bearing_distance: Label
var goal_title: Label
var supplies: Label
var prompt: Label
var prompt_panel: PanelContainer
var prompt_key: Label
var toast: Label
var toast_panel: PanelContainer
var menu_notice: Label
var reticle: Label
var field_header: VBoxContainer
var field_columns: HBoxContainer
var location_card: PanelContainer
var task_card: PanelContainer
var navigation_lane: CenterContainer
var heading_gap: Control
var field_dock: VBoxContainer
var key_panel: PanelContainer
var key_groups: Array[HBoxContainer] = []
var key_profile := ""
var panel: PanelContainer
var briefing_title: Label
var enter: Button
var invite: Button
var briefing: Label
var link_field := LineEdit.new()
var link_sheet: VBoxContainer
var entered_field := false
var toast_until := 0
var last_notice := -1
var vitals: PanelContainer
var vital_bars: Dictionary = {}
var vital_numbers: Dictionary = {}
var backpack_shade: ColorRect
var backpack_panel: PanelContainer
var backpack_capacity: Label
var capacity_bar: ProgressBar
var backpack_grid: GridContainer
var inventory_page: HBoxContainer
var character_page: HBoxContainer
var inventory_tab: Button
var character_tab: Button
var category_buttons: Dictionary = {}
var category_counts: Dictionary = {}
var category := "all"
var backpack_slots: Array[Button] = []
var backpack_items: Array[String] = []
var backpack_names: Array[Label] = []
var backpack_quantities: Array[Label] = []
var backpack_actions: Dictionary = {}
var backpack_open := false
var selected_slot := -1
var can_put_food := false
var bag: Dictionary = {}
var bag_capacity := 0
var inventory_detail: Dictionary = {}
var detail_title: Label
var character_preview: CharacterPreview
var character_numbers: Dictionary = {}
var equipment_detail: Dictionary = {}
var equipment_buttons: Dictionary = {}
var equipment_names: Dictionary = {}
var equipment_actions: Dictionary = {}
var selection := "jacket"
var worn: Dictionary = {}
var wearing_backpack := false
var clothing_supported := false
var preview_slot := 1

func _style(bg: Color, border := EDGE, padding := Vector2(12, 8)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = padding.x
	style.content_margin_right = padding.x
	style.content_margin_top = padding.y
	style.content_margin_bottom = padding.y
	return style

func _place(parent: Control, control: Control, anchors: Vector4, offsets: Rect2) -> void:
	if control.get_parent() == null:
		parent.add_child(control)
	control.anchor_left = anchors.x
	control.anchor_top = anchors.y
	control.anchor_right = anchors.z
	control.anchor_bottom = anchors.w
	control.offset_left = offsets.position.x
	control.offset_top = offsets.position.y
	control.offset_right = offsets.end.x
	control.offset_bottom = offsets.end.y
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _label(parent: Node, font_size: int, tint := INK, content := "", strong := false) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	if strong:
		label.add_theme_font_override("font", strong_font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = content
	parent.add_child(label)
	return label

func _column(parent: Node, separation: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(column)
	return column

func _row(parent: Node, separation: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	return row

func _spacer(parent: Node) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(spacer)

func _hud_card(parent: Control, anchors: Vector4, offsets: Rect2) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(HUD_FILL))
	_place(parent, card, anchors, offsets)
	return card

func _button(text: String, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size.y = 38
	var background := AMBER if primary else TILE
	var foreground := DARK if primary else INK
	button.add_theme_stylebox_override("normal", _style(background, background if primary else EDGE))
	button.add_theme_stylebox_override("hover", _style(background.lightened(0.13), AMBER))
	button.add_theme_stylebox_override("pressed", _style(background.darkened(0.10), AMBER))
	button.add_theme_stylebox_override("disabled", _style(WELL, Color("#303e3d")))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, foreground)
	button.add_theme_color_override("font_disabled_color", Color("#899a98"))
	button.add_theme_font_size_override("font_size", 15)
	if primary:
		button.add_theme_font_override("font", strong_font)
	return button

func _choice(text := "") -> Button:
	var button := _button(text)
	button.toggle_mode = true
	var selected := _style(Color("#414035"), AMBER)
	for state: String in ["pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, selected)
		button.add_theme_color_override("font_%s_color" % state, AMBER)
	return button

func _ready() -> void:
	add_child(base)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	var hud_font := preload("res://fonts/TrailSans.otf").duplicate() as FontFile
	hud_font.fallbacks = [preload("res://fonts/CampHanSupplement.otf")]
	theme.default_font = hud_font
	base.theme = theme
	strong_font = FontVariation.new()
	strong_font.base_font = hud_font
	strong_font.variation_embolden = 0.55
	base.add_child(field)
	field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_field()
	_build_briefing()
	_build_backpack()
	base.resized.connect(_layout_interface)
	_layout_interface()

func _build_field() -> void:
	field_header = VBoxContainer.new()
	field_header.add_theme_constant_override("separation", 8)
	_place(field, field_header, Vector4(0, 0, 1, 0), Rect2(20, 18, -40, 0))
	field_columns = _row(field_header, 12)
	location_card = _pane(field_columns, HUD_FILL, Vector2(12, 8))
	location_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var location := _column(location_card, 2)
	area_title = _label(location, 19, INK, "", true)
	var room_row := _row(location, 8)
	room_line = _label(room_row, 14, MUTED)
	room_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	room_count = _label(room_row, 14, MUTED)
	grove_hint = _label(location, 14, AMBER)
	grove_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	heading_gap = Control.new()
	heading_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_columns.add_child(heading_gap)

	navigation_lane = CenterContainer.new()
	navigation_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	navigation_lane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation_lane.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	field_columns.add_child(navigation_lane)
	var compass := _pane(navigation_lane, HUD_FILL, Vector2(12, 8))
	compass.custom_minimum_size.x = 220
	var navigation := _row(compass, 9)
	bearing_arrow = _label(navigation, 17, AMBER, "", true)
	bearing = _label(navigation, 16, INK)
	bearing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bearing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bearing_distance = _label(navigation, 15, MUTED)

	task_card = _pane(field_columns, HUD_FILL, Vector2(12, 8))
	task_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var task := _column(task_card, 3)
	sky = _label(task, 14, AMBER)
	goal_title = _label(task, 19, INK, "", true)
	supplies = _label(task, 14, MUTED)
	for label: Label in [sky, goal_title, supplies]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	reticle = _label(field, 22, INK, "·", true)
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.add_theme_constant_override("outline_size", 4)
	reticle.add_theme_color_override("font_outline_color", DARK)
	_place(field, reticle, Vector4(0.5, 0.5, 0.5, 0.5), Rect2(-10, -16, 20, 32))

	field_dock = VBoxContainer.new()
	field_dock.alignment = BoxContainer.ALIGNMENT_END
	field_dock.add_theme_constant_override("separation", 8)
	field_dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_place(field, field_dock, Vector4(0, 1, 1, 1), Rect2(20, -19, -40, 0))
	prompt_panel = _pane(field_dock, HUD_FILL, Vector2(12, 6))
	prompt_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var prompt_row := _row(prompt_panel, 9)
	prompt_key = _keycap(prompt_row)
	prompt = _label(prompt_row, 16, INK, "", true)
	prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_panel.hide()
	toast_panel = _pane(field_dock, HUD_FILL, Vector2(12, 5))
	toast_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toast = _label(toast_panel, 15, AMBER)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_panel.hide()

	var bottom := _row(field_dock, 12)
	_build_vitals(bottom)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	_build_key_guide(bottom)
	field_dock.hide()

func _keycap(parent: Node) -> Label:
	var key := _label(parent, 13, AMBER, "", true)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.add_theme_stylebox_override("normal", _style(TILE, EDGE, Vector2(5, 2)))
	return key

func _build_key_guide(parent: HBoxContainer) -> void:
	key_panel = _pane(parent, HUD_FILL, Vector2(8, 6))
	key_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	var keys := HFlowContainer.new()
	keys.alignment = FlowContainer.ALIGNMENT_END
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys.add_theme_constant_override("h_separation", 10)
	keys.add_theme_constant_override("v_separation", 7)
	key_panel.add_child(keys)
	for index in GROUND_KEYS.size() + 4:
		var group := _row(keys, 4)
		_keycap(group)
		_label(group, 14, INK)
		key_groups.append(group)

func _update_key_guide(piloting: bool, swimming: bool, has_survival: bool, holding: bool) -> void:
	var mode := "flight" if piloting else ("swim" if swimming else "ground")
	var profile := "%s/%s/%s" % [mode, has_survival, holding]
	if profile == key_profile:
		return
	key_profile = profile
	var keys := (FLIGHT_KEYS if piloting else (SWIM_KEYS if swimming else GROUND_KEYS)).duplicate()
	if has_survival and not piloting:
		keys.append(["Tab", "背包"])
	if holding and not piloting:
		keys.append_array([["左键", "投掷"], ["G", "放下"]])
	keys.append(["Esc", "菜单"])
	for index in key_groups.size():
		var group := key_groups[index]
		group.visible = index < keys.size()
		if group.visible:
			group.get_child(0).text = keys[index][0]
			group.get_child(1).text = keys[index][1]
	_layout_key_guide()

func _update_prompt(action: String) -> void:
	var split := action.split("    ", false, 1)
	var key := split[0] if split.size() == 2 and split[0] in ["E", "F", "C", "空格"] else ""
	prompt_key.visible = not key.is_empty()
	prompt_key.text = key
	prompt.text = split[1] if not key.is_empty() else action.replace("    ", "  ·  ")

func _layout_interface() -> void:
	var width := base.size.x
	var narrow := width < 740.0
	heading_gap.visible = narrow
	if narrow and navigation_lane.get_parent() != field_header:
		navigation_lane.reparent(field_header, false)
	elif not narrow and navigation_lane.get_parent() != field_columns:
		navigation_lane.reparent(field_columns, false)
		field_columns.move_child(navigation_lane, 2)
	location_card.custom_minimum_size.x = clampf(width * 0.20, 135, 230)
	task_card.custom_minimum_size.x = clampf(width * 0.225, 166, 230)
	var available := maxf(100, width - 40)
	prompt_panel.custom_minimum_size.x = minf(available, 410)
	toast_panel.custom_minimum_size.x = minf(available, 445)
	vitals.custom_minimum_size.x = clampf(width * 0.22, 132, 205)
	_layout_key_guide()
	panel.offset_right = 20 + minf(maxf(width - 40, 100), 488)
	_layout_backpack()

func _layout_key_guide() -> void:
	var natural_width := 16.0
	for group: HBoxContainer in key_groups:
		if group.visible:
			natural_width += group.get_combined_minimum_size().x + 10
	var available := base.size.x - vitals.custom_minimum_size.x - 64
	key_panel.custom_minimum_size.x = clampf(minf(natural_width - 10, available), 140, 710)

func _build_briefing() -> void:
	panel = _hud_card(base, Vector4(0, 1, 0, 1), Rect2(20, -20, 488, 0))
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", _style(PANEL, EDGE, Vector2(16, 14)))
	var content := _column(panel, 10)
	briefing_title = _label(content, 30, INK, "雨线营地", true)
	briefing = _label(content, 16, MUTED)
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var actions := _row(content, 8)
	enter = _button("进入林地", true)
	invite = _button("邀请队友")
	actions.add_child(enter)
	actions.add_child(invite)
	enter.pressed.connect(func(): resume_requested.emit())
	invite.pressed.connect(func(): invite_requested.emit())

	link_sheet = _column(_pane(content, WELL, Vector2(8, 7)), 6)
	_label(link_sheet, 13, MUTED, "房间邀请链接")
	link_field.editable = false
	link_field.custom_minimum_size.y = 34
	link_field.add_theme_font_size_override("font_size", 14)
	link_field.add_theme_color_override("font_uneditable_color", INK)
	link_field.add_theme_color_override("font_selected_color", INK)
	link_field.add_theme_color_override("selection_color", Color("#594934"))
	link_field.add_theme_stylebox_override("read_only", _style(TILE, EDGE, Vector2(7, 5)))
	link_field.add_theme_stylebox_override("focus", _style(TILE, AMBER, Vector2(7, 5)))
	link_sheet.add_child(link_field)
	_label(link_sheet, 12, MUTED, "按 ⌘C 或 Ctrl+C 复制链接")
	link_sheet.get_parent().hide()
	link_field.hide()

	var credits := HFlowContainer.new()
	credits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	credits.add_theme_constant_override("h_separation", 7)
	content.add_child(credits)
	_label(credits, 12, MUTED, "银河照片")
	for entry: Array in [
		["ESO/S. Brunier", "https://www.eso.org/public/images/eso0932a/"],
		["CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"],
	]:
		var credit := LinkButton.new()
		credit.text = entry[0]
		credit.uri = entry[1]
		credit.add_theme_font_size_override("font_size", 12)
		credit.add_theme_color_override("font_color", MUTED)
		credit.add_theme_color_override("font_hover_color", AMBER)
		credits.add_child(credit)

func _bar(tint: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = Survival.MAX_STAT
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size.y = 4
	bar.add_theme_stylebox_override("background", _style(Color("#2f4243"), Color.TRANSPARENT, Vector2.ZERO))
	bar.add_theme_stylebox_override("fill", _style(tint, Color.TRANSPARENT, Vector2.ZERO))
	return bar

func _build_vitals(parent: HBoxContainer) -> void:
	vitals = _pane(parent, HUD_FILL, Vector2(10, 8))
	vitals.size_flags_vertical = Control.SIZE_SHRINK_END
	var content := _column(vitals, 3)
	for entry: Array in VITALS:
		var row := _row(content, 8)
		var name_label := _label(row, 13, MUTED, entry[1])
		name_label.custom_minimum_size.x = 30
		var bar := _bar(entry[2])
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var number := _label(row, 13, INK)
		number.custom_minimum_size.x = 26
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vital_bars[entry[0]] = bar
		vital_numbers[entry[0]] = number
	vitals.hide()

func _build_backpack() -> void:
	backpack_shade = ColorRect.new()
	backpack_shade.color = Color("#091213b5")
	base.add_child(backpack_shade)
	backpack_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backpack_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	backpack_panel = _hud_card(base, Vector4(0.5, 0.5, 0.5, 0.5), Rect2())
	var frame := _style(PANEL, EDGE, Vector2(16, 14))
	frame.shadow_color = Color("#07101185")
	frame.shadow_size = 12
	frame.shadow_offset = Vector2(0, 5)
	backpack_panel.add_theme_stylebox_override("panel", frame)
	backpack_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var content := _column(backpack_panel, 12)
	var header := _row(content, 8)
	var title := _label(header, 26, INK, "随身装备", true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_tab = _choice("背包")
	character_tab = _choice("角色")
	for tab: Button in [inventory_tab, character_tab]:
		tab.custom_minimum_size.x = 84
		header.add_child(tab)
	inventory_tab.pressed.connect(_show_character.bind(false))
	character_tab.pressed.connect(_show_character.bind(true))
	var close := _button("Esc  关闭")
	close.pressed.connect(func(): backpack_close_requested.emit())
	header.add_child(close)
	var line := ColorRect.new()
	line.color = EDGE
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(line)

	var colors := Gradient.new()
	colors.colors = PackedColorArray([Color("#334746"), Color("#192627"), WELL])
	colors.offsets = PackedFloat32Array([0.00, 0.62, 1.00])
	stage_gradient = GradientTexture2D.new()
	stage_gradient.gradient = colors
	stage_gradient.fill = GradientTexture2D.FILL_RADIAL
	stage_gradient.fill_from = Vector2(0.5, 0.43)
	stage_gradient.fill_to = Vector2(1.0, 0.92)
	stage_gradient.width = 192
	stage_gradient.height = 192

	_build_inventory_page(content)
	_build_character_page(content)
	menu_notice = _label(content, 13, AMBER)
	menu_notice.custom_minimum_size.y = 18
	menu_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_show_character(false)
	backpack_panel.hide()
	backpack_shade.hide()
	_refresh_backpack({}, false, Survival.SLOT_COUNT)

func _menu_page(parent: Node) -> HBoxContainer:
	var page := _row(parent, 12)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return page

func _pane(parent: Node, bg: Color, padding := Vector2(12, 12)) -> PanelContainer:
	var pane := PanelContainer.new()
	pane.add_theme_stylebox_override("panel", _style(bg, EDGE, padding))
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pane)
	return pane

func _build_inventory_page(content: VBoxContainer) -> void:
	inventory_page = _menu_page(content)
	var sidebar := _column(_pane(inventory_page, WELL), 8)
	_label(sidebar, 14, MUTED, "物品类别")
	for filter: String in CATEGORIES:
		var button := _choice(CATEGORIES[filter])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select_category.bind(filter))
		sidebar.add_child(button)
		var count := _label(button, 13, MUTED)
		count.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		count.offset_left = -43
		count.offset_right = -12
		count.offset_top = -11
		count.offset_bottom = 11
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		category_buttons[filter] = button
		category_counts[filter] = count
	_spacer(sidebar)
	_label(sidebar, 13, MUTED, "背包容量")
	backpack_capacity = _label(sidebar, 21, INK, "", true)
	capacity_bar = _bar(AMBER)
	sidebar.add_child(capacity_bar)

	var items := _column(inventory_page, 10)
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	backpack_grid = GridContainer.new()
	backpack_grid.add_theme_constant_override("h_separation", 8)
	backpack_grid.add_theme_constant_override("v_separation", 8)
	backpack_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	items.add_child(backpack_grid)
	for index in Survival.slot_count(true):
		_build_inventory_slot(index)
	inventory_detail = _build_detail(inventory_page, [
		["eat", "吃一份", true], ["wear", "穿上", true], ["put", "放回桌上", false], ["drop", "丢下", false],
	], _submit_backpack_action)
	backpack_actions = inventory_detail.actions
	detail_title = inventory_detail.title
	backpack_actions.drop.tooltip_text = "丢到脚边"
	backpack_actions.put.tooltip_text = "将一份食物放回木桌"

func _build_inventory_slot(index: int) -> void:
	var slot := _choice()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.expand_icon = true
	slot.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.add_theme_constant_override("icon_max_width", 111)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := (slot.get_theme_stylebox(state) as StyleBoxFlat).duplicate() as StyleBoxFlat
		style.content_margin_top = 6
		style.content_margin_bottom = 30
		slot.add_theme_stylebox_override(state, style)
	slot.pressed.connect(_select_slot.bind(index))
	backpack_grid.add_child(slot)
	var name_label := _label(slot, 14, INK)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_left = 9
	name_label.offset_right = -37
	name_label.offset_top = -29
	name_label.offset_bottom = -8
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var quantity := _label(slot, 13, MUTED)
	quantity.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	quantity.offset_left = -33
	quantity.offset_right = -9
	quantity.offset_top = -29
	quantity.offset_bottom = -8
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	backpack_slots.append(slot)
	backpack_items.append("")
	backpack_names.append(name_label)
	backpack_quantities.append(quantity)

func _build_character_page(content: VBoxContainer) -> void:
	character_page = _menu_page(content)
	var sidebar := _column(_pane(character_page, WELL), 8)
	_label(sidebar, 14, MUTED, "装备部位")
	for item: String in EQUIPMENT_SLOTS:
		var button := _choice()
		button.custom_minimum_size.y = 60
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.add_theme_constant_override("icon_max_width", 49)
		button.pressed.connect(_select_equipment.bind(item))
		sidebar.add_child(button)
		var text := _column(button, 1)
		text.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
		text.offset_left = 11
		text.offset_top = -23
		_label(text, 12, MUTED, EQUIPMENT_SLOTS[item])
		equipment_names[item] = _label(text, 15, INK)
		equipment_buttons[item] = button

	var center := _column(character_page, 9)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stage := _stage(center)
	character_preview = CharacterPreview.new()
	stage.add_child(character_preview)
	character_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hint := _label(stage, 13, MUTED, "拖动旋转")
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -55
	hint.offset_right = 55
	hint.offset_top = -32
	hint.offset_bottom = -10
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var metrics := _row(_pane(center, WELL, Vector2(10, 7)), 8)
	for entry: Array in VITALS:
		var group := _column(metrics, 0)
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var stat := _label(group, 12, MUTED, entry[1])
		stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var value := _label(group, 18, entry[2], "", true)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		character_numbers[entry[0]] = value

	equipment_detail = _build_detail(character_page, [
		["wear", "穿上", true], ["remove_worn", "脱下", true], ["drop_worn", "丢下", false],
	], _submit_equipment_action)
	equipment_actions = equipment_detail.actions
	equipment_actions.remove_worn.tooltip_text = "脱下并收进背包"
	equipment_actions.drop_worn.tooltip_text = "脱下并丢到脚边"

func _stage(parent: Node) -> Control:
	var stage := Control.new()
	stage.custom_minimum_size.y = 112
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(stage)
	var glow := TextureRect.new()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.texture = stage_gradient
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return stage

func _build_detail(parent: Node, options: Array, submit: Callable) -> Dictionary:
	var pane := _pane(parent, TILE)
	var detail := _column(pane, 9)
	var header := _column(detail, 0)
	var type := _label(header, 13, AMBER)
	var title := _label(header, 25, INK, "", true)
	var stage := _stage(detail)
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.offset_left = 8
	image.offset_top = 8
	image.offset_right = -8
	image.offset_bottom = -8
	var info := _label(detail, 15, INK)
	var stats := _row(detail, 10)
	var values := {}
	for entry: Array in VITALS:
		values[entry[0]] = _label(stats, 13, entry[2])
	var note := _label(detail, 13, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := _row(detail, 6)
	var buttons := {}
	for entry: Array in options:
		var button := _button(entry[1], entry[2])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(submit.bind(entry[0]))
		actions.add_child(button)
		buttons[entry[0]] = button
	return {"pane": pane, "type": type, "title": title, "stage": stage, "image": image, "info": info,
		"stats": stats, "values": values, "note": note, "actions": buttons}

func _layout_backpack() -> void:
	var compact := base.size.x < 1020.0
	var short := base.size.y < 560.0
	for page: HBoxContainer in [inventory_page, character_page]:
		page.get_child(0).custom_minimum_size.x = 142.0 if compact else 171.0
	for detail: Dictionary in [inventory_detail, equipment_detail]:
		detail.pane.custom_minimum_size.x = 263.0 if compact else 302.0
		detail.stage.custom_minimum_size.y = 94.0 if short else 112.0
	for button: Button in equipment_buttons.values():
		button.custom_minimum_size.y = 49.0 if short else 60.0
	_layout_grid()
	_fit_backpack.call_deferred()

func _fit_backpack() -> void:
	var dimensions := Vector2(minf(base.size.x - 32.0, 1120.0), minf(base.size.y - 30.0, 600.0))
	backpack_panel.offset_left = -dimensions.x * 0.5
	backpack_panel.offset_right = dimensions.x * 0.5
	backpack_panel.offset_top = -dimensions.y * 0.5
	backpack_panel.offset_bottom = dimensions.y * 0.5

func _layout_grid() -> void:
	var expanded := bag_capacity > Survival.SLOT_COUNT
	var compact := base.size.x < 1020.0
	backpack_grid.columns = (3 if compact else 4) if expanded else 3
	var rows := maxi(1, ceili(float(bag_capacity) / backpack_grid.columns))
	var available_height := minf(base.size.y - 30.0, 600.0) - 125.0
	var slot_height := clampf(floorf((available_height - 8 * (rows - 1)) / rows), 60.0, 124.0 if expanded else 144.0)
	for slot: Button in backpack_slots:
		slot.custom_minimum_size = Vector2(74.0, slot_height)

func _show_character(show: bool) -> void:
	inventory_page.visible = not show
	character_page.visible = show
	inventory_tab.set_pressed_no_signal(not show)
	character_tab.set_pressed_no_signal(show)
	if show:
		character_preview.update_character(worn, wearing_backpack, preview_slot)
	_fit_backpack.call_deferred()

func _select_category(filter: String) -> void:
	category = filter
	_update_slot_controls()

func _matches_category(item: String) -> bool:
	match category:
		"food":
			return Survival.FOOD_STATS.has(item)
		"clothing":
			return Survival.CLOTHING.has(item)
	return true

func _select_slot(index: int) -> void:
	selected_slot = index
	_update_slot_controls()

func _submit_backpack_action(action: String) -> void:
	if selected_slot >= 0 and backpack_actions[action].visible and not backpack_actions[action].disabled:
		backpack_action_requested.emit(action, backpack_items[selected_slot])

func _update_slot_controls() -> void:
	var first := -1
	var counts := {"all": 0, "food": 0, "clothing": 0}
	for index in backpack_slots.size():
		var item := backpack_items[index]
		var visible_slot := index < bag_capacity and _matches_category(item)
		backpack_slots[index].visible = visible_slot
		if not item.is_empty():
			counts.all += 1
			counts["food" if Survival.FOOD_STATS.has(item) else "clothing"] += 1
			if visible_slot and first == -1:
				first = index
	if selected_slot < 0 or backpack_items[selected_slot].is_empty() or not backpack_slots[selected_slot].visible:
		selected_slot = first
	for filter: String in category_buttons:
		category_buttons[filter].set_pressed_no_signal(filter == category)
		category_counts[filter].text = str(counts[filter])
	for index in backpack_slots.size():
		backpack_slots[index].set_pressed_no_signal(index == selected_slot)
	_update_inventory_detail()

func _update_inventory_detail() -> void:
	var item := backpack_items[selected_slot] if selected_slot >= 0 else ""
	var clothing := Survival.CLOTHING.has(item)
	var food: Dictionary = Survival.FOOD_STATS.get(item, {})
	var detail := inventory_detail
	detail.type.text = "服装" if clothing else ("食物" if not food.is_empty() else "")
	detail.type.visible = not item.is_empty()
	detail_title.text = Survival.ITEM_NAMES.get(item, "背包为空" if category == "all" else "没有%s" % CATEGORIES[category])
	detail.image.texture = ITEM_ICONS.get(item)
	detail.image.modulate = Color(1.18, 1.18, 1.18) if clothing else Color.WHITE
	detail.info.visible = not item.is_empty()
	if clothing:
		detail.info.text = "%s    占用 1 格" % EQUIPMENT_SLOTS[item]
	elif not food.is_empty():
		var quantity := int(bag.get(item, 0))
		detail.info.text = "数量 %d 份" % quantity
		if quantity > Survival.stack_limit(item):
			detail.info.text = "此格 %s    共 %d 份" % [backpack_quantities[selected_slot].text, quantity]
	detail.stats.visible = not food.is_empty()
	for entry: Array in VITALS:
		var amount := int(food.get(entry[0], 0))
		var value: Label = detail.values[entry[0]]
		value.visible = amount > 0
		value.text = "%s +%d" % [entry[1], amount]
	var already_worn := bool(worn.get(item, false))
	var note := ""
	if item.is_empty() and category == "all":
		note = "用 E 拾取地上或桌上的物品"
	elif clothing and not clothing_supported:
		note = "此房间未开放穿戴"
	elif clothing and already_worn:
		note = "此部位已有装备"
	elif not food.is_empty() and not can_put_food:
		note = "靠近木桌后可放回"
	detail.note.text = note
	detail.note.visible = not note.is_empty()
	backpack_actions.eat.visible = not food.is_empty()
	backpack_actions.put.visible = not food.is_empty()
	backpack_actions.put.disabled = not can_put_food
	backpack_actions.wear.visible = clothing
	backpack_actions.wear.disabled = not clothing_supported or already_worn
	backpack_actions.drop.visible = not item.is_empty()

func _refresh_backpack(contents: Dictionary, can_put: bool, slot_capacity: int) -> void:
	slot_capacity = clampi(slot_capacity, 0, backpack_slots.size())
	if bag == contents and bag_capacity == slot_capacity:
		if can_put_food != can_put:
			can_put_food = can_put
			_update_inventory_detail()
		return
	var former_item := backpack_items[selected_slot] if selected_slot >= 0 else ""
	bag = contents.duplicate()
	bag_capacity = slot_capacity
	can_put_food = can_put
	var index := 0
	for item: String in Survival.ITEM_NAMES:
		var count := int(bag.get(item, 0))
		while count > 0 and index < slot_capacity:
			var stack := mini(count, Survival.stack_limit(item))
			_set_stack(index, item, stack)
			count -= stack
			index += 1
	for empty_index in range(index, backpack_slots.size()):
		_set_stack(empty_index, "", 0)
	if selected_slot >= 0 and backpack_items[selected_slot] != former_item:
		selected_slot = backpack_items.find(former_item) if not former_item.is_empty() else -1
	backpack_capacity.text = "%d / %d 格" % [index, slot_capacity]
	capacity_bar.max_value = maxi(1, slot_capacity)
	capacity_bar.value = index
	_layout_grid()
	_update_slot_controls()
	_refresh_equipment_controls()

func _set_stack(index: int, item: String, quantity: int) -> void:
	backpack_items[index] = item
	var slot := backpack_slots[index]
	slot.icon = ITEM_ICONS.get(item)
	slot.disabled = item.is_empty()
	slot.tooltip_text = Survival.ITEM_NAMES.get(item, "")
	backpack_names[index].text = slot.tooltip_text
	backpack_quantities[index].text = "×%d" % quantity if quantity > 0 else ""

func _select_equipment(item: String) -> void:
	selection = item
	_refresh_equipment_controls()

func _submit_equipment_action(action: String) -> void:
	if equipment_actions[action].visible and not equipment_actions[action].disabled:
		backpack_action_requested.emit(action, selection)

func set_equipment(survival: Dictionary, equipped_pack: bool, slot: int) -> void:
	var state: Dictionary = survival.get("worn", Survival.initial_wear())
	var supported := survival.has("worn")
	var changed := worn != state or wearing_backpack != equipped_pack or clothing_supported != supported or preview_slot != slot
	for entry: Array in VITALS:
		character_numbers[entry[0]].text = str(roundi(float(survival.get(entry[0], 100.0 if entry[0] == "health" else 0.0))))
	if changed:
		worn = state.duplicate()
		clothing_supported = supported
		wearing_backpack = equipped_pack
		preview_slot = slot
		_refresh_equipment_controls()
		_update_inventory_detail()
		if character_preview.started or character_page.visible:
			character_preview.update_character(worn, wearing_backpack, slot)

func _refresh_equipment_controls() -> void:
	for item: String in equipment_buttons:
		var equipped := wearing_backpack if item == "backpack" else bool(worn.get(item, false))
		var item_name: String = "背包" if item == "backpack" else Survival.CLOTHING[item]
		var button: Button = equipment_buttons[item]
		button.icon = ITEM_ICONS[item] if equipped else null
		button.set_pressed_no_signal(item == selection)
		equipment_names[item].text = item_name if equipped else "空"
		equipment_names[item].modulate = Color.WHITE if equipped else MUTED

	var pack := selection == "backpack"
	var equipped := wearing_backpack if pack else bool(worn.get(selection, false))
	var can_wear := not pack and clothing_supported and not equipped and int(bag.get(selection, 0)) > 0
	var can_remove := not pack and equipped and Survival.can_carry(bag, selection, bag_capacity)
	var detail := equipment_detail
	detail.type.text = EQUIPMENT_SLOTS[selection]
	detail.title.text = "背包" if pack else Survival.CLOTHING[selection]
	detail.image.texture = ITEM_ICONS[selection] if equipped or can_wear else null
	detail.image.modulate = Color(1.18, 1.18, 1.18)
	detail.info.text = "已装备" if equipped else ("在背包内" if can_wear else "未装备")
	detail.stats.hide()
	var note := ""
	if pack:
		note = "装备后增加 %d 格容量" % Survival.BACKPACK_SLOTS
	elif not clothing_supported:
		note = "此房间未开放穿戴"
	elif equipped:
		note = "脱下后占用 1 格" if can_remove else "背包已满，可丢到脚边"
	elif not can_wear:
		note = "背包里没有这件服装"
	detail.note.text = note
	detail.note.visible = not note.is_empty()
	equipment_actions.wear.visible = can_wear
	equipment_actions.remove_worn.visible = not pack and equipped
	equipment_actions.remove_worn.disabled = not clothing_supported or not can_remove
	equipment_actions.drop_worn.visible = not pack and equipped
	equipment_actions.drop_worn.disabled = not clothing_supported

func set_backpack_open(open: bool, contents: Dictionary = {}, can_put := false, slot_capacity := Survival.SLOT_COUNT) -> void:
	backpack_open = open
	backpack_shade.visible = open
	backpack_panel.visible = open
	field.visible = not open
	if open:
		panel.hide()
		_hide_invitation()
		_refresh_backpack(contents, can_put, slot_capacity)
		_update_slot_controls()
	else:
		selected_slot = -1

func show_invite(link: String) -> void:
	link_field.text = link
	link_sheet.get_parent().show()
	link_field.show()
	link_field.grab_focus()
	link_field.select_all()

func _hide_invitation() -> void:
	if link_field.visible:
		link_field.hide()
		link_sheet.get_parent().hide()

func say(message: String) -> void:
	toast.text = message
	menu_notice.text = message
	toast_until = Time.get_ticks_msec() + 3800

func _direction(angle: float) -> String:
	return HEADING[posmod(roundi(angle / (PI / 4)), 8)]

func refresh(s: Dictionary, target: String, delta_to_target: Vector2, action: String) -> void:
	area_title.text = AREA.get(s.zone,"林间营地")
	room_line.text = "房间 %s" % s.room
	room_count.text = "%s / 4 人" % s.members
	grove_hint.text = s.groveHint
	grove_hint.visible = not s.groveHint.is_empty()
	var phase := fposmod(float(s.elapsed), Rules.WEATHER_CYCLE)
	var time_name: String = {"dawn": "黎明", "day": "白天", "dusk": "暮色", "night": "夜晚"}.get(s.dayPart, "白天")
	var conditions := "晴间多云"
	if phase >= Rules.RAIN_START and phase < Rules.RAIN_END:
		conditions = "雨势渐强" if phase < Rules.RAIN_START + Rules.RAIN_RAMP else "暴雨"
		if phase >= Rules.RAIN_EASING:
			conditions = "雨势渐弱"
		if s.sheltered:
			conditions = "棚下避雨"
	elif phase >= Rules.RAIN_END and phase < Rules.RAIN_END + 35.0:
		conditions = "雨后放晴"
	elif phase < Rules.RAIN_START:
		var wait := ceili(Rules.RAIN_START - phase)
		conditions = "距降雨 %d:%02d" % [wait / 60, wait % 60]
	sky.text = "%s    ·    %s" % [time_name, conditions]
	if s.quest.get("repaired",false):
		goal_title.text = "营地已修好"
		supplies.text = "屋顶完好，营灯已点亮" if s.sheltered else "循灯光回营，与队友会合"
	else:
		goal_title.text = "返回营地修屋顶" if s.quest.get("wood",false) and s.quest.get("tarp",false) else "收集修屋材料"
		supplies.text = "木料 %d/1    防水布 %d/1"%[int(s.quest.get("wood",false)),int(s.quest.get("tarp",false))]
	var direction := atan2(-delta_to_target.x,-delta_to_target.y)
	var relative := wrapf(direction-float(s.yaw),-PI,PI)
	var arrow := "↑" if absf(relative)<.32 else ("身后" if absf(relative)>2.72 else ("←" if relative>0 else "→"))
	bearing_arrow.text = arrow
	bearing.text = GOALS.get(target, "营地")
	bearing_distance.text = "%d m" % roundi(delta_to_target.length())
	bearing.tooltip_text = "面向%s，目标在%s" % [_direction(s.yaw),_direction(direction)]
	var active: bool = s.locked
	entered_field = entered_field or active
	reticle.visible = active
	field_dock.visible = active
	prompt_panel.visible = active and not action.is_empty()
	if prompt_panel.visible:
		_update_prompt(action)
	panel.visible = not active and not backpack_open
	if active:
		_hide_invitation()
	var survival_state: Dictionary = s.get("survival", {})
	var has_survival := not survival_state.is_empty()
	if active:
		_update_key_guide(s.get("shipPiloting", false), s.get("swimming", false), has_survival,
			not s.heldStone.is_empty())
	for entry: Array in VITALS:
		var value := clampf(float(survival_state.get(entry[0], 100.0 if entry[0] == "health" else 0.0)), 0.0, 100.0)
		vital_bars[entry[0]].value = value
		vital_numbers[entry[0]].text = str(roundi(value))
	vitals.visible = has_survival
	if backpack_open:
		var expanded := int(s.get("bagSlots", Survival.SLOT_COUNT)) > Survival.SLOT_COUNT
		set_equipment(survival_state, expanded, int(s.players.get(s.selfId, {}).get("slot", 1)))
		_refresh_backpack(survival_state.get("bag", {}), bool(s.get("canPutProvision", false)), int(s.get("bagSlots", Survival.SLOT_COUNT)))
	var can_walk: bool = s.ready
	enter.disabled = not can_walk
	if not s.connected:
		enter.text = "正在连线…"
		briefing.text = s.status
	elif not s.focusReady:
		enter.text = "加载林区…"
		briefing.text = s.terrainError if not s.terrainError.is_empty() else "正在载入脚下林区"
	else:
		briefing_title.text = "营地菜单" if entered_field else "雨线营地"
		enter.text = "继续探索" if entered_field else "进入林地"
		if entered_field:
			briefing.text = "Esc 放开鼠标。"
		else:
			briefing.text = "去溪谷找木料，到瞭望塔取防水布。带回营地修好木棚。"
	if s.noticeNo != last_notice:
		last_notice = s.noticeNo
		if not s.notice.is_empty():
			say(s.notice)
	var has_notice := Time.get_ticks_msec() < toast_until
	toast_panel.visible = active and has_notice
	if not has_notice:
		menu_notice.text = ""
