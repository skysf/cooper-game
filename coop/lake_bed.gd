extends Node3D

const Layout = preload("res://lake_layout.gd")
const GRAVEL = preload("res://textures/lake_gravel_diff.jpg")
const GRAVEL_NORMAL = preload("res://textures/lake_gravel_nor_gl.jpg")
const RIPPLE_FIELD = preload("res://textures/lake_ripples.png")
const BED_SHADER = preload("res://materials/lake_bed.gdshader")
const WEED_SHADER = preload("res://materials/pondweed.gdshader")
const MOTE_SHADER = preload("res://materials/lake_motes.gdshader")
const SECTORS := 80
const SHADE_SIZE := 384

var substrate := ShaderMaterial.new()
var motes := MultiMeshInstance3D.new()
var shade := Image.create_empty(SHADE_SIZE, SHADE_SIZE, false, Image.FORMAT_L8)

func _ready() -> void:
	substrate.shader = BED_SHADER
	substrate.set_shader_parameter("gravel", GRAVEL)
	substrate.set_shader_parameter("gravel_normal", GRAVEL_NORMAL)
	substrate.set_shader_parameter("ripple_field", RIPPLE_FIELD)
	shade.fill(Color.WHITE)
	_basin()
	_gravel_bars()
	_weed_beds()
	shade.generate_mipmaps()
	substrate.set_shader_parameter("contact_shade", ImageTexture.create_from_image(shade))
	shade = null
	_build_motes()

func light_bed(elapsed: float, sun: Vector3, cover: float) -> void:
	# The refracted sun stays above the critical angle even at sunset.
	var vertical := sqrt(1.0 - 0.75 * 0.75 * (1.0 - sun.y * sun.y))
	var energy := smoothstep(0.035, 0.52, sun.y) * (1.0 - smoothstep(0.3, 0.91, cover))
	substrate.set_shader_parameter("refracted_sun", Vector3(sun.x * 0.75 / vertical, energy * 1.45, sun.z * 0.75 / vertical))
	substrate.set_shader_parameter("room_time", elapsed)

func _basin() -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.set_material(substrate)
	# The outer lip sinks into the streamed forest floor, leaving an irregular
	# wet gravel beach. Both the main mesh and its streaming fallback stay intact.
	var rings := [0.0, 0.12, 0.26, 0.45, 0.63, 0.78, 0.88, 0.95, 0.985, 1.015, 1.045, 1.083, 1.13]
	for row in rings.size():
		var radius: float = rings[row]
		for i in SECTORS:
			var angle := i * TAU / SECTORS
			var fringe := 0.026 * sin(angle * 11.0 + 0.9) + 0.021 * sin(angle * 5.0)
			var distance := radius + fringe * smoothstep(0.985, 1.13, radius)
			var point := Layout.shore_at(angle, distance)
			var ground := Layout.ground_height(point)
			# The coarser streamed triangles interpolate across the exact cone tip.
			# Fill the small central hollow so their forest-floor surface cannot pierce it.
			var lift := lerpf(0.029, -0.075, smoothstep(1.034, 1.13, radius)) + 0.125 * (1.0 - smoothstep(0.0, 0.17, radius))
			var gradient := Vector3(Layout.ground_height(point - Vector2(0.15, 0.0)) - Layout.ground_height(point + Vector2(0.15, 0.0)),
				0.3, Layout.ground_height(point - Vector2(0.0, 0.15)) - Layout.ground_height(point + Vector2(0.0, 0.15)))
			var silt := 0.46 + sin(point.x * 0.52 + point.y * 0.27) * 0.23 + cos(point.y * 0.48 - point.x * 0.13) * 0.19
			mesh.set_normal(gradient.normalized())
			mesh.set_uv(point)
			mesh.set_uv2(Vector2(Layout.water_y() - ground - lift, silt))
			mesh.add_vertex(Vector3(point.x, ground + lift, point.y))
	for row in range(rings.size() - 1):
		for i in SECTORS:
			var left := row * SECTORS + i
			var right := row * SECTORS + (i + 1) % SECTORS
			for index in [left, left + SECTORS, right + SECTORS]:
				mesh.add_index(index)
			if row > 0:
				for index in [left, right + SECTORS, right]:
					mesh.add_index(index)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = mesh.commit()
	floor_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_node)

func _gravel_bars() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = GRAVEL
	material.roughness = 0.88
	material.vertex_color_use_as_albedo = true
	var pebble := SphereMesh.new()
	pebble.material = material
	pebble.radial_segments = 7
	pebble.rings = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 28314
	var stones := MultiMesh.new()
	stones.transform_format = MultiMesh.TRANSFORM_3D
	stones.use_colors = true
	stones.mesh = pebble
	stones.instance_count = 112
	for bar in 16:
		var center := Layout.shore_at(rng.randf() * TAU, rng.randf_range(0.33, 0.99))
		for i in 7:
			var point := center + Vector2(rng.randfn(0.0, 0.83), rng.randfn(0.0, 0.54))
			var size := rng.randf_range(0.09, 0.32) * (1.5 if i == 0 else 1.0)
			var axes := Vector3(size * rng.randf_range(1.0, 1.7), size * rng.randf_range(0.44, 0.70), size)
			var pose := Basis(Vector3.UP, rng.randf() * TAU) * Basis().scaled(axes)
			var foot := Vector3(point.x, Layout.ground_height(point) + 0.028 + axes.y * 0.10, point.y)
			var tint := Color("#90a79d").lerp(Color("#b8ad96"), rng.randf())
			stones.set_instance_transform(bar * 7 + i, Transform3D(pose, foot))
			stones.set_instance_color(bar * 7 + i, tint)
			_contact(point, maxf(axes.x, axes.z) * 0.82 + 0.085, 0.39)
	var cobbles := _scatter(stones)
	cobbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _weed_beds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 46820
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := ShaderMaterial.new()
	material.shader = WEED_SHADER
	mesh.set_material(material)
	for shoot in 5:
		var azimuth := shoot * 2.4 + 0.57
		var outward := Vector3(cos(azimuth), 0.0, sin(azimuth))
		var sideways := Vector3(-outward.z, 0.0, outward.x)
		var height := rng.randf_range(0.36, 0.81)
		var foot := outward * rng.randf_range(0.028, 0.10)
		var previous := foot
		for level in range(1, 7):
			var t := level / 6.0
			var joint := foot + Vector3.UP * height * t + outward * height * (t * t * 0.46)
			var blade := Color("#304635").lerp(Color("#7f8553"), t * 0.84)
			for v in [previous - sideways * 0.004, joint - sideways * 0.004, previous + sideways * 0.004,
					previous + sideways * 0.004, joint - sideways * 0.004, joint + sideways * 0.004]:
				mesh.set_normal(Vector3.UP)
				mesh.set_color(blade)
				mesh.add_vertex(v)
			var az := azimuth + level * 2.22
			var direction := Vector3(cos(az), 0.0, sin(az))
			var reach := height * (1.0 - t * 0.46) * 0.43
			var tip := joint + direction * reach + Vector3.UP * reach * 0.56
			var belly := joint + direction * reach * 0.56 + Vector3.UP * reach * 0.20
			_leaf(mesh, joint, belly, tip, Vector3(-direction.z, 0.22, direction.x) * reach * rng.randf_range(0.15, 0.25), blade)
			previous = joint
	var plants := MultiMesh.new()
	plants.transform_format = MultiMesh.TRANSFORM_3D
	plants.mesh = mesh.commit()
	var poses: Array[Transform3D] = []
	for patch in 21:
		var center := Layout.shore_at(rng.randf() * TAU, rng.randf_range(0.27, 0.92))
		for i in rng.randi_range(3, 6):
			var point := center + Vector2(rng.randfn(0.0, 0.48), rng.randfn(0.0, 0.40))
			var floor_y := Layout.ground_height(point) + 0.025
			var depth := Layout.water_y() - floor_y
			if depth < 0.16:
				continue
			var scale := minf(rng.randf_range(0.38, 1.32), depth * 1.08)
			var axes := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale)
			poses.append(Transform3D(axes, Vector3(point.x, floor_y, point.y)))
			_contact(point, scale * 0.43 + 0.10, 0.21)
	plants.instance_count = poses.size()
	for i in poses.size():
		plants.set_instance_transform(i, poses[i])
	_scatter(plants)

func _leaf(mesh: SurfaceTool, base: Vector3, middle: Vector3, tip: Vector3, width: Vector3, color: Color) -> void:
	var points := [base, middle - width, middle + Vector3.UP * width.length() * 0.25, middle + width, tip]
	var colors := [color.darkened(0.19), color.darkened(0.16), color.lightened(0.065), color, color]
	for vertex in [0, 1, 2, 0, 2, 3, 1, 4, 2, 2, 4, 3]:
		mesh.set_normal(Vector3.UP)
		mesh.set_color(colors[vertex])
		mesh.add_vertex(points[vertex])

func _contact(point: Vector2, radius: float, strength: float) -> void:
	# Static contact occlusion occupies one small single-channel texture. Its
	# coordinates cover a 40 m square centred on the basin, matching lake_bed.gdshader.
	var center := ((point - Layout.center()) / 40.0 + Vector2(0.5, 0.5)) * SHADE_SIZE
	var pixels := radius * SHADE_SIZE / 40.0
	for y in range(maxi(0, floori(center.y - pixels)), mini(SHADE_SIZE, ceili(center.y + pixels) + 1)):
		for x in range(maxi(0, floori(center.x - pixels)), mini(SHADE_SIZE, ceili(center.x + pixels) + 1)):
			var distance := center.distance_to(Vector2(x + 0.5, y + 0.5)) / pixels
			var cover := 1.0 - strength * (1.0 - smoothstep(0.19, 1.0, distance))
			if cover < shade.get_pixel(x, y).r:
				shade.set_pixel(x, y, Color(cover, cover, cover))

func _scatter(instances: MultiMesh) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.multimesh = instances
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 36.0
	add_child(node)
	return node

func _build_motes() -> void:
	var dust := ShaderMaterial.new()
	dust.shader = MOTE_SHADER
	var flake := QuadMesh.new()
	flake.material = dust
	var particles := MultiMesh.new()
	particles.transform_format = MultiMesh.TRANSFORM_3D
	particles.mesh = flake
	particles.instance_count = 270
	var rng := RandomNumberGenerator.new()
	rng.seed = 619027
	for i in particles.instance_count:
		var point := Layout.shore_at(rng.randf() * TAU, sqrt(rng.randf()) * 0.93)
		var y := lerpf(Layout.ground_height(point) + 0.10, Layout.water_y() - 0.08, rng.randf())
		var width := rng.randf_range(0.0035, 0.009)
		var axes := Basis().scaled(Vector3(width, width * rng.randf_range(0.65, 1.5), 1.0))
		particles.set_instance_transform(i, Transform3D(axes, Vector3(point.x, y, point.y)))
	motes.multimesh = particles
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.visible = false
	add_child(motes)
