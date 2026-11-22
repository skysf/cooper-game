extends RefCounted

const Rules = preload("res://rules.gd")
const Lake = preload("res://lake_layout.gd")
const Ferry = preload("res://lake_ferry.gd")
const Spaceship = preload("res://spaceship.gd")
const PlacementWorld = preload("res://placement_world.gd")

const WALK_EYE := 1.67
const CROUCH_EYE := 0.78
const SWIM_EYE := 0.30
const FLOAT_DEPTH := 0.12
const SWIM_MIN_DEPTH := 0.55
const SWIM_SPEED := 2.25
const DIVE_SPEED := 1.42
const JUMP_SPEED := 4.75
const GRAVITY := 13.8

static func spawn(at: Vector2, feet := INF) -> Dictionary:
	var surface := Lake.surface_height(at)
	var floor_y := Lake.walk_height(at,feet)
	var swimming := surface - floor_y >= SWIM_MIN_DEPTH
	return {"point": at, "y": surface - FLOAT_DEPTH if swimming else floor_y,
		"vy": 0.0, "onFerry":false, "crouched":false, "crouchHeld":false, "bed":"", "swimming": swimming, "jumpHeld": false, "grounded": not swimming,
		"vx": 0.0, "vz": 0.0, "waterVy": 0.0, "floorY": floor_y}

static func eye_offset(swimming: bool) -> float:
	return SWIM_EYE if swimming else WALK_EYE

static func boardable(ship: Dictionary, player: Dictionary) -> bool:
	if ship.onWater:
		return float(player.y) >= Lake.water_y() - 0.38 and float(player.y) <= float(ship.y) + 0.85
	return not player.swimming and absf(float(player.y) - float(ship.y)) <= 1.45

static func put_ashore(at: Vector3) -> Dictionary:
	var actor := spawn(Vector2(at.x, at.z),at.y)
	if at.y > float(actor.y) + 0.24:
		actor.y = at.y
		actor.swimming = false
		actor.grounded = false
	return actor

static func _standing_height(at: Vector2, feet: float, flight_grid: Dictionary, grove_time: float) -> float:
	var ground := Lake.walk_height(at,feet)
	if flight_grid.is_empty() or feet < ground + 0.28 or is_finite(Lake.Gallery.floor_at(at,feet)):
		return ground
	return Spaceship.Ground.walk_height(at, feet, flight_grid, grove_time)

static func step(actor: Dictionary, direction: Vector2, lift: float, delta: float,
		grid: Dictionary, ship: Dictionary, flight_grid := {}, grove_time := 0.0, fixtures := {},
		ferry_departure := -1.0, room_time := -1.0) -> void:
	var dt := clampf(delta, 0.0, 0.08)
	var was_swimming: bool = actor.swimming
	var was_grounded: bool = actor.get("grounded", false)
	var was_up: bool = actor.jumpHeld
	actor.jumpHeld = lift > 0.0
	var at: Vector2 = actor.point
	var y: float = actor.y
	var ferry := {}
	var aboard: bool = actor.get("onFerry", false)
	if room_time >= 0.0 and (aboard or at.distance_squared_to(Ferry.MOOR) < 24.0 * 24.0):
		ferry = Ferry.pose(room_time, ferry_departure)
		if aboard and actor.has("ferryLocal"):
			at = Ferry.world_point(actor.ferryLocal, ferry)
	var crouching: bool = aboard and (actor.get("crouchHeld", false) or Ferry.under_canopy(actor.get("ferryLocal", Ferry.ENTRY)))
	var furniture := PlacementWorld.nearby(PlacementWorld.mine_grid(),fixtures,at,3.15)
	var above_obstacles := not flight_grid.is_empty() and not was_swimming and y > Lake.walk_height(at) + 0.45
	var next := Rules.move(at, direction, dt, {} if above_obstacles else grid, true,
		SWIM_SPEED if was_swimming else 0.97 if crouching else 1.85 if aboard else Rules.SPEED, y)
	if above_obstacles and next != at:
		if not Spaceship.Ground.actor_clear(Vector2(next.x, at.y), y, flight_grid, grove_time):
			next.x = at.x
		if not Spaceship.Ground.actor_clear(next, y, flight_grid, grove_time):
			next.y = at.y
	if not furniture.is_empty() and next != at:
		var across := Vector2(next.x,at.y)
		var across_feet := maxf(y,PlacementWorld.floor_height(furniture,across,y,Lake.walk_height(across,y)))
		if PlacementWorld.blocks_player(furniture,across,across_feet):
			next.x = at.x
		var along_feet := maxf(y,PlacementWorld.floor_height(furniture,next,y,Lake.walk_height(next,y)))
		if PlacementWorld.blocks_player(furniture,next,along_feet):
			next.y = at.y
	var supported := false
	if not ferry.is_empty():
		var previous := Ferry.local_point(at, ferry)
		var local := Ferry.local_point(next, ferry)
		var stop_at_rail: bool = was_grounded and not actor.jumpHeld
		if aboard and (Ferry.obstructed(local,crouching and was_grounded) or stop_at_rail and not Ferry.on_deck(local)):
			var across := Vector2(local.x,previous.y)
			if Ferry.obstructed(across,crouching and was_grounded) or stop_at_rail and not Ferry.on_deck(across):
				across.x = previous.x
			local.x = across.x
			if Ferry.obstructed(local,crouching and was_grounded) or stop_at_rail and not Ferry.on_deck(local):
				local.y = previous.y
			next = Ferry.world_point(local, ferry)
		supported = Ferry.on_deck(local) and (aboard or not Ferry.obstructed(local,false) and y >= Lake.water_y() - 0.16)
	var deck_height := Lake.water_y() - Ferry.WATERLINE + Ferry.DECK
	var floor_y := PlacementWorld.floor_height(furniture,next,y,_standing_height(next,y,flight_grid,grove_time))
	if supported:
		floor_y = maxf(floor_y, deck_height)
	var surface := Lake.surface_height(next)
	var can_swim := surface - floor_y >= SWIM_MIN_DEPTH
	if Spaceship.blocks_player(at, next, y - (0.25 if was_swimming else 0.0), y + eye_offset(was_swimming), ship) \
			or (was_swimming and y < Lake.water_y() - 0.43 and not can_swim):
		next = at
		floor_y = PlacementWorld.floor_height(furniture,at,y,_standing_height(at,y,flight_grid,grove_time))
		supported = not ferry.is_empty() and Ferry.on_deck(Ferry.local_point(at, ferry)) and (aboard or y >= Lake.water_y() - 0.16)
		if supported:
			floor_y = maxf(floor_y, deck_height)
		surface = Lake.surface_height(at)
		can_swim = surface - floor_y >= SWIM_MIN_DEPTH
	actor.onFerry = supported
	actor.crouched = supported and (crouching or Ferry.under_canopy(Ferry.local_point(next, ferry)))
	if supported:
		actor.ferryLocal = Ferry.local_point(next, ferry)
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
		var covered: bool = supported and (actor.crouched or Ferry.under_canopy(actor.ferryLocal))
		vertical = JUMP_SPEED if actor.jumpHeld and not was_up and not covered else 0.0
	if y > floor_y or vertical > 0.0:
		vertical -= GRAVITY * dt
		var target_y := y + vertical * dt
		if target_y > y and (PlacementWorld.blocks_player(furniture,next,target_y)
				or Lake.Coast.buddha.intersects(next, y + 1.72, target_y + 1.72)):
			vertical = 0.0
		else:
			y = target_y
	actor.y = maxf(y, floor_y)
	actor.vy = 0.0 if y <= floor_y and vertical < 0.0 else vertical
	actor.grounded = y <= floor_y + 0.001 and float(actor.vy) <= 0.0
