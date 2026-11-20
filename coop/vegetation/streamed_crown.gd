extends Node3D

const TreeWind = preload("res://vegetation/tree_wind.gd")
const WOOD = preload("res://materials/bark.tres")
const NEEDLE_ATLAS = preload("res://pines/pine_needles.png")
const NEAR_END := 18.0
const FAR_START := 23.0

var detail: Array[Node3D] = []
var detail_materials: Array[Array] = []
var wind := TreeWind.new()
var blend := -1.0

func configure(spec: Dictionary) -> bool:
	var scene := load(spec.model) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	var core := model.find_child("StreamedWood", true, false) as MeshInstance3D
	var near := model.find_child("LOD0", true, false) as Node3D
	var far := model.find_child("LOD1", true, false) as Node3D
	if core == null or near == null or far == null:
		model.free()
		return false

	name = spec.id
	position = Vector3(spec.at[0], 0.0, spec.at[1])
	var height: float = spec.height
	var needles := StandardMaterial3D.new()
	needles.albedo_texture = NEEDLE_ATLAS
	needles.vertex_color_use_as_albedo = true
	needles.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	needles.alpha_scissor_threshold = 0.34
	needles.roughness = 0.94
	_set_surface(core, WOOD, height, -1)
	detail.assign([near, far])
	for level in detail.size():
		var active: Array[ShaderMaterial] = []
		for part: MeshInstance3D in TreeWind.meshes(detail[level]):
			var source: StandardMaterial3D = WOOD if part.name == &"TwigWoodNear" else needles
			active.append(_set_surface(part, source, height, level))
		detail_materials.append(active)
	add_child(model)
	return true

func set_focus(eye: Vector3) -> void:
	var distance := Vector2(eye.x, eye.z).distance_to(Vector2(position.x, position.z))
	var weight := smoothstep(NEAR_END, FAR_START, distance)
	if is_equal_approx(weight, blend):
		return
	blend = weight
	detail[0].visible = weight < 1.0
	detail[1].visible = weight > 0.0
	# A whole branch chooses one group using its stable rank in vertex color alpha.
	for material: ShaderMaterial in detail_materials[0]:
		material.set_shader_parameter("lod_clip", Vector2(weight, 1.0))
	for material: ShaderMaterial in detail_materials[1]:
		material.set_shader_parameter("lod_clip", Vector2(0.0, weight))

func set_wind(elapsed: float, field: Vector4) -> void:
	wind.update(elapsed, field)

func _set_surface(part: MeshInstance3D, source: StandardMaterial3D, height: float, level: int) -> ShaderMaterial:
	var material := wind.surface(source, "pine", height, level) as ShaderMaterial
	if level >= 0:
		material.set_shader_parameter("branch_lod", true)
	part.set_surface_override_material(0, material)
	part.extra_cull_margin = 0.28
	return material
