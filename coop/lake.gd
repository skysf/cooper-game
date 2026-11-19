extends Node3D

const Layout = preload("res://lake_layout.gd")
const LakeBed = preload("res://lake_bed.gd")
const WATER_SHADER = preload("res://materials/water.gdshader")
const EVENING_SKY := preload("res://textures/evening_sky.jpg")
const CANOPY_SHADER = preload("res://materials/lake_canopy.gdshader")
const CANOPY = preload("res://textures/lake_canopy.png")
const BANK_FLOOR = preload("res://textures/forest_floor_diff.jpg")
const SHORE_BOULDER = preload("res://props/shore_boulder.glb")
const REFLECTION_LAYER := 1 << 8
const IMPACT_COUNT := 6
const DROPS_PER_IMPACT := 9
const REFLECTION_DISTANCE := 38.0
const REFLECTION_MOVING_INTERVAL := 0.064
const REFLECTION_STILL_INTERVAL := 0.66
const WATER_PARAMETERS := ["sun_direction", "moon_direction", "sky_zenith", "sky_horizon",
	"sun_color", "moon_color", "cloud_cover", "twilight", "evening_weight", "underwater"]

var lake_material := ShaderMaterial.new()
var creek_material := ShaderMaterial.new()
var bed := LakeBed.new()
var reflection := SubViewport.new()
var reflection_camera := Camera3D.new()
var reflection_updated_at := -1.0
var reflection_enabled := false
var reflection_viewer := Transform3D.IDENTITY
var reflection_fov := -1.0
var latest_impact_at := -INF
var impacts := PackedVector4Array()
var next_impact := 0
var splash_mesh := MultiMeshInstance3D.new()
var splash_material := StandardMaterial3D.new()
var splash_offsets := PackedVector3Array()
var timber: StandardMaterial3D
var rock: StandardMaterial3D
var boulder_material: StandardMaterial3D

func configure(wood_material: StandardMaterial3D, rock_material: StandardMaterial3D) -> void:
	timber = wood_material
	rock = rock_material

func _ready() -> void:
	impacts.resize(IMPACT_COUNT)
	var current_field := FastNoiseLite.new()
	current_field.seed = 61039
	current_field.frequency = 0.046
	current_field.fractal_octaves = 2
	var current_texture := NoiseTexture2D.new()
	current_texture.width = 128
	current_texture.height = 128
	current_texture.seamless = true
	current_texture.as_normal_map = true
	current_texture.bump_strength = 3.6
	current_texture.noise = current_field
	for material in [lake_material, creek_material]:
		material.shader = WATER_SHADER
		material.set_shader_parameter("wave_current", current_texture)
		material.set_shader_parameter("ripple_field", LakeBed.RIPPLE_FIELD)
		material.set_shader_parameter("bed_gravel", LakeBed.GRAVEL)
		material.set_shader_parameter("evening_sky", EVENING_SKY)
		material.set_shader_parameter("lake_center", Layout.center())
		material.set_shader_parameter("lake_radius", Layout.radius())
		material.set_shader_parameter("impacts", impacts)
	lake_material.set_shader_parameter("lake_surface", true)
	add_child(bed)
	_build_lake()
	_build_creek()
	_build_dock()
	_build_far_shore()
	_build_boulders()
	_build_reeds()
	_build_splashes()
	_build_reflection()

func set_bank_wet(wet: float) -> void:
	boulder_material.roughness = lerpf(1.0, 0.62, wet)
	boulder_material.albedo_color = Color.WHITE.lerp(Color("#c9ccd0"), wet)

func update_water(elapsed: float, rain: float, lighting: Dictionary) -> void:
	bed.light_bed(elapsed, lighting.get("sun_direction", Vector3.UP), lighting.get("cloud_cover", 0.3))
	bed.motes.visible = lighting.get("underwater", false)
	for material in [lake_material, creek_material]:
		material.set_shader_parameter("water_time", elapsed)
		material.set_shader_parameter("rain_amount", rain)
		for parameter in WATER_PARAMETERS:
			if lighting.has(parameter):
				material.set_shader_parameter(parameter, lighting[parameter])
	if latest_impact_at > -INF and elapsed - latest_impact_at >= 2.9:
		latest_impact_at = -INF
		_set_impact_active(false)
	_update_reflection(elapsed)
	_update_splashes(elapsed, lighting.get("sky_zenith", Color.WHITE))

func add_impact(point: Vector3, elapsed: float) -> void:
	var location := Vector2(point.x, point.z)
	if not is_finite(Layout.surface_height(location)):
		return
	if latest_impact_at == -INF:
		_set_impact_active(true)
	latest_impact_at = maxf(latest_impact_at, elapsed)
	impacts[next_impact] = Vector4(location.x, location.y, elapsed, 1.0)
	next_impact = (next_impact + 1) % IMPACT_COUNT
	_update_impact_materials()

func reset_water() -> void:
	impacts.fill(Vector4.ZERO)
	next_impact = 0
	reflection_updated_at = -1.0
	latest_impact_at = -INF
	_set_impact_active(false)
	_update_impact_materials()
	splash_mesh.visible = false

func _update_impact_materials() -> void:
	lake_material.set_shader_parameter("impacts", impacts)
	creek_material.set_shader_parameter("impacts", impacts)

func _set_impact_active(active: bool) -> void:
	lake_material.set_shader_parameter("active_impacts", active)
	creek_material.set_shader_parameter("active_impacts", active)

func _build_lake() -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.set_material(lake_material)
	var center := Layout.center()
	for segment in 112:
		var first := Layout.shore_at(TAU * segment / 112.0)
		var second := Layout.shore_at(TAU * (segment + 1) / 112.0)
		for point in [center, first, second]:
			mesh.set_normal(Vector3.UP)
			mesh.set_uv2(Vector2(maxf(0.0, Layout.water_y() - Layout.ground_height(point)), 0.0))
			mesh.add_vertex(Vector3(point.x, Layout.water_y(), point.y))
	_add_mesh(mesh.commit(), Vector3.ZERO).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_creek() -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.set_material(creek_material)
	var config: Dictionary = Layout.layout.creek
	var edges := PackedVector3Array()
	for i in int(config.steps) + 1:
		var z := float(config.firstZ) + i * float(config.spacing)
		var sample := Layout.creek_sample(i)
		edges.append(Vector3(sample.x - sample.y, Layout.water_y(), z))
		edges.append(Vector3(sample.x + sample.y, Layout.water_y(), z))
		if i == 0:
			continue
		var previous := (i - 1) * 2
		for offset in [0, 1, 2, 1, 3, 2]:
			mesh.set_normal(Vector3.UP)
			mesh.set_uv2(Vector2(0.17, 0.0))
			mesh.add_vertex(edges[previous + offset])
	_add_mesh(mesh.commit(), Vector3.ZERO).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_dock() -> void:
	var dock: Dictionary = Layout.layout.dock
	var lo := float(dock.west)
	var hi := float(dock.east)
	var z := float(dock.z)
	var half_width := float(dock.halfWidth)
	var board := BoxMesh.new()
	board.size = Vector3(0.23, 0.058, 1.0)
	var plank_material: StandardMaterial3D = timber.duplicate()
	plank_material.vertex_color_use_as_albedo = true
	board.material = plank_material
	var planks := MultiMesh.new()
	planks.transform_format = MultiMesh.TRANSFORM_3D
	planks.use_colors = true
	planks.mesh = board
	planks.instance_count = 17
	var rng := RandomNumberGenerator.new()
	rng.seed = 5242
	for i in planks.instance_count:
		var x := lerpf(lo + 0.125, hi - 0.125, i / float(planks.instance_count - 1))
		var basis := Basis(Vector3.UP, rng.randf_range(-0.026, 0.026)).scaled(Vector3(1.0, 1.0, half_width * 2.0 + rng.randf_range(-0.055, 0.08)))
		planks.set_instance_transform(i, Transform3D(basis, Vector3(x, rng.randf_range(0.076, 0.092), z + rng.randf_range(-0.045, 0.045))))
		var patina := rng.randf_range(0.63, 0.96)
		planks.set_instance_color(i, Color(patina, patina * 0.96, patina * 0.87))
	_add_multimesh(planks)
	for edge in [-0.61, 0.61]:
		var joist := BoxMesh.new()
		joist.size = Vector3(hi - lo, 0.11, 0.12)
		joist.material = timber
		_add_mesh(joist, Vector3((hi + lo) * 0.5, 0.006, z + edge))
		for x in [lo + 0.3, (hi + lo) * 0.5, hi - 0.28]:
			var beam := CylinderMesh.new()
			beam.material = timber
			beam.radial_segments = 8
			beam.rings = 1
			beam.top_radius = 0.064
			beam.bottom_radius = 0.087
			var base := Layout.ground_height(Vector2(x, z + edge)) - 0.07
			beam.height = maxf(0.23, 0.036 - base)
			var support := _add_mesh(beam, Vector3(x, 0.036 - beam.height * 0.5, z + edge))
			support.rotation.z = rng.randf_range(-0.038, 0.038)

func _build_far_shore() -> void:
	var canopy := ShaderMaterial.new()
	canopy.shader = CANOPY_SHADER
	canopy.set_shader_parameter("canopy_atlas", CANOPY)
	var card := QuadMesh.new()
	card.material = canopy
	card.size = Vector2.ONE
	var trees := MultiMesh.new()
	trees.transform_format = MultiMesh.TRANSFORM_3D
	trees.use_custom_data = true
	trees.mesh = card
	trees.instance_count = 135
	var rng := RandomNumberGenerator.new()
	rng.seed = 9317
	var widths := [0.55, 0.61, 0.88, 0.55]
	var shade_roots := PackedVector3Array()
	for stand in 15:
		var center_angle := lerpf(1.68, 4.62, stand / 14.0) + rng.randf_range(-0.066, 0.066)
		var pioneer := sin(center_angle * 5.1) > 0.0
		for stem in 7:
			var angle := center_angle + rng.randfn(0.0, 0.095)
			var distance := rng.randf_range(1.27, 1.81) if stem < 5 else rng.randf_range(1.04, 1.26)
			var point := Layout.shore_at(angle, distance)
			var species := rng.randi_range(0, 3)
			if pioneer and stem >= 4:
				species = 2
			var height := rng.randf_range(4.3, 10.8) if stem < 5 else rng.randf_range(1.4, 5.6)
			var scale := Vector3(height * float(widths[species]) * rng.randf_range(0.91, 1.18), height, 1.0)
			var y := _far_bank_height(angle, distance, point) + height * 0.5 - height * 0.028
			var index := stand * 7 + stem
			trees.set_instance_transform(index, Transform3D(Basis().scaled(scale), Vector3(point.x, y, point.y)))
			trees.set_instance_custom_data(index, Color(species % 2, floori(species / 2.0), rng.randf_range(0.77, 1.0), rng.randi_range(0, 1)))
			shade_roots.append(Vector3(point.x, height * 0.33, point.y))
		# Birch and spruce thickets reach into the wet margin below the canopy.
		for shrub in 2:
			var angle := center_angle + rng.randfn(0.0, 0.085)
			var distance := rng.randf_range(1.044, 1.24)
			var point := Layout.shore_at(angle, distance)
			var h := rng.randf_range(1.05, 2.25)
			var species := 2 if rng.randf() < 0.77 else 1
			var width := h * rng.randf_range(1.35, 2.05)
			var base := Vector3(point.x, _far_bank_height(angle, distance, point) + h * 0.20, point.y)
			var index := 105 + stand * 2 + shrub
			trees.set_instance_transform(index, Transform3D(Basis().scaled(Vector3(width, h, 1.0)), base))
			trees.set_instance_custom_data(index, Color(species % 2, floori(species / 2.0), rng.randf_range(0.52, 0.71), rng.randi_range(0, 1)))
			shade_roots.append(Vector3(point.x, width * 0.53, point.y))
	_far_bank_ground(shade_roots)
	var grove := _add_multimesh(trees)
	grove.layers |= REFLECTION_LAYER
	grove.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var shale := SphereMesh.new()
	shale.material = rock
	shale.radial_segments = 9
	shale.rings = 4
	var stones := MultiMesh.new()
	stones.transform_format = MultiMesh.TRANSFORM_3D
	stones.mesh = shale
	stones.instance_count = 41
	for i in stones.instance_count:
		var angle := (float(i) / stones.instance_count) * TAU
		var location := Layout.shore_at(angle + rng.randf_range(-0.075, 0.075), rng.randf_range(0.993, 1.06))
		var size := rng.randf_range(0.16, 0.60)
		var scale := Vector3(size * rng.randf_range(1.0, 2.0), size * rng.randf_range(0.35, 0.75), size)
		var base := Vector3(location.x, Layout.ground_height(location) + size * 0.10, location.y)
		stones.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(scale), base))
	var bank_stones := _add_multimesh(stones)
	bank_stones.layers |= REFLECTION_LAYER

func _far_bank_height(angle: float, distance: float, point: Vector2) -> float:
	# The bluff rises only beyond the playable western boundary. Its base and
	# each tree root use the same slope, including the trees seen in the mirror.
	var crest := 2.25 + 0.91 * sin(angle * 3.3 - 0.8) + 0.48 * sin(angle * 8.2)
	return Layout.ground_height(point) + smoothstep(29.3, 34.5, -point.x) * smoothstep(1.015, 1.69, distance) \
		* (1.0 - smoothstep(1.89, 2.36, distance)) * crest

func _far_bank_ground(shade_roots: PackedVector3Array) -> void:
	var forest := StandardMaterial3D.new()
	forest.albedo_texture = BANK_FLOOR
	forest.vertex_color_use_as_albedo = true
	forest.roughness = 1.0
	forest.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.set_material(forest)
	var radii := [1.025, 1.09, 1.23, 1.4, 1.61, 1.82, 2.03, 2.37]
	var steps := 82
	for row in radii.size():
		var distance: float = radii[row]
		for i in (steps + 1):
			var angle := lerpf(1.40, 4.91, i / float(steps))
			var point := Layout.shore_at(angle, distance)
			var lift := -0.07 if row == 0 or row == radii.size() - 1 else -0.006
			var y := _far_bank_height(angle, distance, point) + lift
			var inertia := smoothstep(1.06, 1.48, distance)
			var moss := 0.5 + sin(angle * 18.0 + distance * 8.0) * 0.31 + cos(angle * 7.0 - distance * 13.0) * 0.16
			var color := Color("#94916e").lerp(Color("#5f714e"), moss).lerp(Color("#586349"), inertia * 0.40)
			var occlusion := 0.0
			for tree in shade_roots:
				var dx := point.x - tree.x
				var dz := point.y - tree.z
				var relative := (dx * dx + dz * dz) / (tree.y * tree.y)
				occlusion = maxf(occlusion, 1.0 - smoothstep(0.0, 1.0, relative))
			color *= 1.0 - 0.42 * occlusion
			mesh.set_color(color)
			mesh.set_uv(point * 0.44)
			mesh.set_normal(Vector3(-cos(angle) * 0.26 * inertia, 1.0, -sin(angle) * 0.26 * inertia).normalized())
			mesh.add_vertex(Vector3(point.x, y, point.y))
	for row in range(radii.size() - 1):
		for i in steps:
			var a := row * (steps + 1) + i
			var b := a + steps + 1
			for index in [a, b, b + 1, a, b + 1, a + 1]:
				mesh.add_index(index)
	var bank := _add_mesh(mesh.commit(), Vector3.ZERO)
	bank.layers |= REFLECTION_LAYER
	bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_boulders() -> void:
	var template := SHORE_BOULDER.instantiate()
	var model := template as MeshInstance3D
	if model == null:
		model = template.get_child(0) as MeshInstance3D
	var shared_mesh := model.mesh
	boulder_material = shared_mesh.surface_get_material(0).duplicate()
	template.free()
	var bank_boulders := Node3D.new()
	bank_boulders.name = "ShoreBoulders"
	add_child(bank_boulders)
	for config: Dictionary in Layout.layout.boulders:
		var point := Vector2(config.x, config.z)
		var scale := float(config.size)
		var basis := Basis(Vector3.UP, float(config.yaw)).scaled(Vector3.ONE * scale)
		var origin := Vector3(point.x, Layout.ground_height(point) - 0.12 * scale, point.y)
		# Separate bounds keep offscreen boulders out of both cameras while sharing mesh and material.
		var boulder := MeshInstance3D.new()
		boulder.mesh = shared_mesh
		boulder.material_override = boulder_material
		boulder.transform = Transform3D(basis, origin)
		boulder.layers |= REFLECTION_LAYER
		bank_boulders.add_child(boulder)

func _build_reeds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7351
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.set_material(material)
	for i in 12:
		var angle := rng.randf() * TAU
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-direction.z, 0.0, direction.x)
		var h := rng.randf_range(0.28, 0.68)
		var width := rng.randf_range(0.011, 0.023)
		var foot := direction * rng.randf_range(0.018, 0.105)
		var bend := foot + Vector3.UP * h * 0.62 + direction * h * 0.17
		var tip := foot + Vector3.UP * h + direction * h * 0.43
		var base_color := Color("#343f24")
		var middle_color := Color("#596341").lerp(Color("#74704b"), rng.randf())
		var tip_color := middle_color.lerp(Color("#afa377"), 0.30)
		var points := [foot - side * width, foot + side * width, bend - side * width * 0.76,
			bend + side * width * 0.76, tip]
		var colors := [base_color, base_color, middle_color, middle_color, tip_color]
		for vertex in [0, 1, 2, 1, 3, 2, 2, 3, 4]:
			mesh.set_normal(Vector3.UP)
			mesh.set_color(colors[vertex])
			mesh.add_vertex(points[vertex])
	var reeds := MultiMesh.new()
	reeds.transform_format = MultiMesh.TRANSFORM_3D
	reeds.mesh = mesh.commit()
	var positions: Array[Transform3D] = []
	var dock: Dictionary = Layout.layout.dock
	for i in 180:
		var angle := rng.randf_range(-1.57, 1.72)
		var density := 0.46 + sin(angle * 18.0) * 0.37
		if rng.randf() > density:
			continue
		var point := Layout.shore_at(angle, rng.randf_range(0.985, 1.066))
		if point.x > float(dock.west) and absf(point.y - float(dock.z)) < float(dock.halfWidth) + 0.21:
			continue
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.45, 1.25))
		positions.append(Transform3D(basis, Vector3(point.x, Layout.ground_height(point), point.y)))
	reeds.instance_count = positions.size()
	for i in positions.size():
		reeds.set_instance_transform(i, positions[i])
	var marsh := _add_multimesh(reeds)
	marsh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_reflection() -> void:
	reflection.size = Vector2i(400, 225)
	reflection.render_target_update_mode = SubViewport.UPDATE_DISABLED
	reflection.world_3d = get_viewport().find_world_3d()
	add_child(reflection)
	reflection_camera.cull_mask = REFLECTION_LAYER
	reflection_camera.near = 0.08
	reflection_camera.far = 115.0
	reflection.add_child(reflection_camera)
	reflection_camera.make_current()
	lake_material.set_shader_parameter("shore_reflection", reflection.get_texture())

func _update_reflection(elapsed: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var center := Layout.center()
	var viewer := camera.global_transform
	var to_lake := Vector3(center.x, Layout.water_y(), center.y) - viewer.origin
	var viewed := to_lake.length_squared() < REFLECTION_DISTANCE * REFLECTION_DISTANCE
	viewed = viewed and viewer.origin.y > Layout.water_y() - 0.025 and to_lake.dot(-viewer.basis.z) > -4.5
	if viewed != reflection_enabled:
		reflection_enabled = viewed
		lake_material.set_shader_parameter("reflection_strength", 0.88 if viewed else 0.0)
	if not viewed:
		reflection_updated_at = -1.0
		return
	# The reflected geometry is static. Refresh quickly when the camera moves and
	# keep the existing image between changes in the room's sky at a steady view.
	var moved := viewer.origin.distance_squared_to(reflection_viewer.origin) > 0.035 * 0.035 \
		or viewer.basis.z.dot(reflection_viewer.basis.z) < 0.99997 or absf(camera.fov - reflection_fov) > 0.10
	var interval := REFLECTION_MOVING_INTERVAL if moved else REFLECTION_STILL_INTERVAL
	var target_size := get_viewport().get_visible_rect().size
	var width := clampi(roundi(225.0 * target_size.x / maxf(target_size.y, 1.0)), 180, 600)
	if reflection_updated_at >= 0.0 and elapsed >= reflection_updated_at and elapsed - reflection_updated_at < interval \
			and reflection.size.x == width:
		return
	reflection_updated_at = elapsed
	reflection_viewer = viewer
	reflection_fov = camera.fov
	if reflection.size.x != width:
		reflection.size.x = width
	reflection_camera.fov = camera.fov
	reflection_camera.keep_aspect = camera.keep_aspect
	var origin := viewer.origin
	origin.y = Layout.water_y() * 2.0 - origin.y
	var direction := -viewer.basis.z
	direction.y *= -1.0
	var up := viewer.basis.y
	reflection_camera.global_position = origin
	reflection_camera.look_at(origin + direction, Vector3(-up.x, up.y, -up.z))
	reflection.render_target_update_mode = SubViewport.UPDATE_ONCE

func _build_splashes() -> void:
	splash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	splash_material.albedo_color = Color(0.57, 0.70, 0.69)
	var drop := SphereMesh.new()
	drop.material = splash_material
	drop.radial_segments = 5
	drop.rings = 2
	drop.radius = 0.018
	drop.height = 0.06
	var particles := MultiMesh.new()
	particles.transform_format = MultiMesh.TRANSFORM_3D
	particles.mesh = drop
	particles.instance_count = IMPACT_COUNT * DROPS_PER_IMPACT
	splash_mesh.multimesh = particles
	splash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	splash_mesh.custom_aabb = AABB(Vector3(-43.0, -0.3, -71.0), Vector3(38.0, 1.5, 43.0))
	splash_mesh.visible = false
	add_child(splash_mesh)
	var rng := RandomNumberGenerator.new()
	rng.seed = 74591
	for i in DROPS_PER_IMPACT:
		var angle := TAU * i / DROPS_PER_IMPACT + rng.randf_range(-0.23, 0.23)
		var spread := rng.randf_range(0.68, 1.4)
		splash_offsets.append(Vector3(cos(angle) * spread, rng.randf_range(1.12, 2.25), sin(angle) * spread))

func _update_splashes(elapsed: float, sky: Color) -> void:
	var particles := splash_mesh.multimesh
	var count := 0
	for impact in impacts:
		var age := elapsed - impact.z
		if impact.w <= 0.0 or age < 0.0 or age > 0.50:
			continue
		var origin := Vector3(impact.x, Layout.water_y(), impact.y)
		for speed in splash_offsets:
			var point := origin + speed * age - Vector3.UP * (4.9 * age * age)
			if point.y < origin.y:
				continue
			var size := lerpf(1.12, 0.34, age * 2.0)
			var basis := Basis().scaled(Vector3(size, size * (1.0 + absf(speed.y - 9.8 * age) * 0.18), size))
			particles.set_instance_transform(count, Transform3D(basis, point))
			count += 1
	particles.visible_instance_count = count
	splash_mesh.visible = count > 0
	if splash_mesh.visible:
		splash_material.albedo_color = Color(0.14, 0.19, 0.25).lerp(Color(0.66, 0.80, 0.81), clampf(sky.get_luminance() * 2.0, 0.0, 1.0))

func _add_mesh(mesh: Mesh, point: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = point
	add_child(node)
	return node

func _add_multimesh(mesh: MultiMesh) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.multimesh = mesh
	add_child(node)
	return node
