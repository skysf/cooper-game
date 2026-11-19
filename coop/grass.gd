extends RefCounted

const TUFTS = preload("res://vegetation/grass_medium_01.glb")
const ATLAS = preload("res://vegetation/grass_medium_01.png")
const GRASS_SHADER = preload("res://vegetation/grass.gdshader")
const VARIANTS := ["GrassShort", "GrassTuft", "GrassClump"]

var material := ShaderMaterial.new()
var meshes: Array[Mesh] = []

func _init() -> void:
	var prototype := TUFTS.instantiate()
	for variant: String in VARIANTS:
		var tuft := prototype.find_child(variant, true, false) as MeshInstance3D
		meshes.append(tuft.mesh)
	prototype.free()
	material.shader = GRASS_SHADER
	material.set_shader_parameter("grass_atlas", ATLAS)

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
