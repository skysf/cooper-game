extends RefCounted

const Lake = preload("res://lake_layout.gd")
const REGROW_SECONDS := 840.0
const REACH := 2.25
const REST := 11.0
const WALK := 4.8
# This little meadow lies between the dock path and the trees on the east bank.
const MEADOW := [Vector2(-9.72,-46.91), Vector2(-8.00,-46.15), Vector2(-8.60,-47.25)]

static func shorn(elapsed: float, sheared: float) -> bool:
	return sheared >= 0.0 and elapsed - sheared < REGROW_SECONDS

static func pose(elapsed: float, sheared: float) -> Dictionary:
	var leg := REST + WALK
	var age := elapsed - sheared if sheared >= 0.0 else INF
	# The ewe holds still and looks up when clipped, then rejoins the same grazing route.
	var clock := elapsed
	if age >= 0.0 and age < 5.5:
		clock -= minf(age,1.65) * (1.0 - smoothstep(1.65,5.5,age))
	var index := floori(fposmod(clock, leg * MEADOW.size()) / leg)
	var time := fposmod(clock, leg)
	var start: Vector2 = MEADOW[index]
	var end: Vector2 = MEADOW[(index + 1) % MEADOW.size()]
	var previous: Vector2 = MEADOW[posmod(index - 1, MEADOW.size())]
	var direction := start.direction_to(end)
	var yaw := atan2(direction.y, -direction.x)
	var point := start
	var clip := "Graze"
	var phase := fposmod(elapsed, 3.6)
	if time >= REST:
		point = start.lerp(end, (time - REST) / WALK)
		clip = "Walk"
		phase = fposmod(time - REST, 1.2)
	else:
		var old := previous.direction_to(start)
		yaw = lerp_angle(atan2(old.y,-old.x), yaw, smoothstep(0.0, 2.4, time))
		if time < 2.4:
			clip = "Alert"
			phase = fposmod(elapsed, 2.5)
	if age >= 0.0 and age < 1.65:
		clip = "Alert"
		phase = age
	return {"at":Vector3(point.x, Lake.walk_height(point), point.y), "yaw":yaw, "clip":clip, "phase":phase}

static func reachable(point: Vector2, feet: float, elapsed: float, sheared: float) -> bool:
	var at: Vector3 = pose(elapsed, sheared).at
	return absf(feet - at.y) < 1.30 and point.distance_squared_to(Vector2(at.x,at.z)) < REACH * REACH
