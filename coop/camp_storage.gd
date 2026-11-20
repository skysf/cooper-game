extends RefCounted

const Rules = preload("res://rules.gd")
const Survival = preload("res://survival.gd")
const Lake = preload("res://lake_layout.gd")
const Stones = preload("res://stones.gd")
const PlacementWorld = preload("res://placement_world.gd")
const Placement = preload("res://placement.gd")
const PlayerMotion = preload("res://player_motion.gd")

const REACH := 2.35
const WORKBENCH := Vector2(3.1, -88.95)
const MAX_OBJECTS := 96
const FURNACE_SECONDS := 38.0
const FURNACE_RECIPE := {"iron_ore":2,"coal":1}
const EAGLE_COLLAPSE_SECONDS := 0.60
const EAGLE_FALL_MAX_SECONDS := 2.25
const EAGLE_DRIFT_MAX_SECONDS := 4.0
const CROC_COLLAPSE_SECONDS := 0.90
const KINDS := {
	"wicker_basket": {"name":"编织篮", "capacity":4, "radius":0.19, "height":0.452, "carry":true, "salvage":{"wicker_strip":3}, "fuel":24.0},
	"wood_crate": {"name":"木箱", "capacity":8, "radius":0.42, "height":0.36, "carry":true, "salvage":{"wood_plank":4}, "fuel":95.0},
	"military_crate": {"name":"军用木箱", "capacity":12, "radius":0.49, "height":0.39, "carry":true, "salvage":{"wood_plank":5}, "fuel":119.0},
	"wood_barrel": {"name":"木桶", "capacity":10, "radius":0.33, "height":0.78, "carry":true, "salvage":{"wood_plank":4}, "fuel":96.0},
	"wood_barrel_tall": {"name":"大木桶", "capacity":14, "radius":0.38, "height":0.93, "carry":true, "salvage":{"wood_plank":5}, "fuel":120.0},
	"wood_table": {"name":"木桌", "capacity":0, "radius":0.81, "height":0.79, "carry":true, "salvage":{"wood_plank":3}, "fuel":72.0},
	"wood_chair": {"name":"木椅", "capacity":0, "radius":0.26, "height":0.87, "carry":true, "salvage":{"wood_plank":2}, "fuel":48.0},
	"rope_ladder": {"name":"绳梯", "capacity":0, "radius":0.23, "height":2.03, "carry":true, "salvage":{"wood_plank":2,"rope":1}, "fuel":48.0},
	"wood_sign": {"name":"木路牌", "capacity":0, "radius":0.30, "height":1.05, "carry":true, "salvage":{"wood_plank":1}, "fuel":24.0},
	"campfire": {"name":"营火", "capacity":0, "radius":0.38, "height":0.32, "carry":false, "salvage":{}, "fuel":0.0},
	"iron_furnace": {"name":"石砌炼铁炉", "capacity":0, "radius":0.56, "height":1.13, "carry":true, "throwable":false, "salvage":{}, "fuel":0.0},
	"table_gnome": {"name":"矮人摆件", "capacity":0, "radius":0.055, "height":0.19, "carry":true, "salvage":{}, "fuel":0.0},
	"table_babushka": {"name":"木套娃", "capacity":0, "radius":0.04, "height":0.155, "carry":true, "salvage":{"wood_plank":1}, "fuel":9.0},
	"water_jug": {"name":"水壶", "capacity":0, "radius":0.12, "height":0.25, "carry":true, "salvage":{}, "fuel":0.0},
	"cabin_floor": {"name":"木屋地板", "capacity":0, "radius":2.12, "height":0.18, "carry":true, "throwable":false, "salvage":{"wood_plank":5}, "fuel":0.0},
	"cabin_wall": {"name":"原木墙", "capacity":0, "radius":1.45, "height":2.30, "carry":true, "throwable":false, "salvage":{"wood_plank":4}, "fuel":0.0},
	"cabin_doorway": {"name":"原木门框", "capacity":0, "radius":1.45, "height":2.30, "carry":true, "throwable":false, "salvage":{"wood_plank":4}, "fuel":0.0},
	"cabin_roof": {"name":"双坡木瓦屋顶", "capacity":0, "radius":2.40, "height":1.19, "carry":true, "throwable":false, "salvage":{"wood_plank":6}, "fuel":0.0},
	"corpse_croc": {"name":"鳄鱼尸体", "capacity":2, "radius":0.75, "height":0.28, "carry":false, "salvage":{}, "fuel":0.0},
	"corpse_eagle": {"name":"老鹰尸体", "capacity":3, "radius":0.45, "height":0.24, "carry":false, "salvage":{}, "fuel":0.0},
	"corpse_dog": {"name":"藏獒尸体", "capacity":1, "radius":0.6, "height":0.38, "carry":false, "salvage":{}, "fuel":0.0},
}
const MODELS := {
	"wicker_basket":"res://props/storage/wicker_basket.glb", "wood_crate":"res://props/storage/wood_crate.glb",
	"military_crate":"res://props/storage/military_crate.glb", "wood_barrel":"res://props/storage/wood_barrel.glb",
	"wood_barrel_tall":"res://props/storage/wood_barrel_tall.glb", "wood_table":"res://props/camp_table.glb",
	"wood_chair":"res://props/storage/wood_chair.glb", "rope_ladder":"res://props/storage/rope_ladder.glb",
	"wood_sign":"res://props/storage/wood_sign.glb", "campfire":"res://props/storage/campfire.glb",
	"iron_furnace":"res://props/iron_furnace.glb",
	"table_gnome":"res://props/table_gnome.glb", "table_babushka":"res://props/table_babushka.glb",
	"water_jug":"res://props/camp_water_jug.glb",
	"cabin_floor":"res://props/construction/cabin_floor.glb", "cabin_wall":"res://props/construction/cabin_wall.glb",
	"cabin_doorway":"res://props/construction/cabin_doorway.glb", "cabin_roof":"res://props/construction/cabin_roof.glb",
	"corpse_croc":"res://props/camp_crocodile.glb", "corpse_eagle":"res://props/camp_eagle.glb",
	"corpse_dog":"res://props/camp_mastiff.glb",
}
const ITEM_MODELS := {
	"herb":"res://props/storage/herb_bundle.glb",
	"wood_plank":"res://props/storage/wood_plank.glb", "wicker_strip":"res://props/storage/wicker_strip.glb",
	"rope":"res://props/storage/rope.glb", "crocodile_meat_raw":"res://props/storage/crocodile_meat_raw.glb",
	"crocodile_meat_grilled":"res://props/storage/crocodile_meat_grilled.glb",
	"crocodile_sandwich":"res://props/storage/crocodile_sandwich.glb", "eagle_meat":"res://props/storage/eagle_meat.glb",
	"dog_meat":"res://props/storage/dog_meat.glb", "crocodile_hide":"res://props/storage/hide.glb",
	"eagle_feather":"res://props/storage/eagle_feather.glb", "eagle_claw":"res://props/storage/eagle_claw.glb",
	"coal":"res://props/mines/coal.glb", "iron_ore":"res://props/mines/iron_ore.glb", "iron_ingot":"res://props/mines/iron_ingot.glb",
}
const ORE_ICONS := {
	"coal":"res://props/mines/inventory_coal.png",
	"iron_ore":"res://props/mines/inventory_iron_ore.png",
	"iron_ingot":"res://props/mines/inventory_iron_ingot.png",
}
const FUEL_ITEMS := {"wicker_strip":9.0, "wood_plank":24.0, "wood":38.0, "club":16.0, "coal":155.0}
const RECIPES := {
	"wicker_basket":{"name":"编织篮","needs":{"wicker_strip":4},"station":"camp","kind":"wicker_basket"},
	"shield":{"name":"编织盾牌","needs":{"wicker_strip":3,"club":1},"station":"camp","item":"shield"},
	"rope":{"name":"绳子","needs":{"wicker_strip":2},"station":"camp","item":"rope"},
	"wood_table":{"name":"木桌","needs":{"wood_plank":4},"station":"camp","kind":"wood_table"},
	"wood_chair":{"name":"木椅","needs":{"wood_plank":3},"station":"camp","kind":"wood_chair"},
	"rope_ladder":{"name":"绳梯","needs":{"wood_plank":3,"rope":1},"station":"camp","kind":"rope_ladder"},
	"wood_sign":{"name":"木路牌","needs":{"wood_plank":2},"station":"camp","kind":"wood_sign"},
	"campfire":{"name":"营火","needs":{"wood_plank":2},"station":"camp","kind":"campfire"},
	"cabin_floor":{"name":"木屋地板","needs":{"wood_plank":7},"station":"camp","kind":"cabin_floor","build":true},
	"cabin_wall":{"name":"原木墙","needs":{"wood_plank":6},"station":"camp","kind":"cabin_wall","build":true},
	"cabin_doorway":{"name":"原木门框","needs":{"wood_plank":6},"station":"camp","kind":"cabin_doorway","build":true},
	"cabin_roof":{"name":"双坡木瓦屋顶","needs":{"wood_plank":8},"station":"camp","kind":"cabin_roof","build":true},
	"wood_plank":{"name":"劈木板 ×2","needs":{"wood":1},"station":"camp","item":"wood_plank","quantity":2},
	"crocodile_meat_grilled":{"name":"烤鳄鱼肉","needs":{"crocodile_meat_raw":1},"station":"fire","item":"crocodile_meat_grilled"},
	"crocodile_sandwich":{"name":"鳄鱼肉三明治","needs":{"crocodile_meat_grilled":1,"bread":1},"station":"camp","item":"crocodile_sandwich"},
}
const START := [
	["wicker_basket",Vector2(3.95,-88.30),{}],
	["wicker_basket",Vector2(4.23,-84.58),{}],
	["wood_crate",Vector2(0.2,-86.48),{}],
	["military_crate",Vector2(5.55,-86.87),{"rope":2}],
	["wood_barrel",Vector2(-1.3,-87.25),{}],
	["wood_barrel_tall",Vector2(-1.7,-88.70),{}],
	["campfire",Vector2(4.75,-82.85),{}],
]

static func _record(kind: String, point: Vector2, yaw: float, owner := "") -> Dictionary:
	return {"kind":kind,"mode":"ground","at":Stones.pack(Vector3(point.x, Lake.walk_height(point), point.y)),
		"yaw":yaw,"bag":{},"text":"","owner":owner,"fuelUntil":0.0}

static func _name(record: Dictionary) -> String:
	return KINDS[record.kind].name

static func from_save(value: Variant, elapsed: float, grid: Dictionary) -> Dictionary:
	var records := {}
	if value is not Dictionary:
		for i in START.size():
			var entry: Array = START[i]
			var target: Vector2 = entry[1]
			for shift: Vector2 in [Vector2.ZERO, Vector2(0.0,0.5), Vector2(0.65,0.0), Vector2(0.0,-0.65)]:
				if Rules.free_at(target + shift,grid):
					target += shift
					break
			var record := _record(entry[0],target,0.0)
			record.bag = entry[2].duplicate()
			records["camp-storage-%d" % i] = record
		return records
	for id: Variant in value:
		if id is not String or id.length() > 40 or records.size() >= MAX_OBJECTS+4:
			continue
		var saved: Variant = value[id]
		if saved is not Dictionary or not KINDS.has(saved.get("kind")):
			continue
		var at: Variant = saved.get("at")
		if at is not Array or at.size() != 3 or not Survival.finite_number(at[0]) or not Survival.finite_number(at[2]):
			continue
		var point := Vector2(at[0],at[2])
		if point != point.clamp(Rules.MIN_CORNER,Rules.MAX_CORNER):
			continue
		var yaw := wrapf(float(saved.yaw), -PI, PI) if Survival.finite_number(saved.get("yaw")) else 0.0
		var owner: Variant = saved.get("owner","")
		var record := _record(saved.kind,point,yaw,owner if owner is String and owner.length() == 16 else "")
		var rotation := PlacementWorld.saved_rotation(saved.get("rotation"))
		if rotation.length_squared() > .9 and Survival.finite_number(at[1]):
			record.at[1] = float(at[1])
			record.rotation = [rotation.x,rotation.y,rotation.z,rotation.w]
			var supports: Variant = saved.get("supports", [])
			if supports is Array:
				record.supports = []
				for support: Variant in supports:
					if support is String and support.length() <= 40 and support != id and support not in record.supports:
						record.supports.append(support)
		var text: Variant = saved.get("text","")
		record.text = clean_text(text) if text is String else ""
		if record.kind.begins_with("corpse_") and Survival.finite_number(saved.get("deadAt")):
			record.deadAt = clampf(float(saved.deadAt), 0.0, elapsed)
			if record.kind == "corpse_eagle":
				_restore_eagle_fall(record, saved, elapsed)
			elif record.kind == "corpse_croc" and Survival.finite_number(saved.get("landAt")):
				var land_at := minf(float(saved.landAt), float(record.deadAt) + CROC_COLLAPSE_SECONDS)
				if land_at > elapsed:
					record.landAt = land_at
		var until: Variant = saved.get("fuelUntil")
		record.fuelUntil = clampf(float(until),0.0,elapsed+3600.0) if Survival.finite_number(until) else 0.0
		if record.kind == "iron_furnace" and Survival.finite_number(saved.get("batchReady")):
			record.batchReady = clampf(float(saved.batchReady),0.0,elapsed+FURNACE_SECONDS)
		var bag: Variant = saved.get("bag")
		if bag is Dictionary:
			for item: String in Survival.ITEM_NAMES:
				var amount: Variant = bag.get(item)
				if Survival.finite_number(amount) and amount >= 1.0 and Survival.can_carry(record.bag,item,KINDS[record.kind].capacity):
					record.bag[item] = int(clampf(float(amount),1.0,Survival.MAX_ITEM_COUNT))
		records[id] = record
	return records

static func _restore_eagle_fall(record: Dictionary, saved: Dictionary, elapsed: float) -> void:
	if not Survival.finite_number(saved.get("landAt")) or float(saved.landAt) <= elapsed:
		return
	var dead: float = record.deadAt
	var until := dead + EAGLE_FALL_MAX_SECONDS + EAGLE_DRIFT_MAX_SECONDS
	if elapsed >= until:
		return
	record.landAt = clampf(float(saved.landAt), elapsed, until)
	var start: Variant = saved.get("fallFrom")
	if start is not Array or start.size() != 3 or not Survival.finite_number(saved.get("impactAt")):
		record.landAt = minf(record.landAt, dead + EAGLE_COLLAPSE_SECONDS)
		return
	for number in start:
		if not Survival.finite_number(number):
			record.erase("landAt")
			return
	var origin := Stones.unpack(start)
	var point := Vector2(origin.x, origin.z)
	if point != point.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER) or absf(origin.y) > 30.0:
		record.erase("landAt")
		return
	record.fallFrom = start.duplicate()
	record.impactAt = clampf(float(saved.impactAt), dead, minf(record.landAt, dead + EAGLE_FALL_MAX_SECONDS))
	record.foldedFall = saved.get("foldedFall") == true

static func corpse_ready(record: Dictionary, elapsed: float) -> bool:
	return elapsed >= float(record.get("landAt", 0.0))

static func seed_furnace(records: Dictionary, geometry: Dictionary) -> bool:
	const ID := "camp-iron-furnace"
	if records.has(ID):
		return true
	var profile := PlacementWorld.profile("iron_furnace")
	for point: Vector2 in [Vector2(5.98,-84.55), Vector2(5.7,-83.60), Vector2(6.65,-85.0), Vector2(6.78,-86.15)]:
		var ground := Vector3(point.x,Lake.walk_height(point),point.y)
		var physical := PlacementWorld.nearby(geometry,records,point,3.15)
		var placement := Placement.solve(ground+Vector3.UP*.08,ground-Vector3.UP*.08,0.0,profile,physical)
		if placement.ok:
			var record := _record("iron_furnace",point,0.0)
			record.batchReady = 0.0
			_apply_pose(record,placement.pose,0.0,placement.supports)
			records[ID] = record
			return true
	return false

static func seed_furniture(records: Dictionary, provisions: Dictionary) -> void:
	records[Survival.CAMP_TABLE] = _record("wood_table", Survival.TABLE_CENTER, 0.0)
	for entry: Array in [
		["camp-water-jug", "water_jug", Survival.JUG, -.32],
		["camp-table-gnome", "table_gnome", Vector2(3.52,-89.12), PI*.5-.12],
		["camp-table-babushka", "table_babushka", Vector2(3.74,-89.12), .17],
	]:
		var record := _record(entry[1],entry[2],entry[3])
		var pose := PlacementWorld.pose(record)
		pose.origin.y = Survival.TABLE_TOP
		_apply_pose(record, pose, record.yaw, [Survival.CAMP_TABLE])
		records[entry[0]] = record
	for record: Dictionary in provisions.values():
		if record.surface == "table" and not record.has("tableId"):
			record.tableId = Survival.CAMP_TABLE

static func clean_text(text: String) -> String:
	var line := ""
	for i in mini(text.length(),96):
		var code := text.unicode_at(i)
		if code >= 32 and code != 127 and code not in [0x2028,0x2029,0x202a,0x202b,0x202c,0x202d,0x202e,0x2066,0x2067,0x2068,0x2069]:
			line += text[i]
	return line.strip_edges().left(48)

static func held_by(records: Dictionary, player: String) -> String:
	for id: String in records:
		if records[id].mode == "held" and records[id].get("holder","") == player:
			return id
	return ""

static func grounded(record: Dictionary, point: Vector2, yaw: float) -> void:
	var safe := point.clamp(Rules.MIN_CORNER,Rules.MAX_CORNER)
	record.mode = "ground"
	record.at = Stones.pack(Vector3(safe.x, Lake.walk_height(safe), safe.y))
	record.yaw = yaw
	for key: String in ["velocity","launch","thrower","holder","rotation","supports"]:
		record.erase(key)

static func _apply_pose(record: Dictionary, pose: Transform3D, yaw: float, supports: Array) -> void:
	var rotation := pose.basis.get_rotation_quaternion().normalized()
	record.mode = "ground"
	record.at = Stones.pack(pose.origin)
	record.yaw = yaw
	record.rotation = [rotation.x,rotation.y,rotation.z,rotation.w]
	record.supports = supports
	for key: String in ["velocity","launch","thrower","holder"]:
		record.erase(key)

static func _settle_supported(records: Dictionary, provisions: Dictionary, removed: String, geometry: Dictionary) -> bool:
	var queue: Array[String] = [removed]
	var falling: Array[String] = []
	while not queue.is_empty():
		var support: String = queue.pop_front()
		for id: String in records:
			if records[id].mode == "ground" and support in records[id].get("supports", []):
				records[id].mode = "settling"
				falling.append(id)
				queue.append(id)
	falling.sort_custom(func(a: String, b: String) -> bool: return float(records[a].at[1]) < float(records[b].at[1]))
	for id: String in falling:
		var record: Dictionary = records[id]
		var profile := PlacementWorld.profile(record.kind)
		var former := PlacementWorld.pose(record)
		var anchor: Vector3 = profile.get("anchor", Vector3.ZERO)
		var from := former * anchor + Vector3.UP * 0.028
		var center := Vector2(from.x, from.z)
		var nearby := PlacementWorld.nearby(geometry, records, center)
		var settled := false
		for offset: Vector2 in [Vector2.ZERO, Vector2(.18,0), Vector2(-.18,0), Vector2(0,.18), Vector2(0,-.18),
				Vector2(.42,.22), Vector2(-.42,.22), Vector2(.42,-.22), Vector2(-.42,-.22)]:
			var start := from + Vector3(offset.x,0,offset.y)
			var end := Vector3(start.x, Lake.walk_height(center+offset)-.2, start.z)
			if end.y >= start.y:
				continue
			var result := Placement.solve(start,end,record.yaw,profile,nearby,id)
			if result.ok:
				_apply_pose(record,result.pose,record.yaw,result.supports)
				_move_provisions(provisions,id,result.pose * former.affine_inverse())
				settled = true
				break
		if not settled:
			return false
	return true

static func settle_save(records: Dictionary, actors: Dictionary) -> void:
	for record: Dictionary in records.values():
		if record.mode == "held" and actors.has(record.get("holder")):
			var actor: Dictionary = actors[record.holder]
			grounded(record,actor.point,actor.yaw)
		elif record.mode != "ground":
			grounded(record,Survival.horizontal(record.at),record.yaw)

static func near(actor: Dictionary, record: Dictionary, grid: Dictionary) -> bool:
	var at := Stones.unpack(record.at)
	var point: Vector2 = actor.point
	var feet: float = actor.y
	var profile := PlacementWorld.profile(record.get("kind", ""))
	var reach_y := 1.5
	if not profile.is_empty():
		at = PlacementWorld.closest_contact(record, profile, Vector3(point.x, feet+1.12, point.y))
		reach_y = PlacementWorld.HAND_REACH_Y
	var target := Vector2(at.x,at.z)
	if point.distance_squared_to(target) > REACH * REACH or absf(feet - at.y) > reach_y:
		return false
	for i in range(1,5):
		if not Rules.obstacle_free_at(point.lerp(target,float(i)*0.2),grid):
			return false
	return true

static func _yes(text: String) -> Dictionary:
	return {"ok":true,"text":text}

static func _no(text: String) -> Dictionary:
	return {"ok":false,"text":text}

static func _remove(bag: Dictionary, item: String, n := 1) -> void:
	var left := int(bag.get(item,0)) - n
	if left > 0:
		bag[item] = left
	else:
		bag.erase(item)

static func _add(bag: Dictionary, item: String, n := 1) -> void:
	bag[item] = int(bag.get(item,0)) + n

static func _clear_equipment(state: Dictionary) -> void:
	if int(state.bag.get(state.get("weapon",""),0)) <= 0:
		state.weapon = ""
	if int(state.bag.get("shield",0)) <= 0:
		state.shield = false

static func _id(records: Dictionary) -> String:
	var key := Crypto.new().generate_random_bytes(8).hex_encode()
	while records.has(key):
		key = Crypto.new().generate_random_bytes(8).hex_encode()
	return key

static func _find_spot(records: Dictionary, actor: Dictionary, grid: Dictionary, kind: String, skip := "") -> Vector2:
	var origin: Vector2 = actor.point
	var front := Vector2(0.0,-1.0).rotated(-float(actor.yaw))
	var radius: float = KINDS[kind].radius
	for angle: float in [0.0,0.55,-0.55,1.1,-1.1,PI]:
		var point := origin + front.rotated(angle) * (0.90+radius)
		if point != point.clamp(Rules.MIN_CORNER,Rules.MAX_CORNER) or not Rules.free_at(point,grid) or Lake.walk_height(point) <= Lake.surface_height(point):
			continue
		var occupied := false
		for id: String in records:
			var existing: Dictionary = records[id]
			if id == skip or existing.mode != "ground":
				continue
			var gap: float = radius + KINDS[existing.kind].radius
			if point.distance_squared_to(Survival.horizontal(existing.at)) < gap * gap:
				occupied = true
				break
		if not occupied:
			return point
	return Vector2.INF

static func _spill(provisions: Dictionary, bag: Dictionary, center: Vector2, grid: Dictionary) -> void:
	var n := 0
	for item: String in bag:
		if int(bag[item]) <= 0:
			continue
		var offset := Vector2.from_angle(TAU * (float(n) / maxf(1.0,bag.size()))) * (0.23 + 0.08 * float(n % 3))
		var point := (center+offset).clamp(Rules.MIN_CORNER,Rules.MAX_CORNER)
		if not Rules.free_at(point,grid):
			point = center
		var at := Vector3(point.x,maxf(Lake.walk_height(point),Lake.surface_height(point))+0.012,point.y)
		var record := Survival.provision(item,at,"ground")
		record.count = int(bag[item])
		provisions[_id(provisions)] = record
		n += 1

static func _camp_recipe(actor: Dictionary, grid: Dictionary) -> bool:
	return near(actor,{"at":[WORKBENCH.x,Lake.walk_height(WORKBENCH),WORKBENCH.y]},grid) or Survival.inside_shelter(actor.point)

static func _craft(room: Dictionary, player: String, msg: Dictionary, grid: Dictionary, geometry: Dictionary) -> Dictionary:
	var id: Variant = msg.get("recipe")
	if id is not String or not RECIPES.has(id):
		return _no("请选择配方")
	var recipe: Dictionary = RECIPES[id]
	var building: bool = recipe.get("build", false)
	if building != (msg.action == "build"):
		return _no("请选择配方的摆放预览")
	var records: Dictionary = room.data.storage
	var actor: Dictionary = room.actors[player]
	var state: Dictionary = room.data.survival[player]
	var slots := Survival.slot_count(room.data.backpackOwner == player)
	if recipe.station == "fire":
		var fire: Dictionary = records.get(str(msg.get("id","")),{})
		if fire.get("kind") != "campfire" or not near(actor,fire,grid) or float(fire.fuelUntil) <= float(room.data.elapsed):
			return _no("靠近燃烧的营火后再烤制")
	elif not building and not _camp_recipe(actor,grid) and not _near_table(records,actor,grid):
		return _no("回营到木桌旁制作")
	var bag: Dictionary = state.bag.duplicate()
	for item: String in recipe.needs:
		if int(bag.get(item,0)) < int(recipe.needs[item]):
			return _no("缺少" + Survival.ITEM_NAMES[item])
		_remove(bag,item,recipe.needs[item])
	if recipe.has("kind"):
		if records.size() >= MAX_OBJECTS:
			return _no("场景已满，可拆解闲置物件后再制作")
		if building:
			if not held_by(records,player).is_empty() or not Stones.held_by(room.data.stones,player).is_empty():
				return _no("先放下手中的物件")
			var result := _aimed_placement(room,player,msg,geometry,"",recipe.kind)
			if not result.get("ok",false):
				return _no(place_hint(result.get("reason","no_surface")))
			var record := _record(recipe.kind,actor.point,result.yaw,player)
			_apply_pose(record,result.pose,result.yaw,result.supports)
			records[_id(records)] = record
		else:
			var point := _find_spot(records,actor,grid,recipe.kind)
			if not point.is_finite():
				return _no("周围没有合适的摆放位置")
			records[_id(records)] = _record(recipe.kind,point,actor.yaw,player)
	else:
		var quantity := int(recipe.get("quantity",1))
		if not Survival.can_carry(bag,recipe.item,slots) or int(bag.get(recipe.item,0)) > Survival.MAX_ITEM_COUNT-quantity:
			return _no("背包已满")
		_add(bag,recipe.item,quantity)
	state.bag = bag
	_clear_equipment(state)
	return _yes("制作了" + str(recipe.name))

static func _aimed_placement(room: Dictionary, player: String, msg: Dictionary, geometry: Dictionary,
		id: String, kind: String) -> Dictionary:
	for key: String in ["yaw", "pitch", "rotation"]:
		if not Survival.finite_number(msg.get(key)):
			return {}
	var actor: Dictionary = room.actors[player]
	var rotation := wrapf(float(msg.rotation),-PI,PI)
	var answer := PlacementWorld.preview(geometry,room.data.storage,id,actor.point,actor.y,PlayerMotion.WALK_EYE,
		wrapf(float(msg.yaw),-PI,PI),clampf(float(msg.pitch),-1.44,1.51),rotation,msg.get("snap",false) == true,kind)
	if answer.get("ok",false):
		var parts := Placement.bodies(id,PlacementWorld.profile(kind),answer.pose)
		for other: String in room.actors:
			if other == player:
				continue
			var teammate: Dictionary = room.actors[other]
			if PlacementWorld.blocks_player(parts,teammate.point,teammate.y):
				answer.ok = false
				answer.reason = "player"
				break
	return answer

static func action(room: Dictionary, player: String, msg: Dictionary, grid: Dictionary, geometry := {}) -> Dictionary:
	var actor: Dictionary = room.actors[player]
	if actor.get("swimming",false):
		return _no("回到岸上再操作")
	var records: Dictionary = room.data.storage
	var state: Dictionary = room.data.survival[player]
	var action_name: Variant = msg.get("action")
	if action_name in ["craft","build"]:
		return _craft(room,player,msg,grid,geometry)
	var held := held_by(records,player)
	var id: Variant = msg.get("id","")
	if action_name in ["place","drop","throw"] and not held.is_empty():
		id = held
	if id is not String or not records.has(id):
		return _no("这件物品已不在这里")
	var record: Dictionary = records[id]
	if not corpse_ready(record, float(room.data.elapsed)):
		return _no("落地后再操作")
	var is_held: bool = id == held
	if not is_held and (record.mode != "ground" or not near(actor,record,grid)):
		return _no("走近物品后再操作")
	var spec: Dictionary = KINDS[record.kind]
	var label: String = spec.name
	var item: Variant = msg.get("item","")
	match action_name:
		"store", "take":
			if spec.capacity == 0 or item is not String or not Survival.ITEM_NAMES.has(item):
				return _no("请选择可以存取的物品")
			if action_name == "store" and record.kind.begins_with("corpse_"):
				return _no("请选择可以存取的物品")
			var source: Dictionary = state.bag if action_name == "store" else record.bag
			var target: Dictionary = record.bag if action_name == "store" else state.bag
			var slots: int = spec.capacity if action_name == "store" else Survival.slot_count(room.data.backpackOwner == player)
			if int(source.get(item,0)) <= 0:
				return _no("物品已经取完")
			if not Survival.can_carry(target,item,slots):
				return _no("容器已满" if action_name == "store" else "背包已满")
			_remove(source,item)
			_add(target,item)
			_clear_equipment(state)
			return _yes(("存入" if action_name == "store" else "取出") + Survival.ITEM_NAMES[item])
		"carry":
			if not spec.carry or not held.is_empty() or not Stones.held_by(room.data.stones,player).is_empty():
				return _no("先放下手中的东西")
			if float(record.get("batchReady",0.0)) > 0.0:
				return _no("领取这批铁锭后才能移动炼铁炉")
			record.mode = "held"
			record.holder = player
			if not _settle_supported(records,room.data.provisions,id,geometry):
				return _no("上方有物品无法落稳，先移开它们")
			_spill_surface_contents(room.data.provisions,records,id,geometry)
			state.weapon = ""
			state.shield = false
			state.blocking = false
			return _yes("拿起了" + label)
		"place":
			if not is_held:
				return _no("手中没有这件物品")
			var answer := _aimed_placement(room,player,msg,geometry,id,record.kind)
			if not answer.get("ok",false):
				return _no(place_hint(answer.get("reason","no_surface")))
			_apply_pose(record,answer.pose,answer.yaw,answer.supports)
			return _yes("摆放了" + label)
		"drop":
			if not is_held:
				return _no("手中没有这件物品")
			var point := _find_spot(records,actor,grid,record.kind,id)
			if not point.is_finite():
				return _no("周围没有合适的摆放位置")
			grounded(record,point,actor.yaw)
			return _yes("放下了" + label)
		"throw":
			if not is_held or not spec.get("throwable",true) or not Survival.finite_number(msg.get("pitch")) or not Survival.finite_number(msg.get("yaw")):
				return _no("先拿起要投掷的物件")
			var yaw := wrapf(float(msg.yaw),-PI,PI)
			var aim := Basis.from_euler(Vector3(clampf(float(msg.pitch),-1.25,1.45),yaw,0.0))
			var direction := -aim.z
			record.mode = "air"
			record.thrower = player
			record.launch = room.data.elapsed
			record.at = Stones.pack(Vector3(actor.point.x,float(actor.y)+0.92,actor.point.y) + direction*0.43)
			record.velocity = Stones.pack(direction * lerpf(7.5,4.5,clampf(float(spec.radius)*1.2,0,1)) + Vector3.UP*0.8)
			record.yaw = yaw
			record.erase("holder")
			return _yes("投出了" + label)
		"dismantle", "burn":
			if spec.salvage.is_empty():
				return _no("这件物品没有可回收材料")
			if action_name == "burn":
				if float(spec.fuel) <= 0.0:
					return _no("先拆解再把木料加入营火")
				var fire: Dictionary = _nearest_fire(records,actor,grid)
				if fire.is_empty():
					return _no("靠近营火后可整件加入")
				_add_fuel(fire,float(spec.fuel),float(room.data.elapsed))
			var remains: Dictionary = record.bag
			var salvaged := {}
			if action_name == "dismantle":
				for material: String in spec.salvage:
					var n: int = spec.salvage[material]
					if Survival.can_carry(state.bag,material,Survival.slot_count(room.data.backpackOwner == player)) and int(state.bag.get(material,0))+n <= Survival.MAX_ITEM_COUNT:
						_add(state.bag,material,n)
					else:
						salvaged[material] = n
			var at: Vector2 = actor.point if is_held else Survival.horizontal(record.at)
			_spill(room.data.provisions,remains,at,grid)
			_spill(room.data.provisions,salvaged,at,grid)
			records.erase(id)
			if not _settle_supported(records,room.data.provisions,id,geometry):
				return _no("上方有物品无法落稳，先移开它们")
			_spill_surface_contents(room.data.provisions,records,id,geometry)
			return _yes(("拆解了" if action_name == "dismantle" else "投入营火：") + label + ("，原存货落在旁边" if not record.bag.is_empty() else ""))
		"smelt", "take_ingot":
			if record.kind != "iron_furnace" or is_held:
				return _no("走到放稳的炼铁炉前")
			var available: float = record.get("batchReady",0.0)
			var now: float = room.data.elapsed
			if action_name == "smelt":
				if available > 0.0:
					return _no("炉内还有一批矿料")
				for material: String in FURNACE_RECIPE:
					if int(state.bag.get(material,0)) < int(FURNACE_RECIPE[material]):
						return _no("缺少" + Survival.ITEM_NAMES[material])
				for material: String in FURNACE_RECIPE:
					_remove(state.bag,material,FURNACE_RECIPE[material])
				record.batchReady = now+FURNACE_SECONDS
				return _yes("矿料已入炉")
			if available <= 0.0 or now < available:
				return _no("铁锭还未炼好")
			if not Survival.can_carry(state.bag,"iron_ingot",Survival.slot_count(room.data.backpackOwner == player)):
				return _no("背包已满")
			_add(state.bag,"iron_ingot")
			record.batchReady = 0.0
			return _yes("取出了铁锭")
		"fuel":
			if record.kind != "campfire" or item is not String or not FUEL_ITEMS.has(item) or int(state.bag.get(item,0)) <= 0:
				return _no("背包里没有选择的燃料")
			_remove(state.bag,item)
			_clear_equipment(state)
			_add_fuel(record,FUEL_ITEMS[item],float(room.data.elapsed))
			return _yes("添加了" + Survival.ITEM_NAMES[item] + "，营火已点燃")
		"rename":
			if record.kind != "wood_sign" or record.owner != player or msg.get("text") is not String:
				return _no("路牌由制作它的玩家写字")
			record.text = clean_text(msg.text)
			return _yes("路牌已更新")
		"use":
			if record.kind == "rope_ladder" and not is_held and held.is_empty():
				actor.storageSeat = ""
				actor.climbing = "" if actor.get("climbing","") == id else id
				return _yes("已松开绳梯" if actor.climbing.is_empty() else "正在攀爬 · W 上 S 下 · 空格松手")
			if record.kind == "wood_chair" and not is_held and held.is_empty():
				actor.climbing = ""
				actor.storageSeat = "" if actor.get("storageSeat","") == id else id
				return _yes("已站起" if actor.storageSeat.is_empty() else "已坐下 · 移动或按空格起身")
	return _no("请选择可用操作")

static func place_hint(reason: String) -> String:
	match reason:
		"occupied": return "有物品挡住了摆放位置"
		"player": return "退开一些再摆放"
		"unstable", "slope": return "支撑不足，物件放不稳"
		"unsupported_face", "terrain_overlap": return "这个位置没有足够的支撑"
		_: return "瞄准附近可摆放的表面"

static func _nearest_fire(records: Dictionary, actor: Dictionary, grid: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var distance := INF
	for record: Dictionary in records.values():
		if record.kind != "campfire" or record.mode != "ground" or not near(actor,record,grid):
			continue
		var gap: float = actor.point.distance_squared_to(Survival.horizontal(record.at))
		if gap < distance:
			distance = gap
			best = record
	return best

static func table_at(records: Dictionary, point: Vector2) -> String:
	var closest := ""
	var best := Survival.PUT_REACH * Survival.PUT_REACH
	for id: String in records:
		var record: Dictionary = records[id]
		var distance := point.distance_squared_to(Survival.horizontal(record.at))
		if record.kind == "wood_table" and record.mode == "ground" and distance < best:
			closest = id
			best = distance
	return closest


static func table_slot(records: Dictionary, provisions: Dictionary, id: String) -> Vector3:
	var table: Dictionary = records[id]
	var pose := PlacementWorld.pose(table)
	for slot: Vector2 in Survival.TABLE_SLOTS:
		var offset := slot-Survival.TABLE_CENTER
		var position := pose * Vector3(offset.x,Survival.TABLE_TOP,offset.y)
		var used := false
		for provision: Dictionary in provisions.values():
			if _provision_support(provision) == id and Stones.unpack(provision.at).distance_squared_to(position) < 0.01:
				used = true
				break
		if not used:
			return position
	return Vector3.INF


static func provision_landing(from: Vector3, records: Dictionary, geometry: Dictionary, allow_water: bool) -> Dictionary:
	var point := Vector2(from.x,from.z)
	var ground := Lake.walk_height(point)
	var water := Lake.surface_height(point)
	var bottom := Vector3(point.x,maxf(ground,water),point.y)
	if from.y > bottom.y:
		var hit := Placement.trace(from,bottom-Vector3.UP*.05,PlacementWorld.nearby(geometry,records,point,2.0))
		if not hit.is_empty() and hit.support and hit.normal.y >= .80:
			return {"at":hit.point+Vector3.UP*.012,"id":hit.id if records.has(hit.id) else ""}
	return {"at":bottom+Vector3.UP*.012,"id":""} if allow_water or ground > water else {}

static func _provision_support(record: Dictionary) -> String:
	return record.get("tableId",record.get("supportId",""))

static func _move_provisions(provisions: Dictionary, id: String, displacement: Transform3D) -> void:
	for key: String in provisions:
		if _provision_support(provisions[key]) != id:
			continue
		var record: Dictionary = provisions[key].duplicate()
		record.at = Stones.pack(displacement * Stones.unpack(record.at))
		provisions[key] = record

static func _spill_surface_contents(provisions: Dictionary, records: Dictionary, id: String, geometry: Dictionary) -> void:
	for key: String in provisions.keys():
		if _provision_support(provisions[key]) != id:
			continue
		var record: Dictionary = provisions[key].duplicate()
		var landing := provision_landing(Stones.unpack(record.at)+Vector3.UP*.03,records,geometry,true)
		record.at = Stones.pack(landing.at)
		record.surface = "ground"
		record.erase("tableId")
		record.erase("supportId")
		if not landing.id.is_empty():
			record.supportId = landing.id
		provisions[key] = record


static func _near_table(records: Dictionary, actor: Dictionary, grid: Dictionary) -> bool:
	for record: Dictionary in records.values():
		if record.kind == "wood_table" and record.mode == "ground" and near(actor,record,grid):
			return true
	return false

static func _add_fuel(record: Dictionary, seconds: float, now: float) -> void:
	record.fuelUntil = minf(now+3600.0,maxf(float(record.fuelUntil),now)+seconds)
