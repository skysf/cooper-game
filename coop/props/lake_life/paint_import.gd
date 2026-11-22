@tool
extends EditorScenePostImport

# glTF COLOR_0 is linear. Compatibility shades in sRGB, including on the web.
# Encode just the three paint bytes, keeping the imported skins, tangents and LODs.
func _post_import(scene: Node) -> Object:
	var srgb := PackedByteArray()
	srgb.resize(256)
	for value in 256:
		srgb[value] = roundi(Color(float(value)/255.0,0.0,0.0).linear_to_srgb().r*255.0)
	for instance: MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
		var mesh := instance.mesh as ArrayMesh
		var surfaces: Array = mesh.get("_surfaces")
		for surface: Dictionary in surfaces:
			var material := surface.material as BaseMaterial3D
			if material == null or not (int(surface.format) & Mesh.ARRAY_FORMAT_COLOR):
				continue
			var count: int = surface.vertex_count
			var offset := RenderingServer.mesh_surface_get_format_offset(surface.format,count,Mesh.ARRAY_COLOR)
			var stride := RenderingServer.mesh_surface_get_format_attribute_stride(surface.format,count)
			var data: PackedByteArray = surface.attribute_data
			for vertex in count:
				var index := vertex*stride + offset
				for channel in 3:
					data[index+channel] = srgb[data[index+channel]]
			surface.attribute_data = data
			material.vertex_color_use_as_albedo = true
			material.vertex_color_is_srgb = true
		mesh.clear_surfaces()
		mesh.set("_surfaces",surfaces)
	return scene
