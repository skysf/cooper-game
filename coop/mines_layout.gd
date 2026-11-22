extends RefCounted

# The lamp spill is for the gallery and its mouth. Separate distant coastal
# batches so their canopy and boulder materials keep one daylight variant.
const COAST_SCENERY_LAYER := 1 << 14

const Placement = preload("res://placement.gd")
const PATH := "res://props/mines/mines_manifest.json"

static var data: Dictionary = preload("res://east/mine_ground.gd").data
static var _colliders: Dictionary = _build_solids()
static var _poses: Dictionary = _build_poses()

static func _load() -> Dictionary:
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return result.get("mines", {}) if result is Dictionary else {}

static func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

static func _build_poses() -> Dictionary:
	var result := {}
	for id: String in data:
		var entry: Dictionary = data[id]
		result[id] = Transform3D(Basis(Vector3.UP, float(entry.yaw)), vector(entry.origin))
	return result

static func pose(id: String) -> Transform3D:
	return _poses.get(id, Transform3D.IDENTITY)

static func gather(id: String) -> Vector3:
	if not data.has(id):
		return Vector3.ZERO
	return pose(id) * vector(data[id].gather)

static func _build_solids() -> Dictionary:
	var result := {}
	var transforms := _build_poses()
	for id: String in data:
		var cave: Transform3D = transforms[id]
		var shapes: Array[Dictionary] = []
		for row: Dictionary in data[id].colliders:
			var basis := Basis(vector(row.basis[0]), vector(row.basis[1]), vector(row.basis[2]))
			var size := vector(row.size)
			var local := Transform3D(basis, vector(row.center))
			var part := Placement.solid(id, AABB(size * -0.5, size), cave * local, int(row.faces))
			if int(row.faces) == Placement.TOP:
				part["walk_surface"] = true
			shapes.append(part)
		result[id] = shapes
	return result

static func solids(id := "") -> Array[Dictionary]:
	if not id.is_empty():
		var empty: Array[Dictionary] = []
		return _colliders.get(id, empty)
	var result: Array[Dictionary] = []
	for source: String in _colliders:
		result.append_array(_colliders[source])
	return result

static func occludes_plant(at: Vector2) -> bool:
	for id: String in data:
		var local := pose(id).affine_inverse() * Vector3(at.x, 0.0, at.y)
		if local.z >= -0.32 and local.z <= float(data[id].floor.back()[0])+.5 and absf(local.x) < 2.40:
			return true
	return false
