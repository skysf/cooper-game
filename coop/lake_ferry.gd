extends RefCounted

# The hull's bow faces local -X. The deck is 0.446 m above its modelling origin.
const MOOR := Vector2(-14.20, -47.45)
const PIER := Vector2(-12.65, -49.10)
const ENTRY := Vector2(-1.56, 0.42)
const BOARDING_SPOTS := [ENTRY, Vector2(-2.24,0.015), Vector2(1.68,-0.44), Vector2(1.68,0.44)]
const WATERLINE := 0.256
const DECK := 0.446
const CAST_OFF := 1.2
const STROKE := 2.6
const ROW_TIME := STROKE * 17.0
const LAND := 1.6
const CIRCUIT := CAST_OFF + ROW_TIME + LAND

static func moored(elapsed: float, departed: float) -> bool:
	return departed < 0.0 or elapsed < departed or elapsed - departed >= CIRCUIT

static func pose(elapsed: float, departed: float) -> Dictionary:
	var age := elapsed - departed
	var clip := "Moored"
	var phase := fposmod(elapsed, 3.6)
	var heading := -PI * 0.5
	var point := MOOR
	if not moored(elapsed, departed):
		if age < CAST_OFF:
			clip = "CastOff"
			phase = age
		elif age < CAST_OFF + ROW_TIME:
			clip = "Row"
			var rowing := age - CAST_OFF
			phase = fposmod(rowing, STROKE)
			# Ease the first and last strokes. Distance and heading meet at the same berth.
			var t := rowing / ROW_TIME
			var rim := 1.0 / 17.0
			var progress := t - rim * 0.5
			if t < rim:
				progress = 0.5 * t * t / rim
			elif t > 1.0 - rim:
				progress = 1.0 - rim - 0.5 * (1.0 - t) * (1.0 - t) / rim
			var angle := TAU * progress / (1.0 - rim)
			point += Vector2(9.65 * (cos(angle) - 1.0), -8.15 * sin(angle))
			heading = atan2(-8.15 * cos(angle), 9.65 * sin(angle))
		else:
			clip = "Land"
			phase = age - CAST_OFF - ROW_TIME
	return {"point":point, "yaw":heading, "clip":clip, "phase":phase}

static func world_point(local: Vector2, ferry: Dictionary) -> Vector2:
	return (ferry.point as Vector2) + local.rotated(-float(ferry.yaw))

static func local_point(point: Vector2, ferry: Dictionary) -> Vector2:
	return (point - (ferry.point as Vector2)).rotated(float(ferry.yaw))

static func on_deck(local: Vector2) -> bool:
	var lengthwise := absf(local.x)
	var width := 0.87 - 0.57 * smoothstep(1.24, 2.50, lengthwise)
	return lengthwise <= 2.50 and absf(local.y) <= width

static func boarding_spot(actors: Dictionary) -> Vector2:
	for spot: Vector2 in BOARDING_SPOTS:
		var free := true
		for actor: Dictionary in actors.values():
			if actor.get("onFerry",false) and spot.distance_squared_to(actor.ferryLocal) < 0.48 * 0.48:
				free = false
				break
		if free:
			return spot
	return ENTRY

static func under_canopy(local: Vector2) -> bool:
	return local.x > -1.37 and local.x < 1.51 and absf(local.y) < 1.06

static func obstructed(local: Vector2, crouching := true) -> bool:
	if not crouching and under_canopy(local):
		return true
	# Leave a foot's clearance around the clothes chest and the stern water barrel.
	if local.x > -1.77 and local.x < -1.12 and local.y > -.64 and local.y < .043:
		return true
	if local.distance_squared_to(Vector2(2.18,-.26)) < .285*.285:
		return true
	if local.distance_squared_to(Vector2(-1.88,0.0)) < 0.28*0.28 or local.distance_squared_to(Vector2(1.68,0.0)) < 0.28*0.28:
		return true
	return outside_aisle(local)

static func outside_aisle(local: Vector2) -> bool:
	# At both ends the hanging sides of the canvas start before the mattresses.
	return under_canopy(local) and absf(local.y) > 0.17

static func at_pier(point: Vector2, feet: float) -> bool:
	return point.distance_squared_to(PIER) < 2.15 * 2.15 and absf(feet - 0.12) < 0.65

static func place(actor: Dictionary, local: Vector2, ferry: Dictionary, water: float) -> void:
	actor.ferryLocal = local
	actor.point = world_point(local, ferry)
	actor.y = water - WATERLINE + DECK
	actor.vy = 0.0
	actor.swimming = false
	actor.grounded = true
	actor.onFerry = true
	actor.crouched = under_canopy(local)
