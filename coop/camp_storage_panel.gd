extends CanvasLayer

const Storage := preload("res://camp_storage.gd")
const Survival := preload("res://survival.gd")
const SIGN_FONT := preload("res://fonts/CampSignCJK.otf")
const SHELL := Color("#282d22")
const CREAM := Color("#efe6cb")
const MUTED := Color("#c2c2a1")
const EDGE := Color("#626b51")
const PAPER := Color("#e2d9bd")
const PAPER_LIGHT := Color("#eee6cd")
const PAPER_EDGE := Color("#aaa487")
const INK := Color("#353b2b")
const SUBTLE_INK := Color("#5d624e")
const SLOT_SIZE := Vector2(54, 88)

signal close_requested
signal action_requested(action: String, fields: Dictionary)

var is_open := false
var _mode := "storage"
var _id := ""
var _records: Dictionary = {}
var _bag: Dictionary = {}
var _bag_capacity := Survival.SLOT_COUNT
var _elapsed := 0.0
var _self_id := ""
var _signature: Array = []
var _icons: Dictionary = {}
var _shade: ColorRect
var _margins: MarginContainer
var _title: Label
var _summary: Label
var _message: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _grid: GridContainer
var _recipe_buttons: Dictionary = {}
var _slot_grids: Array[GridContainer] = []
var _empty_slot_style: StyleBoxFlat
var _sign_edit: LineEdit
var _save_sign: Button
var _sign_label: Label
var _sign_saved := ""

func _ready() -> void:
	layer = 14
	_shade = ColorRect.new()
	_shade.color = Color(0.065, 0.076, 0.052, 0.78)
	_shade.mouse_force_pass_scroll_events = false
	add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.theme = _theme()
	_margins = MarginContainer.new()
	_shade.add_child(_margins)
	_margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _style(SHELL, EDGE, 13))
	_margins.add_child(frame)
	var body := _column(frame, 9)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	body.add_child(header)
	var heading := _column(header, 2)
	_title = _label(heading, "", 25, CREAM)
	_summary = _label(heading, "", 13, MUTED)
	var close := _button(header, "关闭  Esc")
	close.pressed.connect(func(): close_requested.emit())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	_content = _column(_scroll, 9)
	_message = _label(body, "", 13, CREAM)
	_message.hide()
	_shade.resized.connect(_resize)
	_resize()
	visible = is_open
	if is_open:
		_refresh()

func set_open(open: bool, mode := "storage", id := "") -> void:
	var changed := not is_open or mode != _mode or id != _id
	is_open = open
	visible = open
	if not open:
		return
	_mode = mode
	_id = id
	if changed:
		_signature.clear()
		if _scroll != null:
			_scroll.scroll_vertical = 0
			_message.hide()
	if is_node_ready():
		_refresh()

func sync(records: Dictionary, bag: Dictionary, elapsed: float, self_id: String, bag_capacity := Survival.SLOT_COUNT) -> void:
	_records = records
	_bag = bag
	_bag_capacity = bag_capacity
	_elapsed = elapsed
	_self_id = self_id
	if is_open and is_node_ready():
		_refresh()

func feedback(text: String) -> void:
	if _message == null:
		return
	_message.text = text
	_message.visible = not text.is_empty()

func observables() -> Dictionary:
	var controls := {}
	if is_open:
		var area := _scroll.get_global_rect()
		for key: String in _recipe_buttons:
			var button: Button = _recipe_buttons[key]
			var rect := button.get_global_rect().intersection(area)
			controls[key] = {"disabled":button.disabled,"visible":rect.has_area(),
				"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]}
	return {"mode":_mode if is_open else "","recipes":controls}

func _refresh() -> void:
	var record: Dictionary = _records.get(_id, {})
	var kind: String = record.get("kind", "")
	var info: Dictionary = Storage.KINDS.get(kind, {})
	var contents: Dictionary = record.get("bag", {})
	var on_ground: bool = record.get("mode") == "ground"
	var corpse := kind.begins_with("corpse_")
	var can_use: bool = on_ground or (record.get("mode") == "held" and record.get("holder", "") == _self_id)
	var fuel_seconds := maxi(0, ceili(float(record.get("fuelUntil", 0.0)) - _elapsed))
	var batch_time: float = record.get("batchReady",0.0)
	var batch_stage := 0 if batch_time <= 0.0 else (1 if batch_time > _elapsed else 2)
	var editing: bool = not _self_id.is_empty() and record.get("owner", "") == _self_id
	var signature: Array = [_mode, _id, kind, on_ground, can_use, editing, fuel_seconds > 0, batch_stage, _bag_capacity]
	if _mode != "sign":
		signature.append(_bag.duplicate())
		signature.append(contents.duplicate())
	var saved_sign: String = record.get("text", "")
	if signature != _signature:
		_signature = signature
		var position := _scroll.scroll_vertical
		_clear_content()
		match _mode:
			"craft":
				_title.text = "营地制作"
				_recipe_cards(_content, "camp", true)
			"storage":
				_title.text = info.get("name", "储物")
				if can_use:
					_storage(contents, int(info.get("capacity", 0)), corpse)
			"fire":
				_title.text = info.get("name", "营火")
				if can_use:
					_fire(fuel_seconds > 0)
			"furnace":
				_title.text = info.get("name","炼铁炉")
				if can_use:
					_furnace(on_ground,batch_stage)
			"sign":
				_title.text = info.get("name", "木牌")
				if can_use:
					_build_sign(saved_sign, editing)
			_:
				_title.text = info.get("name", "营地摆设")
		if _mode != "craft":
			if can_use:
				_fixture_actions(kind, info, on_ground and batch_stage == 0)
			else:
				_placeholder(_content, "物品已移走或正在被搬运。")
		_resize()
		_scroll.set_deferred("scroll_vertical", position)
	match _mode:
		"craft":
			_summary.text = "从背包取用制作材料"
		"storage":
			_summary.text = "点击格子取出一份" if can_use and corpse else "点击格子转移一份" if can_use else ""
		"fire":
			_summary.text = ""
			if can_use:
				_summary.text = "剩余 %d 分 %02d 秒" % [floori(fuel_seconds / 60.0), fuel_seconds % 60] if fuel_seconds > 0 else "营火已熄灭"
		"furnace":
			_summary.text = "炉内还剩 %d 秒" % ceili(batch_time - _elapsed) if batch_stage == 1 else (
				"铁锭已炼好" if batch_stage == 2 else "每炉可炼一块铁锭")
		"sign":
			_summary.text = "你可以编辑这块木牌" if editing else ""
			_update_sign(saved_sign)
		_:
			_summary.text = ""

func _storage(contents: Dictionary, capacity: int, corpse: bool) -> void:
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 14)
	_content.add_child(sides)
	_storage_grid(sides, "可拾取物品" if corpse else "容器内", contents, capacity, _bag, _bag_capacity, "take")
	_storage_grid(sides, "随身背包", _bag, _bag_capacity, contents, capacity, "" if corpse else "store")

func _storage_grid(parent: Container, title: String, items: Dictionary, capacity: int,
		destination: Dictionary, destination_capacity: int, action: String) -> void:
	var pane := _column(parent, 7)
	var entries := Survival.inventory_entries(items)
	_label(pane, "%s   %d / %d 格" % [title, entries.size(), capacity], 16, CREAM)
	var slots := GridContainer.new()
	slots.add_theme_constant_override("h_separation", 5)
	slots.add_theme_constant_override("v_separation", 5)
	pane.add_child(slots)
	_slot_grids.append(slots)
	for entry: Dictionary in entries:
		var item: String = entry.item
		var tile := _action(slots, "", action, {"item": item})
		tile.theme_type_variation = &"StorageSlot"
		tile.custom_minimum_size = SLOT_SIZE
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.disabled = action.is_empty() or not Survival.can_carry(destination, item, destination_capacity)
		tile.tooltip_text = "%s ×%d" % [_item_name(item), int(entry.quantity)]
		if not action.is_empty():
			tile.tooltip_text += " · 存入一份" if action == "store" else " · 取出一份"
		var face := VBoxContainer.new()
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_theme_constant_override("separation", 1)
		tile.add_child(face)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.offset_left = 4
		face.offset_right = -4
		face.offset_top = 4
		face.offset_bottom = -4
		var icon := _add_icon(face, item, 50)
		if icon != null:
			icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var name := _label(face, _item_name(item), 12, CREAM)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name.autowrap_mode = TextServer.AUTOWRAP_OFF
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var quantity := _label(face, "×%d" % int(entry.quantity), 11, MUTED)
		quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quantity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		quantity.autowrap_mode = TextServer.AUTOWRAP_OFF
		quantity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in maxi(0, capacity - entries.size()):
		var empty := Panel.new()
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty.custom_minimum_size = SLOT_SIZE
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.add_theme_stylebox_override("panel", _empty_slot_style)
		slots.add_child(empty)

func _fire(burning: bool) -> void:
	var fuel := _paper(_content)
	_label(fuel, "添燃料", 17, INK)
	var added := false
	for item: String in Storage.FUEL_ITEMS:
		var quantity := int(_bag.get(item, 0))
		if quantity > 0:
			var seconds := int(Storage.FUEL_ITEMS[item])
			_recipe_buttons["fuel_" + item] = _item_row(fuel, item, quantity, "加入一份 · %d 秒" % seconds, "fuel")
			added = true
	if not added:
		_label(fuel, "背包里没有可用燃料。", 13, SUBTLE_INK)
	_recipe_cards(_content, "fire", burning)

func _furnace(on_ground: bool, stage: int) -> void:
	var card := _paper(_content)
	var illustration := CenterContainer.new()
	card.add_child(illustration)
	_add_icon(illustration,"iron_ingot",124)
	_label(card,"铁锭 ×1",21,INK).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(card,_materials(Storage.FURNACE_RECIPE),15,SUBTLE_INK).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation",9)
	card.add_child(buttons)
	var start := _action(buttons,"开始炼铁","smelt")
	start.disabled = not on_ground or stage != 0 or not _has_materials(Storage.FURNACE_RECIPE)
	_recipe_buttons["smelt"] = start
	var take := _action(buttons,"取出铁锭","take_ingot")
	take.disabled = not on_ground or stage != 2 or not Survival.can_carry(_bag,"iron_ingot",_bag_capacity)
	_recipe_buttons["take_ingot"] = take

func _recipe_cards(parent: Container, station: String, active: bool) -> void:
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 9)
	_grid.add_theme_constant_override("v_separation", 9)
	parent.add_child(_grid)
	for key: String in Storage.RECIPES:
		var recipe: Dictionary = Storage.RECIPES[key]
		if recipe.get("station", "") != station:
			continue
		var card := _paper(_grid)
		var result := HBoxContainer.new()
		result.add_theme_constant_override("separation", 8)
		card.add_child(result)
		_add_icon(result, str(recipe.get("item", recipe.get("kind", ""))), 44)
		_label(result, str(recipe.get("name", key)), 17, INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var needs: Dictionary = recipe.get("needs", {})
		_label(card, _materials(needs), 13, SUBTLE_INK)
		var building: bool = recipe.get("build",false)
		var cook := _action(card, "预览建造" if building else ("烹饪" if station == "fire" else "制作"),
			"build_preview" if building else "craft", {"recipe": key})
		_recipe_buttons[key] = cook
		cook.disabled = not active or not _has_materials(needs)
		if cook.disabled:
			cook.tooltip_text = "先给营火添燃料" if not active else "背包中的材料不足"

func _build_sign(text: String, editable: bool) -> void:
	var panel := _paper(_content)
	_sign_saved = text
	if not editable:
		_sign_label = _label(panel, text if not text.is_empty() else "木牌上还没有文字。", 18, INK)
		_sign_label.add_theme_font_override("font", SIGN_FONT)
		return
	_sign_edit = LineEdit.new()
	_sign_edit.max_length = 48
	_sign_edit.add_theme_font_override("font", SIGN_FONT)
	_sign_edit.text = text
	_sign_edit.placeholder_text = "输入木牌文字"
	panel.add_child(_sign_edit)
	_save_sign = _button(panel, "保存文字")
	_save_sign.disabled = true
	_sign_edit.text_changed.connect(func(_new_text: String): _save_sign.disabled = _sign_edit.text == _sign_saved)
	_save_sign.pressed.connect(func(): _emit("rename", {"text": _sign_edit.text}))

func _update_sign(saved: String) -> void:
	if saved == _sign_saved:
		return
	if _sign_label != null:
		_sign_label.text = saved if not saved.is_empty() else "木牌上还没有文字。"
	if _sign_edit != null:
		if _sign_edit.text == _sign_saved:
			_sign_edit.text = saved
		_save_sign.disabled = _sign_edit.text == saved
	_sign_saved = saved

func _fixture_actions(kind: String, info: Dictionary, on_ground: bool) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 5)
	_content.add_child(row)
	if kind in ["rope_ladder", "wood_chair"]:
		var use := _action(row, "攀爬" if kind == "rope_ladder" else "坐下", "use")
		use.disabled = not on_ground
	if info.get("carry", false):
		_action(row, "搬起", "carry").disabled = not on_ground
	var salvage: Dictionary = info.get("salvage", {})
	if not salvage.is_empty():
		var dismantle := _action(row, "拆解", "dismantle")
		dismantle.tooltip_text = "回收 " + _materials(salvage)
	if float(info.get("fuel", 0.0)) > 0.0:
		_action(row, "投入营火", "burn")

func _item_row(parent: VBoxContainer, item: String, quantity: int, title: String, action: String, disabled := false) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	parent.add_child(row)
	_add_icon(row, item, 30)
	var description := _label(row, "%s ×%d" % [_item_name(item), quantity], 13, INK)
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var button := _action(row, title, action, {"item": item})
	button.disabled = disabled
	return button

func _add_icon(parent: Container, item: String, size: int) -> TextureRect:
	if item.is_empty():
		return null
	if not _icons.has(item):
		var path: String = Storage.ORE_ICONS.get(item, "res://textures/inventory_%s.png" % item)
		_icons[item] = load(path) if ResourceLoader.exists(path) else null
	var texture: Texture2D = _icons[item]
	if texture == null:
		return null
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon

func _materials(items: Dictionary) -> String:
	var names := PackedStringArray()
	for item: String in items:
		names.append("%s ×%d" % [_item_name(item), int(items[item])])
	return " + ".join(names)

func _item_name(item: String) -> String:
	return str(Survival.ITEM_NAMES.get(item, Storage.KINDS.get(item, {}).get("name", item)))

func _has_materials(items: Dictionary) -> bool:
	for item: String in items:
		if int(_bag.get(item, 0)) < int(items[item]):
			return false
	return true

func _emit(action: String, fields: Dictionary) -> void:
	var payload := fields.duplicate()
	payload.id = _id
	action_requested.emit(action, payload)

func _action(parent: Container, title: String, action: String, fields := {}) -> Button:
	var button := _button(parent, title)
	button.pressed.connect(_emit.bind(action, fields))
	return button

func _resize() -> void:
	var dimensions := _shade.size
	var horizontal := maxi(10, roundi((dimensions.x - 980.0) * 0.5))
	var vertical := maxi(10, roundi((dimensions.y - 650.0) * 0.5))
	for side: String in ["left", "right"]:
		_margins.add_theme_constant_override("margin_" + side, horizontal)
	for side: String in ["top", "bottom"]:
		_margins.add_theme_constant_override("margin_" + side, vertical)
	if _grid != null:
		_grid.columns = 2 if dimensions.x >= 650.0 else 1
	var pane_width := maxf(0.0, dimensions.x - 2.0 * horizontal - 62.0) * 0.5
	for slots: GridContainer in _slot_grids:
		slots.columns = clampi(floori(pane_width / 90.0), 2, 5)

func _clear_content() -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_grid = null
	_recipe_buttons.clear()
	_slot_grids.clear()
	_sign_edit = null
	_save_sign = null
	_sign_label = null
	_sign_saved = ""

func _placeholder(parent: Container, text: String) -> void:
	_label(_paper(parent), text, 14, INK)

func _paper(parent: Container) -> VBoxContainer:
	var pane := PanelContainer.new()
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.add_theme_stylebox_override("panel", _style(PAPER, PAPER_EDGE, 9))
	parent.add_child(pane)
	return _column(pane, 7)

func _column(parent: Container, spacing: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", spacing)
	parent.add_child(column)
	return column

func _label(parent: Container, text: String, points: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", points)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Container, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 33.0
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(button)
	return button

func _style(fill: Color, border: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _theme() -> Theme:
	var theme := Theme.new()
	var font := preload("res://fonts/TrailSans.otf").duplicate() as FontFile
	font.fallbacks = [preload("res://fonts/CampHanSupplement.otf"),SIGN_FONT]
	theme.default_font = font
	theme.default_font_size = 13
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", CREAM)
	theme.set_color("font_pressed_color", "Button", CREAM)
	theme.set_color("font_disabled_color", "Button", MUTED)
	theme.set_stylebox("normal", "Button", _style(Color("#353d31"), EDGE, 6))
	theme.set_stylebox("hover", "Button", _style(Color("#53604a"), EDGE, 6))
	theme.set_stylebox("pressed", "Button", _style(Color("#6a5a3e"), EDGE, 6))
	theme.set_stylebox("disabled", "Button", _style(Color("#404437"), EDGE, 6))
	theme.set_type_variation(&"StorageSlot", &"Button")
	theme.set_stylebox("normal", "StorageSlot", _style(Color("#20271e"), Color.TRANSPARENT, 0))
	theme.set_stylebox("hover", "StorageSlot", _style(Color("#404c38"), Color("#ad9b74"), 0))
	theme.set_stylebox("pressed", "StorageSlot", _style(Color("#4c533a"), Color("#ad9b74"), 0))
	theme.set_stylebox("disabled", "StorageSlot", _style(Color("#252b22"), Color.TRANSPARENT, 0))
	_empty_slot_style = _style(Color("#1b231b"), Color.TRANSPARENT, 0)
	theme.set_stylebox("normal", "LineEdit", _style(PAPER_LIGHT, PAPER_EDGE, 7))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", SUBTLE_INK)
	theme.set_color("caret_color", "LineEdit", INK)
	return theme
