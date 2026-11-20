extends RefCounted

const Weapons = preload("res://weapons.gd")

const TABLE_CENTER := Vector2(3.10, -88.95)
const TABLE_TOP := 0.79
const JUG := Vector2(3.59, -88.76)
const BACKPACK := Vector2(0.55, -88.85)
const TABLE_SLOTS := [
	Vector2(2.50, -88.82), Vector2(2.75, -88.82),
	Vector2(2.50, -89.11), Vector2(2.75, -89.11),
	Vector2(3.00, -88.82), Vector2(3.00, -89.11),
]
const SHELTER := Rect2(-0.55, -92.17, 4.92, 5.19)
const REACH := 1.65
const PUT_REACH := 1.55
const JUG_REACH := 1.55
const SLOT_COUNT := 6
const BACKPACK_SLOTS := 6
# Every registered kind occupies one slot. Count is separate and bounded for save/network safety.
const MAX_ITEM_COUNT := 2147483647
const MATERIAL_RESTOCK := 180.0
const CLOTHING := {"cap": "帽子", "jacket": "夹克", "pants": "长裤"}
const ITEM_NAMES := {"apple": "苹果", "bread": "面包", "cap": "帽子", "jacket": "夹克", "pants": "长裤", "herb": "药草包", "water": "装好的溪水", "stone": "缴获圆石", "club": "木棍", "spear": "长矛", "shield": "编织盾牌", "wood": "木料", "tarp": "防水布", "katana": "日本刀", "rifle": "栓动步枪", "pistol": "手枪"}
const FOOD_STATS := {
	"apple": {"hunger": 19.0, "water": 9.0, "mood": 4.0},
	"bread": {"hunger": 31.0, "water": 0.0, "mood": 3.0},
}
const MAX_STAT := 100.0
const DRINK_GAIN := 32.0
const DRINK_THRESHOLD := 96.0
const HUNGER_LOSS := 0.038
const WATER_LOSS := 0.065
const INDOOR_MOOD := 0.06
const DECOR_MOOD := 0.045
const WARMTH_MOOD := 0.075
const RAIN_MOOD_LOSS := 0.17

static func initial_state() -> Dictionary:
	return {"health": MAX_STAT, "hunger": 86.0, "water": 82.0, "mood": 65.0, "bag": {"apple": 0, "bread": 0},
		"worn": initial_wear(), "weapon": "", "shield": false, "attackAt": -10.0, "attackWeapon": "", "downAt": -1.0}

static func initial_wear() -> Dictionary:
	return {"cap": true, "jacket": true, "pants": true}

static func stack_limit(item: String) -> int:
	return MAX_ITEM_COUNT if ITEM_NAMES.has(item) else 0

static func _quantity(value: Variant) -> int:
	return int(clampf(float(value), 0.0, MAX_ITEM_COUNT)) if finite_number(value) else 0

static func stack_slots(item: String, quantity: Variant) -> int:
	return 1 if ITEM_NAMES.has(item) and _quantity(quantity) > 0 else 0

static func inventory_entries(bag: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for item: String in ITEM_NAMES:
		var quantity := _quantity(bag.get(item, 0))
		if quantity > 0:
			entries.append({"item": item, "quantity": quantity})
	return entries

static func is_drinkable(item: String) -> bool:
	return item == "water"

static func can_table(item: String) -> bool:
	return FOOD_STATS.has(item) or is_drinkable(item)

static func drink(state: Dictionary) -> void:
	state.water = minf(MAX_STAT, float(state.water) + DRINK_GAIN)

static func slot_count(wearing_backpack: bool) -> int:
	return SLOT_COUNT + (BACKPACK_SLOTS if wearing_backpack else 0)

static func state_from_save(value: Variant, slots: int = SLOT_COUNT) -> Dictionary:
	var state := initial_state()
	if value is not Dictionary:
		return state
	for key in ["health", "hunger", "water", "mood"]:
		var amount: Variant = value.get(key)
		if finite_number(amount):
			state[key] = clampf(float(amount), 0.0, MAX_STAT)
	var worn: Variant = value.get("worn")
	if worn is Dictionary:
		for item: String in CLOTHING:
			state.worn[item] = worn.get(item) == true
	var bag: Variant = value.get("bag")
	if bag is Dictionary:
		var available := slots
		for item: String in ITEM_NAMES:
			var count: Variant = bag.get(item)
			if finite_number(count):
				var accepted := _quantity(count) if available > 0 else 0
				if accepted > 0 or not CLOTHING.has(item):
					state.bag[item] = accepted
				available -= stack_slots(item, accepted)
	var weapon: Variant = value.get("weapon", "")
	if Weapons.ATTACKS.has(weapon) and int(state.bag.get(weapon, 0)) > 0:
		state.weapon = weapon
	state.shield = value.get("shield") == true and int(state.bag.get("shield", 0)) > 0
	state.downAt = float(value.get("downAt", -1.0)) if finite_number(value.get("downAt")) else -1.0
	return state

static func initial_provisions() -> Dictionary:
	var provisions := {}
	for i in range(4):
		var item := "apple" if i < 2 else "bread"
		var suffix := "-1" if i % 2 == 0 else "-2"
		var place: Vector2 = TABLE_SLOTS[i]
		provisions[item + suffix] = provision(item, Vector3(place.x, TABLE_TOP, place.y), "table")
	return provisions

static func provisions_from_save(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return initial_provisions()
	var provisions := {}
	for id: String in value:
		var saved: Variant = value[id]
		if id.length() > 64 or saved is not Dictionary or not ITEM_NAMES.has(saved.get("item")):
			continue
		if saved.get("surface") not in ["table", "ground"]:
			continue
		if saved.surface == "table" and not can_table(saved.item):
			continue
		var at: Variant = saved.get("at")
		if at is Array and at.size() == 3 and finite_number(at[0]) and finite_number(at[1]) and finite_number(at[2]):
			provisions[id] = provision(saved.item, Vector3(float(at[0]), float(at[1]), float(at[2])), saved.surface)
	return provisions

static func finite_number(amount: Variant) -> bool:
	return (amount is int or amount is float) and is_finite(float(amount))

static func provision(item: String, at: Vector3, surface: String) -> Dictionary:
	return {"item": item, "at": [at.x, at.y, at.z], "surface": surface}

static func horizontal(at: Array) -> Vector2:
	return Vector2(float(at[0]), float(at[2]))

static func inside_shelter(point: Vector2) -> bool:
	return SHELTER.has_point(point)

static func can_reach(point: Vector2, target: Vector2, surface: String) -> bool:
	return point.distance_squared_to(target) <= REACH * REACH and (surface != "table" or inside_shelter(point))

static func can_put(point: Vector2) -> bool:
	return inside_shelter(point) and point.distance_squared_to(TABLE_CENTER) <= PUT_REACH * PUT_REACH

static func can_drink(point: Vector2) -> bool:
	return inside_shelter(point) and point.distance_squared_to(JUG) <= JUG_REACH * JUG_REACH

static func used_slots(bag: Dictionary) -> int:
	var occupied := 0
	for item: String in ITEM_NAMES:
		occupied += stack_slots(item, bag.get(item, 0))
	return occupied

static func can_carry(bag: Dictionary, item: String, slots: int = SLOT_COUNT) -> bool:
	if not ITEM_NAMES.has(item):
		return false
	var raw: Variant = bag.get(item, 0)
	if not finite_number(raw) or float(raw) < 0.0 or float(raw) > MAX_ITEM_COUNT or float(raw) != floorf(float(raw)):
		return false
	var count := int(raw)
	return count < MAX_ITEM_COUNT and (count > 0 or used_slots(bag) < slots)

static func free_table_slot(provisions: Dictionary) -> Vector3:
	for slot: Vector2 in TABLE_SLOTS:
		var occupied := false
		for record: Dictionary in provisions.values():
			if record.surface == "table" and slot.distance_squared_to(horizontal(record.at)) < 0.015:
				occupied = true
				break
		if not occupied:
			return Vector3(slot.x, TABLE_TOP, slot.y)
	return Vector3.INF

static func eat(state: Dictionary, item: String) -> void:
	var nutrition: Dictionary = FOOD_STATS[item]
	for key in nutrition:
		state[key] = minf(MAX_STAT, float(state[key]) + float(nutrition[key]))

static func tick(state: Dictionary, point: Vector2, roof_repaired: bool, rain: float, delta: float, piloting := false) -> void:
	state.hunger = maxf(0.0, float(state.hunger) - HUNGER_LOSS * delta)
	state.water = maxf(0.0, float(state.water) - WATER_LOSS * delta)
	var mood_change := -RAIN_MOOD_LOSS * rain
	if not piloting and inside_shelter(point):
		# Each of the two fixed decorations contributes separately to the room's comfort.
		var comfort := INDOOR_MOOD + DECOR_MOOD * 2.0
		mood_change = comfort + WARMTH_MOOD if roof_repaired else comfort + mood_change * 0.65
		if roof_repaired and float(state.health) > 0.0:
			state.health = minf(MAX_STAT, float(state.health) + 1.4 * delta)
	state.mood = clampf(float(state.mood) + mood_change * delta, 0.0, MAX_STAT)

static func snapshot(state: Dictionary) -> Dictionary:
	return {
		"health": snappedf(float(state.health), 0.1),
		"hunger": snappedf(float(state.hunger), 0.1),
		"water": snappedf(float(state.water), 0.1),
		"mood": snappedf(float(state.mood), 0.1),
		"bag": state.bag,
		"worn": state.worn,
		"weapon": state.get("weapon", ""), "shield": state.get("shield", false),
		"attackAt": state.get("attackAt", -10.0), "downAt": state.get("downAt", -1.0),
	}
