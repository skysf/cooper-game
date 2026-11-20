extends RefCounted

const Rules = preload("res://rules.gd")
const Lake = preload("res://lake_layout.gd")
const Spaceship = preload("res://spaceship.gd")

const WALK_EYE := 1.67
const SWIM_EYE := 0.30
const FLOAT_DEPTH := 0.12
const SWIM_MIN_DEPTH := 0.55
const SWIM_SPEED := 2.25
const DIVE_SPEED := 1.42
const JUMP_SPEED := 4.75
const GRAVITY := 13.8

static func spawn(at: Vector2) -> Dictionary:
	var surface := Lake.surface_height(at)
	var floor_y := Lake.walk_height(at)
	var swimming := surface - floor_y >= SWIM_MIN_DEPTH
	return {"point": at, "y": surface - FLOAT_DEPTH if swimming else floor_y,
		"vy": 0.0, "swimming": swimming, "jumpHeld": false, "grounded": not swimming,
		"vx": 0.0, "vz": 0.0, "waterVy": 0.0, "floorY": floor_y}

static func eye_offset(swimming: bool) -> float:
	return SWIM_EYE if swimming else WALK_EYE

static func boardable(ship: Dictionary, player: Dictionary) -> bool:
	if ship.onWater:
		return float(player.y) >= Lake.water_y() - 0.38 and float(player.y) <= float(ship.y) + 0.85
	return not player.swimming and absf(float(player.y) - float(ship.y)) <= 1.45

static func put_ashore(at: Vector3) -> Dictionary:
	var actor := spawn(Vector2(at.x, at.z))
	if at.y > float(actor.y) + 0.24:
		actor.y = at.y
		actor.swimming = false
		actor.grounded = false
	return actor

static func _standing_height(at: Vector2, feet: float, flight_grid: Dictionary, grove_time: float) -> float:
	var ground := Lake.walk_height(at)
	if flight_grid.is_empty() or feet < ground + 0.28:
		return ground
	return Spaceship.Ground.walk_height(at, feet, flight_grid, grove_time)

static func step(actor: Dictionary, direction: Vector2, lift: float, delta: float,
		grid: Dictionary, ship: Dictionary, flight_grid := {}, grove_time := 0.0) -> void:
	var dt := clampf(delta, 0.0, 0.08)
	var was_swimming: bool = actor.swimming
	var was_grounded: bool = actor.get("grounded", false)
	var was_up: bool = actor.jumpHeld
	actor.jumpHeld = lift > 0.0
	var at: Vector2 = actor.point
	var y: float = actor.y
	var above_obstacles := not flight_grid.is_empty() and not was_swimming and y > Lake.walk_height(at) + 0.45
	var next := Rules.move(at, direction, dt, {} if above_obstacles else grid, true,
		SWIM_SPEED if was_swimming else Rules.SPEED, y)
	if above_obstacles and next != at:
		if not Spaceship.Ground.actor_clear(Vector2(next.x, at.y), y, flight_grid, grove_time):
			next.x = at.x
		if not Spaceship.Ground.actor_clear(next, y, flight_grid, grove_time):
			next.y = at.y
	var floor_y := _standing_height(next, y, flight_grid, grove_time)
	var surface := Lake.surface_height(next)
	var can_swim := surface - floor_y >= SWIM_MIN_DEPTH
	if Spaceship.blocks_player(at, next, y - (0.25 if was_swimming else 0.0), y + eye_offset(was_swimming), ship) \
			or (was_swimming and y < Lake.water_y() - 0.43 and not can_swim):
		next = at
		floor_y = _standing_height(at, y, flight_grid, grove_time)
		surface = Lake.surface_height(at)
		can_swim = surface - floor_y >= SWIM_MIN_DEPTH
	actor.point = next
	actor.vx = (next.x - at.x) / dt if dt > 0.0 else 0.0
	actor.vz = (next.y - at.y) / dt if dt > 0.0 else 0.0
	actor.floorY = floor_y
	actor.waterVy = 0.0
	actor.swimming = can_swim and (was_swimming or y <= surface + 0.11)
	if actor.swimming:
		var surface_pose := surface - FLOAT_DEPTH
		y = y if was_swimming else surface_pose
		actor.y = clampf(y + lift * DIVE_SPEED * dt, floor_y + 0.27, surface_pose)
		actor.vy = 0.0
		actor.grounded = false
		actor.waterVy = (float(actor.y) - y) / dt if dt > 0.0 else 0.0
		return
	if was_swimming:
		y = floor_y
	var vertical: float = actor.vy
	# Follow small descending terrain steps while already in contact, without snapping a jump apex.
	if was_grounded and not was_swimming and vertical <= 0.0 and absf(y - floor_y) <= 0.18:
		y = floor_y
	if y <= floor_y and vertical <= 0.0:
		y = floor_y
		vertical = JUMP_SPEED if actor.jumpHeld and not was_up else 0.0
	if y > floor_y or vertical > 0.0:
		vertical -= GRAVITY * dt
		y += vertical * dt
	actor.y = maxf(y, floor_y)
	actor.vy = 0.0 if y <= floor_y and vertical < 0.0 else vertical
	actor.grounded = y <= floor_y + 0.001 and float(actor.vy) <= 0.0
