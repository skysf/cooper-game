extends RefCounted

const Rules = preload("res://rules.gd")
const Survival = preload("res://survival.gd")
const Footing = preload("res://companion_footing.gd")
const Lake = preload("res://lake_layout.gd")

const HOME := Vector2(3.56, -87.40)
const CAMP_STOPS := [HOME, Vector2(2.22, -86.42), Vector2(1.12, -84.92), Vector2(3.58, -84.45), Vector2(4.16, -85.90)]
const REACH := 2.1
const STAND := "Stand"
const IDLE := "Idle"
const WALK := "Walk"
const RUN := "Run"
const DOWN := "Lie-down"
const REST := "Rest"
const RISE := "Rise"
const DOWN_SECONDS := 44.0 / 30.0
const RISE_SECONDS := 41.0 / 30.0
const CELL := 0.50
const REST_DELAY := 2.6
const WALK_SPEED := 0.82
const TROT_SPEED := 2.35
const CATCHUP_SPEED := 4.05
const BODY := Vector2(0.47,0.90)

var navigation: AStarGrid2D

static func from_save(saved: Variant, players: Dictionary, grid: Dictionary, repaired: bool, elapsed: float) -> Dictionary:
	var dog := {"x": HOME.x, "z": HOME.y, "yaw": PI, "speed": 0.0, "owner": "", "mode": "camp", "clip": REST if repaired else STAND, "clipAt": elapsed}
	if saved is not Dictionary or saved.get("owner") is not String or not players.has(saved.owner):
		return dog
	dog.owner = saved.owner
	dog.mode = "stay" if saved.get("mode") == "stay" else "follow"
	dog.clip = REST
	if Survival.finite_number(saved.get("x")) and Survival.finite_number(saved.get("z")):
		var at := Vector2(saved.x, saved.z)
		if at == at.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER) and Rules.free_at(at, grid):
			dog.x = at.x
			dog.z = at.y
	if Survival.finite_number(saved.get("yaw")):
		dog.yaw = wrapf(saved.yaw, -PI, PI)
	if Survival.finite_number(saved.get("y")):
		var ground := Lake.walk_height(position(dog))
		dog.y = clampf(float(saved.y),ground,ground+6.0)
	return dog

static func position(dog: Dictionary) -> Vector2:
	return Vector2(dog.x, dog.z)

static func command(dog: Dictionary, player_id: String) -> String:
	if dog.is_empty():
		return ""
	if dog.owner.is_empty():
		return "adopt"
	if dog.owner == player_id:
		return "follow" if dog.mode == "stay" else "stay"
	return ""

func can_reach(dog: Dictionary, actor: Vector2, grid: Dictionary) -> bool:
	var at := position(dog)
	return at.distance_squared_to(actor) <= REACH * REACH and _clear(actor, at, grid)

func tick(room: Dictionary, grid: Dictionary, delta: float) -> void:
	var dog: Dictionary = room.data.dog
	var at := position(dog)
	var footing := Footing.for_room(room) as Footing
	dog.y = footing.height(at,float(dog.get("y",Lake.walk_height(at))))
	dog.fixtureNear = footing.near(at)
	var elapsed: float = room.data.elapsed
	var route: Dictionary = room.dog_route
	var owner: Dictionary = room.actors.get(dog.owner, {})
	if owner.get("swimming", false) or (not dog.owner.is_empty() and dog.owner == room.get("ship", {}).get("pilot", "")):
		owner = {}
	var repaired: bool = room.data.quest.repaired
	var wandering: bool = dog.mode == "camp"
	var goal: Vector2 = at
	if wandering:
		goal = _camp_goal(at, route, elapsed, repaired)
	elif not owner.is_empty():
		goal = owner.point
	var settling: bool = dog.mode == "follow" and repaired and not owner.is_empty() and (
		Survival.inside_shelter(at) and Survival.inside_shelter(owner.point)
		and at.distance_squared_to(owner.point) < 2.8 * 2.8 and owner.direction.is_zero_approx())
	route.idle = float(route.get("idle", 0.0)) + delta if settling else 0.0
	var rest: bool = (repaired and goal == HOME and at.distance_to(HOME) < 0.15) if wandering else (
		dog.mode == "stay" or owner.is_empty() or route.idle >= REST_DELAY)

	match dog.clip:
		DOWN:
			if elapsed >= float(dog.clipAt) + DOWN_SECONDS:
				_set_clip(dog, REST, float(dog.clipAt) + DOWN_SECONDS)
			return
		RISE:
			if elapsed < float(dog.clipAt) + RISE_SECONDS:
				return
			_set_clip(dog, STAND, float(dog.clipAt) + RISE_SECONDS)
	if rest:
		dog.speed = 0.0
		dog.vx = 0.0
		dog.vz = 0.0
		if dog.clip != REST:
			_set_clip(dog, DOWN, elapsed)
		return
	if dog.clip == REST:
		_set_clip(dog, RISE, elapsed)
		return
	var distance := at.distance_to(goal)
	var following: bool = route.get("following", false)
	var gap := 0.15 if wandering else (1.55 if following else 2.15)
	var moving := distance > gap or not _clear(at, goal, grid) or not footing.clear(at,goal,dog.y,BODY)
	route.following = moving
	var pace := 0.0
	var waypoint := goal
	if moving:
		waypoint = _waypoint(at, goal, route, grid, elapsed)
		waypoint = footing.waypoint(at,waypoint,goal,route,grid,dog.y,BODY,elapsed)
		pace = minf(WALK_SPEED, distance * 2.8) if wandering else lerpf(WALK_SPEED, CATCHUP_SPEED, smoothstep(2.2, 6.4, distance))
	_drive(dog, waypoint, pace, grid, elapsed, delta, footing)

func _camp_goal(at: Vector2, route: Dictionary, elapsed: float, repaired: bool) -> Vector2:
	if repaired and not route.get("lamp_lit", false):
		route.lamp_lit = true
		route.camp_index = 0
		route.erase("camp_until")
	var index: int = route.get("camp_index", 0)
	var goal: Vector2 = CAMP_STOPS[index]
	if at.distance_to(goal) >= 0.15:
		return goal
	if not route.has("camp_until"):
		var pause := (8.5 if repaired else 3.2) if index == 0 else (2.0 + float(index % 3) * 0.75)
		route.camp_until = elapsed + pause
	elif elapsed >= float(route.camp_until):
		index = (index + 1) % CAMP_STOPS.size()
		route.camp_index = index
		route.erase("camp_until")
		goal = CAMP_STOPS[index]
	return goal

func _drive(dog: Dictionary, waypoint: Vector2, pace: float, grid: Dictionary, elapsed: float, delta: float, footing: Footing) -> void:
	var at := position(dog)
	var gap := at.distance_to(waypoint)
	var motion := at.direction_to(waypoint)
	if pace > 0.0 and gap > 0.001:
		var heading := atan2(-motion.x, -motion.y)
		dog.yaw = rotate_toward(float(dog.yaw), heading, delta * 4.7)
		pace *= lerpf(0.15, 1.0, smoothstep(0.0, 1.0, cos(heading - float(dog.yaw))))
	else:
		pace = 0.0
	var speed := move_toward(float(dog.speed), pace, delta * (4.9 if pace > float(dog.speed) else 6.5))
	var step := minf(speed * delta, gap)
	var landing := footing.move(at,motion,step/Rules.SPEED,grid,Rules.SPEED,dog.y,BODY)
	var next := Vector2(landing.x,landing.z)
	var velocity := (next - at) / maxf(delta, 0.001)
	dog.x = next.x
	dog.z = next.y
	dog.y = landing.y
	dog.fixtureNear = footing.near(next)
	dog.vx = velocity.x
	dog.vz = velocity.y
	dog.speed = velocity.length()
	var trot := 1.08 if dog.clip == RUN else 1.35
	_set_clip(dog, STAND if dog.speed < 0.10 else (RUN if dog.speed > trot else WALK), elapsed)

func _set_clip(dog: Dictionary, clip: String, elapsed: float) -> void:
	if dog.clip != clip:
		dog.clip = clip
		dog.clipAt = elapsed

func _waypoint(at: Vector2, goal: Vector2, route: Dictionary, grid: Dictionary, elapsed: float) -> Vector2:
	if at.distance_squared_to(goal) <= 36.0 and _clear(at, goal, grid):
		route.erase("refresh")
		return goal
	if elapsed >= float(route.get("refresh", 0.0)):
		if navigation == null:
			prepare_navigation(grid)
		route.refresh = elapsed + 0.55
		var start := _cell_near(at, grid)
		var finish := _cell_near(goal, grid)
		route.path = navigation.get_point_path(start, finish) if navigation.is_in_boundsv(start) and navigation.is_in_boundsv(finish) else PackedVector2Array()
		route.index = 0
	var path: PackedVector2Array = route.get("path", PackedVector2Array())
	var index: int = route.get("index", 0)
	while index < path.size() and at.distance_squared_to(path[index]) < 0.16 * 0.16:
		index += 1
	route.index = index
	return path[index] if index < path.size() else at

func _clear(at: Vector2, goal: Vector2, grid: Dictionary) -> bool:
	var segments := maxi(1, ceili(at.distance_to(goal) / 0.18))
	for step in range(1, segments + 1):
		if not Rules.free_at(at.lerp(goal, float(step) / segments), grid):
			return false
	return true

func prepare_navigation(grid: Dictionary, shared_base: AStarGrid2D = null) -> void:
	if navigation != null:
		return
	navigation = AStarGrid2D.new()
	var first := Vector2i(Rules.MIN_CORNER / CELL)
	var last := Vector2i(Rules.MAX_CORNER / CELL)
	navigation.region = Rect2i(first, last - first + Vector2i.ONE)
	navigation.cell_size = Vector2.ONE * CELL
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	var margin := _route_margin()
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, z)
			var point := Vector2(cell) * CELL
			var solid := shared_base.is_point_solid(cell) if shared_base != null else not Rules.free_at(point, grid)
			if solid or (margin > 0.0 and _inside_route_margin(point, grid, margin)):
				navigation.set_point_solid(cell)

func _route_margin() -> float:
	return 0.0

func _inside_route_margin(point: Vector2, grid: Dictionary, margin: float) -> bool:
	var cell := Vector2i((point / Rules.GRID_SIZE).floor())
	for circle: Vector3 in grid.get(cell, []):
		if point.distance_squared_to(Vector2(circle.x, circle.y)) < pow(sqrt(circle.z) + margin, 2):
			return true
	return false

func _cell_near(point: Vector2, grid: Dictionary) -> Vector2i:
	var center := Vector2i((point / CELL).round())
	var best := navigation.region.end
	var distance := INF
	for z in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			var cell := Vector2i(x, z)
			var at := Vector2(cell) * CELL
			var score := at.distance_squared_to(point)
			if score < distance and navigation.is_in_boundsv(cell) and not navigation.is_point_solid(cell) and _clear(point, at, grid):
				best = cell
				distance = score
	return best
