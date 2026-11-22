extends RefCounted

const Dog = preload("res://camp_dog.gd")
const Boar = preload("res://woodland_boar.gd")
const Sheep = preload("res://lake_sheep.gd")
const Storage = preload("res://camp_storage.gd")
const Lake = preload("res://lake_layout.gd")
const Rules = preload("res://rules.gd")
const Stones = preload("res://stones.gd")
const Survival = preload("res://survival.gd")
const Weapons = preload("res://weapons.gd")
const Wildlife = preload("res://wildlife.gd")

const MAX_HEALTH := {"croc": 100.0, "eagle": 42.0, "dog": 64.0, "boar": 84.0, "sheep": 45.0}
const NAMES := {"croc": "鳄鱼", "eagle": "老鹰", "dog": "藏獒", "boar": "野猪", "sheep": "绵羊"}
const DROPS := {
	"croc": {"crocodile_meat_raw": 3, "crocodile_hide": 1},
	"eagle": {"eagle_meat": 1, "eagle_feather": 1, "eagle_claw": 1},
	"dog": {"dog_meat": 2},
	"boar": {"boar_raw":2,"boar_hide":1,"boar_tusk":2},
	"sheep": {"lamb_raw": 2},
}
# Same imported contact offset that WildlifeScene applies when the eagle perches.
const EAGLE_PERCH_OFFSET := Vector3(0.0, 0.008, 0.057)
const EAGLE_FLAP_HEAD_Y := [0.56, 0.50, 0.37, 0.43, 0.56]
const EAGLE_DIVE_HEAD_Y := [0.45, 0.43, 0.14, 0.07, 0.45]

static func from_save(value: Variant) -> Dictionary:
	var health := MAX_HEALTH.duplicate()
	if value is Dictionary:
		for species: String in MAX_HEALTH:
			var saved: Variant = value.get(species)
			if Survival.finite_number(saved):
				health[species] = clampf(float(saved), 0.0, MAX_HEALTH[species])
	return health

static func alive(room: Dictionary, species: String) -> bool:
	var data: Dictionary = room.get("data", {})
	var health: Dictionary = data.get("storageWildlife", {})
	return float(health.get(species, MAX_HEALTH.get(species, 0.0))) > 0.0

static func hit(room: Dictionary, from: Vector3, to: Vector3, radius: float,
		damage: float, grid: Dictionary) -> bool:
	return not apply_hit(room, room_hit(room, from, to, radius), damage, grid).is_empty()

static func room_hit(room: Dictionary, from: Vector3, to: Vector3, radius := 0.0, firearm := false) -> Dictionary:
	var poses := {}
	for species: String in MAX_HEALTH:
		poses[species] = _live_pose(room, species)
	return ray_hit(poses, from, to, radius, firearm, room.data.elapsed)

static func sighting_position(room: Dictionary, species: String) -> Vector3:
	var pose := _live_pose(room, species)
	if pose.is_empty():
		return Vector3.INF
	var target := _target(species, pose)
	if target.is_empty():
		return Vector3.INF
	return (target.start as Vector3).lerp(target.end, 0.5)

static func _live_pose(room: Dictionary, species: String) -> Dictionary:
	if not alive(room, species):
		return {}
	match species:
		"croc":
			var croc: Dictionary = room.get("crocodile", {})
			return Wildlife.crocodile_pose(croc) if not croc.is_empty() else {}
		"eagle":
			return Wildlife.eagle(room.data.elapsed)
		"dog":
			return room.data.get("dog", {})
		"boar":
			return room.data.get("boar",{})
		"sheep":
			return Sheep.pose(room.data.elapsed, room.data.get("shearedAt", -1.0))
	return {}

static func ray_hit(poses: Dictionary, from: Vector3, to: Vector3, radius := 0.0,
		firearm := false, elapsed := 0.0) -> Dictionary:
	if not from.is_finite() or not to.is_finite() or not is_finite(radius) or radius < 0.0:
		return {}
	var best := {}
	var closest := INF
	for species: String in MAX_HEALTH:
		var pose: Dictionary = poses.get(species, {})
		if pose.is_empty():
			continue
		var candidate := _target(species, pose)
		if candidate.is_empty():
			continue
		var nearest := Geometry3D.get_closest_points_between_segments(from, to, candidate.start, candidate.end)
		var range_limit: float = float(candidate.radius) + radius
		var body := from.distance_squared_to(nearest[0]) if nearest[0].distance_squared_to(nearest[1]) <= range_limit * range_limit else INF
		var head := INF
		if firearm:
			head = Weapons.box_hit_distance(from, to, candidate.origin, Basis(Vector3.UP, float(pose.yaw)),
				_head_bounds(species, pose, elapsed))
		var distance := minf(body, head)
		if distance < closest:
			closest = distance
			best = candidate
			best.species = species
			best.distance = distance
			best.headshot = head < body
	return best

static func apply_hit(room: Dictionary, target: Dictionary, damage: float, grid: Dictionary) -> String:
	if target.is_empty() or not is_finite(damage) or damage <= 0.0:
		return ""
	var species: String = target.species
	if not alive(room, species):
		return ""

	if not room.data.has("storageWildlife"):
		room.data.storageWildlife = from_save(null)
	var health: Dictionary = room.data.storageWildlife
	var headshot: bool = target.get("headshot", false)
	health[species] = 0.0 if headshot else maxf(0.0, float(health.get(species, MAX_HEALTH[species])) - damage)
	if health[species] <= 0.0:
		_leave_corpse(room, species, target, grid)
		return ("头部命中，击杀" if headshot else "击杀") + NAMES[species]
	if species=="boar" and room.data.has("boar"):
		room.data.boar.disturbed=true
	if species == "croc":
		Wildlife.recoil(room.crocodile, room.data.elapsed)
	return "击中" + NAMES[species]

static func _target(species: String, pose: Dictionary) -> Dictionary:
	match species:
		"boar":
			var origin:=Boar.world_at(pose)
			var height:=.32 if pose.clip in ["Rest","LieDown"] else .58
			var center:=origin+Vector3.UP*height
			var axis:=Basis(Vector3.UP,float(pose.yaw)).x
			return {"start":center-axis*.57,"end":center+axis*.53,"radius":.30,"origin":origin,"point":Boar.position(pose),"yaw":pose.yaw}
		"sheep":
			var origin: Vector3 = pose.at
			var center := origin + Vector3.UP * 0.65
			var axis := Basis(Vector3.UP, float(pose.yaw)).x
			return {"start":center - axis * 0.47, "end":center + axis * 0.47, "radius":0.30,
				"origin":origin, "point":Vector2(origin.x,origin.z), "yaw":pose.yaw}
		"croc":
			if pose.get("dead", false) or pose.get("underwater", false) or pose.clip in ["Dive", "Surface"]:
				return {}
			var origin := Stones.unpack(pose.at)
			var center := origin + Vector3.UP * 0.22
			var axis := Basis(Vector3.UP, float(pose.yaw)).z
			return {"start": center + axis * 0.65, "end": center - axis * 0.78,
				"radius": 0.31, "origin": origin, "point": Vector2(center.x, center.z), "yaw": pose.yaw}
		"eagle":
			var basis := Basis(Vector3.UP, float(pose.yaw))
			var origin: Vector3 = pose.at - (basis * EAGLE_PERCH_OFFSET) * float(pose.contact)
			var center := origin + Vector3.UP * 0.24
			var folded: bool = float(pose.contact) >= 0.55 or pose.clip == "GroundIdle"
			var span := 0.18 if float(pose.contact) > 0.0 or pose.clip == "GroundIdle" else 0.66
			return {"start": center - basis.x * span, "end": center + basis.x * span,
				"radius": 0.19, "origin": origin, "point": Vector2(center.x, center.z), "yaw": pose.yaw,
				"fallOrigin": origin, "folded": folded}
		"dog":
			var point := Dog.position(pose)
			var feet: float = pose.get("y", Lake.walk_height(point))
			var height := 0.30 if pose.clip in [Dog.DOWN, Dog.REST] else 0.51
			var origin := Vector3(point.x, feet, point.y)
			var center := origin + Vector3.UP * height
			var axis := Basis(Vector3.UP, float(pose.yaw)).z
			return {"start": center + axis * 0.24, "end": center - axis * 0.32,
				"radius": 0.25, "origin": origin, "point": point, "yaw": pose.yaw}
	return {}

static func _head_bounds(species: String, pose: Dictionary, elapsed: float) -> AABB:
	# Fitted to the head and jaw vertices of each imported model in its live clips.
	var age := maxf(0.0, elapsed - float(pose.get("clipAt", elapsed)))
	match species:
		"boar":
			var height:=.57
			match pose.clip:
				"Forage": height=.32
				"LieDown": height=lerpf(.57,.27,smoothstep(0,1.3,age))
				"Rest": height=.27
				"Rise": height=lerpf(.27,.57,smoothstep(0,1.1,age))
				"Warn","Charge": height=.48
			return AABB(Vector3(-1.09,height-.15,-.145),Vector3(.41,.31,.29))
		"sheep":
			var height := 0.56 if pose.clip == "Graze" else 0.93
			return AABB(Vector3(-0.94,height-0.14,-0.13),Vector3(0.34,0.29,0.26))
		"croc":
			var bounds := AABB(Vector3(-0.23, 0.09, -1.25), Vector3(0.44, 0.36, 0.67))
			if pose.clip == "Attack":
				var lunge := maxf(0.0, 1.0 - absf(age - 0.53) / 0.20)
				bounds.position += Vector3(0.0, 0.33, -0.21) * lunge
				bounds.size.y += 0.22 * lunge
			elif pose.clip == "Hit":
				bounds.position.z += sin(PI * clampf(age / Wildlife.CROC_HIT_TIME, 0.0, 1.0)) * 0.13
			return bounds
		"dog":
			var height := 0.76
			match pose.clip:
				Dog.WALK: height = 0.71
				Dog.RUN: height = 0.69
				Dog.REST: height = 0.43
				Dog.DOWN: height = lerpf(0.76, 0.43, smoothstep(0.0, 0.70, age))
				Dog.RISE: height = lerpf(0.43, 0.76, smoothstep(0.0, Dog.RISE_SECONDS, age))
			return AABB(Vector3(-0.17, height - 0.15, -0.52), Vector3(0.38, 0.31, 0.24))
		"eagle":
			var center := Vector3(0.0, 0.46, -0.35)
			match pose.clip:
				"PerchIdle": center = Vector3(0.0, 0.62, -0.22)
				"GroundIdle": center = Vector3(0.0, 0.60, -0.25)
				"Flap": center.y = _sample_head_height(EAGLE_FLAP_HEAD_Y, fposmod(age, 25.0 / 30.0) / (25.0 / 30.0))
				"Dive": center.y = _sample_head_height(EAGLE_DIVE_HEAD_Y, clampf(age / 1.2, 0.0, 1.0))
				"LandGround", "LandPerch":
					center = Vector3(0.0, 0.59, lerpf(-0.35, -0.23, smoothstep(0.65, 1.4, age)))
				"Takeoff": center = Vector3(0.0, 0.56, -0.31)
			var half := Vector3(0.12, 0.075, 0.13)
			return AABB(center - half, 2.0 * half)
	return AABB()

static func _sample_head_height(samples: Array, phase: float) -> float:
	var offset := phase * (samples.size() - 1)
	var index := mini(floori(offset), samples.size() - 2)
	return lerpf(samples[index], samples[index + 1], offset - index)

static func _leave_corpse(room: Dictionary, species: String, target: Dictionary, grid: Dictionary) -> void:
	var records: Dictionary = room.data.storage
	var id := "corpse-" + species
	if records.has(id):
		return
	var point: Vector2 = target.point
	var at := _loot_point(point, grid)
	var record := {"kind": "corpse_" + species, "mode": "ground",
		"at": Stones.pack(Vector3(at.x, Lake.walk_height(at), at.y)), "yaw": target.yaw,
		"bag": DROPS[species].duplicate(), "text": "", "owner": "", "fuelUntil": 0.0,
		"deadAt": room.data.elapsed}
	if species == "sheep":
		record.shorn = Sheep.shorn(room.data.elapsed, room.data.get("shearedAt", -1.0))
		record.landAt = float(record.deadAt) + Storage.SHEEP_COLLAPSE_SECONDS
		if not record.shorn:
			record.bag.wool = 1
	elif species=="boar":
		record.landAt=float(record.deadAt)+Boar.COLLAPSE_TIME
	elif species == "eagle":
		var start: Vector3 = target.fallOrigin
		var surface := Lake.surface_height(point)
		var altitude := start.y - maxf(Lake.walk_height(point), surface)
		var time: float = room.data.elapsed
		if altitude > 0.13:
			var fall := clampf(sqrt(2.0 * altitude / -Stones.GRAVITY.y), 0.30, Storage.EAGLE_FALL_MAX_SECONDS)
			record.fallFrom = Stones.pack(start)
			record.foldedFall = target.folded
			record.impactAt = time + fall
			# A lake death falls where it happened, then drifts to the usable bank.
			var drift := minf(point.distance_to(at) / 2.6, Storage.EAGLE_DRIFT_MAX_SECONDS) if is_finite(surface) and Lake.walk_height(point) <= surface else 0.0
			record.landAt = record.impactAt + drift
		else:
			record.landAt = time + Storage.EAGLE_COLLAPSE_SECONDS
	elif species == "croc" and _can_loot_at(point, grid):
		record.landAt = float(record.deadAt) + Storage.CROC_COLLAPSE_SECONDS
	records[id] = record

static func _loot_point(point: Vector2, grid: Dictionary) -> Vector2:
	var origin := point.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER)
	if _can_loot_at(origin, grid):
		return origin
	# Swimmers cannot use a container. Leave water deaths on the closest usable shore.
	if Lake.lake_distance(origin) < 1.0:
		var angle := ((origin - Lake.center()) / Lake.radius()).angle()
		for extent: float in [1.025, 1.055, 1.10]:
			for offset: float in [0.0, 0.12, -0.12, 0.27, -0.27, 0.5, -0.5]:
				var shore := Lake.shore_at(angle + offset, extent)
				if _can_loot_at(shore, grid):
					return shore
	for distance: float in [0.35, 0.75, 1.35, 2.6]:
		for step in 8:
			var nearby := origin + Vector2.from_angle(TAU * float(step) / 8.0) * distance
			if _can_loot_at(nearby, grid):
				return nearby
	return origin

static func _can_loot_at(point: Vector2, grid: Dictionary) -> bool:
	return point == point.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER) and (
		Rules.free_at(point, grid) and Lake.walk_height(point) > Lake.surface_height(point))
