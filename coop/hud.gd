extends CanvasLayer

const Rules = preload("res://rules.gd")
const Survival = preload("res://survival.gd")

signal resume_requested
signal invite_requested
signal backpack_close_requested
signal backpack_action_requested(action: String, item: String)

const INK := Color("#eff0e2")
const MUTED := Color("#c1c8b7")
const LIME := Color("#dceaa4")
const DARK := Color("#17231f")
const AREA := {"camp": "林间营地", "creek": "鹿鸣溪谷", "tower": "北坡瞭望塔", "lake": "鹿鸣湖岸"}
const GOALS := {"wood": "溪谷木料", "tarp": "瞭望塔防水布", "repair": "营地木棚"}
const HEADING := ["北","西北","西","西南","南","东南","东","东北"]
const VITALS := [["hunger", "饱腹", Color("#d2ac76")], ["water", "水分", Color("#87b7c0")], ["mood", "心情", Color("#b8c88c")]]
var base := Control.new()
var area_title: Label
var room_line: Label
var grove_hint: Label
var sky: Label
var bearing: Label
var goal_title: Label
var supplies: Label
var prompt: Label
var toast: Label
var reticle: Label
var held_hint: Label
var instructions: Label
var panel: PanelContainer
var enter: Button
var invite: Button
var briefing: Label
var link_field := LineEdit.new()
var toast_until := 0
var last_notice := -1
var vitals: PanelContainer
var vital_bars: Dictionary = {}
var vital_numbers: Dictionary = {}
var backpack_shade: ColorRect
var backpack_panel: PanelContainer
var backpack_capacity: Label
var backpack_slots: Array[Button] = []
var backpack_items: Array[String] = []
var backpack_actions: Dictionary = {}
var backpack_open := false
var selected_slot := -1
var can_put_food := false

func _style(bg: Color, border := Color("#a9b59b55")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _place(c: Control, left: float, top: float, right: float, bottom: float, offsets: Rect2) -> void:
	base.add_child(c)
	c.anchor_left = left
	c.anchor_top = top
	c.anchor_right = right
	c.anchor_bottom = bottom
	c.offset_left = offsets.position.x
	c.offset_top = offsets.position.y
	c.offset_right = offsets.end.x
	c.offset_bottom = offsets.end.y
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _label(parent: Node, font_size: int, tint := INK, text := "") -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", tint)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	parent.add_child(l)
	return l

func _box(parent: PanelContainer) -> VBoxContainer:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	parent.add_child(stack)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return stack

func _card(left: float, top: float, right: float, bottom: float, offsets: Rect2) -> PanelContainer:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", _style(Color("#14241ece")))
	_place(c,left,top,right,bottom,offsets)
	return c

func _btn(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var bg := LIME if primary else Color("#314139")
	var fg := DARK if primary else INK
	for state in ["normal","hover","pressed","disabled"]:
		b.add_theme_stylebox_override(state,_style(bg.lightened(.09) if state=="hover" else bg))
		b.add_theme_color_override("font_color" if state=="normal" else "font_"+state+"_color", fg)
	b.add_theme_font_size_override("font_size", 16)
	return b

func _ready() -> void:
	add_child(base)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = preload("res://fonts/TrailSans.otf")
	base.theme = theme
	var top_left := _box(_card(0,0,0,0,Rect2(24,18,208,0)))
	area_title = _label(top_left, 22)
	room_line = _label(top_left, 13, MUTED)
	grove_hint = _label(top_left, 13, LIME)
	var top_right := _box(_card(1,0,1,0,Rect2(-277,18,253,0)))
	sky = _label(top_right, 14, LIME)
	goal_title = _label(top_right, 21)
	supplies = _label(top_right, 14, MUTED)
	var compass := _card(.5,0,.5,0,Rect2(-115,18,230,0))
	bearing = _label(compass, 16, INK)
	bearing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle = Label.new()
	_place(reticle,.5,.5,.5,.5,Rect2(-7,-11,14,22))
	reticle.text = "·"
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.add_theme_font_size_override("font_size",23)
	prompt = Label.new()
	_place(prompt,.5,1,.5,1,Rect2(-215,-97,430,38))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_stylebox_override("normal",_style(Color("#15231cdd")))
	prompt.add_theme_color_override("font_color",LIME)
	prompt.add_theme_font_size_override("font_size",17)
	toast = Label.new()
	_place(toast,.5,1,.5,1,Rect2(-350,-53,700,30))
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_constant_override("outline_size",5)
	toast.add_theme_color_override("font_outline_color",DARK)
	instructions = _label(base, 14, INK)
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place_instructions()
	instructions.add_theme_constant_override("outline_size",4)
	instructions.add_theme_color_override("font_outline_color", DARK)
	held_hint = _label(base, 14, INK, "左键 投掷    G 放下")
	held_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	held_hint.position += Vector2(24, -18)
	held_hint.add_theme_constant_override("outline_size", 4)
	held_hint.add_theme_color_override("font_outline_color", DARK)
	panel = _card(0,1,0,1,Rect2(31,-254,500,220))
	panel.add_theme_stylebox_override("panel",_style(Color("#14231bf5")))
	var content := _box(panel)
	content.add_theme_constant_override("separation",7)
	_label(content,14,LIME,"林地合作生存")
	_label(content,32,INK,"暴雨将至")
	briefing = _label(content,17,MUTED)
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var credits := HBoxContainer.new()
	content.add_child(credits)
	_label(credits, 13, MUTED, "银河照片")
	for entry: Array in [
		["ESO/S. Brunier", "https://www.eso.org/public/images/eso0932a/"],
		["CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"],
	]:
		var credit := LinkButton.new()
		credit.text = entry[0]
		credit.uri = entry[1]
		credit.add_theme_font_size_override("font_size", 13)
		credit.add_theme_color_override("font_color", MUTED)
		credits.add_child(credit)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	actions.add_theme_constant_override("separation",10)
	enter = _btn("进入林地",true)
	invite = _btn("邀请队友",false)
	actions.add_child(enter)
	actions.add_child(invite)
	link_field.visible = false
	link_field.editable = false
	content.add_child(link_field)
	enter.pressed.connect(func(): resume_requested.emit())
	invite.pressed.connect(func(): invite_requested.emit())
	_build_vitals()
	_build_backpack()
	base.move_child(vitals, -1)
	base.move_child(toast, -1)

func _place_instructions() -> void:
	instructions.anchor_left = 1.0
	instructions.anchor_right = 1.0
	instructions.anchor_top = 1.0
	instructions.anchor_bottom = 1.0
	instructions.offset_left = -555.0
	instructions.offset_right = -24.0
	instructions.offset_top = -41.0
	instructions.offset_bottom = -19.0

func _flat_fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style

func _build_vitals() -> void:
	vitals = _card(0, 1, 0, 1, Rect2(24, -142, 224, 96))
	var content := _box(vitals)
	content.add_theme_constant_override("separation", 4)
	for entry: Array in VITALS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		content.add_child(row)
		var label := _label(row, 14, MUTED, entry[1])
		label.custom_minimum_size.x = 35.0
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 100.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.custom_minimum_size.y = 7.0
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", _flat_fill(Color("#304038")))
		bar.add_theme_stylebox_override("fill", _flat_fill(entry[2]))
		row.add_child(bar)
		var number := _label(row, 14, INK)
		number.custom_minimum_size.x = 28.0
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vital_bars[entry[0]] = bar
		vital_numbers[entry[0]] = number
	vitals.hide()

func _build_backpack() -> void:
	backpack_shade = ColorRect.new()
	backpack_shade.color = Color("#101813b3")
	base.add_child(backpack_shade)
	backpack_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backpack_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	backpack_panel = _card(0.5, 0.5, 0.5, 0.5, Rect2(-226, -147, 452, 294))
	backpack_panel.add_theme_stylebox_override("panel", _style(Color("#17241dfc"), Color("#839378")))
	backpack_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var content := _box(backpack_panel)
	content.add_theme_constant_override("separation", 11)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := _label(header, 23, INK, "背包")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	backpack_capacity = _label(header, 14, MUTED)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	for index in Survival.SLOT_COUNT:
		var slot := _btn("—", false)
		slot.custom_minimum_size = Vector2(120, 65)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.toggle_mode = true
		slot.add_theme_stylebox_override("pressed", _style(Color("#4f6248"), LIME))
		slot.add_theme_stylebox_override("disabled", _style(Color("#202d26"), Color("#81907835")))
		slot.add_theme_color_override("font_disabled_color", Color("#778476"))
		slot.pressed.connect(_select_slot.bind(index))
		grid.add_child(slot)
		backpack_slots.append(slot)
		backpack_items.append("")
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	for entry: Array in [["eat", "吃一份"], ["drop", "放下"], ["put", "放回桌上"]]:
		var button := _btn(entry[1], entry[0] == "eat")
		button.pressed.connect(_submit_backpack_action.bind(entry[0]))
		actions.add_child(button)
		backpack_actions[entry[0]] = button
	var close := _btn("关闭", false)
	close.pressed.connect(func(): backpack_close_requested.emit())
	actions.add_child(close)
	backpack_panel.hide()
	backpack_shade.hide()
	_refresh_backpack({}, false)

func _select_slot(index: int) -> void:
	selected_slot = index
	_update_slot_controls()

func _submit_backpack_action(action: String) -> void:
	if selected_slot >= 0 and not backpack_items[selected_slot].is_empty():
		backpack_action_requested.emit(action, backpack_items[selected_slot])

func _update_slot_controls() -> void:
	for index in backpack_slots.size():
		backpack_slots[index].set_pressed_no_signal(index == selected_slot)
	for action: String in backpack_actions:
		backpack_actions[action].disabled = selected_slot < 0 or (action == "put" and not can_put_food)

func _refresh_backpack(bag: Dictionary, can_put: bool) -> void:
	var former_item := backpack_items[selected_slot] if selected_slot >= 0 else ""
	var index := 0
	for item: String in Survival.ITEM_NAMES:
		var count := int(bag.get(item, 0))
		while count > 0 and index < backpack_slots.size():
			var stack := mini(count, Survival.STACK_SIZE)
			backpack_items[index] = item
			backpack_slots[index].text = "%s   ×%d" % [Survival.ITEM_NAMES[item], stack]
			backpack_slots[index].disabled = false
			count -= stack
			index += 1
	backpack_capacity.text = "%d / %d 格" % [index, Survival.SLOT_COUNT]
	for empty_index in range(index, backpack_slots.size()):
		backpack_items[empty_index] = ""
		backpack_slots[empty_index].text = "—"
		backpack_slots[empty_index].disabled = true
	if selected_slot >= 0 and backpack_items[selected_slot] != former_item:
		selected_slot = backpack_items.find(former_item) if not former_item.is_empty() else -1
	can_put_food = can_put
	_update_slot_controls()

func set_backpack_open(open: bool, bag: Dictionary = {}, can_put := false) -> void:
	backpack_open = open
	backpack_shade.visible = open
	backpack_panel.visible = open
	if open:
		panel.hide()
		link_field.hide()
		reticle.hide()
		prompt.hide()
		_refresh_backpack(bag, can_put)
	else:
		selected_slot = -1
		_update_slot_controls()

func show_invite(link: String) -> void:
	link_field.text = link
	link_field.visible = true
	link_field.grab_focus()
	link_field.select_all()
	say("可复制链接邀请队友进入此房间")

func say(message: String) -> void:
	toast.text = message
	toast_until = Time.get_ticks_msec() + 3800

func _direction(angle: float) -> String:
	return HEADING[posmod(roundi(angle/(PI/4)),8)]

func refresh(s: Dictionary, target: String, delta_to_target: Vector2, action: String) -> void:
	area_title.text = AREA.get(s.zone,"林间营地")
	room_line.text = "房间 %s    %s / 4 人" % [s.room,s.members]
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
	bearing.text = "%s   %s   %d m" % [arrow, GOALS.get(target,"营地"), roundi(delta_to_target.length())]
	bearing.tooltip_text = "面向%s，目标在%s" % [_direction(s.yaw),_direction(direction)]
	reticle.visible = s.locked
	held_hint.visible = s.locked and not s.heldStone.is_empty()
	prompt.text = action
	prompt.visible = s.locked and not action.is_empty()
	panel.visible = not s.locked and not backpack_open
	var survival_state: Dictionary = s.get("survival", {})
	var has_survival := not survival_state.is_empty()
	instructions.text = "WASD 行走     E 互动     Q 换目标     Esc 释放"
	if has_survival:
		instructions.text += "     Tab 背包"
	for entry: Array in VITALS:
		var value := clampf(float(survival_state.get(entry[0], 0.0)), 0.0, 100.0)
		vital_bars[entry[0]].value = value
		vital_numbers[entry[0]].text = str(roundi(value))
	vitals.visible = has_survival and (s.locked or backpack_open)
	if backpack_open:
		_refresh_backpack(survival_state.get("bag", {}), bool(s.get("canPutProvision", false)))
	var can_walk: bool = s.ready
	enter.disabled = not can_walk
	if not s.connected:
		enter.text = "正在连线…"
		briefing.text = s.status
	elif not s.focusReady:
		enter.text = "加载林区…"
		briefing.text = s.terrainError if not s.terrainError.is_empty() else "正在载入脚下林区"
	else:
		enter.text = "进入林地"
		briefing.text = "沿小径去溪谷拾木料，到瞭望塔取防水布。带回营地修好木棚，为队友点亮归途。"
	if s.noticeNo != last_notice:
		last_notice = s.noticeNo
		if not s.notice.is_empty():
			say(s.notice)
	toast.visible = Time.get_ticks_msec()<toast_until
