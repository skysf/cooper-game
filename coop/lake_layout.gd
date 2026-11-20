extends RefCounted

const Coast = preload("res://coast_layout.gd")

static var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://water_layout.json"))

static func center() -> Vector2:
	return Vector2(layout.center[0], layout.center[1])

static func radius() -> Vector2:
	return Vector2(layout.radius[0], layout.radius[1])

static func water_y() -> float:
	return float(layout.waterY)

static func edge_radius(angle: float) -> float:
	return 1.0 + 0.047 * sin(angle * 3.0 + 0.9) + 0.025 * cos(angle * 5.0 + 0.4) + 0.018 * sin(angle * 9.0 + 0.3)

static func lake_distance(point: Vector2) -> float:
	var local := (point - center()) / radius()
	return local.length() / edge_radius(local.angle())

static func shore_at(angle: float, distance: float = 1.0) -> Vector2:
	return center() + Vector2.from_angle(angle) * radius() * (edge_radius(angle) * distance)

static func creek_sample(index: float) -> Vector2:
	var x := -11.4 + sin(index * 0.22) * 2.1 + cos(index * 0.47) * 0.38
	var half_width := 0.16 + sin(PI * index / float(layout.creek.steps)) * 1.13
	return Vector2(x, half_width)

static func creek_distance(point: Vector2) -> float:
	var index := (point.y - float(layout.creek.firstZ)) / float(layout.creek.spacing)
	if index < 0.0 or index > float(layout.creek.steps):
		return INF
	var section := creek_sample(floorf(index)).lerp(creek_sample(ceilf(index)), fposmod(index, 1.0))
	return absf(point.x - section.x) / section.y

static func surface_height(point: Vector2) -> float:
	if Coast.sea_at(point, water_y()):
		return water_y()
	if lake_distance(point) < 1.0 or creek_distance(point) < 1.0:
		return water_y()
	return -INF

static func blocks_walk(point: Vector2) -> bool:
	if Coast.sea_at(point, water_y()) and ground_height(point) < water_y() - 0.28:
		return true
	var dock: Dictionary = layout.dock
	if point.x >= float(dock.west) + 0.14 and point.x <= float(dock.east) and absf(point.y - float(dock.z)) < float(dock.halfWidth) - 0.16:
		return false
	return lake_distance(point) < 0.949

static func ground_height(point: Vector2) -> float:
	if Coast.contains(point):
		return Coast.height(point)
	var distance := lake_distance(point)
	var bed := 0.0
	if distance < 1.08:
		bed = water_y() - 2.35 * clampf(1.0 - distance, 0.0, 1.0)
		if distance > 1.0:
			bed = lerpf(water_y(), 0.0, smoothstep(1.0, 1.08, distance))
	var stream := creek_distance(point)
	if stream < 1.24:
		var creek_bed := water_y() - 0.33 * clampf(1.0 - stream, 0.0, 1.0)
		if stream > 1.0:
			creek_bed = lerpf(water_y(), 0.0, smoothstep(1.0, 1.24, stream))
		bed = minf(bed, creek_bed)
	return bed

static func on_dock(point: Vector2) -> bool:
	var dock: Dictionary = layout.dock
	return point.x >= float(dock.west) and point.x <= float(dock.east) \
		and absf(point.y - float(dock.z)) < float(dock.halfWidth)

static func walk_height(point: Vector2) -> float:
	return 0.12 if on_dock(point) else ground_height(point)

static func open_water_support(point: Vector2) -> float:
	if (Coast.sea_at(point, water_y()) or lake_distance(point) < 0.995) and ground_height(point) < water_y() - 0.045:
		return water_y() + 0.035
	return -INF
