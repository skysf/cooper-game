extends RefCounted

const Lake = preload("res://lake_layout.gd")
const Grove = preload("res://grove.gd")

enum {LAND, WATER, ROCK, TREE, STRUCTURE}

const GRID_SIZE := 6.0
const HULL_PADDING := 2.5
const BALANCE_CENTER := Vector2(0.0, 0.32)
const BALANCE_RADIUS := 0.39
const HULL_CONTACTS := [
	Vector3(0.0, 0.17, -1.84), Vector3(0.0, 0.08, -0.96), Vector3(0.0, 0.16, -0.17),
	Vector3(-0.36, 0.15, 0.36), Vector3(0.36, 0.15, 0.36), Vector3(0.0, 0.10, 0.62),
	Vector3(-0.62, 0.06, 0.91), Vector3(0.62, 0.06, 0.91),
	Vector3(-0.60, 0.0, 1.63), Vector3(0.60, 0.0, 1.63),
	Vector3(-0.67, 0.09, 2.07), Vector3(0.67, 0.09, 2.07), Vector3(0.0, 0.36, 2.02),
]
static var water_min_z := minf(Lake.center().y - Lake.radius().y * 1.19, float(Lake.layout.creek.firstZ))
static var water_max_z := maxf(Lake.center().y + Lake.radius().y * 1.19,
	float(Lake.layout.creek.firstZ) + float(Lake.layout.creek.steps) * float(Lake.layout.creek.spacing))

static func collision_grid(world: Dictionary) -> Dictionary:
	var grid := {}
	var trees := {}
	var saplings := {}
	var grove: Dictionary = world.get("grove", {})
	var seconds_per_year := float(grove.get("secondsPerYear", 5.0))
	for tree: Array in world.get("trees", []):
		trees[Vector2(tree[0], tree[1])] = float(tree[2])
	for tree: Dictionary in grove.get("trees", []):
		saplings[Vector2(tree.x, tree.z)] = tree
	for item: Dictionary in world.get("obstacles", []) + Lake.Coast.obstacles:
		var at := Vector2(item.x, item.z)
		var base := Lake.ground_height(at)
		var radius := float(item.r)
		var top := 0.9
		match item.type:
			"tree", "pine", "birch", "spruce":
				var growth: Dictionary = saplings.get(at, {})
				var height := float(item.get("treeHeight", trees.get(at, 12.0))) if growth.is_empty() else Grove.FINAL_HEIGHT * float(growth.size)
				var width := 0.35 if item.type == "birch" else 0.22
				_register(grid, {"at": at, "base": base, "kind": TREE, "radius": height * width,
					"trunk": radius, "height": height, "width": width,
					"taper": 0.0 if item.type == "birch" else 0.80,
					"growth": growth, "secondsPerYear": seconds_per_year})
				continue
			"rock":
				top = float(item.get("height", radius * 0.74))
				radius = float(item.get("flightRadius", radius))
				var depth := float(item.get("depth", radius * 0.90))
				_register(grid, {"at": at, "base": base, "kind": ROCK, "radius": maxf(radius, depth),
					"radii": Vector2(radius, depth), "height": top, "yaw": float(item.get("yaw", 0.0))})
				continue
			"wall", "post": top = 2.30
			"tower": top = 6.9
		_register(grid, {"at": at, "base": base, "kind": STRUCTURE, "radius": radius, "height": top})
	if world.has("shelter"):
		var cabin: Dictionary = world.shelter
		_register_roof(grid, Vector2(cabin.x, cabin.z), Vector2(cabin.width, cabin.depth) * 0.5
			+ Vector2(0.44, 0.44), 3.63, 0.50)
		_register_roof(grid, Vector2(10.8, -15.1), Vector2(1.64, 1.65), 7.38, 0.32)
	return grid

static func _register_roof(grid: Dictionary, at: Vector2, size: Vector2, y: float, slope: float) -> void:
	_register(grid, {"at": at, "base": 0.0, "kind": STRUCTURE, "radius": size.length(),
		"height": y, "size": size, "slope": slope})

static func _register(grid: Dictionary, shape: Dictionary) -> void:
	var spread := Vector2.ONE * (float(shape.radius) + HULL_PADDING)
	var at: Vector2 = shape.at
	var low := _cell(at - spread)
	var high := _cell(at + spread)
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			var key := Vector2i(x, z)
			if not grid.has(key):
				grid[key] = []
			grid[key].append(shape)

static func _cell(at: Vector2) -> Vector2i:
	return Vector2i((at / GRID_SIZE).floor())

static func _terrain(at: Vector2) -> float:
	if Lake.Coast.contains(at) or at.y >= water_min_z and at.y <= water_max_z:
		return Lake.walk_height(at)
	return 0.0

static func _tree_height(shape: Dictionary, grove_time: float) -> float:
	var growth: Dictionary = shape.growth
	if growth.is_empty():
		return shape.height
	return Grove.grown_height(growth, grove_time, shape.secondsPerYear)

static func _obstacle_top(shape: Dictionary, at: Vector2, grove_time: float) -> float:
	var diff: Vector2 = at - shape.at
	if diff.length_squared() >= float(shape.radius) ** 2:
		return -INF
	match int(shape.kind):
		ROCK:
			var radial := (diff.rotated(-float(shape.yaw)) / (shape.radii as Vector2)).length_squared()
			if radial < 1.0:
				return float(shape.base) + float(shape.height) * sqrt(1.0 - radial)
		TREE:
			var height := _tree_height(shape, grove_time)
			var radial := diff.length() / (height * float(shape.width))
			if radial < 1.0:
				var profile := lerpf(radial * radial, radial, float(shape.taper))
				return float(shape.base) + height * (1.0 - 0.68 * profile)
			if diff.length_squared() < float(shape.trunk) ** 2:
				return float(shape.base) + height * 0.35
		STRUCTURE:
			if not shape.has("size"):
				return float(shape.base) + float(shape.height)
			var size: Vector2 = shape.size
			if diff.abs().x < size.x and diff.abs().y < size.y:
				return float(shape.height) - absf(diff.x) * float(shape.slope)
	return -INF

static func _surface(at: Vector2, grid: Dictionary, grove_time: float,
		water: float, ceiling: float = INF, buoyant := false) -> Vector2:
	var result := Vector2(_terrain(at), LAND)
	if buoyant and not is_finite(water):
		water = Lake.open_water_support(at)
	if water > result.x:
		result = Vector2(water, WATER)
	for shape: Dictionary in grid.get(_cell(at), []):
		var top := _obstacle_top(shape, at, grove_time)
		if top > result.x and top <= ceiling:
			result = Vector2(top, shape.kind)
	return result

static func walk_height(at: Vector2, feet: float, grid: Dictionary, grove_time: float) -> float:
	return _surface(at, grid, grove_time, -INF, feet + 0.23).x

static func actor_clear(at: Vector2, feet: float, grid: Dictionary, grove_time: float) -> bool:
	for shape: Dictionary in grid.get(_cell(at), []):
		var offset: Vector2 = shape.at - at
		if offset.length_squared() > (float(shape.radius) + 0.28) ** 2:
			continue
		if shape.kind == TREE and feet < float(shape.base) + _tree_height(shape, grove_time) * 0.33:
			if offset.length_squared() < (float(shape.trunk) + 0.28) ** 2:
				return false
			continue
		var sample := at + offset.limit_length(0.21)
		var top := _obstacle_top(shape, sample, grove_time)
		if top <= feet + 0.23:
			continue
		if not shape.has("size") or top - feet < 1.75:
			return false
	return true

static func _water_height(at: Vector2, right: Vector2, back: Vector2) -> float:
	# A narrow creek or a single submerged wing cannot support the hull.
	if not Lake.Coast.contains(at) and (at.y < water_min_z or at.y > water_max_z):
		return -INF
	for offset: Vector2 in [Vector2.ZERO, right * 0.82, -right * 0.82, back * 1.68, -back * 1.38]:
		var location := at + offset
		if not is_finite(Lake.open_water_support(location)):
			return -INF
	return Lake.water_y() + 0.035

static func contact(at: Vector2, yaw: float, grid: Dictionary, grove_time: float) -> Dictionary:
	var right := Vector2.RIGHT.rotated(-yaw)
	var back := Vector2.DOWN.rotated(-yaw)
	var water := _water_height(at, right, back)
	var center := at + back * BALANCE_CENTER.y
	var base := _surface(center, grid, grove_time, water, INF, true)
	var x0 := _surface(center - right * BALANCE_RADIUS, grid, grove_time, water, INF, true).x
	var x1 := _surface(center + right * BALANCE_RADIUS, grid, grove_time, water, INF, true).x
	var z0 := _surface(center - back * BALANCE_RADIUS, grid, grove_time, water, INF, true).x
	var z1 := _surface(center + back * BALANCE_RADIUS, grid, grove_time, water, INF, true).x
	var slope := Vector2(x1 - x0, z1 - z0) / (2.0 * BALANCE_RADIUS)
	var surface: int = int(base.y)
	var residual := maxf(absf(base.x - (x0 + x1) * 0.5), absf(base.x - (z0 + z1) * 0.5))
	var max_slope := 0.42 if surface == TREE else 0.53
	var stable := slope.length() <= max_slope and residual < (0.19 if surface == TREE else 0.16)
	var plane_y := base.x - slope.y * BALANCE_CENTER.y
	var level_y := base.x - 0.1
	var resting_y := plane_y
	var high_point := center
	for probe: Vector3 in HULL_CONTACTS:
		var location := at + right * probe.x + back * probe.z
		var sample := _surface(location, grid, grove_time, water, INF, true)
		var obstacle_y := sample.x - probe.y
		if obstacle_y > level_y:
			level_y = obstacle_y
			high_point = location
		resting_y = maxf(resting_y, obstacle_y - slope.dot(Vector2(probe.x, probe.z)))
	# The highest part of a hull-wide contact must still leave support under its center of mass.
	stable = stable and resting_y <= plane_y + 0.16
	var downhill := center - high_point if resting_y > plane_y + 0.16 else -right * slope.x - back * slope.y
	if downhill.length_squared() < 0.025:
		downhill = center - high_point
	if downhill.length_squared() < 0.025:
		downhill = -back
	return {"y": resting_y if stable else level_y, "sideY": level_y,
		"stable": stable, "kind": surface, "slide": downhill.normalized(),
		"pitch": -atan(slope.y) if stable else clampf(downhill.dot(back) * 0.14, -0.21, 0.21),
		"roll": atan(slope.x) if stable else clampf(-downhill.dot(right) * 0.14, -0.21, 0.21)}

static func sight_obstructed(from: Vector3, to: Vector3, grid: Dictionary, grove_time: float) -> bool:
	var steps := maxi(1, ceili(from.distance_to(to) / 0.10))
	for i in range(1, steps + 1):
		var point := from.lerp(to, float(i) / steps)
		var at := Vector2(point.x, point.z)
		if point.y < _terrain(at):
			return true
		for shape: Dictionary in grid.get(_cell(at), []):
			if point.y < float(shape.base):
				continue
			if shape.kind == TREE:
				if (point.y <= float(shape.base) + _tree_height(shape, grove_time)
					and at.distance_squared_to(shape.at) < float(shape.trunk) ** 2):
					return true
				continue
			var top := _obstacle_top(shape, at, grove_time)
			if point.y <= top and (not shape.has("size") or point.y >= top - 0.18):
				return true
	return false

static func camera_clearance(pivot: Vector3, offset: Vector3, grid: Dictionary, grove_time: float) -> float:
	var length := offset.length()
	var steps := maxi(1, ceili(length / 0.21))
	for i in range(1, steps + 1):
		var travel := float(i) / steps
		var point := pivot + offset * travel
		var at := Vector2(point.x, point.z)
		if point.y < _terrain(at) + 0.18:
			return maxf(0.25, travel * length - 0.28)
		for shape: Dictionary in grid.get(_cell(at), []):
			if point.y > float(shape.base) + float(shape.height) + 0.18:
				continue
			var top := _obstacle_top(shape, at, grove_time)
			if point.y + 0.16 < float(shape.base) or point.y > top + 0.16:
				continue
			if shape.kind == TREE and point.y < float(shape.base) + 0.32 * _tree_height(shape, grove_time):
				if at.distance_squared_to(shape.at) > (float(shape.trunk) + 0.14) ** 2:
					continue
			if shape.has("size") and point.y < top - 0.30:
				continue
			return maxf(0.25, travel * length - 0.28)
	return length
