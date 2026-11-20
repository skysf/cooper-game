extends Node3D

const Coast = preload("res://coast_layout.gd")
const Lake = preload("res://lake_layout.gd")
const TERRAIN = preload("res://coast/headlands.glb")
const GROUND_SHADER = preload("res://materials/coast_ground.gdshader")
const OCEAN_SHADER = preload("res://materials/ocean.gdshader")
const CANOPY = preload("res://textures/lake_canopy.png")
const SPRUCE = preload("res://trees/spruce_mature.glb")
const PINE = preload("res://pines/pine_mature.glb")
const STONE = preload("res://props/shore_boulder.glb")
const SEASIDE_COLOR = preload("res://coast/seaside_color.jpg")
const SEASIDE_NORMAL = preload("res://coast/seaside_normal.jpg")
const TILE := 18.0

var rock_shader := ShaderMaterial.new()
var ocean_shader := ShaderMaterial.new()
var last_light_time := -INF

func _ready() -> void:
	rock_shader.shader = GROUND_SHADER
	rock_shader.set_shader_parameter("cliff_color", preload("res://coast/cliff_color.jpg"))
	rock_shader.set_shader_parameter("cliff_normal", preload("res://coast/cliff_normal.jpg"))
	rock_shader.set_shader_parameter("seaside_color", SEASIDE_COLOR)
	rock_shader.set_shader_parameter("seaside_normal", SEASIDE_NORMAL)
	rock_shader.set_shader_parameter("sand_color", preload("res://coast/sand_color.jpg"))
	rock_shader.set_shader_parameter("sand_normal", preload("res://coast/sand_normal.jpg"))
	rock_shader.set_shader_parameter("forest_color", preload("res://textures/forest_floor_diff.jpg"))
	rock_shader.set_shader_parameter("sea_level", Lake.water_y())
	var land := TERRAIN.instantiate() as Node3D
	add_child(land)
	for piece: MeshInstance3D in land.find_children("*", "MeshInstance3D", true, false):
		piece.material_override = rock_shader
	_build_ocean()
	_build_vegetation()
	_build_stones()
	_waymark(Vector2(-17.8, -69.2), PI * 0.44, "海湾")
	_waymark(Vector2(-73.4, -47.3), PI * 0.90, "沙滩")

func _build_ocean() -> void:
	ocean_shader.shader = OCEAN_SHADER
	ocean_shader.set_shader_parameter("wave_slopes", preload("res://textures/lake_ripples.png"))
	ocean_shader.set_shader_parameter("tide_field", preload("res://coast/tide_field.png"))
	ocean_shader.set_shader_parameter("sand_color", preload("res://coast/sand_color.jpg"))
	ocean_shader.set_shader_parameter("rock_color", preload("res://coast/reef_rock_color.jpg"))
	var span := Vector2(Coast.cells) * Coast.step_size
	ocean_shader.set_shader_parameter("field_rect", Vector4(Coast.origin.x, Coast.origin.y, span.x, span.y))
	var water := MeshInstance3D.new()
	var surface := PlaneMesh.new()
	surface.size = Vector2(1200.0, 2400.0)
	water.mesh = surface
	water.position = Vector3(float(Coast.layout.seaEast) - surface.size.x * 0.5, Lake.water_y(), -51.0)
	water.material_override = ocean_shader
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

func update_light(elapsed: float, rain: float, light: Dictionary) -> void:
	if absf(elapsed - last_light_time) < 1.0 / 30.0:
		return
	last_light_time = elapsed
	var sunlight: float = light.get("sun_energy", 1.0)
	rock_shader.set_shader_parameter("room_seconds", elapsed)
	rock_shader.set_shader_parameter("rain_amount", rain)
	rock_shader.set_shader_parameter("sunlight", sunlight)
	ocean_shader.set_shader_parameter("water_time", elapsed)
	ocean_shader.set_shader_parameter("rain_amount", rain)
	ocean_shader.set_shader_parameter("sunlight", sunlight)
	for parameter in ["sun_direction", "sky_zenith", "sky_horizon", "sun_color"]:
		if light.has(parameter):
			ocean_shader.set_shader_parameter(parameter, light[parameter])

func _tiles(plants: Array) -> Dictionary:
	var result := {}
	for plant: Array in plants:
		var cell := Vector2i((Vector2(plant[0], plant[1]) / TILE).floor())
		if not result.has(cell):
			result[cell] = []
		result[cell].append(plant)
	return result

func _batch(mesh: Mesh, cell: Vector2i, poses: Array[Transform3D], override: Material = null,
		from_distance := 0.0, to_distance := 0.0, custom: Array[Color] = []) -> void:
	if poses.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = not custom.is_empty()
	multi.mesh = mesh
	multi.instance_count = poses.size()
	for i in poses.size():
		multi.set_instance_transform(i, poses[i])
		if multi.use_custom_data:
			multi.set_instance_custom_data(i, custom[i])
	var node := MultiMeshInstance3D.new()
	node.position = Vector3((cell.x + 0.5) * TILE, 0.0, (cell.y + 0.5) * TILE)
	node.multimesh = multi
	node.material_override = override
	node.visibility_range_begin = from_distance
	node.visibility_range_end = to_distance
	if to_distance > 0.0:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func _pose(plant: Array, cell: Vector2i, scale: Vector3, lift := 0.0) -> Transform3D:
	var at := Vector2(plant[0], plant[1])
	var local := at - (Vector2(cell) + Vector2.ONE * 0.5) * TILE
	var basis := Basis(Vector3.UP, float(plant[3]) * TAU)
	return Transform3D(basis.scaled_local(scale), Vector3(local.x, Coast.height(at) + lift, local.y))

func _trees(scene: PackedScene, plants: Array, species: int, canopy_mat: ShaderMaterial) -> void:
	var sample := scene.instantiate() as Node3D
	sample.hide()
	add_child(sample)
	var parts := sample.find_children("*", "MeshInstance3D", true, false)
	var billboard := QuadMesh.new()
	var tiles := _tiles(plants)
	for cell: Vector2i in tiles:
		var group: Array = tiles[cell]
		var cards: Array[Transform3D] = []
		var details: Array[Transform3D] = []
		var tint: Array[Color] = []
		for plant: Array in group:
			var h := float(plant[2])
			details.append(_pose(plant, cell, Vector3.ONE * (h / 7.0)))
			cards.append(_pose(plant, cell, Vector3(h * 0.55, h, 1.0), h * 0.5))
			tint.append(Color(float(species), 0.0, 0.83 + 0.16 * float(plant[3]), floorf(2.0 * plant[3])))
		for part: MeshInstance3D in parts:
			var posed: Array[Transform3D] = []
			for detail: Transform3D in details:
				posed.append(detail * part.transform)
			_batch(part.mesh, cell, posed, null, 0.0, 39.0)
		_batch(billboard, cell, cards, canopy_mat, 39.0, 165.0, tint)
	sample.queue_free()

func _build_vegetation() -> void:
	var canopy_mat := ShaderMaterial.new()
	canopy_mat.shader = preload("res://materials/lake_canopy.gdshader")
	canopy_mat.set_shader_parameter("canopy_atlas", CANOPY)
	var spruce: Array = Coast.foliage.trees.filter(func(plant: Array) -> bool: return plant[3] < 0.65)
	var pine: Array = Coast.foliage.trees.filter(func(plant: Array) -> bool: return plant[3] >= 0.65)
	_trees(SPRUCE, spruce, 0, canopy_mat)
	_trees(PINE, pine, 1, canopy_mat)

	var fern_mat := StandardMaterial3D.new()
	fern_mat.albedo_texture = preload("res://textures/fern.png")
	fern_mat.albedo_color = Color("#a5b492")
	fern_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fern_mat.alpha_scissor_threshold = 0.28
	fern_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fern_mat.roughness = 1.0
	var leaves := QuadMesh.new()
	var tiles := _tiles(Coast.foliage.shrubs)
	for cell: Vector2i in tiles:
		var poses: Array[Transform3D] = []
		for plant: Array in tiles[cell]:
			var h := float(plant[2])
			var base := _pose(plant, cell, Vector3.ONE, h * 0.39)
			for i in 3:
				var leaf := Basis.from_euler(Vector3(-0.47, TAU * float(i) / 3.0, 0.08))
				poses.append(base * Transform3D(leaf.scaled_local(Vector3(h * 1.7, h, 1.0)), Vector3.ZERO))
		_batch(leaves, cell, poses, fern_mat, 0.0, 51.0)

func _build_stones() -> void:
	var sample := STONE.instantiate() as Node3D
	var stone := sample as MeshInstance3D
	if stone == null:
		stone = sample.get_child(0) as MeshInstance3D
	var exposed_rock := rock_shader.duplicate() as ShaderMaterial
	exposed_rock.set_shader_parameter("solid_stone", true)
	var worn_stone := exposed_rock.duplicate() as ShaderMaterial
	worn_stone.set_shader_parameter("cliff_color", SEASIDE_COLOR)
	worn_stone.set_shader_parameter("cliff_normal", SEASIDE_NORMAL)
	var tiles := _tiles(Coast.foliage.stones)
	for cell: Vector2i in tiles:
		var poses: Array[Transform3D] = []
		for plant: Array in tiles[cell]:
			var size := float(plant[2])
			poses.append(_pose(plant, cell, Vector3(size, size * 0.67, size * 0.84), -size * 0.15))
		_batch(stone.mesh, cell, poses, worn_stone, 0.0, 64.0)
	tiles = _tiles(Coast.foliage.crags)
	for cell: Vector2i in tiles:
		var poses: Array[Transform3D] = []
		for plant: Array in tiles[cell]:
			var size := float(plant[2])
			poses.append(_pose(plant, cell, Vector3(size * 0.68, size * 1.13, size * 0.91), -size * 0.52))
		_batch(stone.mesh, cell, poses, exposed_rock)
	sample.free()

func _waymark(at: Vector2, heading: float, text: String) -> void:
	var marker := Node3D.new()
	marker.position = Vector3(at.x, Lake.walk_height(at), at.y)
	marker.rotation.y = heading
	add_child(marker)
	for part: Array in [[Vector3(0.12, 1.36, 0.13), Vector3(0.0, 0.55, 0.0)],
			[Vector3(0.76, 0.24, 0.072), Vector3(0.0, 1.05, 0.03)]]:
		var lumber := BoxMesh.new()
		lumber.size = part[0]
		lumber.material = preload("res://materials/wood.tres")
		var node := MeshInstance3D.new()
		node.mesh = lumber
		node.position = part[1]
		marker.add_child(node)
	var font := preload("res://fonts/TrailSans.otf").duplicate() as FontFile
	font.fallbacks = [preload("res://fonts/CampHanSupplement.otf")]
	var title := Label3D.new()
	title.text = text + "  ›"
	title.font = font
	title.font_size = 37
	title.pixel_size = 0.0041
	title.outline_size = 1
	title.modulate = Color("#e9dec4")
	title.position = Vector3(0.0, 1.052, 0.073)
	marker.add_child(title)
