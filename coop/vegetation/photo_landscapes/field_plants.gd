extends RefCounted

const STUDIES = preload("res://vegetation/photo_landscapes/field_plants.glb")
const WIND = preload("res://vegetation/photo_landscapes/field_botany.gdshader")
const ATLAS = preload("res://vegetation/photo_landscapes/field_botany.png")
static var meshes := {}

static func material(flex: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WIND
	mat.set_shader_parameter("botanical_atlas", ATLAS)
	mat.set_shader_parameter("flexibility", flex)
	return mat

static func batch(parent: Node3D, kind: String, poses: Array, mat: Material, far_distance: float) -> MultiMeshInstance3D:
	if meshes.is_empty():
		var source := STUDIES.instantiate()
		for model: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
			meshes[String(model.name)] = model.mesh
		source.free()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = meshes[kind]
	multimesh.instance_count = poses.size()
	for i in poses.size():
		multimesh.set_instance_transform(i, poses[i])
	var batch_node := MultiMeshInstance3D.new()
	batch_node.name = kind
	batch_node.multimesh = multimesh
	batch_node.material_override = mat
	batch_node.extra_cull_margin = 1.1
	batch_node.visibility_range_end = far_distance
	batch_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(batch_node)
	return batch_node

static func set_wind(mat: ShaderMaterial, seconds: float, field: Vector4, rain: float) -> void:
	mat.set_shader_parameter("wind_time",seconds)
	mat.set_shader_parameter("wind_field",field)
	mat.set_shader_parameter("wetness",rain)
