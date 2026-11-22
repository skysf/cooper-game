extends VBoxContainer

const Storage = preload("res://camp_storage.gd")
const Survival = preload("res://survival.gd")
const Wildlife = preload("res://storage_wildlife.gd")

const ANIMALS := {
	"boar": ["根影林径西侧","林地 · 野猪","常在灌木间拱土、走动，也会卧下休息。受到惊扰时会压低头发出警告，随后沿直线冲撞。皮和獠牙可在营地加工。","boar_wood",preload("res://textures/guide_woodland_boar.png")],
	"sheep": ["鹿鸣湖东岸草地", "林间 · 放牧", "栈台旁的空地上有一只绵羊。走近后按 E 剪羊毛，过一段时间羊毛会长回来。", "lake", preload("res://textures/guide_meadow_sheep.png")],
	"croc": ["鹿鸣湖东南岸", "岸边 · 水中", "常伏在浅岸，入水后会下潜。靠得过近时会扑咬。", "lake", preload("res://textures/guide_crocodile.webp")],
	"eagle": ["鹿鸣湖东岸", "高枝 · 空中", "在栈台旁的松枝上栖停，绕湖滑翔，偶尔俯冲。", "lake", preload("res://textures/guide_eagle.webp")],
	"dog": ["营地木屋", "营地 · 可收养", "在木屋附近走动。收养后会跟随主人，待命时趴下休息。", "camp", preload("res://textures/guide_mastiff.webp")],
}
const COOKING := {
	"boar_raw":["野猪林地","从野猪身上取得的肩肉，可在营火旁烤熟。",preload("res://textures/inventory_boar_raw.png")],
	"boar_grilled":["营火","烤熟的野猪肉补充饱腹，也能改善心情。",preload("res://textures/inventory_boar_grilled.png")],
	"lamb_raw": ["鹿鸣湖", "绵羊取材所得。在营火旁可以烤成羊排。", preload("res://textures/inventory_lamb_raw.png")],
	"lamb_grilled": ["营火", "将带骨生羊排放在点燃的营火旁烤熟。", preload("res://textures/inventory_lamb_grilled.png")],
	"crocodile_sandwich": ["营地木桌", "在木桌旁，把烤鳄鱼肉和面包组合成一份三明治。", preload("res://textures/guide_crocodile_sandwich.webp")],
	"crocodile_meat_grilled": ["营火", "生鳄鱼肉需要在燃烧的营火旁烤熟。", preload("res://textures/guide_crocodile_meat_grilled.webp")],
	"crocodile_meat_raw": ["鹿鸣湖", "从鳄鱼尸体上取材。可直接食用，也可以用营火烤制。", preload("res://textures/guide_crocodile_meat_raw.webp")],
	"bread": ["营地木桌", "可在营地木桌上拾取。与烤鳄鱼肉搭配可做三明治。", preload("res://textures/inventory_bread.png")],
	"campfire": ["营地", "向营火添加燃料。火点燃后就可以烤制肉类。", preload("res://textures/guide_campfire.webp")],
}
const RECIPES := ["boar_grilled", "crocodile_sandwich", "crocodile_meat_grilled", "lamb_grilled"]

signal habitat_requested(site: String)

var animals: Array = []
var cooking := false
var section := "animals"
var animal := ""
var recipe := ""
var trail: Array[String] = []
var tabs := {}
var empty: VBoxContainer
var empty_title: Label
var empty_hint: Label
var article: HBoxContainer
var index: VBoxContainer
var detail_title: Label
var context: Label
var picture: TextureRect
var description: Label
var formula: HFlowContainer
var controls: HBoxContainer
var back: Button
var habitat: Button
var cooking_link: Button

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	add_child(header)
	var title := _label(header, "野外图鉴", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for tab: String in ["animals", "cooking"]:
		var button := _button(header, "动物" if tab == "animals" else "烹饪", true)
		button.custom_minimum_size.x = 76
		button.pressed.connect(_show_section.bind(tab))
		tabs[tab] = button
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(center)
	empty = VBoxContainer.new()
	empty.add_theme_constant_override("separation", 8)
	center.add_child(empty)
	empty_title = _label(empty, "", 22)
	empty_hint = _label(empty, "", 15)
	empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.modulate = Color("#c4c7aa")
	article = HBoxContainer.new()
	article.add_theme_constant_override("separation", 12)
	article.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(article)
	index = VBoxContainer.new()
	index.custom_minimum_size.x = 170.0
	index.add_theme_constant_override("separation", 6)
	article.add_child(index)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	article.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	card.add_child(body)
	var heading := HBoxContainer.new()
	body.add_child(heading)
	detail_title = _label(heading, "", 22)
	detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context = _label(heading, "", 14)
	context.modulate = Color("#c4c7aa")
	context.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back = _button(body, "")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_back_to_recipe)
	picture = TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size.y = 92
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(picture)
	formula = HFlowContainer.new()
	formula.add_theme_constant_override("h_separation", 7)
	formula.add_theme_constant_override("v_separation", 5)
	body.add_child(formula)
	description = _label(body, "", 16)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 7)
	body.add_child(controls)
	habitat = _button(controls, "查看栖地")
	habitat.pressed.connect(func(): habitat_requested.emit(ANIMALS[animal][3]))
	cooking_link = _button(controls, "查看烹饪")
	cooking_link.pressed.connect(func(): show_recipe("boar_grilled" if animal=="boar" else "lamb_grilled" if animal == "sheep" else "crocodile_sandwich"))
	_refresh()

func set_progress(progress: Dictionary) -> bool:
	var sightings: Array = progress.get("animals", [])
	var known_recipes: bool = progress.get("cooking", false)
	if sightings == animals and known_recipes == cooking:
		return false
	animals = sightings.duplicate()
	cooking = known_recipes
	_refresh()
	return true

func has_recipe_page(item: String) -> bool:
	return cooking and COOKING.has(item)

func show_recipe(item: String) -> void:
	if not has_recipe_page(item):
		return
	section = "cooking"
	_select_recipe(item)

func _show_section(tab: String) -> void:
	section = tab
	_refresh()

func _select_animal(id: String) -> void:
	animal = id
	_refresh()

func _select_recipe(id: String) -> void:
	trail.clear()
	recipe = id
	_refresh()

func _open_ingredient(id: String) -> void:
	trail.append(recipe)
	recipe = id
	_refresh()

func _back_to_recipe() -> void:
	recipe = trail.pop_back()
	_refresh()

func _refresh() -> void:
	var is_cooking := section == "cooking"
	for key: String in tabs:
		tabs[key].set_pressed_no_signal(key == section)
	var has_entries := cooking if is_cooking else not animals.is_empty()
	empty.get_parent().visible = not has_entries
	article.visible = has_entries
	empty_title.text = "尚无烹饪记录" if is_cooking else "尚无动物记录"
	empty_hint.text = "取得食材后，相关做法会收入图鉴。" if is_cooking else "首次目击动物后，图鉴会自动记录。"
	if not has_entries:
		return
	_clear(index)
	_clear(formula)
	controls.visible = not is_cooking
	back.visible = is_cooking and not trail.is_empty()
	if is_cooking:
		_show_recipe_card()
	else:
		_show_animal_card()

func _show_animal_card() -> void:
	if animal not in animals:
		animal = animals[0]
	for id: String in ANIMALS:
		if id in animals:
			_index_card(Wildlife.NAMES[id], ANIMALS[id][4], id == animal).pressed.connect(_select_animal.bind(id))
	var entry: Array = ANIMALS[animal]
	detail_title.text = Wildlife.NAMES[animal]
	context.text = "%s  ·  %s" % [entry[0], entry[1]]
	picture.texture = entry[4]
	var drops := PackedStringArray()
	for item: String in Wildlife.DROPS[animal]:
		drops.append(Survival.ITEM_NAMES[item])
	if animal == "sheep":
		drops.append(Survival.ITEM_NAMES.wool)
	description.text = "%s\n可取得  %s" % [entry[2], "、".join(drops)]
	formula.hide()
	cooking_link.visible = animal in ["croc","sheep","boar"] and cooking

func _show_recipe_card() -> void:
	if recipe.is_empty():
		recipe = RECIPES[0]
	var selected := recipe if trail.is_empty() else trail[0]
	for id: String in RECIPES:
		_index_card(_ingredient_name(id), COOKING[id][2], id == selected).pressed.connect(_select_recipe.bind(id))
	if back.visible:
		back.text = "返回 " + _ingredient_name(trail.back())
	var entry: Array = COOKING[recipe]
	detail_title.text = _ingredient_name(recipe)
	context.text = entry[0]
	picture.texture = entry[2]
	description.text = entry[1]
	var content: Dictionary = Storage.RECIPES.get(recipe, {}) if recipe in RECIPES else {}
	formula.visible = not content.is_empty()
	if content.is_empty():
		return
	var needs: Dictionary = content.needs.duplicate()
	if content.station == "fire":
		needs["campfire"] = 1
	for id: String in needs:
		if formula.get_child_count() > 0:
			var plus := _label(formula, "+", 17)
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var text := _ingredient_name(id)
		if int(needs[id]) > 1:
			text += " ×%d" % int(needs[id])
		var ingredient := _button(formula, text + "  ›")
		ingredient.custom_minimum_size = Vector2(ingredient.get_minimum_size().x + 40, 42)
		ingredient.expand_icon = true
		ingredient.icon = COOKING[id][2]
		ingredient.add_theme_constant_override("icon_max_width", 39)
		ingredient.pressed.connect(_open_ingredient.bind(id))

func _ingredient_name(id: String) -> String:
	return Storage.KINDS.campfire.name if id == "campfire" else Survival.ITEM_NAMES[id]

func _index_card(text: String, icon: Texture2D, selected: bool) -> Button:
	var card := _button(index, text, true)
	card.icon = icon
	card.expand_icon = true
	card.add_theme_constant_override("icon_max_width", 43)
	card.custom_minimum_size.y = 56.0
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.set_pressed_no_signal(selected)
	return card

func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, toggle := false) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = toggle
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size.y = 34
	parent.add_child(button)
	return button

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func observables() -> Dictionary:
	var choices := {}
	for button: Button in index.get_children():
		var rect := button.get_global_rect()
		choices[button.text] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	var ingredients := {}
	for child in formula.get_children():
		if child is Button:
			var rect: Rect2 = child.get_global_rect()
			ingredients[child.text.strip_edges().trim_suffix("›").strip_edges()] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	var tab_rects := {}
	for key: String in tabs:
		var rect: Rect2 = tabs[key].get_global_rect()
		tab_rects[key] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	return {"open": is_visible_in_tree(), "section": section, "title": detail_title.text if article.visible else empty_title.text,
		"index": choices if article.visible else {}, "ingredients": ingredients, "tabs": tab_rects}
