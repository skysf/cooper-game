extends SceneTree

const Terrain = preload("res://terrain.gd")
const Atmosphere = preload("res://atmosphere.gd")
const Lake = preload("res://lake_layout.gd")
const Coast = preload("res://coast_layout.gd")

var view := SubViewport.new()
var terrain := Terrain.new()
var atmosphere := Atmosphere.new()
var camera := Camera3D.new()
var folder := ""
var terrain_meshes: Array[MeshInstance3D] = []
var stones: Array[MultiMeshInstance3D] = []
var stone_sources: Dictionary[MultiMeshInstance3D, ShaderMaterial] = {}
var ocean: MeshInstance3D
var report := {}
var valid := true

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		quit(2)
		return
	folder = args[0]
	view.size = Vector2i(1280,720)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(atmosphere)
	view.add_child(terrain)
	terrain.set_process(false)
	view.add_child(camera)
	camera.near = .07
	camera.far = 290.0
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 78.0
	camera.make_current()
	fixed_camera()
	for mesh: MeshInstance3D in terrain.coast.find_children("*","MeshInstance3D",true,false):
		if mesh.material_override == terrain.coast.rock_shader:
			terrain_meshes.append(mesh)
		elif mesh.material_override == terrain.coast.ocean_shader:
			ocean = mesh
	for batch: MultiMeshInstance3D in terrain.coast.find_children("*","MultiMeshInstance3D",true,false):
		if batch.material_override is ShaderMaterial and batch.material_override.shader == terrain.coast.rock_shader.shader and batch.material_override.get_shader_parameter("solid_stone") == true:
			stones.append(batch)
			stone_sources[batch] = batch.material_override
	check(not terrain_meshes.is_empty() and not stones.is_empty() and ocean != null, "Live coastal terrain, ocean and stone batches loaded")
	report["actual_terrain_batches"] = terrain_meshes.size()
	report["actual_boulder_batches"] = stones.size()
	report["eye"] = [camera.position.x,camera.position.y,camera.position.z]
	report["camera_turn"] = [camera.rotation.y,camera.rotation.x]
	set_climate(90.466600,1.0)
	var original := args[1].path_join("original.gdshader")
	var reference := FileAccess.file_exists(original)
	if reference:
		apply_material(make_variant(original),true)
	await shot("baseline-rain",21)
	atmosphere.rain.hide()
	await shot("baseline",8)
	if FileAccess.file_exists(args[1].path_join("no-sand.gdshader")):
		for rock in stones:
			rock.hide()
		await shot("no-boulders",6)
		for rock in stones:
			rock.show()
		ocean.hide()
		await shot("no-water",6)
		ocean.show()
		for name: String in ["no-sand","no-flat-layers","facet-projection","layers-probe"]:
			apply_material(make_variant(args[1].path_join(name+".gdshader")))
			ocean.visible = name != "layers-probe"
			await shot(name,8)
		ocean.show()
	var variant := args[1].path_join("candidate.gdshader")
	var selected := FileAccess.file_exists(variant)
	if selected or reference:
		var revised := make_variant(variant) if selected else terrain.coast.rock_shader
		apply_material(revised,true)
		await shot("candidate",12)
		atmosphere.rain.show()
		await shot("candidate-rain",8)
		atmosphere.rain.hide()
		set_climate(24.0,0.0)
		apply_material(make_variant(original) if reference else terrain.coast.rock_shader, reference)
		await shot("baseline-clear",8)
		apply_material(make_variant(variant) if selected else terrain.coast.rock_shader,true)
		await shot("candidate-clear",8)
		# The calm walkable shelf and sea foam use the same terrain and water assets.
		camera.position = Vector3(-83.38,Coast.height(Vector2(-83.38,-51.2))+1.67,-51.2)
		camera.look_at(Vector3(-89.8,.05,-52.4))
		set_climate(24.0,0.0)
		apply_material(make_variant(original) if reference else terrain.coast.rock_shader, reference)
		await shot("beach-before",8)
		apply_material(make_variant(variant) if selected else terrain.coast.rock_shader,true)
		await shot("beach-after",8)
	print("COAST_CLIFF_QA " + JSON.stringify(report))
	quit(0 if valid else 4)

func fixed_camera() -> void:
	var at := Vector2(-85.1,-51.0)
	camera.position = Vector3(at.x,Coast.height(at)+1.67,at.y)
	camera.rotation = Vector3(-.34075,1.4809,0.0)
	terrain.update_focus(camera.position)

func set_climate(elapsed: float, rain: float) -> void:
	var at := camera.position
	var depth := Lake.surface_height(Vector2(at.x,at.z))-at.y
	atmosphere.update_weather(at,elapsed,rain,false,false,depth,1.0)
	terrain.set_wet(rain)
	terrain.update_water(elapsed,rain,{
		"sun_direction":atmosphere.sun_direction,"moon_direction":atmosphere.moon_direction,
		"sun_energy":atmosphere.sun_energy,"sky_zenith":atmosphere.sky_zenith,"sky_horizon":atmosphere.sky_horizon,
		"sun_color":atmosphere.sun_color,"moon_color":atmosphere.moon_color,"cloud_cover":atmosphere.cloud_cover,
		"twilight":atmosphere.twilight,"evening_weight":atmosphere.evening_weight,"underwater":atmosphere.underwater})

func make_variant(path: String, source: ShaderMaterial = null) -> ShaderMaterial:
	if source == null:
		source = terrain.coast.rock_shader
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string(path)
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	for uniform in source.shader.get_shader_uniform_list():
		var param: Variant = source.get_shader_parameter(uniform.name)
		if param != null:
			shader_material.set_shader_parameter(uniform.name,param)
	return shader_material

func apply_material(material: ShaderMaterial, test_boulders := false) -> void:
	for mesh in terrain_meshes:
		mesh.material_override = material
	var replacements := {}
	for batch in stones:
		var original: ShaderMaterial = stone_sources[batch]
		if not test_boulders:
			batch.material_override = original
			continue
		if not replacements.has(original):
			var recolored := ShaderMaterial.new()
			recolored.shader = material.shader
			for uniform in original.shader.get_shader_uniform_list():
				var param: Variant = original.get_shader_parameter(uniform.name)
				if param != null:
					recolored.set_shader_parameter(uniform.name,param)
			replacements[original] = recolored
		batch.material_override = replacements[original]

func shot(name: String, frames: int) -> void:
	for frame in frames:
		await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	check(image != null and image.save_png(folder.path_join(name+".png")) == OK,"Saved " + name)

func check(ok: bool, text: String) -> void:
	if not ok:
		valid = false
		push_error(text)
