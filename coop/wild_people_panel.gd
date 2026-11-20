extends CanvasLayer

const People = preload("res://wild_people.gd")
const Survival = preload("res://survival.gd")
signal close_requested
signal action_requested(action: String, item: String, id: String)
signal locate_requested(source: String)
var is_open := false
var selected := ""
var base := Control.new()
var sheet := PanelContainer.new()
var title: Label
var overview: Label
var notice: Label
var roster := ItemList.new()
var details: Label
var actions := GridContainer.new()
var source_buttons: Dictionary = {}
var action_buttons: Dictionary = {}
var people_ids: Array[String] = []
var last_roster := ""
var state: Dictionary = {}
var personal: Dictionary = {}
var point := Vector2.ZERO
var last_notice := -1
var public_button: Button
var repair_button: Button
var equipment_status: Label

func _style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#132122f8")
	s.border_color = Color("#65726a")
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s

func _label(parent: Node, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("#e5e7d9"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: String, item := "", npc := true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 37
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 14)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): action_requested.emit(action, item, selected if npc else ""))
	parent.add_child(b)
	return b

func _ready() -> void:
	layer = 12
	add_child(base)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	var font := preload("res://fonts/TrailSans.otf").duplicate() as FontFile
	font.fallbacks = [preload("res://fonts/CampHanSupplement.otf")]
	theme.default_font = font
	base.theme = theme
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.02, 0.72)
	base.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.add_child(sheet)
	sheet.anchor_right = 1
	sheet.anchor_bottom = 1
	sheet.offset_left = 28
	sheet.offset_top = 22
	sheet.offset_right = -28
	sheet.offset_bottom = -22
	sheet.add_theme_stylebox_override("panel", _style())
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	sheet.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	title = _label(header, 26)
	title.text = "营地住民与照料"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "关闭  B / Esc"
	close.custom_minimum_size = Vector2(126, 37)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): close_requested.emit())
	header.add_child(close)
	overview = _label(layout, 15)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 250
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	left_scroll.add_child(left)
	_label(left, 17).text = "住民 · 关系因人而异"
	roster.custom_minimum_size.y = 164
	roster.add_theme_font_size_override("font_size", 15)
	roster.item_selected.connect(func(index: int): selected = people_ids[index])
	left.add_child(roster)
	_label(left, 17).text = "补给来源 · 走近后采集"
	for key: String in People.SOURCES:
		var row := HBoxContainer.new()
		left.add_child(row)
		var b := _button(row, "", "gather", key, false)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var locate := Button.new()
		locate.text = "定位"
		locate.focus_mode = Control.FOCUS_NONE
		locate.pressed.connect(func(): locate_requested.emit(key))
		row.add_child(locate)
		source_buttons[key] = b
	public_button = _button(left, "", "public_food", "", false)
	repair_button = _button(left, "修补 +25（木料1 / 布1）", "repair_facility", "", false)
	_label(left, 17).text = "你的缴获装备"
	equipment_status = _label(left, 14)
	var equipment := GridContainer.new()
	equipment.columns = 2
	left.add_child(equipment)
	for item: String in ["", "club", "spear", "stone"]:
		_button(equipment, People.WEAPONS[item], "equip", item, false)
	_button(equipment, "盾牌 开 / 关", "shield", "", false)
	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)
	details = _label(right, 16)
	details.custom_minimum_size.x = 420
	actions.columns = 3
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 7)
	right.add_child(actions)
	for spec: Array in [
		["制服（清醒者会反抗）", "capture", ""], ["编条加固束缚", "bind", ""], ["缴获 / 取回战利品", "loot", ""], ["解除约束并释放", "release", ""],
		["给一份苹果", "feed", "apple"], ["给一份面包", "feed", "bread"], ["给一份装好的溪水", "water", ""],
		["用一份药草治疗", "treat", ""], ["邀请自愿留下", "invite", ""], ["协商守家", "order", "guard"],
		["协商回营休养", "order", "rest"], ["交给木棍", "give_equipment", "club"], ["交给长矛", "give_equipment", "spear"],
		["交给盾牌", "give_equipment", "shield"], ["交给圆石", "give_equipment", "stone"], ["取回武器", "take_equipment", ""],
		["取回盾牌", "take_equipment", "shield"], ["闲聊（每60秒）", "chat", ""], ["赠送一份苹果", "gift", "apple"],
		["表达心意（可拒绝）", "romance", ""], ["结束恋爱关系", "end_romance", ""],
	]:
		var b := _button(actions, spec[0], spec[1], spec[2])
		action_buttons[spec[1] + "/" + spec[2]] = b
	_label(right, 13).text = "左键近战；持石时投掷。徒手、圆石和木棍为钝击；长矛和磨利的石片是锐器。锐器只有实际击中左腿或右腿才造成腿伤。\n钝击也会损伤健康，持续攻击可能致命。死亡不可逆。俘虏无法发展恋爱；招募需要本人自愿。"
	notice = _label(layout, 15)
	notice.add_theme_color_override("font_color", Color("#f1c581"))
	notice.custom_minimum_size.y = 38
	base.hide()

func set_open(open: bool, focus_id := "") -> void:
	is_open = open
	base.visible = open
	if not focus_id.is_empty():
		selected = focus_id
	last_roster = ""

func refresh(data: Dictionary, survival: Dictionary, at: Vector2, elapsed: float, message: String, number: int) -> void:
	state = data
	personal = survival
	point = at
	if not is_open:
		return
	if number != last_notice:
		last_notice = number
		notice.text = message
	var raid: Dictionary = data.get("raid", {})
	var wait := maxi(0, ceili(float(raid.get("nextAt", elapsed)) - elapsed))
	var warning: String = "来袭进行中" if raid.get("phase") == "active" else "来袭预警，%d秒" % wait if raid.get("phase") == "warning" else "距下一次来袭 %d:%02d" % [wait / 60, wait % 60]
	overview.text = "%s    ·    已经历 %d 次袭击    ·    设施 %d%%    ·    房间无人时生活与难度暂停" % [warning, raid.get("wave", 0), roundi(data.get("facility", 100.0))]
	var people: Dictionary = data.get("people", {})
	var roster_text := ""
	people_ids.clear()
	for id: String in people:
		people_ids.append(id)
		var npc: Dictionary = people[id]
		roster_text += id + npc.phase + str(roundi(at.distance_to(People.position(npc)))) + "\n"
	if roster_text != last_roster:
		last_roster = roster_text
		roster.clear()
		for id: String in people_ids:
			var npc: Dictionary = people[id]
			roster.add_item("%s · %s · %dm" % [npc.name, People.PHASE_NAMES.get(npc.phase, npc.phase), roundi(at.distance_to(People.position(npc)))])
		if not people.has(selected):
			selected = people_ids[0] if not people_ids.is_empty() else ""
		if people_ids.has(selected):
			roster.select(people_ids.find(selected))
	for key: String in source_buttons:
		var source: Dictionary = People.SOURCES[key]
		var distance := at.distance_to(Vector2(source.x, source.z))
		var stock: int = data.get("resources", {}).get(key, {}).get("stock", 0)
		source_buttons[key].text = "%s %d · %dm" % [source.name, stock, roundi(distance)]
		source_buttons[key].disabled = distance > People.REACH or stock <= 0
		source_buttons[key].tooltip_text = "到达采集点后可消耗一份库存；库存仅随在线游戏时间缓慢再生"
	public_button.text = "公共木桌：" + ("允许同伴取食" if data.get("publicFood", false) else "保留给玩家")
	public_button.disabled = not Survival.can_put(at)
	repair_button.disabled = at.distance_to(People.HOME) > 3.0 or data.get("facility", 100.0) >= 100.0
	var bag: Dictionary = survival.get("bag", {})
	repair_button.disabled = repair_button.disabled or int(bag.get("wood", 0)) < 1 or int(bag.get("tarp", 0)) < 1
	equipment_status.text = "%s\n药草 %d  溪水 %d  木棍 %d  长矛 %d  盾牌 %d" % [People.WEAPONS.get(survival.get("weapon", ""), "徒手"), bag.get("herb", 0), bag.get("water", 0), bag.get("club", 0), bag.get("spear", 0), bag.get("shield", 0)]
	var npc: Dictionary = people.get(selected, {})
	if npc.is_empty():
		details.text = "目前没有住民。\n\n首次袭击留出建造和采集时间，先准备食物、药草与溪水。\n\n钝击可击晕；受伤的腿会减慢撤退速度。倒地后先制服，再明确选择救治、释放或拿走装备。\n\n照料记录和信任不会因等待自动补齐，必须实际供给。"
		for b: Button in action_buttons.values():
			b.hide()
		return
	var rel: Dictionary = npc.relation
	var distance := at.distance_to(People.position(npc))
	var phase: String = npc.phase
	var loot_names := PackedStringArray()
	for item: String in npc.loot:
		if int(npc.loot[item]) > 0:
			loot_names.append("%s×%d" % [Survival.ITEM_NAMES.get(item, item), npc.loot[item]])
	var trust_name := "戒备" if rel.trust < 20 else "逐渐信任" if rel.trust < 40 else "信任你" if rel.trust < 65 else "深厚信任"
	var care_time := minf(100, npc.careSeconds / maxf(1.0, npc.careDuration) * 100.0)
	details.text = "%s · %s · %d岁（成年人） · %s · %dm\n\n健康 %d / %d    饱腹 %d    水分 %d    心情 %d\n左腿伤势 %d    右腿伤势 %d    移速 %d%%    疾病 %d\n装备：%s%s    遗留物：%s\n状态：%s\n\n对你：%s · 信任 %d / 100    好感 %d / 100    %s\n你的照料：食物 %d/2 · 水 %d/2 · 治疗 %d/1 · 照料点 %d/%d\n有效休养 %d%%（仅在物资充分且治疗有效时推进）\n%s\n\n%s" % [npc.name, "女性" if npc.sex == "female" else "男性", npc.age, People.PHASE_NAMES.get(phase, phase), roundi(distance), roundi(npc.health), roundi(npc.maxHealth), roundi(npc.hunger), roundi(npc.water), roundi(npc.mood), roundi(npc.legL), roundi(npc.legR), roundi(npc.speedFactor * 100), roundi(npc.disease), People.WEAPONS.get(npc.weapon, "徒手"), " + 盾牌" if npc.shield else "", "、".join(loot_names) if not loot_names.is_empty() else "暂无", npc.help, trust_name, roundi(rel.trust), roundi(rel.affection), npc.relationship, int(rel.food), int(rel.water), int(rel.treatments), int(rel.care), int(npc.careNeed), roundi(care_time), "本人愿意谈谈去留，可提出自愿留下的邀请" if npc.readyToJoin else "留下条件：个人信任40、供给2次食物和2次水、治疗、照料点及有效休养达标", "请走近并确保没有墙阻挡，才能互动。" if distance > People.REACH else "你已走近，可选择下方互动。清醒者仍可能反抗。"]
	if elapsed < float(rel.refusedUntil):
		details.text += "\n\n对方需要空间：请尊重拒绝，%d 秒后才可再谈感情。" % ceili(float(rel.refusedUntil) - elapsed)
	for key: String in action_buttons:
		var b: Button = action_buttons[key]
		var command := key.get_slice("/", 0)
		var item := key.get_slice("/", 1)
		var visible := false
		match command:
			"capture": visible = phase in ["raider", "retreat", "down"]
			"bind": visible = phase == "captive" and not npc.get("bound", false)
			"loot": visible = phase in ["down", "captive", "dead"]
			"release", "invite": visible = phase == "captive"
			"feed", "water", "treat": visible = phase in ["captive", "companion", "down"]
			_: visible = phase == "companion"
		b.visible = visible
		b.disabled = distance > People.REACH or survival.get("health", 0) <= 0
		if command in ["feed", "gift"]:
			b.disabled = b.disabled or int(bag.get(item, 0)) <= 0 or npc.hunger >= 87
		elif command == "water":
			b.disabled = b.disabled or int(bag.get("water", 0)) <= 0 or npc.water >= 96
		elif command == "treat":
			b.disabled = b.disabled or int(bag.get("herb", 0)) <= 0
		elif command == "invite":
			b.disabled = b.disabled or not npc.readyToJoin
		elif command == "give_equipment":
			b.disabled = b.disabled or int(bag.get(item, 0)) <= 0
		elif command == "romance":
			b.disabled = b.disabled or elapsed < npc.joinedAt + 180.0 or rel.trust < 65 or rel.affection < 40 or elapsed < rel.refusedUntil or npc.relationship != "尚未恋爱"
		elif command == "end_romance":
			b.visible = phase == "companion" and npc.relationship == "你的伴侣"
		elif command == "chat":
			b.disabled = b.disabled or elapsed < rel.chatAt + 60

func observables() -> Dictionary:
	if not is_open:
		return {}
	var buttons := {}
	for key: String in action_buttons:
		var b: Button = action_buttons[key]
		var rect := b.get_global_rect()
		buttons[key] = {"text": b.text, "visible": b.visible, "disabled": b.disabled, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]}
	return {"selected": selected, "details": details.text, "notice": notice.text, "actions": buttons}
