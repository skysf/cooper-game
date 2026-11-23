extends RefCounted

const Rules = preload("res://rules.gd")
const Lake = preload("res://lake_layout.gd")
const Ground = preload("res://spaceship_ground.gd")

const PAD := Vector2(1.5, -79.4)
const HULL_RADIUS := 2.55
const MIN_CORNER := Rules.MIN_CORNER + Vector2.ONE * HULL_RADIUS
const MAX_CORNER := Rules.MAX_CORNER - Vector2.ONE * HULL_RADIUS
const BOARD_RANGE := 3.65
const MAX_ALTITUDE := 100_000.0 # Metres above the game's sea level.
const TURN_SPEED := 4.4
const SURFACE_NAMES := ["land", "water", "rock", "tree", "structure"]

static func point(ship: Dictionary) -> Vector2:
	return Vector2(ship.x, ship.z)

static func position(ship: Dictionary) -> Vector3:
	return Vector3(ship.x, ship.y, ship.z)

static func velocity_sample(ship: Dictionary) -> Vector3:
	var value: Array = ship.get("v", [0.0, 0.0, 0.0])
	return Vector3(value[0], value[1], value[2])

static func vertical_scale(clearance: float) -> float:
	# Keep precision around terrain and landmarks. Cruise becomes faster as the hull clears them.
	return 1.0 + clampf((clearance - 32.0) / 22.0, 0.0, 749.0)

static func exit_point(ship: Dictionary) -> Vector2:
	return point(ship) + Vector2(1.60, 0.0).rotated(-float(ship.yaw))

static func dismount(ship: Dictionary, walk_grid: Dictionary, flight_grid: Dictionary,
		grove_time: float) -> Vector3:
	var origin := point(ship)
	var max_feet := float(ship.y) + 0.65
	var best := Vector3.INF
	var closest_height := INF
	for local: Vector2 in [Vector2(1.60, 0.0), Vector2(-1.60, 0.0), Vector2(1.53, 0.93),
			Vector2(-1.53, 0.93), Vector2(0.0, -2.65), Vector2(0.0, 2.72)]:
		var at := origin + local.rotated(-float(ship.yaw))
		if at != at.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER):
			continue
		var y := Ground.walk_height(at, max_feet, flight_grid, grove_time)
		var ground := Lake.walk_height(at)
		if y <= ground + 0.23 and not Rules.free_at(at, walk_grid, true):
			continue
		var water := Lake.surface_height(at)
		y = maxf(y, water - 0.12)
		var height_difference := absf(y - float(ship.y))
		if y <= max_feet and height_difference < minf(1.45, closest_height):
			best = Vector3(at.x, y, at.y)
			closest_height = height_difference
	return best

static func parked_save(ship: Dictionary) -> Dictionary:
	return {"x": ship.x, "y": ship.y, "z": ship.z, "yaw": ship.yaw}

static func from_save(saved: Variant, grid: Dictionary, grove_time: float = 0.0) -> Dictionary:
	var at := PAD
	var heading := PI
	var support := Ground.contact(at, heading, grid, grove_time)
	if saved is Dictionary and saved.has_all(["x", "z", "yaw"]):
		if float_value(saved.x) and float_value(saved.z) and float_value(saved.yaw):
			var stored := point(saved)
			var stored_heading := wrapf(float(saved.yaw), -PI, PI)
			if stored == stored.clamp(MIN_CORNER, MAX_CORNER):
				var candidate := Ground.contact(stored, stored_heading, grid, grove_time)
				if candidate.stable:
					at = stored
					heading = stored_heading
					support = candidate
	var ship := {"x": at.x, "y": support.y, "z": at.y, "yaw": heading,
		"pilot": "", "landed": true, "onWater": false, "slipping": false,
		"thrust": 0.0, "rearThrust": 0.0}
	_apply_support(ship, support, true)
	return ship

static func float_value(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func collision_grid(world: Dictionary) -> Dictionary:
	return Ground.collision_grid(world)

static func can_park(at: Vector2, grid: Dictionary) -> bool:
	return Ground.contact(at, PI, grid, 0.0).stable

static func _apply_support(ship: Dictionary, support: Dictionary, touching: bool) -> void:
	ship.canLand = support.stable
	ship.onWater = ship.landed and support.kind == Ground.WATER
	ship.surface = SURFACE_NAMES[int(support.kind)]
	ship.floor = support.y
	ship.tiltX = float(support.pitch) if touching else 0.0
	ship.tiltZ = float(support.roll) if touching else 0.0

static func step(ship: Dictionary, velocity: Vector3, move: Vector2, lift: float,
		yaw: float, delta: float, grid: Dictionary, grove_time: float = 0.0) -> Vector3:
	var dt := clampf(delta, 0.0, 0.06)
	if dt <= 0.0:
		return velocity
	var at := point(ship)
	var heading := float(ship.yaw)
	var altitude := float(ship.y)
	var slipping: bool = ship.get("slipping", false) and lift <= 0.0
	if ship.landed and lift <= 0.0 and ship.surface != "tree":
		return Vector3.ZERO
	var support := Ground.contact(at, heading, grid, grove_time)
	if ship.landed and lift <= 0.0:
		if support.stable:
			ship.y = support.y
			_set_thrust(ship, 0.0, 0.0)
			_apply_support(ship, support, true)
			return Vector3.ZERO
		slipping = true
	else:
		heading = rotate_toward(heading, yaw, dt * TURN_SPEED)

	var incoming := Vector2(velocity.x, velocity.z)
	var horizontal := incoming
	if slipping and not support.stable:
		var slide: Vector2 = support.slide
		horizontal = horizontal.move_toward(slide * 3.1 + move * 0.85, dt * 4.6)
	else:
		var speed := 2.0 if slipping else 11.0
		horizontal = horizontal.move_toward(move * speed, dt * (16.0 if move.is_zero_approx() else 8.5))
	var next := (at + horizontal * dt).clamp(MIN_CORNER, MAX_CORNER)
	if not next.is_equal_approx(at) or not is_equal_approx(heading, float(ship.yaw)):
		var candidate := Ground.contact(next, heading, grid, grove_time)
		var side_clearance := maxf(altitude, float(support.sideY)) + 0.025
		if candidate.sideY <= side_clearance and (not slipping or candidate.y <= altitude + 0.020):
			support = candidate
		elif slipping:
			var tangent := (support.slide as Vector2).orthogonal() * maxf(0.5, horizontal.length()) * dt
			var left := (at - tangent).clamp(MIN_CORNER, MAX_CORNER)
			var right := (at + tangent).clamp(MIN_CORNER, MAX_CORNER)
			var left_support := Ground.contact(left, float(ship.yaw), grid, grove_time)
			var right_support := Ground.contact(right, float(ship.yaw), grid, grove_time)
			var go_left: bool = left_support.y < right_support.y
			candidate = left_support if go_left else right_support
			heading = ship.yaw
			next = at
			if candidate.y <= altitude + 0.020 and candidate.sideY <= side_clearance:
				next = left if go_left else right
				support = candidate
		else:
			next = at
			heading = ship.yaw
	horizontal = (next - at) / dt

	var clearance := altitude - float(support.y)
	var scale := vertical_scale(clearance)
	var acceleration := 11.0 * scale
	var ceiling := Lake.water_y() + MAX_ALTITUDE
	var climb_speed := minf(4.8 * scale, sqrt(2.0 * acceleration * maxf(ceiling - altitude, 0.0)))
	var descent_speed := lerpf(0.78, 3.9, smoothstep(0.0, 3.0, clearance)) * scale
	var climb := lift * (climb_speed if lift >= 0.0 else descent_speed)
	var vertical_before := velocity.y
	if slipping:
		velocity.y = maxf(-6.5, velocity.y - 9.8 * dt)
	else:
		velocity.y = move_toward(velocity.y, climb, dt * acceleration)
	altitude = clampf(altitude + velocity.y * dt, float(support.y), ceiling)
	var touching := altitude <= float(support.y) + 0.001 and lift <= 0.0
	ship.x = next.x
	ship.z = next.y
	ship.y = altitude
	ship.yaw = heading
	ship.landed = touching and support.stable and horizontal.length_squared() <= 1.30 ** 2
	ship.slipping = not ship.landed and (slipping or touching)
	_update_thrust(ship, move, lift, incoming, horizontal, vertical_before, velocity.y, dt)
	_apply_support(ship, support, touching)
	if not touching and lift <= 0.0:
		var approach := 1.0 - smoothstep(0.12, 0.82, altitude - float(support.y))
		ship.tiltX = float(support.pitch) * approach
		ship.tiltZ = float(support.roll) * approach
	if altitude >= ceiling or touching:
		velocity.y = 0.0
	return Vector3.ZERO if ship.landed else Vector3(horizontal.x, velocity.y, horizontal.y)

static func _update_thrust(ship: Dictionary, move: Vector2, lift: float,
		incoming: Vector2, horizontal: Vector2, vertical_before: float, vertical: float, dt: float) -> void:
	if ship.landed or ship.slipping:
		_set_thrust(ship, 0.0, 0.0)
		return
	var forward := Vector2.UP.rotated(-float(ship.yaw))
	var forward_input := clampf(move.dot(forward), 0.0, 1.0)
	var acceleration := (horizontal - incoming) / dt
	var pushing := clampf(acceleration.dot(forward) / 8.5, 0.0, 1.0)
	var rear := forward_input * lerpf(0.53, 1.0, pushing)
	var braking := clampf(-acceleration.dot(incoming.normalized()) / 16.0, 0.0, 1.0)
	var underside := 0.31 + 0.17 * braking
	if lift > 0.0:
		underside = lerpf(underside, 1.0, lift)
	elif lift < 0.0:
		underside = lerpf(underside, 0.14, -lift)
	elif vertical_before < -0.26:
		var arrest := clampf((vertical - vertical_before) / (dt * 11.0), 0.0, 1.0)
		underside = maxf(underside, 0.31 + arrest * 0.55)
	_set_thrust(ship, underside, rear)

static func _set_thrust(ship: Dictionary, underside: float, rear: float) -> void:
	ship.thrust = underside
	ship.rearThrust = rear

static func blocks_sight(ship: Dictionary, from: Vector3, to: Vector3) -> bool:
	if ship.is_empty():
		return false
	var to_ship := Basis(Vector3.UP, -float(ship.yaw))
	var at := position(ship)
	var hull := AABB(Vector3(-1.0, 0.0, -2.28), Vector3(2.0, 1.64, 4.56))
	return hull.intersects_segment(to_ship * (from - at), to_ship * (to - at)) != null

static func blocks_player(at: Vector2, next: Vector2, feet: float, head: float, ship: Dictionary) -> bool:
	return not ship.is_empty() and head >= float(ship.y) and feet <= float(ship.y) + 1.64 \
		and not _inside_hull(at, ship) and _inside_hull(next, ship)

static func _inside_hull(at: Vector2, ship: Dictionary) -> bool:
	var local := ((at - point(ship)).rotated(float(ship.yaw))).abs()
	return local.x < 1.0 + Rules.RADIUS and local.y < 2.28 + Rules.RADIUS
