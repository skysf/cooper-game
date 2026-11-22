extends RefCounted

const Lake = preload("res://lake_layout.gd")
const Survival = preload("res://survival.gd")
const REGROW_SECONDS := 240.0
const REACH := 2.35
# Stable save IDs follow the bearing in hundredths of a radian from lake center.
const BEARINGS := [-137,-124,-114,-97,-85,-71,-58,-45,-36,-18,21,36,48,59,77,89,100,116,129,144]
static var centers := _centers()

static func _centers() -> Dictionary:
	var result := {}
	for bearing: int in BEARINGS:
		result[str(bearing)] = Lake.shore_at(float(bearing)*.01, .994)
	return result

static func cut(id: String, times: Dictionary, elapsed: float) -> bool:
	return times.has(id) and elapsed < float(times[id]) + REGROW_SECONDS

static func from_save(raw: Variant, elapsed: float) -> Dictionary:
	var valid := {}
	if raw is Dictionary:
		for id: String in centers:
			var t: Variant = raw.get(id)
			if Survival.finite_number(t) and t >= 0 and t <= elapsed and elapsed < t + REGROW_SECONDS:
				valid[id] = float(t)
	return valid

static func reachable(id: String, point: Vector2, feet: float) -> bool:
	if not centers.has(id):
		return false
	var center: Vector2 = centers[id]
	return point.distance_squared_to(center) <= REACH*REACH and absf(feet-Lake.ground_height(center)) < 1.3

static func target(point: Vector2, feet: float, eye: Vector3, forward: Vector3) -> String:
	if point.distance_squared_to(Lake.center()) > 24.0*24.0:
		return ""
	var result := ""
	var best := -.45
	for id: String in centers:
		if not reachable(id,point,feet):
			continue
		var p: Vector2 = centers[id]
		var to := Vector3(p.x,Lake.ground_height(p)+1.10,p.y)-eye
		var alignment := forward.dot(to.normalized())
		var score := alignment - 0.14 * point.distance_to(p)
		if alignment > .34 and score > best:
			best = score
			result = id
	return result
