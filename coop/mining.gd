extends RefCounted

const Survival = preload("res://survival.gd")
const Placement = preload("res://placement.gd")
const Rules = preload("res://rules.gd")

const REACH := 2.32
const STRIKE_INTERVAL := .72
const VEINS := {
	"coal_mine": {"item":"coal", "name":"煤矿", "capacity":14, "period":145.0},
	"iron_mine": {"item":"iron_ore", "name":"铁矿", "capacity":10, "period":185.0},
}

static func from_save(saved: Variant, elapsed: float) -> Dictionary:
	var veins := {}
	for id: String in VEINS:
		var spec: Dictionary = VEINS[id]
		var entry: Variant = saved.get(id) if saved is Dictionary else null
		var capacity: int = spec.capacity
		var stock := capacity
		var next_at := 0.0
		if entry is Dictionary and Survival.finite_number(entry.get("stock")):
			stock = clampi(int(entry.stock), 0, capacity)
			if stock < capacity:
				var deadline: Variant = entry.get("nextAt")
				next_at = clampf(float(deadline), 0.0, elapsed+float(spec.period)) if Survival.finite_number(deadline) else elapsed+float(spec.period)
		veins[id] = {"stock":stock,"nextAt":next_at}
	refresh(veins, elapsed)
	return veins

static func refresh(veins: Dictionary, elapsed: float) -> void:
	for id: String in veins:
		var entry: Dictionary = veins[id]
		if float(entry.nextAt) <= 0.0 or elapsed < float(entry.nextAt):
			continue
		var period: float = VEINS[id].period
		var units := 1 + floori((elapsed - float(entry.nextAt)) / period)
		entry.stock = mini(int(VEINS[id].capacity), int(entry.stock) + units)
		entry.nextAt = 0.0 if entry.stock == VEINS[id].capacity else float(entry.nextAt) + units*period

static func reachable(actor: Dictionary, target: Vector3, obstruction: Array[Dictionary]) -> bool:
	if actor.get("swimming", false) or not target.is_finite():
		return false
	var point: Vector2 = actor.point
	var from := Vector3(point.x, float(actor.y)+1.30, point.y)
	if from.distance_squared_to(target) > REACH*REACH:
		return false
	var hit := Placement.trace(from, target, obstruction)
	return hit.is_empty() or (hit.point as Vector3).distance_squared_to(target) <= .18*.18

static func extract(veins: Dictionary, id: String, state: Dictionary, actor: Dictionary, elapsed: float,
		slots: int, target: Vector3, obstruction: Array[Dictionary]) -> Dictionary:
	if not veins.has(id) or not VEINS.has(id) or not reachable(actor,target,obstruction):
		return {"ok":false,"text":"靠近矿脉后再开采"}
	if elapsed - float(actor.get("lastMineAt",-STRIKE_INTERVAL)) < STRIKE_INTERVAL:
		return {"ok":false,"text":"稳住后再凿下一块"}
	refresh(veins, elapsed)
	var entry: Dictionary = veins[id]
	if int(entry.stock) <= 0:
		return {"ok":false,"text":"当前露出的矿石已经采完"}
	var spec: Dictionary = VEINS[id]
	var item: String = spec.item
	if not Survival.can_carry(state.bag,item,slots):
		return {"ok":false,"text":"背包已满"}
	state.bag[item] = int(state.bag.get(item,0)) + 1
	entry.stock -= 1
	if float(entry.nextAt) <= 0.0:
		entry.nextAt = elapsed + float(spec.period)
	actor.lastMineAt = elapsed
	return {"ok":true,"text":"挖到一块" + Survival.ITEM_NAMES[item]}
