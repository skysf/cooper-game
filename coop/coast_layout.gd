extends RefCounted

const EAST_EDGE := -30.0
const WEST_LIMIT := -304.0

static var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://coast_layout.json"))
static var buddha := preload("res://coast/buddha_contact.gd").new(layout.buddha)
static var origin := Vector2(layout.origin[0], layout.origin[1])
static var step_size := float(layout.spacing)
static var cells := Vector2i(layout.cells[0], layout.cells[1])
static var heights := FileAccess.get_file_as_bytes("res://coast/elevation.bin").to_float32_array()
static var foliage: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://coast/foliage.json"))
static var obstacles := _obstacles()

static func _obstacles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tree: Array in foliage.trees:
		var h := float(tree[2])
		result.append({"type": "pine", "x": tree[0], "z": tree[1], "r": h * 0.033, "treeHeight": h})
	for stone: Array in foliage.stones:
		var size := float(stone[2])
		result.append({"type": "rock", "x": stone[0], "z": stone[1], "r": size * 0.57,
			"flightRadius": size * 0.63, "depth": size * 0.61, "height": size * 0.53, "yaw": stone[3] * TAU})
	for stone: Array in foliage.crags:
		var size := float(stone[2])
		result.append({"type": "rock", "x": stone[0], "z": stone[1], "r": size * 0.38,
			"flightRadius": size * 0.45, "depth": size * 0.55, "height": size * 0.53, "yaw": stone[3] * TAU})
	return result

static func contains(at: Vector2) -> bool:
	return at.x < EAST_EDGE and at.x >= origin.x and at.y >= origin.y and at.y <= origin.y + cells.y * step_size

static func height(at: Vector2) -> float:
	var grid := ((at - origin) / step_size).clamp(Vector2.ZERO, Vector2(cells))
	var x := mini(int(grid.x), cells.x - 1)
	var z := mini(int(grid.y), cells.y - 1)
	var start := z * (cells.x + 1) + x
	var east := grid.x - x
	var south := grid.y - z
	var a := heights[start]
	var b := heights[start + 1]
	var c := heights[start + cells.x + 1]
	var d := heights[start + cells.x + 2]
	# Follow the same diagonal as the terrain triangles on both clients and server.
	if east + south <= 1.0:
		return a + (b - a) * east + (c - a) * south
	return d + (c - d) * (1.0 - east) + (b - d) * (1.0 - south)

static func sea_at(at: Vector2, sea_level: float) -> bool:
	return at.x <= float(layout.seaEast) and contains(at) and height(at) < sea_level

static func can_step(from: Vector2, to: Vector2, feet: float = -INF) -> bool:
	if not contains(to):
		return true
	var base := height(from)
	var rise := maxf(0.034, from.distance_to(to) * 0.89)
	return height(to) <= maxf(base + rise, feet + 0.065)

static func point(key: String) -> Vector2:
	var pair: Array = layout[key]
	return Vector2(pair[0], pair[1])

static func area(at: Vector2, sea_level: float) -> String:
	if at.distance_squared_to(buddha.pose.origin) < 26.0 * 26.0:
		return "buddha"
	if at.distance_to(point("island")) < 32.0 and height(at) >= sea_level:
		return "island"
	if at.x < point("reef").x - 3.0:
		return "ocean"
	if at.x < point("lookout").x + 1.5 and height(at) < 3.1:
		return "beach"
	return "headland" if at.x <= point("lookout").x + 6.5 else "coast-trail"
