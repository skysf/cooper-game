extends RefCounted

const Lake = preload("res://lake_layout.gd")
const Rules = preload("res://rules.gd")

const PERCH := Vector3(-9.03, 3.44, -48.622)
const PERCH_TRUNK := Vector3(-7.493, 3.28, -48.622)
const EAGLE_GROUND := Vector3(-9.33, 0.0, -47.16)
const EAGLE_PERIOD := 66.0
# Each row gives the time, position, velocity, outgoing clip, and branch-contact weight.
const EAGLE_ROUTE := [
	[0.0, PERCH, Vector3.ZERO, "PerchIdle", 1.0],
	[9.0, PERCH, Vector3.ZERO, "Takeoff", 1.0],
	[10.2, Vector3(-9.68, 4.82, -50.28), Vector3(-1.62, 2.2, -2.1), "Flap", 0.0],
	[15.2, Vector3(-17.2, 16.4, -57.7), Vector3(-3.0, 1.0, 0.0), "BankRight", 0.0],
	[19.4, Vector3(-29.1, 18.0, -60.3), Vector3(-2.6, 0.1, -1.3), "BankLeft", 0.0],
	[22.2, Vector3(-35.5, 18.1, -58.6), Vector3(-0.5, 0.15, 2.6), "Glide", 0.0],
	[26.0, Vector3(-32.3, 17.4, -46.0), Vector3(2.5, -0.4, 2.4), "BankLeft", 0.0],
	[29.2, Vector3(-19.0, 15.8, -40.7), Vector3(3.0, -0.9, -1.4), "Flap", 0.0],
	[31.0, Vector3(-14.5, 13.0, -42.8), Vector3(2.5, -2.3, -1.45), "Dive", 0.0],
	[32.2, Vector3(-11.8, 8.8, -44.8), Vector3(1.7, -3.0, -1.6), "Glide", 0.0],
	[35.0, Vector3(-9.33, 1.15, -46.14), Vector3(0.0, -1.29, -1.0), "LandGround", 0.0],
	[36.43334, EAGLE_GROUND, Vector3.ZERO, "GroundIdle", 0.0],
	[44.0, EAGLE_GROUND, Vector3.ZERO, "Takeoff", 0.0],
	[45.2, Vector3(-9.4, 1.35, -48.72), Vector3(-0.4, 2.0, -2.7), "Flap", 0.0],
	[51.0, Vector3(-21.9, 12.7, -54.9), Vector3(-2.0, 0.25, 1.35), "BankLeft", 0.0],
	[55.8, Vector3(-20.6, 11.4, -44.2), Vector3(2.1, -1.0, 1.7), "Glide", 0.0],
	[60.0, Vector3(-11.6, 6.2, -43.7), Vector3(2.0, -1.3, -1.25), "BankLeft", 0.0],
	[64.56666, Vector3(-9.03, 3.78, -46.99), Vector3(0.0, -0.42, -1.5), "LandPerch", 1.0],
	[EAGLE_PERIOD, PERCH, Vector3.ZERO, "PerchIdle", 1.0],
]

const BASK := Vector2(-12.7, -59.05)
const CROC_ROUTE := [
	BASK, Vector2(-13.25, -58.40), Vector2(-14.15, -57.80),
	Vector2(-18.5, -56.40), Vector2(-21.1, -53.00), Vector2(-18.2, -52.40),
	Vector2(-15.2, -55.30), Vector2(-14.15, -57.80), Vector2(-13.25, -58.40),
]
const WATER_OFFSET := 0.265
const DIVE_DEPTH := 0.47
const CROC_DIVE_TIME := 38.0 / 30.0
const CROC_HIT_TIME := 23.0 / 30.0
const CROC_ATTACK_TIME := 32.0 / 30.0
const BITE_TIME := 0.56
const BITE_REACH := 1.82
const BITE_DAMAGE := 18.0

static func eagle(elapsed: float) -> Dictionary:
	var time := fposmod(elapsed, EAGLE_PERIOD)
	var index := 0
	while index + 2 < EAGLE_ROUTE.size() and time >= float(EAGLE_ROUTE[index + 1][0]):
		index += 1
	var from: Array = EAGLE_ROUTE[index]
	var to: Array = EAGLE_ROUTE[index + 1]
	var duration: float = to[0] - from[0]
	var t := clampf((time - float(from[0])) / duration, 0.0, 1.0)
	var p: Vector3 = from[1]
	var q: Vector3 = to[1]
	var v: Vector3 = from[2] * duration
	var w: Vector3 = to[2] * duration
	var offset := q - p
	var at := p + t * (v + t * ((3.0 - 2.0 * t) * offset + (t - 2.0) * v + (t - 1.0) * w))
	var tangent := v + t * ((6.0 - 6.0 * t) * offset + (3.0 * t - 4.0) * v + (3.0 * t - 2.0) * w)
	var heading := Vector2(tangent.x, tangent.z)
	return {
		"at": at, "yaw": _yaw(heading) if heading.length_squared() > 0.00001 else 0.0,
		"clip": from[3], "clipAt": elapsed - (time - float(from[0])),
		"contact": lerpf(from[4], to[4], smoothstep(0.0, 1.0, t)),
	}

static func crocodile(elapsed: float) -> Dictionary:
	return {
		"point": BASK, "yaw": _yaw(BASK.direction_to(CROC_ROUTE[1])), "clip": "Idle", "clipAt": elapsed,
		"leg": 1, "holdUntil": elapsed + 5.5, "underwater": false,
		"cooldown": elapsed, "target": "", "bitten": false,
	}

static func crocodile_pose(croc: Dictionary) -> Dictionary:
	var point: Vector2 = croc.point
	return {"at": [point.x, _height(croc), point.y], "yaw": croc.yaw, "clip": croc.clip,
		"clipAt": croc.clipAt, "underwater": croc.underwater}

static func tick_crocodile(croc: Dictionary, actors: Dictionary, grid: Dictionary, elapsed: float, delta: float) -> Dictionary:
	if elapsed < float(croc.holdUntil) and croc.clip in ["Attack", "Dive", "Surface", "Hit"]:
		if croc.clip == "Attack" and not croc.bitten and elapsed >= float(croc.clipAt) + BITE_TIME:
			croc.bitten = true
			var target: Dictionary = actors.get(croc.target, {})
			if not target.is_empty() and _can_bite(croc, target.point, grid):
				return {"bit": croc.target}
		return {}

	match croc.clip:
		"Dive": croc.underwater = true
		"Surface": croc.underwater = false

	var point: Vector2 = croc.point
	if elapsed >= float(croc.cooldown) and _walks(point):
		var id := _approaching_actor(point, actors, grid)
		if not id.is_empty():
			var direction := point.direction_to(actors[id].point)
			croc.yaw = _yaw(direction)
			croc.target = id
			croc.bitten = false
			croc.cooldown = elapsed + 6.5
			_play(croc, "Attack", elapsed, CROC_ATTACK_TIME)
			return {"warn": id}
	if elapsed < float(croc.holdUntil):
		return {}

	var goal: Vector2 = CROC_ROUTE[croc.leg]
	if point.distance_squared_to(goal) < 0.07 * 0.07:
		var reached: int = croc.leg
		croc.leg = (reached + 1) % CROC_ROUTE.size()
		match reached:
			0: _play(croc, "Idle", elapsed, 7.0)
			3: _play(croc, "Dive", elapsed, CROC_DIVE_TIME)
			5: _play(croc, "Surface", elapsed, CROC_DIVE_TIME)
		if elapsed < float(croc.holdUntil):
			return {}
		goal = CROC_ROUTE[croc.leg]
	var heading := _yaw(point.direction_to(goal))
	croc.yaw = rotate_toward(float(croc.yaw), heading, delta * 1.7)
	var pace := 0.267 if _walks(point) else 1.05
	var alignment := lerpf(0.18, 1.0, smoothstep(-0.25, 1.0, cos(heading - float(croc.yaw))))
	var next := point.move_toward(goal, delta * pace * alignment)
	croc.point = next
	_play(croc, "Walk" if _walks(next) else "Swim", elapsed)
	return {}

static func recoil(croc: Dictionary, elapsed: float) -> void:
	if croc.clip == "Hit":
		return
	var point: Vector2 = croc.point
	croc.cooldown = elapsed + 13.0
	croc.target = ""
	if _walks(point):
		croc.leg = 2
	_play(croc, "Hit", elapsed, CROC_HIT_TIME)

static func _yaw(direction: Vector2) -> float:
	return atan2(-direction.x, -direction.y)

static func _walks(point: Vector2) -> bool:
	return Lake.lake_distance(point) > 0.97

static func _height(croc: Dictionary) -> float:
	var point: Vector2 = croc.point
	var base := maxf(Lake.ground_height(point), Lake.water_y() - WATER_OFFSET)
	# The dive and surface clips already animate the vertical displacement on their bones.
	return base - (DIVE_DEPTH if croc.underwater and croc.clip != "Surface" else 0.0)

static func _play(croc: Dictionary, clip: String, elapsed: float, hold := 0.0) -> void:
	if croc.clip != clip:
		croc.clip = clip
		croc.clipAt = elapsed
	croc.holdUntil = elapsed + hold

static func _approaching_actor(point: Vector2, actors: Dictionary, grid: Dictionary) -> String:
	var nearest := ""
	var closest := 2.38 * 2.38
	for id: String in actors:
		var target: Vector2 = actors[id].point
		var distance := point.distance_squared_to(target)
		if distance < closest and _reachable(point, target, grid):
			nearest = id
			closest = distance
	return nearest

static func _can_bite(croc: Dictionary, target: Vector2, grid: Dictionary) -> bool:
	var point: Vector2 = croc.point
	var facing := Vector2(0.0, -1.0).rotated(-float(croc.yaw))
	return point.distance_squared_to(target) <= BITE_REACH * BITE_REACH and (
		point.is_equal_approx(target) or facing.dot(point.direction_to(target)) >= 0.68
	) and _reachable(point, target, grid)

static func _reachable(from: Vector2, to: Vector2, grid: Dictionary) -> bool:
	if absf(Lake.walk_height(to) - Lake.ground_height(from)) > 0.48:
		return false
	for part in [0.25, 0.50, 0.75, 1.0]:
		if not Rules.obstacle_free_at(from.lerp(to, part), grid):
			return false
	return true
