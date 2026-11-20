extends Node3D

const Layout = preload("res://lake_layout.gd")
const HAZEL = preload("res://vegetation/lakeside_hazel.glb")
const BULRUSH = preload("res://vegetation/lakeside_bulrush.glb")
const PLANT_SHADER = preload("res://vegetation/lake_margin.gdshader")
const TILE := 8.0

var materials: Array[ShaderMaterial] = []

func build(reflection_layer: int) -> void:
	var planting: Dictionary = Layout.layout.get("lakesideVegetation", {})
	_build_species("Hazel", HAZEL, planting.get("hazel", []), true, reflection_layer)
	_build_species("Bulrush", BULRUSH, planting.get("bulrush", []), false, reflection_layer)

func set_wind(elapsed: float, wind: Vector4, rain: float) -> void:
	for material in materials:
		material.set_shader_parameter("wind_time", elapsed)
		material.set_shader_parameter("wind_field", wind)
		material.set_shader_parameter("rain", rain)

func _build_species(label: String, scene: PackedScene, plants: Array, shrub: bool, reflection_layer: int) -> void:
	if plants.is_empty():
		return
	var model := scene.instantiate() as Node3D
	var part := model as MeshInstance3D
	if part == null:
		part = model.find_children("*", "MeshInstance3D", true, false)[0]
	var source := part.get_active_material(0) as StandardMaterial3D
	var mesh := part.mesh
	var material := ShaderMaterial.new()
	material.shader = PLANT_SHADER
	material.set_shader_parameter("plant_color", source.albedo_texture)
	material.set_shader_parameter("shrub", shrub)
	material.set_shader_parameter("waterline", Layout.water_y())
	materials.append(material)
	model.free()

	var cells := {}
	for plant: Array in plants:
		var at := Vector2(plant[0], plant[1])
		var height := Layout.ground_height(at)
		var water := Layout.surface_height(at)
		if (shrub and is_finite(water)) or (not shrub and (not is_finite(water) or water - height > 0.42)):
			continue
		var cell := Vector2i((at / TILE).floor())
		var local := at - (Vector2(cell) + Vector2.ONE * 0.5) * TILE
		var basis := Basis(Vector3.UP, float(plant[3])).scaled_local(Vector3.ONE * float(plant[2]))
		var pose := Transform3D(basis, Vector3(local.x, height - 0.014, local.y))
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(pose)

	for cell: Vector2i in cells:
		var poses: Array = cells[cell]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = poses.size()
		for i in poses.size():
			multimesh.set_instance_transform(i, poses[i])
		var batch := MultiMeshInstance3D.new()
		batch.name = "%s_%d_%d" % [label, -cell.x, -cell.y]
		batch.position = Vector3((cell.x + 0.5) * TILE, 0.0, (cell.y + 0.5) * TILE)
		batch.multimesh = multimesh
		batch.material_override = material
		batch.layers |= reflection_layer
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch.visibility_range_end = 39.0
		batch.extra_cull_margin = 0.38
		add_child(batch)
