extends RefCounted

const TUFTS = preload("res://vegetation/grass_medium_01.glb")
const ATLAS = preload("res://vegetation/grass_medium_01.png")
const GRASS_SHADER = preload("res://vegetation/grass.gdshader")
const FERN_SHADER = preload("res://vegetation/camp_fern.gdshader")
const FERN_ATLAS = preload("res://textures/fern.png")
const PlacementWorld = preload("res://placement_world.gd")
const VARIANTS := ["GrassShort", "GrassTuft", "GrassClump"]
const MAX_FERN_COVERS := 12
const COVER_WIDTH := {"cabin_floor": 1.57, "campfire": 0.68}

var material := ShaderMaterial.new()
var fern_material := ShaderMaterial.new()
var meshes: Array[Mesh] = []
var _covers: Dictionary = {}
var _batches: Dictionary = {}
var _fern_focus := Vector3.INF

func _init() -> void:
	var prototype := TUFTS.instantiate()
	for variant: String in VARIANTS:
		var tuft := prototype.find_child(variant, true, false) as MeshInstance3D
		meshes.append(tuft.mesh)
	prototype.free()
	material.shader = GRASS_SHADER
	material.set_shader_parameter("grass_atlas", ATLAS)
	fern_material.shader = FERN_SHADER
	fern_material.set_shader_parameter("foliage",FERN_ATLAS)

func add_to_chunk(chunk: Node3D, cells: Array) -> void:
	for cell: Array in cells:
		var origin := Vector3(cell[0], 0.0, cell[1])
		var variants: Array = cell[2]
		for index in variants.size():
			var plants: Array = variants[index]
			if plants.is_empty():
				continue
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_custom_data = true
			multi.mesh = meshes[index]
			multi.instance_count = plants.size()
			var buffer := PackedFloat32Array()
			buffer.resize(plants.size() * 16)
			for i in plants.size():
				var plant: Array = plants[i]
				var basis := Basis(Vector3.UP, plant[3]).scaled(Vector3(plant[4], plant[5], plant[4]))
				var position := Vector3(plant[0], plant[1], plant[2]) - origin
				var offset := i * 16
				# MultiMesh stores three transform rows followed by four custom channels.
				buffer[offset] = basis.x.x
				buffer[offset + 2] = basis.z.x
				buffer[offset + 3] = position.x
				buffer[offset + 5] = basis.y.y
				buffer[offset + 7] = position.y
				buffer[offset + 8] = basis.x.z
				buffer[offset + 10] = basis.z.z
				buffer[offset + 11] = position.z
				buffer[offset + 12] = plant[6]
				buffer[offset + 13] = plant[7]
				buffer[offset + 15] = 1.0
			multi.buffer = buffer
			var batch := MultiMeshInstance3D.new()
			batch.position = origin
			batch.multimesh = multi
			batch.material_override = material
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			batch.lod_bias = 0.48
			batch.visibility_range_end = 39.0
			batch.extra_cull_margin = 0.1
			chunk.add_child(batch)
			var key := batch.get_instance_id()
			var data := {"instance":batch,"buffer":buffer,"masked":false}
			_batches[key] = data
			batch.tree_exited.connect(func(): _batches.erase(key))
			_apply_covers(data)

func set_ground_cover(records: Dictionary, focus: Vector3) -> void:
	var active := {}
	for id: String in records:
		var record: Dictionary = records[id]
		if COVER_WIDTH.has(record.kind) and record.mode == "ground":
			active[id] = {"pose": PlacementWorld.pose(record), "half_width": COVER_WIDTH[record.kind],
				"circle": record.kind == "campfire"}
	if active == _covers:
		if _covers.size() > MAX_FERN_COVERS and focus.distance_squared_to(_fern_focus) > 16.0:
			_cover_ferns(focus)
		return
	_covers = active
	for data: Dictionary in _batches.values():
		_apply_covers(data)
	_cover_ferns(focus)

func _cover_ferns(focus: Vector3) -> void:
	_fern_focus = focus
	var ordered := _covers.values()
	if ordered.size() > MAX_FERN_COVERS:
		ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return focus.distance_squared_to(a.pose.origin) < focus.distance_squared_to(b.pose.origin))
	var count := mini(ordered.size(), MAX_FERN_COVERS)
	var poses := PackedVector4Array()
	var shapes := PackedVector2Array()
	poses.resize(MAX_FERN_COVERS)
	shapes.resize(MAX_FERN_COVERS)
	for i in range(count):
		var cover: Dictionary = ordered[i]
		var pose: Transform3D = cover.pose
		poses[i] = Vector4(pose.origin.x, pose.origin.y, pose.origin.z, atan2(pose.basis.z.x, pose.basis.z.z))
		shapes[i] = Vector2(cover.half_width, 1.0 if cover.circle else 0.0)
	fern_material.set_shader_parameter("cover_poses", poses)
	fern_material.set_shader_parameter("cover_shapes", shapes)
	fern_material.set_shader_parameter("cover_count", count)

func _apply_covers(data: Dictionary) -> void:
	var batch: MultiMeshInstance3D = data.instance
	var bounds := batch.get_aabb()
	bounds.position += batch.position
	var nearby: Array[Dictionary] = []
	for cover: Dictionary in _covers.values():
		var half_width: float = cover.half_width
		var footprint := AABB(Vector3(-half_width, -.47, -half_width), Vector3(2.0 * half_width, .65, 2.0 * half_width))
		if (cover.pose * footprint).intersects(bounds):
			nearby.append({"inverse": cover.pose.affine_inverse(), "bounds": footprint,
				"circle": cover.circle, "radius_squared": half_width * half_width})
	var original: PackedFloat32Array = data.buffer
	if nearby.is_empty():
		if data.masked:
			batch.multimesh.buffer = original
			data.masked = false
		return
	var filtered := original.duplicate()
	for offset in range(0, original.size(), 16):
		var root := batch.position + Vector3(original[offset+3],original[offset+7],original[offset+11])
		for cover: Dictionary in nearby:
			var local: Vector3 = cover.inverse * root
			if cover.bounds.has_point(local) and (not cover.circle or Vector2(local.x, local.z).length_squared() < cover.radius_squared):
				for axis: int in [0,2,5,8,10]:
					filtered[offset+axis] *= .001
				filtered[offset+7] -= .46
				break
	batch.multimesh.buffer = filtered
	data.masked = true
