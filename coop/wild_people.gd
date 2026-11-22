extends RefCounted

# All life, combat and social decisions run on the room server. Only JSON values live in saves.
const Beds = preload("res://camp_beds.gd")
const Caves = preload("res://east/cave_life.gd")
const Rules = preload("res://rules.gd")
const Survival = preload("res://survival.gd")
const Lake = preload("res://lake_layout.gd")
const Navigator = preload("res://wild_people_navigation.gd")
const Footing = preload("res://companion_footing.gd")
const Motion = preload("res://player_motion.gd")
const Weapons = preload("res://weapons.gd")
const Ship = preload("res://spaceship.gd")
const StorageWildlife = preload("res://storage_wildlife.gd")
const HOME := Vector2(1.8, -84.9)
const REST := Vector2(0.1, -87.6)
const FOOD := Vector2(6.0, -81.0)
const HERBS := Vector2(6.4, -83.8)
const WATER := Vector2(-16.0, -61.0) # Walkable southeast shore used by camp residents.
const RETREAT_DISTANCE := 21.0
const RETREAT_EXITS := [Vector2(14.5, -65.5), Vector2(17.0, -67.5), Vector2(20.0, -69.0), Vector2(21.5, -71.0)]
const REACH := 2.25
# In-place stride distances authored by bake-wild-people-locomotion.py.
const STRIDE_METERS := {"Walk": 1.38, "Run": 1.92, "Limp": 1.04, "LimpLeft": 1.04}
const TURN_RADIANS := PI * 0.5
const TURN_SPEED := 3.0
const TURN_START := 0.80
const TURN_END := 0.08
const WORK_SECONDS := {"DrawWater": 1.50, "GatherFruit": 1.25}
const SOURCES := {
	"fruit": {"name": "林果采集点", "x": 6.0, "z": -81.0, "item": "apple", "capacity": 8, "period": 65.0},
	"herbs": {"name": "药草采集点", "x": 6.4, "z": -83.8, "item": "herb", "capacity": 5, "period": 100.0},
}
const WEAPONS := {"": "徒手", "stone": "圆石", "club": "木棍", "spear": "长矛"}
const PHASE_NAMES := {"resident":"洞居者","raider": "来袭者", "retreat": "受伤撤退", "down": "昏迷", "captive": "受约束的俘虏", "companion": "自由同伴", "released": "已释放", "dead": "死亡", "gone": "已离开"}
const DEFAULT_SETTINGS := {"firstRaid": 540.0, "warning": 30.0, "rest": 300.0, "maxRaiders": 4, "maxCompanions": 4, "maxCaptives": 6, "damageScale": 1.0}
const MALE_NAMES := ["岩岚", "木衡", "阿峦", "砾川", "林弦", "山青"]
const FEMALE_NAMES := ["禾岚", "阿榆", "苇宁", "溪棠", "叶遥", "芦音"]

var navigator := Navigator.new()

static func settings_from(value: Variant) -> Dictionary:
	var out := DEFAULT_SETTINGS.duplicate()
	if value is Dictionary:
		for key: String in out:
			if Survival.finite_number(value.get(key)):
				var limits: Array = {"firstRaid": [20.0, 7200.0], "warning": [8.0, 180.0], "rest": [45.0, 3600.0], "maxRaiders": [1.0, 6.0], "maxCompanions": [1.0, 6.0], "maxCaptives": [1.0, 8.0], "damageScale": [0.25, 3.0]}[key]
				out[key] = clampf(float(value[key]), limits[0], limits[1])
		out.maxRaiders = int(out.maxRaiders)
		out.maxCompanions = int(out.maxCompanions)
		out.maxCaptives = int(out.maxCaptives)
	return out

static func initial(elapsed: float, config: Variant = null) -> Dictionary:
	var settings := settings_from(config)
	var resources := {}
	for key: String in SOURCES:
		resources[key] = {"stock": SOURCES[key].capacity, "progress": 0.0}
	return {"version": 1, "people": {}, "caves":Caves.camps_from_save({},elapsed), "nextId": 1, "settings": settings, "raid": {"wave": 0, "phase": "rest", "nextAt": elapsed + settings.firstRaid + settings.warning, "warningAt": 0.0, "startedAt": 0.0}, "resources": resources, "publicFood": false, "facility": 100.0, "log": [], "logId": 0, "repairAt": -10.0}

static func from_save(value: Variant, elapsed: float, grid: Dictionary, config: Variant = null) -> Dictionary:
	var out := initial(elapsed, config)
	if value is not Dictionary or value.get("version") != 1:
		return out
	out.caves = Caves.camps_from_save(value.get("caves"),elapsed)
	out.settings = settings_from(value.get("settings", config))
	out.publicFood = value.get("publicFood") == true
	out.facility = _number(value, "facility", 100.0, 0.0, 100.0)
	out.nextId = int(_number(value, "nextId", 1, 1, 10000000))
	out.repairAt = _number(value, "repairAt", -10.0, -10.0, elapsed)
	var raid: Variant = value.get("raid")
	if raid is Dictionary:
		out.raid.wave = int(_number(raid, "wave", 0, 0, 100000))
		out.raid.phase = raid.get("phase") if raid.get("phase") in ["rest", "warning", "active"] else "rest"
		for key in ["nextAt", "warningAt", "startedAt"]:
			out.raid[key] = _number(raid, key, elapsed + out.settings.rest, 0.0, elapsed + 10000.0)
	var resources: Variant = value.get("resources")
	if resources is Dictionary:
		for key: String in SOURCES:
			if resources.get(key) is Dictionary:
				out.resources[key].stock = int(_number(resources[key], "stock", 0, 0, SOURCES[key].capacity))
				out.resources[key].progress = _number(resources[key], "progress", 0, 0, SOURCES[key].period)
	var people: Variant = value.get("people")
	if people is Dictionary:
		for id: String in people:
			if out.people.size() >= 64 or id.length() > 32 or people[id] is not Dictionary:
				continue
			var saved: Dictionary = people[id]
			if saved.get("phase") not in PHASE_NAMES:
				continue
			var npc := make_person(id, int(_number(saved, "tier", 0, 0, 5)), str(saved.get("sex", "male")), Vector2(_number(saved, "x", HOME.x, Rules.MIN_CORNER.x, Rules.MAX_CORNER.x), _number(saved, "z", HOME.y, Rules.MIN_CORNER.y, Rules.MAX_CORNER.y)), elapsed)
			for key: String in npc:
				if key in ["x", "z", "yaw", "stepPhase", "maxHealth", "tier"]:
					continue
				if npc[key] is float or npc[key] is int:
					npc[key] = _number(saved, key, float(npc[key]), -1000.0 if key.ends_with("At") else 0.0, maxf(elapsed + 10000.0, 100000.0))
				elif npc[key] is bool:
					npc[key] = saved.get(key) == true
			npc.yaw = wrapf(_number(saved, "yaw", 0, -1000, 1000), -PI, PI)
			npc.stepPhase = _number(saved, "stepPhase", 0.0, 0.0, 1.0)
			npc.careNeed = int(_number(saved, "careNeed", npc.careNeed, 5, 7))
			npc.careDuration = _number(saved, "careDuration", npc.careDuration, 65, 115)
			npc.phase = saved.phase
			if npc.phase in ["captive","companion"] and saved.get("bedGoal") is String and str(saved.bedGoal).length() <= 40:
				npc.bedGoal = saved.bedGoal
				npc.bedStarted = _number(saved,"bedStarted",elapsed,0.0,elapsed)
				var exit_at: Variant = saved.get("cotExit")
				if saved.get("bed") == npc.bedGoal and exit_at is Array and exit_at.size()==3 and Survival.finite_number(exit_at[0]) and Survival.finite_number(exit_at[1]) and Survival.finite_number(exit_at[2]):
					npc.bed = npc.bedGoal
					npc.cotExit = exit_at
			Caves.restore(npc,saved,elapsed)
			if npc.phase=="resident" and not npc.has("homeMine"):
				continue
			npc.sex = "female" if saved.get("sex") == "female" else "male"
			npc.name = str(saved.get("name", npc.name)).left(24)
			npc.age = clampi(int(npc.age), 23, 55)
			npc.health = clampf(npc.health, 0, npc.maxHealth)
			for key in ["hunger", "water", "mood", "legL", "legR", "stun", "disease"]:
				npc[key] = clampf(npc[key], 0, 100)
			if not Rules.free_at(position(npc), grid):
				npc.x = HOME.x
				npc.z = HOME.y
			var saved_y := float(saved.y) if Survival.finite_number(saved.get("y")) else INF
			var ground := Lake.walk_height(position(npc),saved_y)
			npc.y = _number(saved,"y",ground,ground,ground+6.0)
			npc.weapon = saved.get("weapon", "") if saved.get("weapon", "") in WEAPONS else ""
			npc.shield = saved.get("shield") == true
			npc.order = "rest" if saved.get("order") == "rest" else "guard"
			npc.partner = str(saved.get("partner", "")) if _player_id(saved.get("partner")) else ""
			npc.clip = str(saved.get("clip", "Idle"))
			npc.help = str(saved.get("help", "")).left(80)
			npc.loot = {}
			if saved.get("loot") is Dictionary:
				for item: String in ["stone", "club", "spear", "shield", "apple", "bread"]:
					var count := int(_number(saved.loot, item, 0, 0, 6))
					if count > 0:
						npc.loot[item] = count
			npc.relations = {}
			if saved.get("relations") is Dictionary:
				for player: String in saved.relations:
					if _player_id(player) and npc.relations.size() < 64 and saved.relations[player] is Dictionary:
						var rel := relation(npc, player)
						for key: String in rel:
							rel[key] = _number(saved.relations[player], key, rel[key], -1000 if key.ends_with("At") else 0, elapsed + 10000.0 if key.ends_with("At") or key.ends_with("Until") else 100.0 if key in ["trust", "affection"] else 100000.0)
			if npc.phase == "dead" or npc.health <= 0:
				npc.phase = "dead"
				npc.health = 0.0
				npc.clip = "Down"
			out.people[id] = npc
			if id.begins_with("person-") and id.trim_prefix("person-").is_valid_int():
				out.nextId = maxi(out.nextId, id.trim_prefix("person-").to_int() + 1)
	# Restore the bounded feed counter so reconnecting clients never miss newer notices.
	out.logId = int(_number(value, "logId", 0, 0, 100000000))
	if value.get("log") is Array:
		for record: Variant in value.log.slice(-12):
			if record is Dictionary and record.get("text") is String and Survival.finite_number(record.get("at")) and Survival.finite_number(record.get("id")):
				out.log.append({"id": int(record.id), "at": float(record.at), "text": record.text.left(160)})
	return out

static func _number(d: Dictionary, key: String, fallback: float, lo: float, hi: float) -> float:
	return clampf(float(d[key]), lo, hi) if Survival.finite_number(d.get(key)) else fallback

static func _player_id(value: Variant) -> bool:
	return value is String and value.length() == 16 and value.is_valid_hex_number(false)

static func position(npc: Dictionary) -> Vector2:
	return Vector2(npc.x, npc.z)

static func relation(npc: Dictionary, player: String) -> Dictionary:
	if not npc.relations.has(player):
		if npc.relations.size() >= 64:
			return {"trust": 0.0, "affection": 0.0, "food": 0.0, "water": 0.0, "treatments": 0.0, "care": 0.0, "chatAt": -1000.0, "giftAt": -1000.0, "romanceAt": -1000.0, "refusedUntil": 0.0}
		npc.relations[player] = {"trust": 0.0, "affection": 0.0, "food": 0.0, "water": 0.0, "treatments": 0.0, "care": 0.0, "chatAt": -1000.0, "giftAt": -1000.0, "romanceAt": -1000.0, "refusedUntil": 0.0}
	return npc.relations[player]

static func make_person(id: String, tier: int, sex: String, at: Vector2, elapsed: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var names: Array = FEMALE_NAMES if sex == "female" else MALE_NAMES
	return {"id": id, "name": names[rng.randi_range(0, names.size() - 1)], "sex": sex, "age": rng.randi_range(23, 45), "tier": tier, "elite": tier >= 4,
		"x": at.x, "z": at.y, "y": Lake.walk_height(at), "yaw": 0.0, "phase": "raider", "health": 84.0 + tier * 17.0, "maxHealth": 84.0 + tier * 17.0,
		"hunger": 48.0, "water": 42.0, "mood": 44.0, "legL": 0.0, "legR": 0.0, "stun": 0.0, "stunUntil": 0.0, "disease": 0.0,
		"weapon": ["", "stone", "club", "spear", "spear", "spear"][tier], "shield": tier >= 4, "loot": {}, "looted": false, "bound": false,
		"relations": {}, "careNeed": rng.randi_range(5, 7), "careDuration": rng.randf_range(65.0, 115.0), "careSeconds": 0.0,
		"treatedUntil": 0.0, "joinedAt": 0.0, "capturedAt": 0.0, "partner": "", "romanceOpen": rng.randf() > 0.24, "order": "guard", "help": "",
		"clip": "Idle", "clipAt": elapsed, "stepPhase": 0.0, "attackAt": -10.0, "hitAt": -10.0, "speechAt": -1000.0, "captureAt": -10.0, "swingAt": 0.0, "escapeAt": 0.0, "escapeWarned": false,
		"bornAt": elapsed, "deadAt": 0.0, "actionAt": elapsed, "sickProgress": 0.0, "workAt": 0.0, "resistance": 65.0}

static func event(state: Dictionary, text: String, elapsed: float) -> void:
	state.logId += 1
	state.log.append({"id": state.logId, "text": text, "at": elapsed})
	while state.log.size() > 12:
		state.log.pop_front()

static func _clip(npc: Dictionary, name: String, elapsed: float) -> void:
	if npc.clip != name:
		npc.clip = name
		npc.clipAt = elapsed

static func _start_swing(npc: Dictionary, elapsed: float, throwing := false) -> void:
	if npc.weapon == "":
		npc.punchStep = posmod(int(npc.get("punchStep", -1)) + 1, Weapons.PUNCHES.size())
	npc.clip = "Throw" if throwing else String(Weapons.melee_clip(npc.weapon, npc.get("punchStep", 0), npc.shield))
	npc.clipAt = elapsed

static func _pace(npc: Dictionary, clip: String, advance: float, elapsed: float) -> void:
	var keep_phase: bool = npc.clip == clip or STRIDE_METERS.has(npc.clip) and STRIDE_METERS.has(clip)
	var phase := float(npc.stepPhase) if keep_phase else 0.0
	_clip(npc, clip, elapsed)
	npc.stepPhase = fposmod(phase + advance, 1.0)

static func _work(npc: Dictionary, clip: String, target: Vector2, elapsed: float) -> void:
	_face(npc, target)
	npc.clip = clip
	npc.clipAt = elapsed

static func _leg_scale(npc: Dictionary) -> float:
	return maxf(0.18, 1.0 - (float(npc.legL) + float(npc.legR)) * 0.0042)

static func _alive(npc: Dictionary) -> bool:
	return npc.phase not in ["dead", "gone", "released"] and npc.health > 0.0

static func loot_equipment(npc: Dictionary) -> void:
	if not npc.weapon.is_empty():
		npc.loot[npc.weapon] = int(npc.loot.get(npc.weapon, 0)) + 1
	if npc.shield:
		npc.loot.shield = int(npc.loot.get("shield", 0)) + 1
	npc.weapon = ""
	npc.shield = false

static func kill(state: Dictionary, npc: Dictionary, elapsed: float) -> void:
	if npc.phase == "dead":
		return
	loot_equipment(npc)
	npc.health = 0.0
	npc.phase = "dead"
	npc.deadAt = elapsed
	npc.partner = ""
	npc.help = "死亡不可恢复；可取回遗留装备"
	_clip(npc, "Down", elapsed)
	event(state, npc.name + "死亡了", elapsed)

static func harm(state: Dictionary, npc: Dictionary, damage: float, blunt: bool, zone: String, player: String, elapsed: float) -> Dictionary:
	if not _alive(npc):
		return {"ok": false, "text": "对方已经没有生命迹象"}
	var defense := 1.0 - minf(0.32, float(npc.tier) * 0.045 + (0.12 if npc.shield and zone == "body" and npc.phase == "raider" else 0.0))
	npc.health = maxf(0.0, npc.health - damage * defense)
	npc.hitAt = elapsed
	if blunt:
		npc.stun = minf(100.0, npc.stun + damage * 2.9)
	elif zone in ["legL", "legR"]:
		npc[zone] = minf(100.0, npc[zone] + damage * 2.25)
	if npc.phase == "companion":
		var rel := relation(npc, player)
		rel.trust = maxf(0.0, rel.trust - 25.0)
		rel.affection = maxf(0.0, rel.affection - 30.0)
		if npc.partner == player:
			npc.partner = ""
		npc.help = "受到了同伴的伤害，需要休养"
	if npc.health <= 0.0:
		kill(state, npc, elapsed)
		return {"ok": true, "text": npc.name + "死亡了，无法再招募"}
	if npc.stun >= 78.0 and npc.phase in ["raider", "retreat", "down"]:
		npc.phase = "down"
		npc.stunUntil = elapsed + 26.0
		_clip(npc, "Down", elapsed)
		return {"ok": true, "text": npc.name + "被击晕，靠近按 E 可制服（不会自动杀死）"}
	return {"ok": true, "text": ("左腿受伤，移动减慢" if zone == "legL" else "右腿受伤，移动减慢") if not blunt and zone != "body" else "钝击使对方眩晕" if blunt else "锐器造成伤害，继续攻击可能致命"}

static func ray_hit(npc: Dictionary, from: Vector3, to: Vector3, firearm := false) -> Dictionary:
	var p := position(npc)
	var base := Vector3(p.x, npc.get("y",Lake.walk_height(p)), p.y)
	var basis := Basis(Vector3.UP, float(npc.yaw))
	var down: bool = npc.phase in ["down", "dead"]
	# Match the exported rig: Down chest/head extend toward local +Z; legs toward -Z.
	var spheres := [["body", base + basis * Vector3(0, 1.14, 0), 0.38], ["body", base + basis * Vector3(0, 1.62, 0), 0.24]]
	var capsules := []
	if down:
		spheres = [["body", base + basis * Vector3(0, 0.18, 0.70), 0.23]]
		capsules.append(["body", base + basis * Vector3(0, 0.18, 0), base + basis * Vector3(0, 0.18, 0.43), 0.27])
	for side: String in ["legL", "legR"]:
		var x := -0.14 if side == "legL" else 0.14
		var a := Vector3(x, 0.18, 0)
		var b := Vector3(x, 0.76, 0)
		if down:
			a = Vector3(x, 0.23, -0.18)
			b = Vector3(x, 0.23, -0.79)
		capsules.append([side, base + basis * a, base + basis * b, 0.17])
	var best := {}
	var distance := INF
	for zone: Array in spheres:
		var near := Geometry3D.get_closest_point_to_segment(zone[1], from, to)
		var score := from.distance_squared_to(near)
		if near.distance_squared_to(zone[1]) <= float(zone[2]) ** 2 and score < distance:
			best = {"zone": zone[0], "distance": score}
			distance = score
	for zone: Array in capsules:
		var nearest := Geometry3D.get_closest_points_between_segments(from, to, zone[1], zone[2])
		var score := from.distance_squared_to(nearest[0])
		if nearest[0].distance_squared_to(nearest[1]) <= float(zone[3]) ** 2 and score < distance:
			best = {"zone": zone[0], "distance": score}
			distance = score
	if firearm:
		var head := Weapons.box_hit_distance(from, to, base, basis, _head_bounds(npc, down))
		if head < distance:
			return {"zone": "head", "distance": head}
	return best

static func _head_bounds(npc: Dictionary, down: bool) -> AABB:
	var elite: bool = npc.get("elite", false)
	var width := 0.42 if elite else 0.24
	if down or npc.clip == "Down":
		return AABB(Vector3(-width * 0.5, 0.05, 0.57), Vector3(width, 0.30, 0.43))
	var bounds := AABB(Vector3(-width * 0.5, 1.48, -0.15), Vector3(width, 0.46 if elite else 0.37, 0.29))
	match npc.clip:
		"Run": bounds.position += Vector3(0.0, -0.12, -0.08)
		"Captive": bounds.position += Vector3(0.0, -0.41, -0.07)
	return bounds

func can_reach(from: Vector2, to: Vector2, grid: Dictionary, reach := REACH) -> bool:
	return from.distance_squared_to(to) <= reach * reach and navigator._clear(from, to, grid)

func attack(room: Dictionary, player: String, msg: Dictionary, grid: Dictionary, sight_grid: Dictionary = {}) -> Dictionary:
	var actor: Dictionary = room.actors[player]
	var state: Dictionary = room.data.survival[player]
	var elapsed: float = room.data.elapsed
	var weapon: String = state.get("weapon", "")
	var stats := Weapons.stats(weapon)
	var previous_time: float = Weapons.stats(state.get("attackWeapon", weapon)).time
	if float(state.health) <= 0 or elapsed < float(state.get("attackAt", -2.0)) + previous_time:
		return {"ok": false, "text": "稍等武器收回"}
	if not Survival.finite_number(msg.get("yaw")) or not Survival.finite_number(msg.get("pitch")):
		return {"ok": false, "text": "无效的瞄准"}
	var heading := wrapf(float(msg.yaw), -PI, PI)
	if absf(angle_difference(actor.yaw, heading)) > 0.65:
		return {"ok": false, "text": "朝目标转身后再攻击"}
	if actor.swimming and Weapons.CAMP_MODELS.has(weapon):
		return {"ok": false, "text": "上岸后再使用武器"}
	var held := ""
	for id: String in room.data.stones:
		if room.data.stones[id].get("holder") == player and room.data.stones[id].mode == "held":
			held = id
	if not held.is_empty():
		return {"ok": false, "text": "手持石块时左键投掷，按 G 放下再近战"}
	if weapon == "":
		var continuing: bool = state.get("attackWeapon", "") == "" and elapsed - float(state.get("attackAt", -10.0)) < 1.65
		state.punchStep = posmod(int(state.get("punchStep", -1)) + 1, Weapons.PUNCHES.size()) if continuing else 0
	state.attackAt = elapsed
	state.attackWeapon = weapon
	state.attackPitch = clampf(float(msg.pitch), -1.44, 1.44)
	var sharp: bool = stats.sharp
	var firearm := Weapons.firearm(weapon)
	var reach: float = stats.reach
	var from := Vector3(actor.point.x, float(actor.y) + Motion.eye_offset(actor.swimming), actor.point.y)
	var to := from - Basis.from_euler(Vector3(clampf(msg.pitch, -1.44, 1.44), heading, 0)).z * reach
	var target := ""
	var closest := INF
	var zone := "body"
	for id: String in room.data.wildPeople.people:
		var npc: Dictionary = room.data.wildPeople.people[id]
		if not _alive(npc) or npc.phase == "companion" or npc.phase == "captive" and not sharp:
			continue
		var npc_at := position(npc)
		if actor.point.distance_squared_to(npc_at) > (reach + 0.5) ** 2:
			continue
		if not firearm and not navigator._clear(actor.point, npc_at, grid):
			continue
		var hit := ray_hit(npc, from, to, firearm)
		if not hit.is_empty() and float(hit.distance) < closest:
			target = id
			closest = hit.distance
			zone = hit.zone
	var animal := StorageWildlife.room_hit(room, from, to, 0.0, firearm)
	var hits_animal: bool = not animal.is_empty() and float(animal.distance) < closest
	if hits_animal:
		closest = animal.distance
	elif target.is_empty():
		return {"ok": true, "text": ""}
	if firearm or hits_animal:
		var grove_time := maxf(0.0, elapsed - float(room.data.get("groveStartedAt", 0.0)))
		var contact := from + from.direction_to(to) * sqrt(closest)
		if Ship.Ground.sight_obstructed(from, contact, sight_grid, grove_time) or Ship.blocks_sight(room.get("ship", {}), from, contact):
			return {"ok": true, "text": ""}
	if hits_animal:
		var report := StorageWildlife.apply_hit(room, animal, stats.damage, grid)
		return {"ok": not report.is_empty(), "text": report, "animalContact": from + from.direction_to(to) * sqrt(closest)}
	var npc: Dictionary = room.data.wildPeople.people[target]
	if zone == "head":
		npc.hitAt = elapsed
		kill(room.data.wildPeople, npc, elapsed)
		return {"ok": true, "text": "头部命中，击杀" + npc.name}
	var result := harm(room.data.wildPeople, npc, stats.damage, not sharp, zone, player, elapsed)
	if firearm and npc.health > 0.0 and zone == "body":
		result.text = "击中" + npc.name
	return result

func action(room: Dictionary, player: String, msg: Dictionary, grid: Dictionary, sight_grid: Dictionary = {}) -> Dictionary:
	var state: Dictionary = room.data.wildPeople
	var personal: Dictionary = room.data.survival[player]
	var actor: Dictionary = room.actors[player]
	var elapsed: float = room.data.elapsed
	var command: String = str(msg.get("action", ""))
	var item: String = str(msg.get("item", ""))
	if personal.health <= 0.0:
		return _no("倒地时无法进行这项操作")
	if command == "attack":
		return attack(room, player, msg, grid, sight_grid)
	if command in ["equip", "unequip", "shield"]:
		if command != "shield":
			for stone: Dictionary in room.data.stones.values():
				if stone.mode == "held" and stone.get("holder") == player:
					return _no("先按 G 放下手里的石块，再切换武器")
		if command == "shield":
			if int(personal.bag.get("shield", 0)) <= 0:
				return _no("背包里没有缴获的盾牌")
			personal.shield = not personal.get("shield", false)
		else:
			if command != "unequip" and not Weapons.ATTACKS.has(item):
				return _no("无法装备此物品")
			if not item.is_empty() and int(personal.bag.get(item, 0)) <= 0:
				return _no("先缴获或拾取这件武器")
			personal.weapon = item if command != "unequip" else ""
			actor.aimPitch = null
			if Weapons.firearm(personal.weapon):
				personal.blocking = false
		return _yes("装备已更新；武器在背包占一格")
	if command == "public_food":
		if not Survival.can_put(actor.point):
			return _no("靠近木桌才能更改公共食物权限")
		state.publicFood = not state.publicFood
		event(state, "木桌食物" + ("已允许自由同伴取用" if state.publicFood else "已保留给玩家"), elapsed)
		return _yes("权限已更新；俘虏仍需亲自供给")
	if command == "repair_facility":
		if not can_reach(actor.point, HOME, grid, 3.0):
			return _no("回营靠近门前再维修")
		if state.facility >= 100.0:
			return _no("设施完好")
		if elapsed < state.repairAt + 4.0:
			return _no("修补还在进行，4秒后可继续")
		if int(personal.bag.get("wood", 0)) < 1 or int(personal.bag.get("tarp", 0)) < 1:
			return _no("你的背包需要木料 1 份和防水布 1 份")
		personal.bag.wood -= 1
		personal.bag.tarp -= 1
		state.repairAt = elapsed
		state.facility = minf(100.0, state.facility + 25.0)
		if state.facility >= 100.0:
			room.data.quest.repaired = true
		return _yes("已消耗你的木料与防水布；设施完整度 +25")
	if command == "gather":
		if item == "water":
			if not Lake.can_fill_water(actor.point,actor.y):
				return _no("走近鹿鸣湖的水边再装水")
			if not Survival.can_carry(personal.bag,"water",Survival.slot_count(room.data.backpackOwner == player)):
				return _no("背包已满")
			personal.bag.water = int(personal.bag.get("water",0)) + 1
			return _yes("从鹿鸣湖装了一份淡水")
		if not SOURCES.has(item):
			return _no("未知采集点")
		var source: Dictionary = SOURCES[item]
		if not can_reach(actor.point, Vector2(source.x, source.z), grid):
			return _no("走近" + source.name + "再按 F 采集")
		if state.resources[item].stock <= 0:
			return _no("这里暂时采空了，稍后再来")
		if not Survival.can_carry(personal.bag, source.item, Survival.slot_count(room.data.backpackOwner == player)):
			return _no("背包已满")
		state.resources[item].stock -= 1
		personal.bag[source.item] = int(personal.bag.get(source.item, 0)) + 1
		return _yes("获得" + Survival.ITEM_NAMES[source.item] + "，采集点库存 -1")
	var id: String = str(msg.get("id", ""))
	if not state.people.has(id):
		return _no("对方已经离开")
	var npc: Dictionary = state.people[id]
	if not can_reach(actor.point, position(npc), grid):
		return _no("走近对方，并确保中间没有墙或深水")
	if command == "loot":
		if npc.phase not in ["down", "captive", "dead"]:
			return _no("先制服或击倒，清醒的来袭者不会交出装备")
		if not npc.weapon.is_empty() or npc.shield:
			loot_equipment(npc)
		var collected := 0
		for key: String in npc.loot.keys():
			while int(npc.loot[key]) > 0 and Survival.can_carry(personal.bag, key, Survival.slot_count(room.data.backpackOwner == player)):
				personal.bag[key] = int(personal.bag.get(key, 0)) + 1
				npc.loot[key] -= 1
				collected += 1
			if npc.loot[key] == 0:
				npc.loot.erase(key)
		return _yes("缴获 %d 件物品，已放入背包" % collected) if collected > 0 else _no("没有可拿走的装备，或背包已满")
	if not _alive(npc):
		return _no("死亡无法恢复，不能治疗、招募或发展关系")
	if command == "bed":
		if npc.phase not in ["companion","captive"]:
			return _no("可以为同伴或俘虏安排营地床位")
		if not str(npc.get("bedGoal","")).is_empty():
			_leave_cot(npc,elapsed)
			return _yes(npc.name + "结束了这次休息")
		var cot := Beds.nearest_cot(room,position(npc),npc.id)
		if cot.is_empty():
			return _no("营地里没有空床，可以再建一张绳床")
		npc.bedGoal = cot
		npc.bedStarted = elapsed
		return _yes("已为" + npc.name + "安排绳床")

	if command == "chat" and npc.phase in ["resident", "companion"]:
		if absf(float(actor.get("y", 0.0)) - float(npc.get("y", 0.0))) > 1.6:
			return _no("走到对方所在的高度再交谈")
		if elapsed - float(npc.speechAt) < 4.0:
			return _no("对方正在说话")
		if npc.phase == "resident":
			npc.speechAt = elapsed
			_face(npc, actor.point)
			_clip(npc, "Idle", elapsed)
			return _yes(npc.name + "向你打了个招呼")
	var rel := relation(npc, player)
	if command == "capture":
		if npc.phase not in ["raider", "retreat", "down"]:
			return _no("对方目前无需制服")
		if elapsed < npc.captureAt + 5.0:
			return _no("对方仍在反抗，先拉开距离")
		npc.captureAt = elapsed
		var captive_count := 0
		for person: Dictionary in state.people.values():
			if person.phase == "captive":
				captive_count += 1
		if captive_count >= int(state.settings.maxCaptives):
			return _no("营地最多照料 %d 名俘虏；先救治招募或释放现有俘虏" % state.settings.maxCaptives)
		var weak: bool = npc.phase == "down" or npc.legL + npc.legR >= 80.0 or npc.health <= npc.maxHealth * 0.34
		if not weak:
			personal.health = maxf(0.0, personal.health - 7.0)
			return _no("对方清醒且仍有体力，反抗造成 7 点伤害；先钝击击晕或伤腿追上")
		if npc.phase != "down" and npc.health > npc.maxHealth * 0.23:
			personal.health = maxf(0.0, personal.health - 4.0)
		npc.phase = "captive"
		npc.bound = false
		npc.capturedAt = elapsed
		npc.stunUntil = elapsed + 8.0 if npc.stun > 70.0 else 0.0
		npc.resistance = 70.0
		rel.trust = maxf(rel.trust, 2.0)
		npc.help = "需要食物、装好的淡水和药草治疗；不接受强迫亲密关系"
		_clip(npc, "Captive", elapsed)
		event(state, npc.name + "被制服，仍需照料并尊重本人去留", elapsed)
		return _yes("已制服；清醒后仍可能反抗，按 E 查看照料和释放选项")
	if command == "bind":
		if npc.phase != "captive" or npc.get("bound", false):
			return _no("对方当前无法加固约束")
		if int(personal.bag.get("wicker_strip", 0)) <= 0:
			return _no("背包中需要一份编条")
		personal.bag.wicker_strip -= 1
		if int(personal.bag.wicker_strip) <= 0 and personal.weapon == "wicker_strip":
			personal.weapon = ""
		npc.bound = true
		if npc.escapeAt > elapsed:
			npc.escapeAt += 14.0
		return _yes("用了编条加固约束")
	if command == "release":
		if npc.phase != "captive":
			return _no("只有俘虏需要解除约束")
		npc.phase = "released"
		npc.bound = false
		npc.escapeAt = 0.0
		_clip(npc, "Walk", elapsed)
		event(state, npc.name + "获释离开营地", elapsed)
		return _yes("已解除约束；对方可以自由离开")
	if command in ["feed", "water", "treat", "gift"]:
		if npc.phase not in ["captive", "companion", "down"]:
			return _no("对方正在敌对，先制服或击倒")
		if command == "gift" and (npc.phase != "companion" or elapsed < rel.giftAt + 65.0):
			return _no("自由同伴收到礼物后需要一些相处时间")
		if command in ["feed", "gift"]:
			if item not in Survival.FOOD_STATS or int(personal.bag.get(item, 0)) <= 0:
				return _no("背包中需要一份食物")
			if npc.hunger >= 87.0:
				return _no("对方已经吃饱，不必浪费食物")
			personal.bag[item] -= 1
			Survival.eat(npc, item)
			rel.food += 1.0
			rel.care += 1.0
			rel.trust = minf(100.0, rel.trust + 8.0)
			if command == "gift":
				rel.giftAt = elapsed
				rel.affection = minf(100.0, rel.affection + 7.0)
		elif command == "water":
			if int(personal.bag.get("water", 0)) <= 0:
				return _no("到鹿鸣湖边按 F 装水")
			if npc.water >= 96.0:
				return _no("对方暂时不渴")
			personal.bag.water -= 1
			npc.water = minf(100.0, npc.water + 32.0)
			rel.water += 1.0
			rel.care += 1.0
			rel.trust = minf(100.0, rel.trust + 8.0)
		else:
			if int(personal.bag.get("herb", 0)) <= 0:
				return _no("先采集一份药草包")
			if npc.health >= npc.maxHealth - 0.1 and npc.legL + npc.legR < 0.1 and npc.disease < 0.1:
				return _no("对方没有需要治疗的伤病")
			if elapsed < npc.treatedUntil - 50.0:
				return _no("药草仍在生效，让对方休养后再补药")
			personal.bag.herb -= 1
			npc.treatedUntil = elapsed + 100.0
			rel.treatments += 1.0
			rel.care += 2.0
			rel.trust = minf(100.0, rel.trust + 14.0)
			npc.disease = maxf(0.0, npc.disease - 18.0)
		npc.resistance = maxf(0.0, npc.resistance - 12.0)
		npc.help = "正在接受照料；药草需要时间帮助恢复" if command == "treat" else "已获得实际物资，照料记录已更新"
		return _yes("已消耗一份" + ("药草包，伤病会在供养充分时逐渐恢复" if command == "treat" else "溪水" if command == "water" else Survival.ITEM_NAMES[item]))
	if command == "invite":
		if npc.phase != "captive":
			return _no("只有愿意留下的俘虏可通过这项邀请成为自由同伴")
		if not ready_to_join(npc, rel):
			return _no("尚未建立足够信任：需要亲自供给食物、水、治疗并完成有效照料")
		var count := 0
		for person: Dictionary in state.people.values():
			if person.phase == "companion":
				count += 1
		if count >= state.settings.maxCompanions:
			return _no("营地目前的自由同伴人数已达上限；可以选择释放")
		npc.phase = "companion"
		npc.joinedAt = elapsed
		npc.escapeAt = 0.0
		npc.order = "guard"
		npc.help = "本人自愿留下；会守家并在安全范围寻找食物和溪水"
		rel.trust = minf(100.0, rel.trust + 12.0)
		event(state, npc.name + "自愿成为自由同伴", elapsed)
		return _yes(npc.name + "愿意留下，已解除约束；可以分配任务、装备和自由交往")
	if npc.phase != "companion":
		return _no("只有自由同伴可以协商任务、装备和关系")
	match command:
		"order":
			npc.order = "rest" if item == "rest" else "guard"
			return _yes("已协商休养" if npc.order == "rest" else "已协商守家；来袭时回防，重伤时撤退")
		"give_equipment":
			if item not in ["club", "spear", "shield", "stone"] or int(personal.bag.get(item, 0)) <= 0:
				return _no("背包中没有这件缴获装备")
			if item == "shield" and npc.shield or item != "shield" and not npc.weapon.is_empty():
				return _no("先取回同类装备，再交给新装备")
			personal.bag[item] -= 1
			if personal.get("weapon", "") == item and personal.bag[item] <= 0:
				personal.weapon = ""
			if item == "shield":
				personal.shield = false if personal.bag[item] <= 0 else personal.get("shield", false)
				npc.shield = true
			else:
				npc.weapon = item
			return _yes("已把" + Survival.ITEM_NAMES[item] + "交给同伴")
		"take_equipment":
			var chosen: String = "shield" if item == "shield" and npc.shield else npc.weapon
			if chosen.is_empty() or not Survival.can_carry(personal.bag, chosen, Survival.slot_count(room.data.backpackOwner == player)):
				return _no("没有装备可取，或背包已满")
			personal.bag[chosen] = int(personal.bag.get(chosen, 0)) + 1
			if chosen == "shield":
				npc.shield = false
			else:
				npc.weapon = ""
			return _yes("同伴交回了" + Survival.ITEM_NAMES[chosen])
		"chat":
			if elapsed < rel.chatAt + 60.0:
				return _no("刚聊过，留些时间一起生活再聊")
			if npc.health < npc.maxHealth * 0.35 or npc.hunger < 25 or npc.water < 25 or npc.disease > 35:
				return _no("对方现在需要照料，暂时无心闲聊")
			rel.chatAt = elapsed
			npc.speechAt = elapsed
			_face(npc, actor.point)
			rel.trust = minf(100.0, rel.trust + 5.0)
			rel.affection = minf(100.0, rel.affection + 8.0)
			npc.mood = minf(100.0, npc.mood + 6.0)
			return _yes(npc.name + "和你聊起了营地与今后的打算；尊重与相处增进了信任")
		"romance":
			if elapsed < rel.refusedUntil:
				return _no("对方已经表示需要空间；请尊重拒绝，稍后再谈")
			if not npc.partner.is_empty():
				return _no("对方已有伴侣" if npc.partner != player else "你们已经是伴侣")
			if elapsed < npc.joinedAt + 180.0 or rel.trust < 65.0 or rel.affection < 40.0:
				return _no("需要成为自由同伴至少 3 分钟、个人信任 65、好感 40；俘虏不能发展恋爱")
			rel.romanceAt = elapsed
			if not npc.romanceOpen and (rel.trust < 90.0 or rel.affection < 85.0) or npc.mood < 40:
				rel.refusedUntil = elapsed + 600.0
				return _yes(npc.name + "婉拒了：现在希望保持朋友关系。10 分钟内不能重复请求")
			npc.partner = player
			rel.affection = minf(100.0, rel.affection + 12.0)
			return _yes(npc.name + "自愿接受了你的心意；你们成为伴侣")
		"end_romance":
			if npc.partner != player:
				return _no("你们目前没有恋爱关系")
			npc.partner = ""
			rel.refusedUntil = elapsed + 600.0
			return _yes("已平和地结束恋爱关系，仍是自由同伴")
	return _no("未知互动")

static func ready_to_join(npc: Dictionary, rel: Dictionary) -> bool:
	return npc.phase == "captive" and rel.trust >= 40.0 and rel.food >= 2 and rel.water >= 2 and rel.treatments >= 1 and rel.care >= npc.careNeed and npc.careSeconds >= npc.careDuration and npc.health >= npc.maxHealth * 0.5 and npc.hunger >= 35 and npc.water >= 35 and npc.disease < 25.0

static func _no(text: String) -> Dictionary:
	return {"ok": false, "text": text}

static func _yes(text: String) -> Dictionary:
	return {"ok": true, "text": text}

func tick(room: Dictionary, grid: Dictionary, delta: float) -> void:
	var state: Dictionary = room.data.wildPeople
	var elapsed: float = room.data.elapsed
	for key: String in SOURCES:
		var resource: Dictionary = state.resources[key]
		resource.progress += delta
		while resource.progress >= SOURCES[key].period:
			resource.progress -= SOURCES[key].period
			resource.stock = mini(SOURCES[key].capacity, int(resource.stock) + 1)
	_trim_records(room, 48)
	_raid(room, grid)
	Caves.discover(room,self)
	var footing := Footing.for_room(room) as Footing
	for id: String in state.people.keys():
		var npc: Dictionary = state.people[id]
		if npc.phase == "gone":
			continue
		var at := position(npc)
		npc.y = footing.height(at,float(npc.get("y",Lake.walk_height(at))))
		if npc.phase not in ["captive","companion"] and npc.has("bedGoal"):
			_leave_cot(npc,elapsed)
		if npc.phase == "dead":
			if elapsed - npc.deadAt > 600.0:
				state.people.erase(id)
				room.people_routes.erase(id)
			continue
		_life(state, npc, elapsed, delta)
		if not _alive(npc):
			if npc.phase == "released":
				_drive(room, npc, Vector2(13.0, -72.0), 1.3, grid, delta)
				if position(npc).distance_to(HOME) > 16:
					npc.phase = "gone"
			continue
		match npc.phase:
			"resident":
				Caves.step(room,npc,grid,delta,self)
			"down":
				_clip(npc, "Down", elapsed)
				if elapsed >= npc.stunUntil:
					npc.phase = "retreat"
					npc.stun = 25.0
			"captive":
				_captive(room, npc, grid, delta)
				if npc.phase == "captive":
					_rest_at_cot(room,npc,grid,delta)
				elif npc.has("bedGoal"):
					_leave_cot(npc,elapsed)
			"raider", "retreat":
				_enemy(room, npc, grid, delta)
			"companion":
				if not _rest_at_cot(room,npc,grid,delta) and elapsed - float(npc.speechAt) >= 3.0:
					_companion(room, npc, grid, delta)
	# Corpses retain their loot and record, while distant departed people are compacted first.
	if state.people.size() > 48:
		for id: String in state.people.keys():
			var npc: Dictionary = state.people[id]
			if npc.phase == "gone" or npc.phase == "dead" and elapsed - npc.deadAt > 120.0:
				state.people.erase(id)
				room.people_routes.erase(id)
			if state.people.size() <= 40:
				break


func _trim_records(room: Dictionary, limit: int) -> void:
	var state: Dictionary = room.data.wildPeople
	while state.people.size() > limit:
		var oldest := ""
		var age := INF
		for id: String in state.people:
			var npc: Dictionary = state.people[id]
			if npc.phase not in ["dead", "gone"]:
				continue
			var at: float = npc.deadAt if npc.phase == "dead" else npc.bornAt
			if at < age:
				oldest = id
				age = at
		if oldest.is_empty():
			return
		state.people.erase(oldest)
		room.people_routes.erase(oldest)

func _raid(room: Dictionary, grid: Dictionary) -> void:
	var state: Dictionary = room.data.wildPeople
	var elapsed: float = room.data.elapsed
	var raid: Dictionary = state.raid
	if raid.phase == "rest" and elapsed >= raid.nextAt - state.settings.warning:
		raid.phase = "warning"
		raid.warningAt = elapsed
		event(state, "林外传来急促脚步，约 %d 秒后有人来袭。准备防守或回营！" % int(state.settings.warning), elapsed)
	if raid.phase == "warning" and elapsed >= raid.nextAt:
		var tier := mini(5, int(raid.wave))
		var count := mini(int(state.settings.maxRaiders), 1 + int(raid.wave / 2))
		var spawned := 0
		for i in count:
			if state.people.size() >= 64:
				break
			var at := Vector2(11.8 + i * 0.85, -72.6 - i * 1.3) if int(raid.wave) % 2 == 0 else Vector2(-8.3 - i, -76.0 + i * 0.7)
			if not Rules.free_at(at, grid):
				at = Vector2(9.0 + i, -79.0)
			var id := "person-%d" % state.nextId
			while state.people.has(id):
				state.nextId += 1
				id = "person-%d" % state.nextId
			state.nextId += 1
			state.people[id] = make_person(id, tier, "female" if (int(raid.wave) + i) % 2 == 1 else "male", at, elapsed)
			spawned += 1
		raid.phase = "active"
		raid.startedAt = elapsed
		raid.wave += 1
		event(state, "第 %d 次来袭：%d 名成年人，%s" % [raid.wave, spawned, "长矛与盾牌" if tier >= 4 else WEAPONS[["", "stone", "club", "spear"][mini(tier, 3)]]], elapsed)
	if raid.phase == "active":
		var enemies := 0
		for npc: Dictionary in state.people.values():
			if npc.phase in ["raider", "retreat"]:
				enemies += 1
		if enemies == 0 or elapsed > raid.startedAt + 135.0:
			for npc: Dictionary in state.people.values():
				if npc.phase == "raider":
					npc.phase = "retreat"
			raid.phase = "rest"
			raid.nextAt = elapsed + state.settings.rest + state.settings.warning + float(int(raid.wave) % 3) * 25.0
			event(state, "这一轮袭击结束，至少 %d 秒休整；检查伤员和营地设施" % int(state.settings.rest), elapsed)

static func _life(state: Dictionary, npc: Dictionary, elapsed: float, delta: float) -> void:
	npc.hunger = maxf(0, npc.hunger - 0.053 * delta)
	npc.water = maxf(0, npc.water - 0.075 * delta)
	npc.stun = maxf(0, npc.stun - 0.6 * delta) if npc.phase != "down" else npc.stun
	var supplied: bool = npc.hunger > 20.0 and npc.water > 20.0
	var treated: bool = elapsed < npc.treatedUntil
	if not supplied:
		npc.health -= delta * (0.18 if npc.water <= 0 or npc.hunger <= 0 else 0.025)
		npc.mood = maxf(0, npc.mood - delta * 0.08)
		npc.sickProgress += delta
		if npc.sickProgress > 65:
			npc.disease = minf(100.0, npc.disease + delta * 0.07)
	elif treated:
		npc.health = minf(npc.maxHealth, npc.health + delta * 0.45)
		npc.legL = maxf(0, npc.legL - delta * 0.50)
		npc.legR = maxf(0, npc.legR - delta * 0.50)
		npc.disease = maxf(0, npc.disease - delta * 0.32)
		npc.sickProgress = maxf(0, npc.sickProgress - delta)
		npc.mood = minf(100, npc.mood + delta * 0.05)
	elif npc.disease > 0:
		npc.health -= delta * npc.disease * 0.0017
	var previously_treated := false
	for rel: Dictionary in npc.relations.values():
		previously_treated = previously_treated or rel.treatments >= 1.0
	if npc.phase == "captive" and supplied and (treated or previously_treated and npc.health >= npc.maxHealth - 0.1):
		npc.careSeconds = minf(npc.careDuration, npc.careSeconds + delta)
	if npc.health <= 0:
		kill(state, npc, elapsed)

static func _leave_cot(npc: Dictionary, elapsed: float) -> void:
	if npc.has("cotExit"):
		var foot: Array = npc.cotExit
		npc.x = foot[0]
		npc.y = foot[1]
		npc.z = foot[2]
	npc.erase("cotExit")
	npc.erase("bed")
	npc.erase("bedGoal")
	npc.cotCheckAt = elapsed + 25.0

func _rest_at_cot(room: Dictionary, npc: Dictionary, grid: Dictionary, delta: float) -> bool:
	var elapsed: float = room.data.elapsed
	if not npc.has("bedGoal"):
		# A captive is escorted to an assigned bed. Companions plan their own breaks.
		if npc.phase=="captive" or npc.order!="rest" and (npc.water<60 or npc.hunger<57) and npc.health>=npc.maxHealth*.35:
			return false
		if elapsed < float(npc.get("cotCheckAt",0.0)):
			return false
		npc.cotCheckAt = elapsed+4.0
		var night := fposmod(elapsed-122.0,420.0)
		var tired: bool = npc.health < npc.maxHealth*.70 or npc.order=="rest" or night>22 and night<150
		if not tired or npc.phase == "companion" and room.data.wildPeople.raid.phase=="active" and npc.order!="rest" and npc.health>=npc.maxHealth*.35:
			return false
		var cot := Beds.nearest_cot(room,position(npc),npc.id)
		if cot.is_empty():
			return false
		npc.bedGoal = cot
		npc.bedStarted = elapsed
	var id: String = npc.bedGoal
	var socket := Beds.socket(room,id)
	if socket.is_empty() or Beds.claimed(room,id,npc.id) or npc.get("escapeAt",0.0)>0.0:
		_leave_cot(npc,elapsed)
		return false
	if not npc.has("bed"):
		if elapsed > float(npc.bedStarted)+90.0:
			_leave_cot(npc,elapsed)
			return false
		var at := position(npc)
		var center: Vector2 = socket.point
		var right := Vector2.RIGHT.rotated(-float(socket.yaw))
		var side := center+right*.82
		if at.distance_squared_to(side)>at.distance_squared_to(center-right*.82):
			side=center-right*.82
		if not Rules.free_at(side,grid):
			side=center*2.0-side
		if at.distance_to(side)>.5 or absf(float(npc.y)-float(socket.ground))>.48:
			npc.help = "正在走向铺盖" if room.data.storage[id].kind==Beds.BEDROLL else "正在走向营地绳床"
			_drive(room,npc,side,1.12,grid,delta)
			return true
		npc.cotExit = [npc.x,npc.y,npc.z]
		npc.bed = id
		npc.bedStarted = elapsed
	npc.x = socket.point.x
	npc.z = socket.point.y
	npc.y = socket.y
	npc.yaw = socket.yaw
	npc.help = "正在床上睡觉"
	_clip(npc,"Sleep",elapsed)
	if npc.hunger>20 and npc.water>20:
		npc.health = minf(npc.maxHealth,npc.health + Beds.HEAL_PER_SECOND*delta)
	if elapsed - float(npc.bedStarted)>18 and (npc.health>=npc.maxHealth or npc.water<25 or npc.hunger<25):
		_leave_cot(npc,elapsed)
		return false
	return true

func _captive(room: Dictionary, npc: Dictionary, grid: Dictionary, delta: float) -> void:
	var state: Dictionary = room.data.wildPeople
	var elapsed: float = room.data.elapsed
	if not npc.has("bed"):
		_clip(npc, "Down" if elapsed < npc.stunUntil else "Captive", elapsed)
	if not npc.has("bed") and elapsed >= npc.stunUntil and npc.resistance > 55.0 and npc.mood < 45.0 and elapsed > npc.attackAt + 12.0:
		for player: String in room.actors:
			if room.data.survival[player].health > 0 and can_reach(position(npc), room.actors[player].point, grid, 1.25):
				npc.attackAt = elapsed
				npc.resistance = maxf(0, npc.resistance - 8.0)
				room.data.survival[player].health = maxf(0, room.data.survival[player].health - 4.0)
				npc.help = "仍在清醒反抗；退开一些、提供补给和治疗以建立信任"
				event(state, npc.name + "仍在反抗，近身玩家受了轻伤", elapsed)
				break
	var cared: bool = npc.hunger >= 25.0 and npc.water >= 25.0 and npc.disease < 35.0
	npc.resistance = clampf(npc.resistance + delta * (-0.035 if cared else 0.12), 0, 100)
	if not cared and elapsed >= npc.stunUntil:
		if npc.escapeAt <= 0:
			var wait := 38.0 if npc.get("bound", false) else 24.0
			npc.escapeAt = elapsed + wait
			npc.help = "缺乏照料，正在挣脱。%d 秒内请提供食物、水或治疗" % int(wait)
			event(state, npc.name + "因缺乏照料开始挣脱约束", elapsed)
		elif elapsed >= npc.escapeAt:
			npc.phase = "retreat"
			npc.bound = false
			npc.escapeAt = 0.0
			npc.help = "挣脱后逃离；重伤减速仍可追上"
			event(state, npc.name + "挣脱逃走了", elapsed)
	else:
		npc.escapeAt = 0.0

func _enemy(room: Dictionary, npc: Dictionary, grid: Dictionary, delta: float) -> void:
	var state: Dictionary = room.data.wildPeople
	var elapsed: float = room.data.elapsed
	if npc.health < npc.maxHealth * 0.28 or npc.legL + npc.legR > 130.0:
		npc.phase = "retreat"
	if npc.phase == "retreat":
		# Aim past the departure boundary. Adjacent raiders can take different paths out.
		var exit: Vector2 = RETREAT_EXITS[posmod(npc.id.hash(), RETREAT_EXITS.size())]
		_drive(room, npc, exit, 2.0, grid, delta)
		if position(npc).distance_squared_to(HOME) > RETREAT_DISTANCE * RETREAT_DISTANCE:
			npc.phase = "gone"
			room.people_routes.erase(npc.id)
		return
	var target := ""
	var distance := 11.0
	for id: String in room.actors:
		var actor: Dictionary = room.actors[id]
		if room.data.survival[id].health <= 0 or room.ship.pilot == id or actor.swimming:
			continue
		var gap := position(npc).distance_to(actor.point)
		if gap < distance:
			distance = gap
			target = id
	if not target.is_empty():
		var actor: Dictionary = room.actors[target]
		var reach := 2.55 if npc.weapon == "spear" else 1.55
		if distance <= reach and can_reach(position(npc), actor.point, grid, reach):
			_face(npc, actor.point)
			if elapsed >= npc.attackAt + 2.7:
				npc.attackAt = elapsed
				npc.swingAt = elapsed + 0.66
				_start_swing(npc, elapsed, npc.weapon == "stone")
			if npc.swingAt > 0 and elapsed >= npc.swingAt:
				npc.swingAt = 0.0
				var personal: Dictionary = room.data.survival[target]
				var damage := (6.5 + float(npc.tier) * 2.5) * float(state.settings.damageScale)
				if personal.get("shield", false) and personal.get("blocking", false):
					var facing := Vector2(0, -1).rotated(-actor.yaw)
					if facing.dot(actor.point.direction_to(position(npc))) > 0.25:
						damage *= 0.22
				personal.health = maxf(0, personal.health - damage)
				personal.hurtAt = elapsed
			if elapsed > npc.attackAt + 1.1:
				_clip(npc, "Guard", elapsed)
		else:
			npc.swingAt = 0.0
			_drive(room, npc, actor.point, 2.2, grid, delta)
		return
	# Raiders can steal an actual table item and damage a shared, repairable facility.
	var food_id := ""
	for id: String in room.data.provisions:
		if room.data.provisions[id].surface == "table" and Survival.FOOD_STATS.has(room.data.provisions[id].item):
			food_id = id
			break
	var goal := Survival.TABLE_CENTER + Vector2(0.0, 0.85) if not food_id.is_empty() else HOME + Vector2(0, -1.2)
	var ready: bool = position(npc).distance_to(goal) <= 1.3
	if not food_id.is_empty():
		var record: Dictionary = room.data.provisions[food_id]
		ready = Survival.can_reach(position(npc), Survival.horizontal(record.at), "table")
	if not ready:
		_drive(room, npc, goal, 1.8, grid, delta)
	elif elapsed >= npc.actionAt + 4.0:
		npc.actionAt = elapsed
		_start_swing(npc, elapsed)
		if not food_id.is_empty():
			var item: String = room.data.provisions[food_id].item
			room.data.provisions.erase(food_id)
			npc.loot[item] = int(npc.loot.get(item, 0)) + 1
			npc.phase = "retreat"
			event(state, npc.name + "抢走了桌上一份食物；制服后可以取回", elapsed)
		else:
			state.facility = maxf(0, state.facility - 8.0 - npc.tier * 2.0)
			if state.facility <= 0.0:
				room.data.quest.repaired = false
			event(state, "营地设施遭到破坏，完整度 %d%%" % state.facility, elapsed)
	elif elapsed > npc.actionAt + 1.0:
		_clip(npc, "Guard", elapsed)

func _companion(room: Dictionary, npc: Dictionary, grid: Dictionary, delta: float) -> void:
	var state: Dictionary = room.data.wildPeople
	var elapsed: float = room.data.elapsed
	var injured: bool = npc.health < npc.maxHealth * 0.35 or npc.legL + npc.legR > 110 or npc.disease > 45
	if injured or npc.order == "rest":
		npc.help = "重伤撤退休养，请带来药草和补给" if injured else "按约定在营地休养"
		if position(npc).distance_to(REST) > 0.6:
			_drive(room, npc, REST, 1.1, grid, delta)
		else:
			_clip(npc, "Rest", elapsed)
		return
	var enemy := ""
	var nearest := 999.0
	for id: String in state.people:
		var other: Dictionary = state.people[id]
		if other.phase == "raider" and position(other).distance_to(HOME) < 25.0:
			var gap := position(npc).distance_to(position(other))
			if gap < nearest:
				nearest = gap
				enemy = id
	if not enemy.is_empty():
		npc.help = "来袭回防中"
		var other: Dictionary = state.people[enemy]
		var reach := 2.4 if npc.weapon == "spear" else 1.55
		if can_reach(position(npc), position(other), grid, reach):
			_face(npc, position(other))
			if elapsed > npc.attackAt + 2.2:
				npc.attackAt = elapsed
				_start_swing(npc, elapsed)
				var damage := 13.0 if npc.weapon == "spear" else 8.0 if not npc.weapon.is_empty() else 5.0
				harm(state, other, damage, npc.weapon != "spear", "body", "", elapsed)
				# A defending raider fights back. Heavy injuries make the companion retreat next tick.
				npc.health = maxf(0, npc.health - (4.0 + other.tier * 1.8) * (0.65 if npc.shield else 1.0))
				if npc.health <= 0:
					kill(state, npc, elapsed)
			elif elapsed > npc.attackAt + 1.1 or WORK_SECONDS.has(npc.clip):
				_clip(npc, "Guard", elapsed)
		else:
			_drive(room, npc, position(other), 2.1, grid, delta)
		return
	if WORK_SECONDS.has(npc.clip) and elapsed < float(npc.clipAt) + float(WORK_SECONDS[npc.clip]):
		return
	if npc.disease > 0 or npc.health < npc.maxHealth * 0.75 or npc.legL + npc.legR > 15:
		npc.help = "需要药草治疗；有食物和水时才会逐渐恢复"
	elif npc.hunger < 50:
		npc.help = "正在安全范围寻找食物"
	else:
		npc.help = "守家巡逻中；保留食物和水的生活需求"
	if npc.water < 60:
		if Lake.can_fill_water(position(npc), npc.get("y",0.0)) and Lake.lake_distance(position(npc)) <= 1.015:
			npc.water = minf(100.0, npc.water + 32.0)
			npc.help = "正在湖边取水"
			_work(npc, "DrawWater", Lake.center(), elapsed)
		else:
			_drive(room,npc,WATER,1.55,grid,delta)
		return
	if npc.hunger < 57:
		var food_id := ""
		if state.publicFood:
			for id: String in room.data.provisions:
				if room.data.provisions[id].surface == "table" and Survival.FOOD_STATS.has(room.data.provisions[id].item):
					food_id = id
					break
		if not food_id.is_empty():
			var goal := Survival.TABLE_CENTER + Vector2(0.0, 0.85)
			var record: Dictionary = room.data.provisions[food_id]
			var can_eat: bool = Survival.can_reach(position(npc), Survival.horizontal(record.at), "table")
			if not can_eat:
				_drive(room, npc, goal, 1.35, grid, delta)
			else:
				Survival.eat(npc, room.data.provisions[food_id].item)
				room.data.provisions.erase(food_id)
				_clip(npc, "Rest", elapsed)
		elif state.resources.fruit.stock > 0:
			if position(npc).distance_to(FOOD) > 0.85:
				_drive(room, npc, FOOD, 1.35, grid, delta)
			else:
				if elapsed >= npc.workAt + 5.0:
					npc.workAt = elapsed
					state.resources.fruit.stock -= 1
					Survival.eat(npc, "apple")
					npc.help = "正在采集林果"
					_work(npc, "GatherFruit", FOOD, elapsed)
				else:
					_clip(npc, "Rest", elapsed)
		else:
			npc.help = "找不到食物，请亲自送食物或开放桌上储备"
			_clip(npc, "Guard", elapsed)
		return
	var patrol := HOME + Vector2(sin(elapsed * 0.026 + float(npc.id.hash() % 10)) * 2.1, cos(elapsed * 0.026 + float(npc.id.hash() % 10)) * 1.5)
	if position(npc).distance_to(patrol) > 0.5:
		_drive(room, npc, patrol, 0.85, grid, delta)
	else:
		_clip(npc, "Guard", elapsed)

static func _face(npc: Dictionary, goal: Vector2) -> void:
	var direction := position(npc).direction_to(goal)
	if not direction.is_zero_approx():
		npc.yaw = atan2(-direction.x, -direction.y)

func _drive(room: Dictionary, npc: Dictionary, goal: Vector2, speed: float, grid: Dictionary, delta: float) -> void:
	if not room.people_routes.has(npc.id):
		room.people_routes[npc.id] = {}
	var route: Dictionary = room.people_routes[npc.id]
	var at := position(npc)
	var waypoint := navigator._waypoint(at, goal, route, grid, room.data.elapsed)
	if float(route.get("stalled", 0.0)) > 0.8:
		waypoint = navigator.recover(at, goal, route, grid, room.data.elapsed)
		route.stalled = 0.0
	var footing := Footing.for_room(room) as Footing
	var feet := float(npc.get("y",Lake.walk_height(at)))
	waypoint = footing.waypoint(at,waypoint,goal,route,grid,feet,Navigator.PEOPLE_BODY,room.data.elapsed)
	var direction := at.direction_to(waypoint)
	var elapsed: float = room.data.elapsed
	var leg_scale := _leg_scale(npc)
	var turn_limit := TURN_SPEED * delta * lerpf(0.65, 1.0, leg_scale)
	if not direction.is_zero_approx():
		var yaw_change := angle_difference(npc.yaw, atan2(-direction.x, -direction.y))
		var turning: bool = npc.clip in ["TurnLeft", "TurnRight"]
		if absf(yaw_change) > (TURN_END if turning else TURN_START):
			var turn := clampf(yaw_change, -turn_limit, turn_limit)
			npc.yaw = wrapf(float(npc.yaw) + turn, -PI, PI)
			_pace(npc, "TurnLeft" if turn > 0 else "TurnRight", absf(turn) / TURN_RADIANS, elapsed)
			return
	var landing := footing.move(at,direction,minf(delta,at.distance_to(waypoint)/maxf(0.01,speed*leg_scale)),grid,
		speed*leg_scale,feet,Navigator.PEOPLE_BODY)
	var next := Vector2(landing.x,landing.z)
	npc.x = next.x
	npc.z = next.y
	npc.y = landing.y
	var moved := next - at
	var distance := moved.length()
	route.stalled = float(route.get("stalled", 0.0)) + delta if distance < 0.006 and at.distance_to(goal) > 0.4 else 0.0
	if moved.is_zero_approx():
		_clip(npc, "Guard", elapsed)
		if at.distance_to(goal) > 2.0 and npc.phase == "companion":
			npc.help = "道路受阻，无法到达补给，请来帮助"
	else:
		var yaw_change := angle_difference(npc.yaw, atan2(-moved.x, -moved.y))
		npc.yaw = wrapf(float(npc.yaw) + clampf(yaw_change, -turn_limit, turn_limit), -PI, PI)
		var clip := ("LimpLeft" if npc.legL > npc.legR else "Limp") if leg_scale < 0.75 else "Run" if speed > 1.75 else "Walk"
		_pace(npc, clip, distance / float(STRIDE_METERS[clip]), elapsed)

static func snapshot(state: Dictionary, player: String, elapsed: float) -> Dictionary:
	var people := {}
	for id: String in state.people:
		var npc: Dictionary = state.people[id]
		if npc.phase == "gone":
			continue
		var out := npc.duplicate()
		out.erase("relations")
		out.erase("romanceOpen")
		out.relation = npc.relations.get(player, {"trust": 0.0, "affection": 0.0, "food": 0.0, "water": 0.0, "treatments": 0.0, "care": 0.0, "chatAt": -1000.0, "giftAt": -1000.0, "refusedUntil": 0.0}).duplicate()
		out.readyToJoin = ready_to_join(npc, out.relation)
		out.relationship = "你的伴侣" if npc.partner == player else "已有伴侣" if not npc.partner.is_empty() else "尚未恋爱"
		out.erase("partner")
		out.y = npc.get("y",Lake.walk_height(position(npc)))
		out.speedFactor = _leg_scale(npc)
		people[id] = out
	return {"people": people, "caves":state.caves.duplicate(true), "raid": state.raid.duplicate(), "resources": state.resources.duplicate(true), "publicFood": state.publicFood, "facility": state.facility, "log": state.log.duplicate(true), "settings": state.settings.duplicate(), "elapsed": elapsed}
