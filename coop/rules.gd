extends RefCounted

const LakeLayout = preload("res://lake_layout.gd")

const SPEED := 3.6
const RADIUS := 0.29
const STEP_OVER_ROCK := 0.36
const INTERACT_RANGE := 2.5
const MIN_CORNER := Vector2(LakeLayout.Coast.WEST_LIMIT, -119)
const MAX_CORNER := Vector2(LakeLayout.East.LIMIT, 12)
const RAIN_START := 65.0
const RAIN_RAMP := 15.0
const RAIN_EASING := 101.0
const RAIN_END := 119.0
const WEATHER_CYCLE := 420.0
const CLOUD_BASE_METRES := 1600.0
const CLOUD_TOP_METRES := 4500.0

const GRID_SIZE := 4.0

static func pair(value: Array) -> Vector2:
	return Vector2(value[0], value[1])

static func rain_at(elapsed: float) -> float:
	var phase := fposmod(elapsed, WEATHER_CYCLE)
	return clampf((phase - RAIN_START) / RAIN_RAMP, 0.0, 1.0) * (1.0 - smoothstep(RAIN_EASING, RAIN_END, phase))

static func rain_exposure(world_y: float) -> float:
	return 1.0 - smoothstep(CLOUD_BASE_METRES, CLOUD_TOP_METRES, world_y - LakeLayout.water_y())

# Index each obstacle in every overlapping cell, including the player's radius.
static func collision_grid(obstacles: Array) -> Dictionary:
	var grid := {}
	for obstacle in obstacles + LakeLayout.Coast.obstacles + LakeLayout.East.obstacles:
		if obstacle.has("profile") or obstacle.get("type") == "table":
			continue
		if obstacle.get("type") == "rock" and float(obstacle.r) <= STEP_OVER_ROCK:
			continue
		var center := Vector2(obstacle.x, obstacle.z)
		var clearance: float = obstacle.r + RADIUS
		var lo := Vector2i(((center - Vector2.ONE * clearance) / GRID_SIZE).floor())
		var hi := Vector2i(((center + Vector2.ONE * clearance) / GRID_SIZE).floor())
		for x in range(lo.x, hi.x + 1):
			for z in range(lo.y, hi.y + 1):
				var cell := Vector2i(x, z)
				if not grid.has(cell):
					grid[cell] = []
				grid[cell].append(Vector3(center.x, center.y, clearance * clearance))
	return grid

static func free_at(point: Vector2, grid: Dictionary, allow_swim := false) -> bool:
	return (allow_swim or not LakeLayout.blocks_walk(point)) and obstacle_free_at(point, grid)

static func obstacle_free_at(point: Vector2, grid: Dictionary, feet := -INF, from := Vector2.INF) -> bool:
	if LakeLayout.Coast.buddha.bounds.has_point(point):
		var standing := feet if is_finite(feet) else LakeLayout.walk_height(from if from.is_finite() else point)
		if not LakeLayout.Coast.buddha.clears(point, standing, from):
			return false
	if LakeLayout.East.contains(point):
		var base := feet if is_finite(feet) else LakeLayout.East.height(point)
		if not is_finite(LakeLayout.Gallery.floor_at(point,base)) and not LakeLayout.East.Rocks.clears(point,base,from):
			return false
	return static_free_at(point,grid)

static func static_free_at(point: Vector2, grid: Dictionary) -> bool:
	var cell := Vector2i((point / GRID_SIZE).floor())
	for circle: Vector3 in grid.get(cell, []):
		if point.distance_squared_to(Vector2(circle.x, circle.y)) < circle.z:
			return false
	return true

static func move(point: Vector2, direction: Vector2, delta: float, grid: Dictionary,
		allow_swim := false, speed := SPEED, feet: float = -INF) -> Vector2:
	if direction.is_zero_approx():
		return point
	var motion := direction.limit_length() * speed * clampf(delta, 0.0, 0.1)
	var steps := maxi(1, ceili(motion.length() / 0.12))
	for i in steps:
		var target := (point + motion / steps).clamp(MIN_CORNER, MAX_CORNER)
		var across := Vector2(target.x, point.y)
		if (allow_swim or not LakeLayout.blocks_walk(across)) and obstacle_free_at(across,grid,feet,point) and LakeLayout.Coast.can_step(point, across, feet):
			point.x = target.x
		var along := Vector2(point.x, target.y)
		if (allow_swim or not LakeLayout.blocks_walk(along)) and obstacle_free_at(along,grid,feet,point) and LakeLayout.Coast.can_step(point, along, feet):
			point.y = target.y
	return point

static func room_code_valid(value: String) -> bool:
	if value.is_empty() or value.length() > 24:
		return false
	for i in value.length():
		var c := value.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 45 or c == 95):
			return false
	return true
