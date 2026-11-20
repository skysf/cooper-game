extends "res://camp_dog.gd"

# Keep circular collision geometry authoritative. The route grid reserves a small
# clearance so diagonals between free grid centres do not clip a curved rock edge.
const ROUTE_MARGIN := 0.14

func _build_navigation(grid: Dictionary) -> void:
	super._build_navigation(grid)
	var end := navigation.region.end
	for z in range(navigation.region.position.y, end.y):
		for x in range(navigation.region.position.x, end.x):
			var point := Vector2(x, z) * CELL
			var cell := Vector2i(x, z)
			if navigation.is_point_solid(cell):
				continue
			for circle: Vector3 in grid.get(Vector2i((point / Rules.GRID_SIZE).floor()), []):
				if point.distance_squared_to(Vector2(circle.x, circle.y)) < pow(sqrt(circle.z) + ROUTE_MARGIN, 2):
					navigation.set_point_solid(cell)
					break

func _waypoint(at: Vector2, goal: Vector2, route: Dictionary, grid: Dictionary, elapsed: float) -> Vector2:
	if route.has("detour"):
		var detour: Vector2 = route.detour
		if at.distance_to(detour) > 0.14 and elapsed < float(route.get("detourUntil", 0)) and _clear(at, detour, grid):
			return detour
		route.erase("detour")
		route.refresh = 0.0
	var result := super._waypoint(at, goal, route, grid, elapsed)
	if (result.is_equal_approx(at) and at.distance_to(goal) > 0.4) or not _clear(at, result, grid):
		return recover(at, goal, route, grid, elapsed)
	return result

func recover(at: Vector2, goal: Vector2, route: Dictionary, grid: Dictionary, elapsed: float) -> Vector2:
	var best := at
	var best_score := INF
	var heading := at.direction_to(goal)
	# A local turn can initially increase distance; it must be entirely walkable.
	# The persistent short detour prevents switching sides on successive frames.
	for radius: float in [0.85, 1.25]:
		for i in 24:
			var direction := heading.rotated(float(i) * TAU / 24.0)
			var candidate := at + direction * radius
			if candidate != candidate.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER) or not _clear(at, candidate, grid):
				continue
			var score := candidate.distance_to(goal) + (1.0 - heading.dot(direction)) * 0.16
			if score < best_score:
				best_score = score
				best = candidate
	route.refresh = 0.0
	if best != at:
		route.detour = best
		route.detourUntil = elapsed + 2.6
	return best
