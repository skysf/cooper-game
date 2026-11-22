extends Node3D

const Land = preload("res://east/land.gd")
const Lake = preload("res://lake_layout.gd")
const FieldPlants = preload("res://vegetation/photo_landscapes/field_plants.gd")
const WindField = preload("res://vegetation/wind_field.gd")
const FLOOR = preload("res://east/terrain.glb")
const GROUND = preload("res://east/ground.gdshader")
const LEAVES = preload("res://east/foliage.gdshader")
const GROUND_DEPTH := {"bank_roots":.14,"tangled_roots":.17,"litter":.018,"fallen_trunk":.12,"old_stump":.11,"dry_branch":.045}
const CELL := 20.0
const COVER_CELL := 14.0
const COVER_SWITCH := 20.0
var cover_tiles := {}
var close_tiles := {}
var specimens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://east/cover_specimens.json"))
var available_meshes := {}
var last_tile := Vector2i(100000,100000)
var focus := Vector3.ZERO
var packs := {}
var counts := {}
var plants: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://east/plants.json"))
var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://east/model_catalog.json"))
var root_rims: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://east/root_contacts.json"))
var vine_material := FieldPlants.material(.045)
var floor_mat := ShaderMaterial.new()
var portal_materials: Dictionary = {}
var springs_and_slopes: Array[ShaderMaterial] = []
var spring_mat := ShaderMaterial.new()
var leaves: Array[ShaderMaterial] = []
var cover: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://east/cover.json"))

func _ready() -> void:
	floor_mat.shader = GROUND
	for kind: String in ["vine_drape","vine_scramble","leaf_mantle"]:
		counts[kind] = plants[kind].size()
		var cells := _cells(kind,12.0)
		for cell: Vector2i in cells:
			var poses := []
			for p: Array in cells[cell]:
				var basis := Basis(Vector3.UP,p[3]).scaled(Vector3.ONE * float(p[4]))
				poses.append(Transform3D(basis,Vector3(p[0],p[1],p[2])))
			FieldPlants.batch(self,kind,poses,vine_material,86.0)
	for surface in ["loam","gravel","sand"]:
		for channel in ["color","normal"]:
			var param: String = surface if channel=="color" else surface+"_normal"
			floor_mat.set_shader_parameter(param,load("res://east/maps/%s_%s.jpg" % [surface,channel]))
	floor_mat.set_shader_parameter("litter_normal",preload("res://east/maps/litter_normal.jpg"))
	floor_mat.set_shader_parameter("litter",preload("res://east/maps/litter_color.jpg"))
	floor_mat.set_shader_parameter("camp_soil",preload("res://textures/forest_floor_diff.jpg"))
	floor_mat.set_shader_parameter("camp_normal",preload("res://textures/forest_floor_nor_gl.jpg"))
	floor_mat.set_shader_parameter("camp_arm",preload("res://textures/forest_floor_arm.jpg"))
	spring_mat.shader = preload("res://east/spring_water.gdshader")
	spring_mat.set_shader_parameter("ripple",preload("res://textures/lake_ripples.png"))
	floor_mat.set_shader_parameter("mine_gravel",preload("res://textures/lake_gravel_diff.jpg"))
	floor_mat.set_shader_parameter("mine_normal",preload("res://textures/lake_gravel_nor_gl.jpg"))
	# Ordinary slope tiles have no gallery or horizon UVs, so their rock sampler
	# can carry the photographed shale without another WebGL texture unit.
	var slope_material := floor_mat.duplicate() as ShaderMaterial
	slope_material.set_shader_parameter("mine_gravel",preload("res://vegetation/photo_landscapes/rose_shale.jpg"))
	springs_and_slopes.append(slope_material)
	springs_and_slopes.append(floor_mat)
	for id: String in Land.region.camps:
		var site: Dictionary = Land.region.camps[id]
		var material := floor_mat.duplicate() as ShaderMaterial
		material.set_shader_parameter("portal_origin",Vector2(site.origin[0],site.origin[2]))
		material.set_shader_parameter("portal_sign",cos(site.yaw))
		portal_materials["portal_ground_"+id] = material
		springs_and_slopes.append(material)
	var slopes := FLOOR.instantiate()
	add_child(slopes)
	for tile: MeshInstance3D in slopes.find_children("*","MeshInstance3D",true,false):
		tile.material_override = spring_mat if String(tile.name).begins_with("spring_water_") else portal_materials.get(String(tile.name),floor_mat)
		if String(tile.name).begins_with("slope_"):
			tile.material_override = slope_material
		tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for key: String in cover:
		var row: Dictionary = cover[key]
		var leaf := ShaderMaterial.new()
		leaf.shader = preload("res://east/cover.gdshader")
		leaf.set_shader_parameter("pigment",load("res://east/maps/"+key+".png"))
		leaves.append(leaf)
		var mesh := _cover_mesh(float(row.span),float(row.height),leaf)
		var cells := _cells(key,COVER_CELL)
		for cell: Vector2i in cells:
			if not cover_tiles.has(cell):
				cover_tiles[cell] = {}
			cover_tiles[cell][key] = cells[cell]
			_batch(mesh,cell,cells[cell],COVER_SWITCH,55.0 if row.span>2.6 else 46.0,0,COVER_CELL)
		counts[key]=plants[key].size()

func _cover_mesh(span: float, height: float, material: Material) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	for k in 3:
		var turn := Basis(Vector3.UP,k*PI/3.0)
		# Three camera projections preserve the shape of the clump as the viewer passes it.
		for index in [0,1,2,0,2,3]:
			var u := 1.0 if index in [1,2] else 0.0
			var v := 1.0 if index in [0,1] else 0.0
			surface.set_uv(Vector2((k+lerpf(.001,.999,u))/3.0,v))
			surface.set_normal(Vector3.UP)
			surface.add_vertex(turn*Vector3((u-.5)*span,(.82-v)*height,.08*(1-v)))
	surface.generate_tangents()
	return surface.commit()

func _cells(key: String, width := CELL) -> Dictionary:
	var cells := {}
	for p: Array in plants[key]:
		var cell := Vector2i(floori(p[0]/width),floori(p[2]/width))
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(p)
	return cells

func needed(at: Vector3) -> String:
	var near_wooded_bench := at.x > 260 and at.x < 356 and at.z > -92 and at.z < -6
	if ((at.x > -68 and at.x < 188) or near_wooded_bench) and not packs.has("verdant"):
		return "verdant"
	if (at.x > 107 or at.x < -45) and not packs.has("namaqua"):
		return "namaqua"
	return ""

func install(id: String, source: Node) -> void:
	var meshes := {}
	for plant: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		meshes[String(plant.name)] = plant.mesh
	var shared_leaves := {}
	for key: String in catalog:
		if catalog[key].pack != id or not meshes.has(key):
			continue
		var height: float = catalog[key].height
		for mesh_key: String in [key,key+"_far"]:
			if not meshes.has(mesh_key):
				continue
			var mesh: Mesh = meshes[mesh_key]
			for surface in mesh.get_surface_count():
				var mat := mesh.surface_get_material(surface) as StandardMaterial3D
				if mat == null or mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
					continue
				var cache_key := String(mat.resource_name)+"_"+key
				if not shared_leaves.has(cache_key):
					var leaf := ShaderMaterial.new()
					leaf.shader = LEAVES
					leaf.set_shader_parameter("pigment",mat.albedo_texture)
					leaf.set_shader_parameter("relief",mat.normal_texture)
					leaf.set_shader_parameter("plant_height",height)
					leaf.set_shader_parameter("flexibility",clampf(height*.065,.018,.19))
					shared_leaves[cache_key] = leaf
					leaves.append(leaf)
				mesh.surface_set_material(surface,shared_leaves[cache_key])
		var cells := _cells(key)
		var far_end := 139.0 if height > 3.5 else 78.0
		if key in ["granite_tor", "rock_shelf", "weathered_rock"]:
			far_end = 270.0
		elif key in ["quiver_tree", "fork_tree"]:
			far_end = 195.0
		for cell: Vector2i in cells:
			var group: Array = cells[cell]
			var far_mesh: Mesh = meshes.get(key+"_far")
			var seam := 32.0 if height > 3.5 else 24.0
			_batch(meshes[key],cell,group,0,seam if far_mesh else (44.0 if height<.8 else 60.0),height,CELL,null,key)
			if far_mesh:
				_batch(far_mesh,cell,group,seam-.4,far_end,height,CELL,null,key)
		counts[key] = plants[key].size()
	available_meshes.merge(meshes)
	packs[id] = true
	for node: Node in close_tiles.values():
		node.queue_free()
	close_tiles.clear()
	update_focus(focus,true)
	source.free()

func plant_pose(kind: String, p: Array) -> Transform3D:
	var soil_depth := float(GROUND_DEPTH.get(kind,0.0))
	var orientation := Basis(Vector3.UP,float(p[3]))
	var position := Vector3(p[0],p[1],p[2])
	if soil_depth>0.0:
		# A scan of a root mat includes a thin soil skirt. Bury that skirt parallel to the bank.
		var ground := Vector2(position.x,position.z)
		var rise_x := Lake.ground_height(ground+Vector2(.28,0))-Lake.ground_height(ground-Vector2(.28,0))
		var rise_z := Lake.ground_height(ground+Vector2(0,.28))-Lake.ground_height(ground-Vector2(0,.28))
		var up := Vector3(-rise_x,.56,-rise_z).normalized()
		var right := up.cross(orientation.z).normalized()
		orientation = Basis(right,up,right.cross(up))
		if kind in ["bank_roots","tangled_roots","old_stump"]:
			# Fit the entire scanned apron, including its downhill edge, to the real bank.
			var base_y := INF
			for v: Array in root_rims[kind]:
				var offset := orientation*Vector3(v[0],v[1],v[2])*float(p[4])
				base_y = minf(base_y,Lake.ground_height(ground+Vector2(offset.x,offset.z))-offset.y)
			position.y = base_y-.038
		else:
			position.y -= soil_depth*float(p[4])
	return Transform3D(orientation.scaled(Vector3.ONE*float(p[4])),position)

func _batch(mesh: Mesh, cell: Vector2i, group: Array, near: float, far_limit: float, height: float, width := CELL, parent: Node3D = null, kind := "") -> void:
	var field := MultiMesh.new()
	field.transform_format = MultiMesh.TRANSFORM_3D
	field.mesh = mesh
	field.instance_count = group.size()
	var base := Vector3((cell.x+.5)*width,0,(cell.y+.5)*width)
	for i in group.size():
		var pose := plant_pose(kind,group[i])
		pose.origin -= base
		field.set_instance_transform(i,pose)
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = field
	batch.position = base
	batch.visibility_range_begin = near
	batch.visibility_range_end = far_limit
	batch.visibility_range_begin_margin = 1.6
	batch.visibility_range_end_margin = 1.6
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near==0 and height>=1.05 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(batch)

func update_focus(at: Vector3, rebuild := false) -> void:
	focus = at
	var cell := Vector2i(floori(at.x/COVER_CELL),floori(at.z/COVER_CELL))
	if cell==last_tile and not rebuild:
		return
	last_tile = cell
	for old: Vector2i in close_tiles.keys():
		if (old-cell).abs().x>3 or (old-cell).abs().y>3:
			close_tiles[old].queue_free()
			close_tiles.erase(old)
	for dx in range(-3,4):
		for dz in range(-3,4):
			var next := cell+Vector2i(dx,dz)
			if cover_tiles.has(next) and not close_tiles.has(next):
				_close_cover(next)

func _close_cover(cell: Vector2i) -> void:
	var group := Node3D.new()
	add_child(group)
	close_tiles[cell] = group
	var batches := {}
	for key: String in cover_tiles[cell]:
		var members: Array = specimens[key]
		# Represent each clump with intact source plants nearby and a photo of the complete clump beyond.
		var stride := maxi(1,ceili(members.size()/8.0))
		for p: Array in cover_tiles[cell][key]:
			for i in range(0,members.size(),stride):
				var sample: Array = members[i]
				var kind: String = sample[0]
				if not available_meshes.has(kind):
					continue
				var offset := Vector2(sample[1],sample[2]).rotated(-float(p[3]))*float(p[4])
				var x := float(p[0])+offset.x
				var z := float(p[2])+offset.y
				var soil := Lake.ground_height(Vector2(x,z))
				if Land.Rocks.top(Vector2(x,z))>soil+.02 or is_finite(Land.water_height(Vector2(x,z))):
					continue
				var y := soil-.018
				if not batches.has(kind):
					batches[kind] = []
				batches[kind].append([x,y,z,float(p[3])+float(sample[3]),float(p[4])*float(sample[4])])
	for kind: String in batches:
		_batch(available_meshes[kind],cell,batches[kind],0,COVER_SWITCH+.6,0,COVER_CELL,group)

func weather(seconds: float, rain: float, lighting: Dictionary = {}) -> void:
	FieldPlants.set_wind(vine_material,seconds,WindField.sample(seconds,rain),rain)
	for soil in springs_and_slopes:
		soil.set_shader_parameter("wetness",rain)
	spring_mat.set_shader_parameter("rain",rain)
	spring_mat.set_shader_parameter("water_time",seconds)
	for key: String in ["sky_horizon","sky_zenith","sun_direction","sun_color","cloud_cover"]:
		if lighting.has(key):
			spring_mat.set_shader_parameter(key,lighting[key])
	for leaf in leaves:
		leaf.set_shader_parameter("room_seconds",seconds)
		leaf.set_shader_parameter("wind_strength",.85+rain*.8)
