extends RefCounted

const Mines = preload("res://mines_layout.gd")
const Placement = preload("res://placement.gd")
const PlacementWorld = preload("res://placement_world.gd")

# The largest horizontal/vertical slope from WindField in a full storm is 0.4074.
const MAX_SLOPE := 0.42
const FOCUS_CELL := 2.0
const DROP_REACH := 8.27 # The 8.2 m visible radius plus the longest streak tip.
const DROP_BOTTOM := 2.10

var _storage: Dictionary = {}
var _roof_poses: Dictionary = {}
var _built: Array[Dictionary] = []
var _camp: Array[Dictionary] = []
var _mine: Array[Dictionary] = []
var _cell := Vector3i(0, -10000, 0)
var _last_repaired := false
var _dirty := true
var _cover_texture: ImageTexture
var _texture_rows := 0
var _roof_slopes: Array[Dictionary] = []

func _init() -> void:
	for part: Dictionary in PlacementWorld.profile("cabin_roof").get("parts", []):
		if part.faces == Placement.TOP:
			_roof_slopes.append(part)
	for part: Dictionary in Mines.solids():
		var bounds: AABB = part.bounds
		# Stone shell and closed end have thick collision pieces. Thin walk
		# surfaces and timber frames do not seal the open mouth.
		if part.faces == 0 and bounds.size.y > 0.55:
			_mine.append(_cover(part.pose, bounds))
	_camp = _camp_roof()

func set_roofs(records: Dictionary) -> void:
	# Network snapshots replace the dictionary. Between snapshots there is
	# no need to scan the room for an unchanged set of roofs.
	if is_same(records, _storage):
		return
	_storage = records
	var poses := {}
	for id: String in records:
		var record: Dictionary = records[id]
		if record.kind == "cabin_roof" and record.mode == "ground":
			poses[id] = PlacementWorld.pose(record)
	if poses == _roof_poses:
		return
	_roof_poses = poses
	_built.clear()
	for pose: Transform3D in poses.values():
		for part: Dictionary in _roof_slopes:
			_built.append(_cover(pose * part.pose, part.bounds))
	_dirty = true

func apply(at: Vector3, repaired: bool, material: ShaderMaterial) -> void:
	var cell := Vector3i((at / FOCUS_CELL).floor())
	if not _dirty and cell == _cell and repaired == _last_repaired:
		return
	_dirty = false
	_cell = cell
	_last_repaired = repaired
	var origin := Vector2((cell.x + 0.5) * FOCUS_CELL, (cell.z + 0.5) * FOCUS_CELL)
	var bottom := cell.y * FOCUS_CELL - DROP_BOTTOM
	var baked := PackedFloat32Array()
	_pack_nearby(_built, origin, bottom, baked)
	_pack_nearby(_mine, origin, bottom, baked)
	if repaired:
		_pack_nearby(_camp, origin, bottom, baked)

	var rows := baked.size() / 16
	material.set_shader_parameter("shelter_rows", rows)
	if rows == 0:
		return
	# A row contains the centre and conservative projected radius, then the
	# three axes and half lengths. This uses a small nearest float texture.
	var capacity := maxi(_texture_rows, nearest_po2(rows))
	baked.resize(capacity * 16)
	var image := Image.create_from_data(4, capacity, false, Image.FORMAT_RGBAF, baked.to_byte_array())
	if capacity != _texture_rows:
		_cover_texture = ImageTexture.create_from_image(image)
		_texture_rows = capacity
		material.set_shader_parameter("shelter_boxes", _cover_texture)
	else:
		_cover_texture.update(image)

static func _pack_nearby(parts: Array[Dictionary], origin: Vector2, bottom: float,
		baked: PackedFloat32Array) -> void:
	for part in parts:
		var bounds: AABB = part.bounds
		var height := bounds.end.y - bottom
		if height < 0.0:
			continue
		var nearest := origin.clamp(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.end.x, bounds.end.z))
		var radius := DROP_REACH + FOCUS_CELL * 0.71 + MAX_SLOPE * height
		if nearest.distance_squared_to(origin) <= radius * radius:
			baked.append_array(part.data)

static func _cover(pose: Transform3D, bounds: AABB) -> Dictionary:
	var center := pose * bounds.get_center()
	var world: AABB = pose * bounds
	var half := world.size * 0.5
	var projected_radius := Vector2(half.x, half.z).length() + half.y * MAX_SLOPE + 0.008
	var extent := bounds.size * 0.5
	return {"bounds": world, "data": PackedFloat32Array([
		center.x, center.y, center.z, projected_radius,
		pose.basis.x.x, pose.basis.x.y, pose.basis.x.z, extent.x,
		pose.basis.y.x, pose.basis.y.y, pose.basis.y.z, extent.y,
		pose.basis.z.x, pose.basis.z.y, pose.basis.z.z, extent.z,
	])}

static func _roof_board(a: Vector3, b: Vector3, width: float, depth: float) -> Dictionary:
	var line := b - a
	var basis := Basis(Vector3.BACK, atan2(line.y, line.x))
	var size := Vector3(line.length(), width, depth)
	return _cover(Transform3D(basis, (a + b) * 0.5), AABB(-size * 0.5, size))

static func _camp_roof() -> Array[Dictionary]:
	# The continuous wooden slopes follow the baked planks in build-scene.mjs.
	# The repaired canvas matches Terrain._landmarks, including the east eave.
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	var shelter: Dictionary = world.shelter
	var x := float(shelter.x)
	var z := float(shelter.z)
	var run := float(shelter.width) * 0.5 + 0.40
	var first := z - float(shelter.depth) * 0.5 - 0.43
	var last := first + floorf((float(shelter.depth) + 0.85 - 0.001) / 0.30) * 0.30
	var ridge := Vector3(x, 3.56, (first + last) * 0.5)
	var depth := last - first + 0.31
	return [
		_roof_board(Vector3(x - run, 2.04, ridge.z), ridge, 0.098, depth),
		_roof_board(ridge, Vector3(x + run, 2.04, ridge.z), 0.098, depth),
		_roof_board(Vector3(x - 0.05, 3.65, z), Vector3(x + 3.20, 2.066, z), 0.045, 2.7),
	]
