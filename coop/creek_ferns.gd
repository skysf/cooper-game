extends Node3D

const Layout = preload("res://lake_layout.gd")
const MODEL = preload("res://vegetation/creek_ostrich_fern.glb")
const FERN_SHADER = preload("res://vegetation/creek_ostrich_fern.gdshader")
const DISTANCES := Vector4(8.0, 11.5, 22.0, 29.0)
const TILE := 6.0

var materials: Array[ShaderMaterial] = []

func build(reflection_layer: int) -> void:
	var planting: Array = Layout.layout.get("lakesideVegetation", {}).get("ostrichFern", [])
	if planting.is_empty():
		return
	var model := MODEL.instantiate()
	var parts := {}
	for piece: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		parts[piece.name] = piece.mesh
	var reference: ArrayMesh = parts[&"FernMatureNear"]
	var source := reference.surface_get_material(0) as StandardMaterial3D
	model.free()
	for near: bool in [true, false]:
		var material := ShaderMaterial.new()
		material.shader = FERN_SHADER
		material.set_shader_parameter("fern_atlas", source.albedo_texture)
		material.set_shader_parameter("near_mesh", near)
		material.set_shader_parameter("distances", DISTANCES)
		materials.append(material)

	var cells := {}
	# Each row stores x, z, scale, yaw, growth stage and the measured render height.
	for plant: Array in planting:
		var location := Vector2(plant[0], plant[1])
		if is_finite(Layout.surface_height(location)) or Layout.on_dock(location):
			continue
		var cell := Vector3i(floori(location.x / TILE), floori(location.y / TILE), 0 if plant[4] == "mature" else 1)
		if not cells.has(cell):
			cells[cell] = []
		var basis := Basis(Vector3.UP, float(plant[3])).scaled_local(Vector3.ONE * float(plant[2]))
		# Match the surveyed render mesh at a shallow creek bank, where the visible
		# triangle surface between samples differs slightly from the analytic slope.
		cells[cell].append(Transform3D(basis, Vector3(location.x, float(plant[5]) - 0.004, location.y)))

	for cell: Vector3i in cells:
		var growth := "Mature" if cell.z == 0 else "Young"
		var poses: Array = cells[cell]
		var center := Vector3.ZERO
		for pose: Transform3D in poses:
			center += pose.origin
		center /= poses.size()
		for i in materials.size():
			var kind := "Near" if i == 0 else "Far"
			var mesh: Mesh = parts[StringName("Fern" + growth + kind)]
			var label := "%s%s_%d_%d" % [growth, kind, -cell.x, -cell.y]
			_batch(label, mesh, center, poses, i, reflection_layer)

func set_wind(elapsed: float, wind: Vector4, rain: float) -> void:
	for material in materials:
		material.set_shader_parameter("wind_time", elapsed)
		material.set_shader_parameter("wind_field", wind)
		material.set_shader_parameter("rain", rain)

func _batch(label: String, mesh: Mesh, center: Vector3, poses: Array, role: int, reflection_layer: int) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = poses.size()
	var radius := 0.0
	for i in poses.size():
		var pose: Transform3D = poses[i]
		pose.origin -= center
		multi.set_instance_transform(i, pose)
		radius = maxf(radius, pose.origin.length())
	var batch := MultiMeshInstance3D.new()
	batch.name = label
	batch.position = center
	batch.multimesh = multi
	batch.material_override = materials[role]
	batch.layers |= reflection_layer
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.extra_cull_margin = 0.13
	# The GPU blends the exact root ranges. Expand the CPU culling by the
	# batch radius and the model height so it never cuts that overlap short.
	batch.visibility_range_begin = 0.0 if role == 0 else maxf(0.0, DISTANCES.x - radius - 1.25)
	batch.visibility_range_end = (DISTANCES.y if role == 0 else DISTANCES.w) + radius + 1.25
	add_child(batch)
