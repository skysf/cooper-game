extends RefCounted

const Lake = preload("res://lake_layout.gd")
const Rules = preload("res://rules.gd")

const TOP := 1 << 3
const SIDES := (1 << 0) | (1 << 1) | (1 << 4) | (1 << 5)
const ALL_FACES := TOP | SIDES | (1 << 2)
const CONTACT := 0.002
const TERRAIN_STEP := 0.12

# The box is in the owner's local space. Face bits are X−, X+, Y−, Y+, Z−, Z+.
# Repeated IDs can group a tabletop and its legs. All boxes block the ray, even
# when none of their faces can support a placement.
static func solid(id: String, bounds: AABB, pose := Transform3D.IDENTITY, faces := TOP) -> Dictionary:
	return {"id": id, "bounds": bounds, "pose": pose, "faces": faces}

static func rectangle_feet(bounds: AABB) -> PackedVector3Array:
	return PackedVector3Array([
		bounds.position,
		Vector3(bounds.end.x, bounds.position.y, bounds.position.z),
		Vector3(bounds.position.x, bounds.position.y, bounds.end.z),
		Vector3(bounds.end.x, bounds.position.y, bounds.end.z),
	])

static func bodies(id: String, profile: Dictionary, pose: Transform3D) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for part: Dictionary in profile.get("parts", []):
		output.append(solid(id, part.bounds, pose * part.pose, part.faces))
	if output.is_empty():
		output.append(solid(id, profile.bounds, pose, profile.get("faces", TOP)))
	return output

static func trace(from: Vector3, to: Vector3, solids: Array[Dictionary], moving := "") -> Dictionary:
	return _trace(from, to, solids, moving)

static func overlaps(first: Dictionary, second: Dictionary) -> bool:
	return _overlaps(first, second)

# Profiles and nearby solids are game-owned. Use the same query for the ghost
# and the current server scene once the aim and reach have been checked.
# A profile has local bounds and optionally feet, center_of_mass, or an aim
# anchor. Align follows an uphill surface. Mount also accepts enabled wall or
# underside faces. Both use local +Y as the outward contact axis.
static func solve(from: Vector3, to: Vector3, yaw: float, profile: Dictionary,
		solids: Array[Dictionary], moving := "") -> Dictionary:
	if not from.is_finite() or not to.is_finite() or not is_finite(yaw) or from.is_equal_approx(to):
		return {"ok": false, "reason": "invalid_aim", "pose": Transform3D.IDENTITY}
	var pose := Transform3D(Basis(Vector3.UP, yaw), to)
	var hit := _trace(from, to, solids, moving)
	if hit.is_empty():
		return {"ok": false, "reason": "no_surface", "pose": pose}

	pose.origin = hit.point
	var answer := {"ok": false, "reason": "unsupported_face", "pose": pose, "hit": hit, "supports": []}
	if not hit.support:
		return answer
	var bounds: AABB = profile.bounds
	var feet: PackedVector3Array = profile.get("feet", rectangle_feet(bounds))
	if feet.is_empty():
		answer.reason = "no_contact_points"
		return answer
	var mounting: bool = profile.get("mount", false)
	var minimum_up := cos(float(profile.get("slope_limit", deg_to_rad(28.0))))
	var normal: Vector3 = hit.normal
	if not mounting and normal.y < minimum_up:
		answer.reason = "slope"
		return answer
	var aligned: bool = mounting or profile.get("align", false)
	pose.basis = _orientation(normal, yaw) if aligned else pose.basis
	var anchor: Vector3 = profile.get("anchor", Vector3(0.0, feet[0].y, 0.0))
	pose.origin -= pose.basis * anchor
	var outward := pose.basis.y
	var tolerance: float = profile.get("contact_tolerance", 0.026)
	var correction := 0.0
	for foot: Vector3 in feet:
		var point := pose * foot
		var sample := _contact(point, outward, tolerance, solids, moving)
		if _supports(sample, normal if aligned else Vector3.UP, 0.965 if aligned else minimum_up):
			correction = maxf(correction, (sample.point - point).dot(outward))
	pose.origin += outward * correction
	answer.pose = pose

	var contacts := PackedVector2Array()
	var support_ids: Array[String] = []
	for foot: Vector3 in feet:
		var point := pose * foot
		var sample := _contact(point, outward, tolerance, solids, moving)
		if not _supports(sample, normal if aligned else Vector3.UP, 0.965 if aligned else minimum_up):
			continue
		var at: Vector3 = sample.point
		contacts.append(Vector2(at.x, at.z))
		if sample.id not in support_ids:
			support_ids.append(sample.id)
	var mass: Vector3 = pose * (profile.get("center_of_mass", bounds.get_center()) as Vector3)
	if (mounting and contacts.size() != feet.size()) or (not mounting and not _balances(contacts, Vector2(mass.x, mass.z))):
		answer.reason = "unstable"
		return answer

	for placed: Dictionary in bodies("", profile, pose):
		if not _above_ground_and_in_bounds(placed.bounds, placed.pose):
			answer.reason = "terrain_overlap"
			return answer
		for existing: Dictionary in solids:
			if (moving.is_empty() or existing.id != moving) and _overlaps(placed, existing):
				answer.reason = "occupied"
				return answer
	answer.ok = true
	answer.reason = ""
	answer.supports = support_ids
	return answer

static func _orientation(normal: Vector3, yaw: float) -> Basis:
	var right := Vector3.RIGHT.slide(normal)
	if right.length_squared() < 0.01:
		right = Vector3.BACK.slide(normal)
	right = right.normalized()
	return Basis(normal, yaw) * Basis(right, normal, right.cross(normal))

static func _contact(point: Vector3, outward: Vector3, tolerance: float,
		solids: Array[Dictionary], moving: String) -> Dictionary:
	return _trace(point + outward * tolerance, point - outward * tolerance, solids, moving)

static func _supports(hit: Dictionary, outward: Vector3, minimum: float) -> bool:
	return not hit.is_empty() and hit.support and outward.dot(hit.normal) >= minimum

static func _balances(points: PackedVector2Array, center: Vector2) -> bool:
	var polygon := Geometry2D.convex_hull(points)
	if polygon.size() < 4:
		return false
	var side := 0.0
	for i in polygon.size() - 1:
		var edge := polygon[i + 1] - polygon[i]
		var distance := edge.normalized().cross(center - polygon[i])
		if absf(distance) <= CONTACT or distance * side < 0.0:
			return false
		side = signf(distance)
	return true

static func _trace(from: Vector3, to: Vector3, solids: Array[Dictionary], moving: String) -> Dictionary:
	var best := _terrain_hit(from, to)
	for object: Dictionary in solids:
		if not moving.is_empty() and object.id == moving:
			continue
		var hit := _box_hit(from, to, object)
		if not hit.is_empty() and _nearer(hit, best):
			best = hit
	return best

static func _nearer(hit: Dictionary, best: Dictionary) -> bool:
	if best.is_empty():
		return true
	if not is_equal_approx(float(hit.t), float(best.t)):
		return float(hit.t) < float(best.t)
	return String(hit.id) < String(best.id)

static func _box_hit(from: Vector3, to: Vector3, object: Dictionary) -> Dictionary:
	var pose: Transform3D = object.pose
	var bounds: AABB = object.bounds
	var inverse := pose.affine_inverse()
	var start := inverse * from
	var direction := inverse * to - start
	var entry := 0.0
	var exit := 1.0
	var face := -1
	for axis in 3:
		var low := bounds.position[axis]
		var high := bounds.end[axis]
		if absf(direction[axis]) < 0.00001:
			if start[axis] < low or start[axis] > high:
				return {}
			continue
		var a := (low - start[axis]) / direction[axis]
		var b := (high - start[axis]) / direction[axis]
		if minf(a, b) >= entry:
			entry = minf(a, b)
			face = axis * 2 + int(a > b)
		exit = minf(exit, maxf(a, b))
		if entry > exit:
			return {}
	if face < 0:
		return {"t": 0.0, "id": object.id, "point": from, "normal": Vector3.ZERO,
			"support": false, "walk_surface": object.get("walk_surface",false)}
	var normal := Vector3.ZERO
	normal[face >> 1] = 1.0 if face % 2 else -1.0
	return {"t": entry, "id": object.id, "point": from.lerp(to, entry),
		"normal": (pose.basis * normal).normalized(), "support": (int(object.faces) & (1 << face)) != 0,
		"walk_surface": object.get("walk_surface",false)}

static func _inside(at: Vector2) -> bool:
	return at == at.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER)

static func _height(at: Vector2, reference := INF, gallery := false) -> float:
	if not _inside(at):
		return -INF
	if Lake.East.contains(at):
		if gallery:
			var floor_y := Lake.Gallery.floor_at(at,reference,1.35,INF)
			if is_finite(floor_y):
				return floor_y
		return maxf(Lake.walk_height(at,reference),Lake.surface_height(at))
	return maxf(Lake.walk_height(at),Lake.surface_height(at))

static func _terrain_hit(from: Vector3, to: Vector3) -> Dictionary:
	var start := Vector2(from.x, from.z)
	var finish := Vector2(to.x, to.z)
	var gallery := Lake.East.contains(start) and is_finite(Lake.Gallery.floor_at(start,from.y,.30,2.9))
	if from.y < _height(start,from.y,gallery) - CONTACT:
		return {"t": 0.0, "id": "", "point": from, "normal": Vector3.ZERO, "support": false}
	var steps := maxi(1, ceili(start.distance_to(finish) / TERRAIN_STEP))
	for i in range(1, steps + 1):
		var high := float(i) / steps
		var point := from.lerp(to, high)
		if point.y > _height(Vector2(point.x, point.z),point.y,gallery):
			continue
		var low := float(i - 1) / steps
		for _step in 12:
			var mid := (low + high) * 0.5
			point = from.lerp(to, mid)
			if point.y > _height(Vector2(point.x, point.z),point.y,gallery):
				low = mid
			else:
				high = mid
		point = from.lerp(to, high)
		var at := Vector2(point.x, point.z)
		var ground := _height(at,point.y,gallery) if Lake.East.contains(at) else Lake.walk_height(at)
		var water := Lake.surface_height(at)
		point.y = maxf(ground, water)
		var wet := water >= ground
		return {"t": high, "id": "water" if wet else "terrain", "point": point,
			"normal": Vector3.UP if wet else _terrain_normal(at,point.y), "support": not wet}
	return {}

static func _terrain_normal(at: Vector2, feet := INF) -> Vector3:
	var step := 0.035
	var left := Lake.walk_height(at - Vector2(step, 0),feet)
	var right := Lake.walk_height(at + Vector2(step, 0),feet)
	var near := Lake.walk_height(at - Vector2(0, step),feet)
	var far := Lake.walk_height(at + Vector2(0, step),feet)
	return Vector3(left - right, step * 2.0, near - far).normalized()

static func _above_ground_and_in_bounds(bounds: AABB, pose: Transform3D) -> bool:
	# Include the face interiors so a small ridge between the feet is tested.
	for x in 3:
		for y in 3:
			for z in 3:
				var point := pose * (bounds.position + bounds.size * Vector3(x, y, z) * 0.5)
				var at := Vector2(point.x, point.z)
				if not _inside(at) or point.y < _height(at,point.y) - CONTACT:
					return false
	return true

static func _overlaps(a: Dictionary, b: Dictionary) -> bool:
	var first: Transform3D = a.pose
	var second: Transform3D = b.pose
	var size_a: Vector3 = a.bounds.size * 0.5
	var size_b: Vector3 = b.bounds.size * 0.5
	var offset: Vector3 = second * b.bounds.get_center() - first * a.bounds.get_center()
	var axes: Array[Vector3] = [first.basis.x, first.basis.y, first.basis.z, second.basis.x, second.basis.y, second.basis.z]
	for i in 3:
		for j in range(3, 6):
			axes.append(axes[i].cross(axes[j]))
	for direction: Vector3 in axes:
		if direction.length_squared() < 0.0000001:
			continue
		var axis := direction.normalized()
		var limit := 0.0
		for i in 3:
			limit += absf(axis.dot(first.basis[i])) * size_a[i] + absf(axis.dot(second.basis[i])) * size_b[i]
		if absf(offset.dot(axis)) >= limit - CONTACT:
			return false
	return true
