extends RefCounted

const Dog = preload("res://camp_dog.gd")
const Storage = preload("res://camp_storage.gd")
const Lake = preload("res://lake_layout.gd")
const Rules = preload("res://rules.gd")
const Stones = preload("res://stones.gd")
const Survival = preload("res://survival.gd")
const Wildlife = preload("res://wildlife.gd")

const MAX_HEALTH := {"croc": 100.0, "eagle": 42.0, "dog": 64.0}
const DROPS := {
	"croc": {"crocodile_meat_raw": 3, "crocodile_hide": 1},
	"eagle": {"eagle_meat": 1, "eagle_feather": 1, "eagle_claw": 1},
	"dog": {"dog_meat": 2},
}
# Same imported contact offset that WildlifeScene applies when the eagle perches.
const EAGLE_PERCH_OFFSET := Vector3(0.0, 0.008, 0.057)

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
	if not from.is_finite() or not to.is_finite() or not is_finite(radius) or not is_finite(damage) or radius < 0.0 or damage <= 0.0:
		return false
	var elapsed: float = room.data.elapsed
	var closest := INF
	var contact := Vector3.ZERO
	var victim := ""
	var target := {}
	for species: String in MAX_HEALTH:
		if not alive(room, species):
			continue
		var candidate := _target(room, species, elapsed)
		if candidate.is_empty():
			continue
		var nearest := Geometry3D.get_closest_points_between_segments(from, to, candidate.start, candidate.end)
		var range_limit: float = float(candidate.radius) + radius
		var distance := from.distance_squared_to(nearest[0])
		if distance < closest and nearest[0].distance_squared_to(nearest[1]) <= range_limit * range_limit:
			closest = distance
			contact = nearest[1]
			victim = species
			target = candidate
	if victim.is_empty():
		return false

	if not room.data.has("storageWildlife"):
		room.data.storageWildlife = from_save(null)
	var health: Dictionary = room.data.storageWildlife
	health[victim] = maxf(0.0, float(health.get(victim, MAX_HEALTH[victim])) - damage)
	if health[victim] <= 0.0:
		_leave_corpse(room, victim, target, grid)
	elif victim == "croc":
		Wildlife.stone_hit(room.crocodile, contact, contact, elapsed)
	return true

static func _target(room: Dictionary, species: String, elapsed: float) -> Dictionary:
	match species:
		"croc":
			var croc: Dictionary = room.get("crocodile", {})
			if croc.is_empty() or croc.underwater or croc.clip in ["Dive", "Surface"]:
				return {}
			var pose := Wildlife.crocodile_pose(croc)
			var center := Stones.unpack(pose.at) + Vector3.UP * 0.22
			var axis := Basis(Vector3.UP, float(croc.yaw)).z
			return {"start": center + axis * 0.65, "end": center - axis * 0.78,
				"radius": 0.31, "point": croc.point, "yaw": croc.yaw}
		"eagle":
			var bird := Wildlife.eagle(elapsed)
			var basis := Basis(Vector3.UP, float(bird.yaw))
			var origin: Vector3 = bird.at - (basis * EAGLE_PERCH_OFFSET) * float(bird.contact)
			var center := origin + Vector3.UP * 0.24
			var folded: bool = float(bird.contact) >= 0.55 or bird.clip == "GroundIdle"
			var span := 0.18 if float(bird.contact) > 0.0 or bird.clip == "GroundIdle" else 0.66
			return {"start": center - basis.x * span, "end": center + basis.x * span,
				"radius": 0.19, "point": Vector2(center.x, center.z), "yaw": bird.yaw,
				"fallOrigin": origin, "folded": folded}
		"dog":
			var dog: Dictionary = room.data.get("dog", {})
			if dog.is_empty():
				return {}
			var point := Dog.position(dog)
			var height := 0.30 if dog.clip in [Dog.DOWN, Dog.REST] else 0.51
			var center := Vector3(point.x, Lake.walk_height(point) + height, point.y)
			var axis := Basis(Vector3.UP, float(dog.yaw)).z
			return {"start": center + axis * 0.24, "end": center - axis * 0.32,
				"radius": 0.25, "point": point, "yaw": dog.yaw}
	return {}

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
	if species == "eagle":
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
