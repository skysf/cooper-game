extends CanvasLayer

const Rules = preload("res://rules.gd")
const Survival = preload("res://survival.gd")
const Weapons = preload("res://weapons.gd")
const CharacterPreview = preload("res://character_preview.gd")
const Storage = preload("res://camp_storage.gd")
const FieldGuidePanel = preload("res://field_guide_panel.gd")
const CAMP_CONTOURS = preload("res://textures/camp_menu_contours.webp")
const ITEM_ICONS := {
	"reed_bundle": preload("res://textures/inventory_reed_bundle.png"),
	"crocodile_meat_raw": preload("res://textures/inventory_crocodile_meat_raw.png"),
	"crocodile_meat_grilled": preload("res://textures/inventory_crocodile_meat_grilled.png"),
	"crocodile_sandwich": preload("res://textures/inventory_crocodile_sandwich.png"),
	"eagle_meat": preload("res://textures/inventory_eagle_meat.png"),
	"boar_raw":preload("res://textures/inventory_boar_raw.png"),
	"boar_grilled":preload("res://textures/inventory_boar_grilled.png"),
	"boar_tusk":preload("res://textures/inventory_boar_tusk.png"),
	"boar_hide":preload("res://textures/inventory_boar_hide.png"),
	"boar_cloak":preload("res://textures/inventory_boar_cloak.png"),
	"tusk_whistle":preload("res://textures/inventory_tusk_whistle.png"),
	"boar_bedroll":preload("res://textures/inventory_boar_bedroll.png"),
	"wool": preload("res://textures/inventory_wool.png"),
	"lamb_raw": preload("res://textures/inventory_lamb_raw.png"),
	"lamb_grilled": preload("res://textures/inventory_lamb_grilled.png"),
	"dog_meat": preload("res://textures/inventory_dog_meat.png"),
	"crocodile_hide": preload("res://textures/inventory_crocodile_hide.png"),
	"eagle_feather": preload("res://textures/inventory_eagle_feather.png"),
	"eagle_claw": preload("res://textures/inventory_eagle_claw.png"),
	"wicker_strip": preload("res://textures/inventory_wicker_strip.png"),
	"wood_plank": preload("res://textures/inventory_wood_plank.png"),
	"rope": preload("res://textures/inventory_rope.png"),
	"apple": preload("res://textures/inventory_apple.png"),
	"bread": preload("res://textures/inventory_bread.png"),
	"cap": preload("res://textures/inventory_cap.png"),
	"helmet": preload("res://textures/inventory_helmet.png"),
	"jacket": preload("res://textures/inventory_jacket.png"),
	"pants": preload("res://textures/inventory_pants.png"),
	"backpack": preload("res://textures/inventory_backpack.png"),
	"club": preload("res://textures/inventory_club.png"),
	"spear": preload("res://textures/inventory_spear.png"),
	"shield": preload("res://textures/inventory_shield.png"),
	"stone": preload("res://textures/inventory_stone.png"),
	"water": preload("res://textures/inventory_water.png"),
	"herb": preload("res://textures/inventory_herb.png"),
	"wood": preload("res://textures/inventory_wood.png"),
	"tarp": preload("res://textures/inventory_tarp.png"),
	"katana": preload("res://textures/inventory_katana.png"),
	"rifle": preload("res://textures/inventory_rifle.png"),
	"pistol": preload("res://textures/inventory_pistol.png"),
}
const EQUIPMENT_SLOTS := {"cap": "头部", "jacket": "上身", "pants": "下身", "backpack": "背部","boar_cloak":"肩部"}
const CATEGORIES := {"all": "全部", "food": "食物", "material": "材料", "gear": "装备"}

signal resume_requested
signal invite_requested
signal backpack_close_requested
signal backpack_action_requested(action: String, item: String)
signal camp_page_requested(page: String)
signal habitat_requested(site: String)

const INK := Color("#f0eee4")
const MUTED := Color("#aebfbb")
const AMBER := Color("#f1c581")
const DARK := Color("#111a1b")
const PANEL := Color("#172324")
const WELL := Color("#131d1e")
const TILE := Color("#223031")
const EDGE := Color("#3e5250")
const HUD_FILL := Color("#122022ec")
const CAMP_PAPER := Color("#efe6ce")
const CAMP_SOFT := Color("#bac1a8")
const CAMP_FRAME := Color("#1f271e")
const CAMP_SURFACE := Color("#252e24")
const CAMP_BUTTON := Color("#354133")
const CAMP_TILE := Color("#192018")
const CAMP_GOLD := Color("#cab895")
const AREA := {"vine_gap":"藤蔓谷口","shale_steps":"赤层岩坡","reed_bank":"湖岸芦苇荡","root_trail":"根影林径","flower_valley":"箭袋树花谷","east_ridge":"层岩台地","coal_mine":"林坡煤矿","iron_mine":"层岩铁矿",
	"camp": "林间营地", "creek": "鹿鸣溪谷", "tower": "北坡瞭望塔", "lake": "鹿鸣湖岸",
	"coast-trail": "西岸山径", "headland": "海湾崖顶", "beach": "海湾浅滩", "ocean": "外海", "island": "外海小岛", "buddha": "乐山大佛"}
const GOALS := {"wood": "溪谷木料", "tarp": "瞭望塔防水布", "repair": "营地木棚"}
const HEADING := ["北", "西北", "西", "西南", "南", "东南", "东", "东北"]
const VITALS := [
	["health", "健康", Color("#ec9f8b")], ["hunger", "饱腹", Color("#e9be83")],
	["water", "水分", Color("#8bced7")], ["mood", "心情", Color("#bacd98")],
]
const GROUND_KEYS := [["WASD", "行走"], ["鼠标", "转向"], ["空格", "跳跃"], ["E", "互动"], ["K", "制作"], ["Q", "目标"], ["V", "视角"]]
const SWIM_KEYS := [["WASD", "游泳"], ["鼠标", "转向"], ["C", "下潜"], ["空格", "上浮"], ["V", "视角"]]
const FLIGHT_KEYS := [["WASD", "飞行"], ["鼠标", "转向"], ["空格", "上升"], ["C", "下降"], ["V", "视角"]]

var base := Control.new()
var ore_icons: Dictionary = {}
var field := Control.new()
var strong_font: FontVariation
var stage_gradient: GradientTexture2D
var area_title: Label
var room_line: Label
var room_count: Label
var grove_hint: Label
var raid_hint: Label
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
var scope_overlay := ColorRect.new()
var scope_material := ShaderMaterial.new()
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
var material_pending: Label
var backpack_grid: GridContainer
var inventory_view: VBoxContainer
var character_view: VBoxContainer
var inventory_page: HBoxContainer
var character_page: HBoxContainer
var guide_page: FieldGuidePanel
var camp_tabs: Dictionary = {}
var camp_location: Label
var camp_room: Label
var category_buttons: Dictionary = {}
var category := "all"
var backpack_slots: Array[Button] = []
var backpack_items: Array[String] = []
var backpack_names: Array[Label] = []
var backpack_quantities: Array[Label] = []
var backpack_actions: Dictionary = {}
var backpack_open := false
var modal_open := false
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
var headgear_buttons: Dictionary = {}
var headgear_row: HBoxContainer
var headgear_choice := ""
var selection := "jacket"
var worn: Dictionary = {}
var wearing_backpack := false
var clothing_supported := false
var equipped_weapon := ""
var drinking_full := false
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

func _camp_button(text := "", toggle := false, variant := "") -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = toggle
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size.y = 35
	if not variant.is_empty():
		button.theme_type_variation = variant
	return button

func _camp_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = base.theme.default_font
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", CAMP_PAPER)
	theme.set_stylebox("panel", "PanelContainer", _style(CAMP_FRAME, Color.TRANSPARENT, Vector2(13, 11)))
	theme.set_stylebox("normal", "Button", _style(CAMP_BUTTON, Color.TRANSPARENT, Vector2(10, 5)))
	theme.set_stylebox("hover", "Button", _style(Color("#465542"), Color.TRANSPARENT, Vector2(10, 5)))
	theme.set_stylebox("pressed", "Button", _style(Color("#495942"), CAMP_GOLD, Vector2(10, 5)))
	theme.set_stylebox("hover_pressed", "Button", theme.get_stylebox("pressed", "Button"))
	theme.set_stylebox("disabled", "Button", _style(CAMP_TILE, Color.TRANSPARENT, Vector2(10, 5)))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, "Button", CAMP_PAPER)
	theme.set_color("font_disabled_color", "Button", Color("#84907d"))
	theme.set_type_variation("CampPrimary", "Button")
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		theme.set_stylebox(state, "CampPrimary", _style(CAMP_GOLD.lightened(0.13) if state == "hover" else CAMP_GOLD, Color.TRANSPARENT, Vector2(10, 5)))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, "CampPrimary", CAMP_TILE)
	theme.set_type_variation("CampSlot", "Button")
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := theme.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		style.content_margin_top = 9
		style.content_margin_bottom = 31
		if state == "normal":
			style.bg_color = CAMP_TILE
		elif state == "disabled":
			style.bg_color = Color("#1c251c")
		theme.set_stylebox(state, "CampSlot", style)
	return theme

func _ready() -> void:
	add_child(base)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	var hud_font := preload("res://fonts/TrailSans.otf").duplicate() as FontFile
	hud_font.fallbacks = [preload("res://fonts/CampHanSupplement.otf"), preload("res://fonts/CampSignCJK.otf")]
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
	scope_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_material.shader = preload("res://weapon_scope.gdshader")
	scope_overlay.material = scope_material
	field.add_child(scope_overlay)
	scope_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scope_overlay.hide()
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
	raid_hint = _label(location, 14, AMBER)
	raid_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

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
	reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reticle.add_theme_constant_override("outline_size", 4)
	reticle.add_theme_color_override("font_outline_color", DARK)
	_place(field, reticle, Vector4(0.5, 0.5, 0.5, 0.5), Rect2(-10, -16, 20, 32))
	reticle.hide()

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
	for index in GROUND_KEYS.size() + 8:
		var group := _row(keys, 4)
		_keycap(group)
		_label(group, 14, INK)
		key_groups.append(group)

func set_weapon_view(weapon: String, aim: float, active: bool) -> void:
	scope_overlay.visible = active and weapon == "rifle" and aim > 0.24
	if scope_overlay.visible:
		scope_material.set_shader_parameter("strength", smoothstep(0.24, 0.82, aim))
	reticle.visible = active and not scope_overlay.visible and (weapon != "pistol" or aim < 0.80)

func _update_key_guide(piloting: bool, swimming: bool, has_survival: bool, holding: bool, weapon: String) -> void:
	var mode := "flight" if piloting else ("swim" if swimming else "ground")
	var profile := "%s/%s/%s/%s" % [mode, has_survival, holding, weapon]
	if profile == key_profile:
		return
	key_profile = profile
	var keys := (FLIGHT_KEYS if piloting else (SWIM_KEYS if swimming else GROUND_KEYS)).duplicate()
	if has_survival and not piloting:
		keys.append_array([["Tab", "背包"], ["B", "住民"]])
		if not holding:
			if not swimming and Weapons.firearm(weapon):
				keys.append_array([["左键", "射击"], ["右键", "开镜" if weapon == "rifle" else "瞄准"]])
			elif not swimming or not Weapons.CAMP_MODELS.has(weapon):
				keys.append(["左键", "近战"])
	if holding and not piloting:
		keys.append_array([["左键", "投掷"], ["G", "放下"]])
	keys.append(["M", "地图"])
	keys.append(["Shift+Esc", "菜单"])
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
	briefing_title = _label(content, 30, INK, "Cooper", true)
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
	backpack_shade.color = Color("#0d150edb")
	base.add_child(backpack_shade)
	backpack_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backpack_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	backpack_panel = _hud_card(base, Vector4(0.5, 0.5, 0.5, 0.5), Rect2())
	backpack_panel.theme = _camp_theme()
	var frame := _style(CAMP_SURFACE, Color("#56604b"), Vector2(0, 0))
	frame.shadow_color = Color("#0d150eaa")
	frame.shadow_size = 12
	frame.shadow_offset = Vector2(0, 5)
	backpack_panel.add_theme_stylebox_override("panel", frame)
	backpack_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var shell := _column(backpack_panel, 0)
	var top := _column(_camp_band(shell, CAMP_FRAME, Vector2(18, 11)), 9)
	var header := _row(top, 14)
	_label(header, 27, CAMP_PAPER, "Cooper", true)
	camp_location = _label(header, 14, CAMP_SOFT)
	camp_location.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camp_location.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var room := _camp_button("房间  Shift+Esc")
	room.pressed.connect(func(): camp_page_requested.emit("room"))
	header.add_child(room)
	var close := _camp_button("关闭  Esc")
	close.pressed.connect(func(): backpack_close_requested.emit())
	header.add_child(close)
	var nav := _row(top, 7)
	for entry: Array in [["map", "地图  M"], ["guide", "图鉴"], ["bag", "背包  Tab"], ["storage", "储物"],
			["role", "角色"], ["people", "住民  B"], ["field", "探索"]]:
		var local_page: bool = entry[0] in ["guide", "bag", "role"]
		var tab := _camp_button(entry[1], local_page)
		nav.add_child(tab)
		if local_page:
			camp_tabs[entry[0]] = tab
			tab.pressed.connect(_show_camp_page.bind(entry[0]))
		else:
			tab.pressed.connect(camp_page_requested.emit.bind(entry[0]))

	var colors := Gradient.new()
	colors.colors = PackedColorArray([Color("#445241"), Color("#333f32"), Color("#2b352b")])
	colors.offsets = PackedFloat32Array([0.00, 0.62, 1.00])
	stage_gradient = GradientTexture2D.new()
	stage_gradient.gradient = colors
	stage_gradient.fill = GradientTexture2D.FILL_RADIAL
	stage_gradient.fill_from = Vector2(0.5, 0.43)
	stage_gradient.fill_to = Vector2(1.0, 0.92)
	stage_gradient.width = 192
	stage_gradient.height = 192

	var content_pane := _camp_band(shell, Color.TRANSPARENT, Vector2(18, 14))
	content_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content := _column(content_pane, 10)
	_build_inventory_page(content)
	_build_character_page(content)
	guide_page = FieldGuidePanel.new()
	content.add_child(guide_page)
	guide_page.habitat_requested.connect(habitat_requested.emit)
	var footer := _row(_camp_band(shell, CAMP_FRAME, Vector2(18, 6)), 14)
	menu_notice = _label(footer, 13, CAMP_GOLD)
	menu_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	camp_room = _label(footer, 13, CAMP_SOFT)
	_show_camp_page("bag")
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

func _camp_band(parent: Node, bg: Color, padding: Vector2) -> PanelContainer:
	var pane := _pane(parent, bg, padding)
	pane.add_theme_stylebox_override("panel", _style(bg, Color.TRANSPARENT, padding))
	return pane

func _build_inventory_page(content: VBoxContainer) -> void:
	inventory_view = _column(content, 12)
	inventory_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var heading := _row(inventory_view, 10)
	_label(heading, 26, CAMP_PAPER, "背包", true)
	backpack_capacity = _label(heading, 14, CAMP_SOFT)
	backpack_capacity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inventory_page = _menu_page(inventory_view)
	var sidebar := _column(inventory_page, 6)
	for filter: String in CATEGORIES:
		var button := _camp_button(CATEGORIES[filter], true)
		button.custom_minimum_size = Vector2(68, 48)
		button.pressed.connect(_select_category.bind(filter))
		sidebar.add_child(button)
		category_buttons[filter] = button

	var items := ScrollContainer.new()
	items.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_page.add_child(items)
	backpack_grid = GridContainer.new()
	backpack_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	backpack_grid.add_theme_constant_override("h_separation", 6)
	backpack_grid.add_theme_constant_override("v_separation", 6)
	backpack_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	items.add_child(backpack_grid)
	for index in Survival.slot_count(true):
		_build_inventory_slot(index)
	inventory_detail = _build_detail(inventory_page, [
		["eat", "吃一份", true], ["drink", "喝一份", true], ["wear", "穿上", true],
		["whistle","吹哨召回",true], ["unroll","铺开休息",true],
		["equip", "装备", true], ["put", "放桌上", false], ["drop", "丢下", false], ["guide", "查看图鉴", false],
	], _submit_backpack_action)
	backpack_actions = inventory_detail.actions
	detail_title = inventory_detail.title
	backpack_actions.drop.tooltip_text = "丢到脚边"
	backpack_actions.put.tooltip_text = "将一份食物或溪水放到木桌"
	material_pending = _label(inventory_view, 13, CAMP_GOLD)
	material_pending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	material_pending.hide()

func _build_inventory_slot(index: int) -> void:
	var slot := _camp_button("", true, "CampSlot")
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.expand_icon = true
	slot.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.add_theme_constant_override("icon_max_width", 111)
	slot.pressed.connect(_select_slot.bind(index))
	backpack_grid.add_child(slot)
	var name_label := _label(slot, 14, CAMP_PAPER)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_left = 4
	name_label.offset_right = -4
	name_label.offset_top = -25
	name_label.offset_bottom = -4
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var quantity := _label(slot, 13, CAMP_PAPER)
	quantity.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	quantity.offset_left = -73
	quantity.offset_right = -6
	quantity.offset_top = 3
	quantity.offset_bottom = 24
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	backpack_slots.append(slot)
	backpack_items.append("")
	backpack_names.append(name_label)
	backpack_quantities.append(quantity)

func _build_character_page(content: VBoxContainer) -> void:
	character_view = _column(content, 12)
	character_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label(character_view, 26, CAMP_PAPER, "角色", true)
	character_page = _menu_page(character_view)
	var center := _column(character_page, 9)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stage := _stage(center, true)
	var layout := _row(stage, 8)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 12
	layout.offset_top = 10
	layout.offset_right = -12
	layout.offset_bottom = -10
	var layers := _column(layout, 8)
	layers.alignment = BoxContainer.ALIGNMENT_CENTER
	var stand := _column(layout, 5)
	stand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kit := _column(layout, 8)
	kit.alignment = BoxContainer.ALIGNMENT_CENTER
	for item: String in EQUIPMENT_SLOTS:
		var button := _camp_button("", true, "CampSlot")
		button.custom_minimum_size = Vector2(86, 96)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", 70)
		button.pressed.connect(_select_equipment.bind(item))
		(kit if item in ["backpack","boar_cloak"] else layers).add_child(button)
		var label := _label(button, 14, CAMP_PAPER)
		label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		label.offset_top = -26
		label.offset_bottom = -4
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.tooltip_text = EQUIPMENT_SLOTS[item]
		equipment_names[item] = label
		equipment_buttons[item] = button

	character_preview = CharacterPreview.new()
	character_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stand.add_child(character_preview)
	var turns := _row(stand, 6)
	turns.alignment = BoxContainer.ALIGNMENT_CENTER
	var left := _camp_button("‹")
	left.tooltip_text = "向左旋转角色"
	left.pressed.connect(character_preview.rotate_by.bind(-PI / 4.0))
	turns.add_child(left)
	var hint := _label(turns, 13, CAMP_SOFT, "拖动旋转")
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var right := _camp_button("›")
	right.tooltip_text = "向右旋转角色"
	right.pressed.connect(character_preview.rotate_by.bind(PI / 4.0))
	turns.add_child(right)
	var metrics := _row(_camp_band(center, CAMP_FRAME, Vector2(10, 7)), 8)
	for entry: Array in VITALS:
		var group := _column(metrics, 0)
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var stat := _label(group, 12, CAMP_SOFT, entry[1])
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
	headgear_row = _row(equipment_detail.header, 6)
	for item: String in ["cap", "helmet"]:
		var button := _camp_button(Survival.ITEM_NAMES[item], true)
		button.pressed.connect(_select_headgear.bind(item))
		headgear_row.add_child(button)
		headgear_buttons[item] = button

func _stage(parent: Node, contours := false) -> Control:
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
	if contours:
		var map := TextureRect.new()
		map.texture = CAMP_CONTOURS
		map.modulate.a = 0.18
		map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		map.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(map)
		map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return stage

func _build_detail(parent: Node, options: Array, submit: Callable) -> Dictionary:
	var pane := _camp_band(parent, CAMP_FRAME, Vector2(13, 11))
	var detail := _column(pane, 9)
	var header := _column(detail, 6)
	var heading := _row(header, 7)
	var title := _label(heading, 24, CAMP_PAPER, "", true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var type := _label(heading, 13, CAMP_SOFT)
	type.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	var info := _label(detail, 15, CAMP_PAPER)
	var stats := _row(detail, 10)
	var values := {}
	for entry: Array in VITALS:
		values[entry[0]] = _label(stats, 13, entry[2])
	var note := _label(detail, 13, CAMP_SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := _row(detail, 6)
	var buttons := {}
	for entry: Array in options:
		var button := _camp_button(entry[1], false, "CampPrimary" if entry[2] else "")
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(submit.bind(entry[0]))
		actions.add_child(button)
		buttons[entry[0]] = button
	return {"pane": pane, "header": header, "type": type, "title": title, "stage": stage, "image": image, "info": info,
		"stats": stats, "values": values, "note": note, "actions": buttons}

func _layout_backpack() -> void:
	var short := base.size.y < 650.0
	for detail: Dictionary in [inventory_detail, equipment_detail]:
		detail.pane.custom_minimum_size.x = clampf(base.size.x * .35, 288.0, 456.0)
		detail.stage.custom_minimum_size.y = 94.0 if short else 112.0
	for button: Button in equipment_buttons.values():
		button.custom_minimum_size.y = 72.0 if short else 96.0
	_layout_grid()
	_fit_backpack.call_deferred()

func _fit_backpack() -> void:
	var dimensions := Vector2(minf(base.size.x - 32.0, 1220.0), minf(base.size.y - 30.0, 682.0))
	backpack_panel.offset_left = -dimensions.x * 0.5
	backpack_panel.offset_right = dimensions.x * 0.5
	backpack_panel.offset_top = -dimensions.y * 0.5
	backpack_panel.offset_bottom = dimensions.y * 0.5

func _layout_grid() -> void:
	var expanded := bag_capacity > Survival.SLOT_COUNT
	var compact := base.size.x < 960.0
	backpack_grid.columns = (3 if compact else 4) if expanded else 3
	var rows := maxi(1, ceili(float(bag_capacity) / backpack_grid.columns))
	var available_height := minf(base.size.y - 30.0, 682.0) - 205.0
	var slot_height := clampf(floorf((available_height - 6 * (rows - 1)) / rows), 73.0, 137.0 if expanded else 156.0)
	for slot: Button in backpack_slots:
		slot.custom_minimum_size = Vector2(74.0, slot_height)

func _show_camp_page(page: String) -> void:
	inventory_view.visible = page == "bag"
	character_view.visible = page == "role"
	guide_page.visible = page == "guide"
	for id: String in camp_tabs:
		camp_tabs[id].set_pressed_no_signal(id == page)
	if character_view.visible:
		character_preview.update_character(worn, wearing_backpack, preview_slot)
	_fit_backpack.call_deferred()

func _select_category(filter: String) -> void:
	category = filter
	_update_slot_controls()

func _item_category(item: String) -> String:
	if Survival.FOOD_STATS.has(item) or Survival.is_drinkable(item):
		return "food"
	if Storage.ORE_ICONS.has(item) or item in ["boar_hide","boar_tusk", "wood", "tarp", "wood_plank", "reed_bundle", "wicker_strip", "rope", "crocodile_hide", "eagle_feather", "eagle_claw"]:
		return "material"
	return "gear"

func _select_slot(index: int) -> void:
	selected_slot = index
	_update_slot_controls()

func _submit_backpack_action(action: String) -> void:
	if selected_slot >= 0 and backpack_actions[action].visible and not backpack_actions[action].disabled:
		var item := backpack_items[selected_slot]
		if action == "guide":
			guide_page.show_recipe(item)
			_show_camp_page("guide")
		else:
			backpack_action_requested.emit(action, item)

func _update_slot_controls() -> void:
	var first := -1
	for index in backpack_slots.size():
		var item := backpack_items[index]
		var group := _item_category(item)
		var visible_slot := index < bag_capacity and (category == "all" or not item.is_empty() and group == category)
		backpack_slots[index].visible = visible_slot
		if not item.is_empty() and visible_slot and first == -1:
			first = index
	if selected_slot < 0 or backpack_items[selected_slot].is_empty() or not backpack_slots[selected_slot].visible:
		selected_slot = first
	for filter: String in category_buttons:
		category_buttons[filter].set_pressed_no_signal(filter == category)
	for index in backpack_slots.size():
		backpack_slots[index].set_pressed_no_signal(index == selected_slot)
	_update_inventory_detail()

func _item_icon(item: String) -> Texture2D:
	if not Storage.ORE_ICONS.has(item):
		return ITEM_ICONS.get(item)
	if not ore_icons.has(item):
		var path: String = Storage.ORE_ICONS[item]
		ore_icons[item] = load(path) if ResourceLoader.exists(path) else null
	return ore_icons[item]

func _update_inventory_detail() -> void:
	var item := backpack_items[selected_slot] if selected_slot >= 0 else ""
	var clothing := Survival.CLOTHING.has(item)
	var food: Dictionary = Survival.FOOD_STATS.get(item, {})
	var drinkable := Survival.is_drinkable(item)
	var table_item := Survival.can_table(item)
	var weapon := Weapons.CAMP_MODELS.has(item) or item == "wicker_strip"
	var benefits: Dictionary = {"water": Survival.DRINK_GAIN} if drinkable else food
	var detail := inventory_detail
	detail.type.text = "服装" if clothing else ("溪水" if drinkable else CATEGORIES[_item_category(item)])
	detail.type.visible = not item.is_empty()
	detail_title.text = Survival.ITEM_NAMES.get(item, "背包为空" if category == "all" else "没有%s" % CATEGORIES[category])
	detail.image.texture = FieldGuidePanel.COOKING[item][2] if item in Survival.COOKING_DISCOVERIES else _item_icon(item)
	detail.image.modulate = Color(1.18, 1.18, 1.18) if clothing else Color.WHITE
	detail.info.visible = not item.is_empty()
	if clothing:
		detail.info.text = "%s · 数量 %d · 占用 1 格" % [EQUIPMENT_SLOTS["cap" if item == "helmet" else item], int(bag.get(item, 0))]
	elif not item.is_empty():
		var quantity := int(bag.get(item, 0))
		detail.info.text = "数量 %d 份" % quantity
	detail.stats.visible = not benefits.is_empty()
	for entry: Array in VITALS:
		var amount := int(benefits.get(entry[0], 0))
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
	elif item=="boar_cloak":
		note="穿在夹克外，雨天的心情损耗减少三分之一。"
	elif item=="tusk_whistle":
		note="吹哨可唤回 36 米内自己收养的藏獒。"
	elif item=="boar_bedroll":
		note="在平地铺开，每次可供一人休息。空置时按 G 收卷。"
	elif item == "wicker_strip":
		note = "装备后左键抽击。也可编织、引火或加固俘虏约束。"
	elif item in ["wood", "tarp"]:
		note = "修屋时消耗你背包中的木料 1 份和防水布 1 份；丢下后可交给队友"
	elif weapon:
		var key := char(int(Weapons.KEYS.find_key(item)))
		note = "%s 切换 · 左键挥刀" % key if item == "katana" else "%s 切换 · 左键射击 · 按住右键%s" % [key, "开镜" if item == "rifle" else "瞄准"]
		detail.info.text = "数量 %d · %s" % [int(bag.get(item, 0)), "已装备" if equipped_weapon == item else "占用 1 格"]
	elif table_item and not can_put_food:
		note = "靠近木桌后可放回"
	detail.note.text = note
	detail.note.visible = not note.is_empty()
	backpack_actions.eat.visible = not food.is_empty()
	backpack_actions.drink.visible = drinkable
	backpack_actions.drink.disabled = drinking_full
	backpack_actions.drink.tooltip_text = "现在不渴，溪水会保留" if drinking_full else "消耗一份溪水，水分 +32"
	backpack_actions.put.visible = table_item
	backpack_actions.put.disabled = not can_put_food
	backpack_actions.wear.visible = clothing
	backpack_actions.wear.disabled = not clothing_supported or already_worn
	backpack_actions.whistle.visible=item=="tusk_whistle"
	backpack_actions.unroll.visible=item=="boar_bedroll"
	backpack_actions.equip.visible = weapon
	backpack_actions.equip.text = "收起" if equipped_weapon == item else "装备"
	backpack_actions.drop.visible = not item.is_empty()
	backpack_actions.guide.visible = guide_page.has_recipe_page(item)

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
	for entry: Dictionary in Survival.inventory_entries(bag):
		if index >= slot_capacity:
			break
		_set_stack(index, entry.item, entry.quantity)
		index += 1
	for empty_index in range(index, backpack_slots.size()):
		_set_stack(empty_index, "", 0)
	if selected_slot >= 0 and backpack_items[selected_slot] != former_item:
		selected_slot = backpack_items.find(former_item) if not former_item.is_empty() else -1
	backpack_capacity.text = "%d / %d 格" % [index, slot_capacity]
	_layout_grid()
	_update_slot_controls()
	_refresh_equipment_controls()

func _set_stack(index: int, item: String, quantity: int) -> void:
	backpack_items[index] = item
	var slot := backpack_slots[index]
	slot.icon = _item_icon(item)
	slot.disabled = item.is_empty()
	slot.tooltip_text = Survival.ITEM_NAMES.get(item, "")
	backpack_names[index].text = slot.tooltip_text
	backpack_quantities[index].text = "×%d" % quantity if quantity > 0 else ""

func _select_equipment(item: String) -> void:
	selection = item
	headgear_choice = ""
	_refresh_equipment_controls()

func _select_headgear(item: String) -> void:
	headgear_choice = item
	_refresh_equipment_controls()

func _selected_equipment() -> String:
	return headgear_choice if selection == "cap" and not headgear_choice.is_empty() else _equipment_at(selection)

func _equipment_at(slot: String) -> String:
	if slot == "cap" and (bool(worn.get("helmet", false)) or (not bool(worn.get("cap", false)) and int(bag.get("helmet", 0)) > 0)):
		return "helmet"
	return slot

func _submit_equipment_action(action: String) -> void:
	if equipment_actions[action].visible and not equipment_actions[action].disabled:
		backpack_action_requested.emit(action, _selected_equipment())

func set_equipment(survival: Dictionary, equipped_pack: bool, slot: int) -> void:
	if guide_page.set_progress(survival.get("fieldGuide", {})):
		_update_inventory_detail()
	var pending: Dictionary = survival.get("materialPending", {})
	material_pending.visible = int(pending.get("wood", 0)) + int(pending.get("tarp", 0)) > 0
	material_pending.text = "营地保留的材料待收取：木料 %d / 布 %d。空出格子后会放入背包。" % [pending.get("wood", 0), pending.get("tarp", 0)]
	var full := float(survival.get("water", 100.0)) >= Survival.DRINK_THRESHOLD
	var weapon: String = survival.get("weapon", "")
	if drinking_full != full or equipped_weapon != weapon:
		drinking_full = full
		equipped_weapon = weapon
		_update_inventory_detail()
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
		if character_preview.started or character_view.visible:
			character_preview.update_character(worn, wearing_backpack, slot)

func _refresh_equipment_controls() -> void:
	for slot: String in equipment_buttons:
		var item := _equipment_at(slot)
		var equipped := wearing_backpack if item == "backpack" else bool(worn.get(item, false))
		var item_name: String = "背包" if item == "backpack" else Survival.CLOTHING[item]
		var button: Button = equipment_buttons[slot]
		button.icon = ITEM_ICONS[item] if equipped else null
		button.set_pressed_no_signal(slot == selection)
		equipment_names[slot].text = item_name if equipped else EQUIPMENT_SLOTS[slot]
		equipment_names[slot].modulate = Color.WHITE if equipped else CAMP_SOFT

	var selected_item := _selected_equipment()
	headgear_row.visible = selection == "cap"
	for item: String in headgear_buttons:
		headgear_buttons[item].set_pressed_no_signal(selected_item == item)
	var pack := selection == "backpack"
	var equipped := wearing_backpack if pack else bool(worn.get(selected_item, false))
	var can_wear := not pack and clothing_supported and not equipped and int(bag.get(selected_item, 0)) > 0
	var can_remove := not pack and equipped and Survival.can_carry(bag, selected_item, bag_capacity)
	var detail := equipment_detail
	detail.type.text = EQUIPMENT_SLOTS[selection]
	detail.title.text = "背包" if pack else Survival.CLOTHING[selected_item]
	detail.image.texture = ITEM_ICONS[selected_item] if equipped or can_wear else null
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

func show_target_distance(s: Dictionary, offset: Vector2) -> void:
	var metres := offset.length()
	if s.get("shipPiloting", false):
		var below := Vector2(s.x, s.z) + offset
		var rise := float(s.flightAltitude) + Rules.LakeLayout.water_y() - Rules.LakeLayout.ground_height(below)
		metres = Vector2(metres, rise).length()
	bearing_distance.text = "%.1f km" % (metres * 0.001) if metres >= 1000.0 else "%d m" % roundi(metres)

func refresh(s: Dictionary, target: String, delta_to_target: Vector2, action: String) -> void:
	area_title.text = AREA.get(s.zone,"林间营地")
	if float(s.get("flightAltitude", 0.0)) >= 1000.0:
		area_title.text += "上空"
	room_line.text = "房间 %s" % s.room
	room_count.text = "%s / 4 人" % s.members
	grove_hint.text = s.groveHint
	grove_hint.visible = not s.groveHint.is_empty()
	var people: Dictionary = s.get("wildPeople", {})
	var raid: Dictionary = people.get("raid", {})
	var raid_wait := maxi(0, ceili(float(raid.get("nextAt", 0.0)) - float(s.elapsed)))
	raid_hint.text = ("来袭警报 · %d 秒" % raid_wait if raid.get("phase") == "warning" else "来袭进行中 · B 查看住民" if raid.get("phase") == "active" else "休整 · 下次来袭 %d:%02d" % [raid_wait / 60, raid_wait % 60])
	raid_hint.visible = not people.is_empty()
	var phase := fposmod(float(s.elapsed), Rules.WEATHER_CYCLE)
	var time_name: String = {"dawn": "黎明", "day": "白天", "dusk": "暮色", "night": "夜晚"}.get(s.dayPart, "白天")
	var conditions := "晴间多云"
	if float(s.get("flightAltitude", 0.0)) >= Rules.CLOUD_TOP_METRES:
		conditions = "云层上方"
	elif phase >= Rules.RAIN_START and phase < Rules.RAIN_END:
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
		goal_title.text = "返回营地修屋顶" if int(s.get("survival", {}).get("bag", {}).get("wood", 0)) > 0 and int(s.get("survival", {}).get("bag", {}).get("tarp", 0)) > 0 else "收集你的修屋材料"
		supplies.text = "木料 %d/1    防水布 %d/1"%[int(s.get("survival", {}).get("bag", {}).get("wood", 0)),int(s.get("survival", {}).get("bag", {}).get("tarp", 0))]
	var direction := atan2(-delta_to_target.x,-delta_to_target.y)
	var relative := wrapf(direction-float(s.yaw),-PI,PI)
	var arrow := "↑" if absf(relative)<.32 else ("身后" if absf(relative)>2.72 else ("←" if relative>0 else "→"))
	bearing_arrow.text = arrow
	bearing.text = GOALS.get(target, "营地")
	show_target_distance(s, delta_to_target)
	bearing.tooltip_text = "面向%s，目标在%s" % [_direction(s.yaw),_direction(direction)]
	var active: bool = s.locked
	var show_world := not backpack_open and not modal_open
	var waiting_for_mouse: bool = s.ready and not s.menuOpen and not active
	entered_field = entered_field or active
	field_dock.visible = active or waiting_for_mouse
	prompt_panel.visible = waiting_for_mouse or (active and not action.is_empty())
	if prompt_panel.visible:
		_update_prompt("点击画面继续探索" if waiting_for_mouse else action)
	panel.visible = s.menuOpen and not active and show_world
	field.visible = show_world
	if active:
		_hide_invitation()
	var survival_state: Dictionary = s.get("survival", {})
	var has_survival := not survival_state.is_empty()
	if active:
		_update_key_guide(s.get("shipPiloting", false), s.get("swimming", false), has_survival,
			not s.heldStone.is_empty(), survival_state.get("weapon", ""))
	for entry: Array in VITALS:
		var value := clampf(float(survival_state.get(entry[0], 100.0 if entry[0] == "health" else 0.0)), 0.0, 100.0)
		vital_bars[entry[0]].value = value
		vital_numbers[entry[0]].text = str(roundi(value))
	vitals.visible = has_survival
	if backpack_open:
		camp_location.text = area_title.text
		camp_room.text = "%s  ·  %s" % [room_line.text, room_count.text]
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
		briefing_title.text = "营地菜单" if entered_field else "Cooper"
		enter.text = "继续探索" if entered_field else "进入林地"
		if entered_field:
			briefing.text = "Shift+Esc 放开鼠标。"
		else:
			briefing.text = "去溪谷找木料，到瞭望塔取防水布。带回营地修好木棚。木屋旁可按 E 拾取武器，Tab 打开背包装备，B 查看住民与补给。"
	if s.noticeNo != last_notice:
		last_notice = s.noticeNo
		if not s.notice.is_empty():
			say(s.notice)
	var has_notice := Time.get_ticks_msec() < toast_until
	toast_panel.visible = active and has_notice
	if not has_notice:
		menu_notice.text = ""

# Observation only: normal UI tests still click these Controls and send their ordinary actions.
func inventory_observables() -> Dictionary:
	var slots := []
	for index in backpack_slots.size():
		var rect := backpack_slots[index].get_global_rect()
		slots.append({"item": backpack_items[index], "quantity": int(backpack_quantities[index].text.trim_prefix("×")),
			"visible": backpack_slots[index].is_visible_in_tree(), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	var actions := {}
	for key: String in backpack_actions:
		var button: Button = backpack_actions[key]
		var rect := button.get_global_rect()
		actions[key] = {"visible": button.is_visible_in_tree(), "disabled": button.disabled, "text": button.text,
			"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]}
	var pages := {}
	for id: String in camp_tabs:
		var rect: Rect2 = camp_tabs[id].get_global_rect()
		pages[id] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	return {"open": backpack_open, "slots": slots, "selectedItem": backpack_items[selected_slot] if selected_slot >= 0 else "", "actions": actions, "pages": pages}
