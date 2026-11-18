extends SceneTree

func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file("res://source.glb", state) != OK:
		push_error("Could not load the Poly Haven wood geometry")
		quit(1)
		return

	var mesh: ImporterMesh = state.get_meshes()[0].mesh
	mesh.generate_lods(25, 70, [])
	var output := FileAccess.open("res://wood-lods.bin", FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	for surface in mesh.get_surface_count():
		var arrays := mesh.get_surface_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		output.store_32(positions.size())
		output.store_buffer(positions.to_byte_array())
		output.store_buffer(normals.to_byte_array())
		output.store_buffer(uvs.to_byte_array())
		var budgets := [1500, 650] if surface == 0 else [650, 450]
		for budget: int in budgets:
			var indices := _pick_lod(mesh, surface, budget)
			output.store_32(indices.size())
			# Godot uses clockwise front faces. glTF uses counterclockwise.
			for face in range(0, indices.size(), 3):
				output.store_32(indices[face])
				output.store_32(indices[face + 2])
				output.store_32(indices[face + 1])
	output.close()
	quit()

func _pick_lod(mesh: ImporterMesh, surface: int, triangle_budget: int) -> PackedInt32Array:
	var best := PackedInt32Array()
	for lod in mesh.get_surface_lod_count(surface):
		var indices := mesh.get_surface_lod_indices(surface, lod)
		if best.is_empty() or abs(indices.size() - triangle_budget * 3) < abs(best.size() - triangle_budget * 3):
			best = indices
	return best
