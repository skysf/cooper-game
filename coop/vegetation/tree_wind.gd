extends RefCounted

const WOOD_SHADER = preload("res://vegetation/tree_wood.gdshader")
const LEAF_SHADER = preload("res://vegetation/tree_leaves.gdshader")
const FLEX := {"pine": Vector2(0.66, 0.007), "spruce": Vector2(0.76, 0.011), "birch": Vector2(1.0, 0.022)}

var material_cache: Dictionary[String, ShaderMaterial] = {}
var elapsed := 0.0
var field := Vector4(0.917, -0.400, 0.32, 0.0)

func update(seconds: float, wind: Vector4) -> void:
	elapsed = seconds
	field = wind
	for material: ShaderMaterial in material_cache.values():
		_set_sample(material)

func surface(source: Material, species: String, height: float, detail := -1, coast := false) -> Material:
	if source is not StandardMaterial3D or source.albedo_texture == null or not FLEX.has(species):
		return source
	var key := "%d/%s/%f/%d/%s" % [source.get_instance_id(), species, height, detail, coast]
	if material_cache.has(key):
		return material_cache[key]
	var leaves: bool = source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var flex: Vector2 = FLEX[species]
	var material := ShaderMaterial.new()
	material.shader = LEAF_SHADER if leaves else WOOD_SHADER
	material.set_shader_parameter("tree_color", source.albedo_texture)
	material.set_shader_parameter("surface_tint", source.albedo_color)
	material.set_shader_parameter("surface_roughness", source.roughness)
	material.set_shader_parameter("vertex_tint", source.vertex_color_use_as_albedo)
	material.set_shader_parameter("source_tree_height", height)
	material.set_shader_parameter("branch_flexibility", flex.x)
	material.set_shader_parameter("coast_transition", coast)
	material.set_shader_parameter("uv_mapping", Vector4(source.uv1_scale.x, source.uv1_scale.y,
		source.uv1_offset.x, source.uv1_offset.y))
	if leaves:
		material.set_shader_parameter("leaf_cutoff", source.alpha_scissor_threshold)
		material.set_shader_parameter("flutter_metres", flex.y)
		material.set_shader_parameter("spray_tip_uv", species != "pine")
	else:
		if source.normal_enabled and source.normal_texture != null:
			material.set_shader_parameter("has_normal_texture", true)
			material.set_shader_parameter("tree_normal", source.normal_texture)
			material.set_shader_parameter("normal_depth", source.normal_scale)
		if source.roughness_texture != null:
			material.set_shader_parameter("has_roughness_texture", true)
			material.set_shader_parameter("tree_roughness", source.roughness_texture)
			material.set_shader_parameter("roughness_channel", _channel(source.roughness_texture_channel))
	material_cache[key] = material
	_set_sample(material)
	return material

static func meshes(model: Node3D) -> Array[MeshInstance3D]:
	var parts: Array[MeshInstance3D] = []
	if model is MeshInstance3D and model.mesh != null:
		parts.append(model)
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh != null:
			parts.append(part)
	return parts

func _set_sample(material: ShaderMaterial) -> void:
	material.set_shader_parameter("wind_time", elapsed)
	material.set_shader_parameter("wind_field", field)

static func _channel(channel: int) -> Vector4:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN: return Vector4(0, 1, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE: return Vector4(0, 0, 1, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: return Vector4(0, 0, 0, 1)
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE: return Vector4(0.333333, 0.333333, 0.333334, 0)
	return Vector4(1, 0, 0, 0)
