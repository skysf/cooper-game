extends Node3D

signal lantern_warmed

const SURFACES = {
	"mud": preload("res://materials/mud.tres"),
	"forest_floor": preload("res://materials/forest_floor.tres"),
	"wood": preload("res://materials/wood.tres"),
	"bark": preload("res://materials/bark.tres"),
	"rock": preload("res://materials/rock.tres"),
	"needles": preload("res://materials/needles.tres"),
	"fern": preload("res://materials/fern.tres")
}
const FAR_FIR = preload("res://textures/distant_fir.png")
const Grove = preload("res://grove.gd")
const Grass = preload("res://grass.gd")
const LakeLayout = preload("res://lake_layout.gd")
const Lake = preload("res://lake.gd")
const CoastScene = preload("res://coast_scene.gd")
const ProvisionScene = preload("res://provision_scene.gd")
const CAMP_LANTERN = preload("res://props/camp_lantern.glb")
const Wildlife = preload("res://wildlife.gd")
const LANTERN_GLASS = preload("res://materials/lantern_glass.tres")
const PREFETCH_METRES := 26.0
const KEEP_METRES := 34.0
const MAX_RESIDENT_CHUNKS := 4
const REPLACE_MARGIN := 3.0
const HORIZON_MARGIN := 105.0
const GROUND_OFFSET := 0.12
const LAMP_FADE_SECONDS := 0.55
const UNLIT_FLAME_SCALE := 0.001
var last_error := ""
var source_url := ""
var world: Dictionary
var focus := Vector3(1.9, 1.67, -85.0)
var chunks: Array
var loaded := {}
var far_trees := {}
var background_floor: MeshInstance3D
var materials := {}
var pending := ""
var web_request: JavaScriptObject
var next_try := {}
var http := HTTPRequest.new()
var fire_lamp := OmniLight3D.new()
var wood_pile := Node3D.new()
var supply_roll := Node3D.new()
var roof_patch := Node3D.new()
var lantern: Node3D
var flame: MeshInstance3D
var lamp_lit := false
var lamp_progress := 0.0
var lantern_warmup_ms := 0.0
var _lantern_warming := false
var _warmup_exhaust_mesh: Mesh
var _warmup_exhaust_material: ShaderMaterial
var wetness := -1.0
var grove := Grove.new()
var grass := Grass.new()
var lake := Lake.new()
var coast := CoastScene.new()
var household := ProvisionScene.new()

func configure(zone_base_url: String) -> void:
	source_url = zone_base_url.trim_suffix("/") + "/"

func _ready() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	chunks = world.chunks
	if source_url.is_empty():
		if OS.has_feature("web"):
			configure(str(JavaScriptBridge.get_interface("location").origin) + "/coop/zones/")
		else:
			configure("http://localhost:4184/coop/zones/")
	for key in SURFACES:
		materials[key] = SURFACES[key].duplicate()
	add_child(http)
	http.timeout = 25.0
	http.request_completed.connect(_received)
	_background()
	_landmarks()
	add_child(coast)
	add_child(grove)
	grove.configure(world.get("grove", {}))
	set_wet(0.0)
	set_quest(false, false, false)
	if OS.has_feature("web"):
		_lantern_warming = true
		_warm_lantern_materials.call_deferred()

func update_focus(pos: Vector3) -> void:
	focus = pos
	grove.update_focus(pos)

func focus_zone() -> String:
	var at := Vector2(focus.x, focus.z)
	if at.x < -42.0 and LakeLayout.Coast.contains(at):
		return LakeLayout.Coast.area(at, LakeLayout.water_y())
	if focus.z < -70.0:
		return "camp"
	if focus.z < -36.0:
		var dock: Dictionary = LakeLayout.layout.dock
		if focus.x < float(dock.east) + 0.5 and absf(focus.z - float(dock.z)) < 1.8:
			return "lake"
		return "creek"
	return "tower"

func resident_count() -> int:
	return loaded.size()

func _distance(chunk: Dictionary) -> float:
	var x := maxf(0.0, maxf(-30.0 - focus.x, focus.x - 30.0))
	var z := maxf(0.0, maxf(float(chunk.lo) - focus.z, focus.z - float(chunk.hi)))
	return Vector2(x, z).length()

func is_focus_ready() -> bool:
	if _lantern_warming:
		return false
	if LakeLayout.Coast.contains(Vector2(focus.x, focus.z)):
		return true
	for chunk in chunks:
		if focus.z >= float(chunk.lo) and focus.z < float(chunk.hi):
			return loaded.has(chunk.id)
	return false

func wait_for_lantern_warmup() -> void:
	if _lantern_warming:
		await lantern_warmed

func prepare_exhaust_warmup(mesh: Mesh, material: ShaderMaterial) -> void:
	_warmup_exhaust_mesh = mesh
	_warmup_exhaust_material = material

func _warm_lantern_materials() -> void:
	var started := Time.get_ticks_usec()
	# Draw the actual lantern once so the browser links its glass, emission and shadow variants
	# before the first chase turn can bring the cabin into view.
	var preview := SubViewport.new()
	preview.size = Vector2i(96, 54)
	preview.world_3d = get_world_3d()
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(preview)
	var lens := Camera3D.new()
	lens.near = 0.07
	lens.far = 3.4
	preview.add_child(lens)
	var center := lantern.global_position + Vector3.DOWN * 0.27
	lens.global_position = center + Vector3(1.05, 0.48, 1.25)
	lens.look_at(center)
	lens.make_current()
	if _warmup_exhaust_mesh != null:
		# Both nozzle pairs use this shader. Draw it with zero opacity in the same real scene.
		var exhaust := MeshInstance3D.new()
		exhaust.mesh = _warmup_exhaust_mesh
		var material := _warmup_exhaust_material.duplicate() as ShaderMaterial
		material.set_shader_parameter("power", 0.0)
		exhaust.material_override = material
		exhaust.position = Vector3(0.20, -0.22, -0.8)
		exhaust.scale = Vector3(0.08, 0.55, 0.08)
		exhaust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lens.add_child(exhaust)
		_warmup_exhaust_mesh = null
		_warmup_exhaust_material = null
	preview.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	preview.queue_free()
	await preview.tree_exited
	lantern_warmup_ms = (Time.get_ticks_usec() - started) / 1000.0
	_lantern_warming = false
	lantern_warmed.emit()

func _process(_dt: float) -> void:
	if web_request != null and bool(web_request.done):
		var result := web_request
		web_request = null
		if not str(result.error).is_empty():
			_failed(pending, str(result.error))
		else:
			_parse_chunk(pending, JavaScriptBridge.js_buffer_to_packed_byte_array(result.bytes))
	for chunk in chunks:
		var id: String = chunk.id
		if loaded.has(id) and _distance(chunk) > KEEP_METRES:
			_unload_chunk(id)
	if pending.is_empty():
		var candidate := _next_chunk()
		if not candidate.is_empty():
			_request_chunk(candidate)

func _farthest_resident() -> Dictionary:
	var farthest := {}
	var distance := -1.0
	for chunk: Dictionary in chunks:
		if loaded.has(chunk.id) and _distance(chunk) > distance:
			distance = _distance(chunk)
			farthest = chunk
	return farthest

func _next_chunk() -> String:
	var limit := PREFETCH_METRES
	if loaded.size() >= MAX_RESIDENT_CHUNKS:
		limit = minf(limit, _distance(_farthest_resident()) - REPLACE_MARGIN)
	var candidate := ""
	var best := INF
	var now := Time.get_ticks_msec()
	for chunk: Dictionary in chunks:
		var distance := _distance(chunk)
		if distance <= limit and distance < best and not loaded.has(chunk.id) and int(next_try.get(chunk.id, 0)) <= now:
			candidate = chunk.id
			best = distance
	return candidate

func _unload_chunk(id: String) -> void:
	far_trees[id].show()
	loaded[id].hide()
	loaded[id].queue_free()
	loaded.erase(id)

func _request_chunk(id: String) -> void:
	pending = id
	if OS.has_feature("web"):
		var bridge := JavaScriptBridge.get_interface("CooperJoin")
		web_request = bridge.fetchZone(source_url + id + ".glb")
		return
	else:
		var bundled := OS.get_executable_path().get_base_dir().path_join("../Resources/zones")
		var file := bundled.path_join(id + ".glb").simplify_path()
		if FileAccess.file_exists(file):
			_parse_chunk.call_deferred(id, FileAccess.get_file_as_bytes(file))
			return
	var status := http.request(source_url + id + ".glb")
	if status != OK:
		_failed(id, error_string(status))

func _failed(id: String, reason: String) -> void:
	pending = ""
	next_try[id] = Time.get_ticks_msec() + 3500
	last_error = id + " · " + reason
	push_warning("Chunk load: " + last_error)

func _received(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_failed(pending, "HTTP %s / %s" % [code, result])
		return
	_parse_chunk(pending, bytes)

func _parse_chunk(id: String, bytes: PackedByteArray) -> void:
	var replace := {}
	if loaded.size() >= MAX_RESIDENT_CHUNKS:
		replace = _farthest_resident()
	for chunk: Dictionary in chunks:
		if chunk.id == id and (_distance(chunk) > KEEP_METRES or (
			not replace.is_empty() and _distance(chunk) > _distance(replace) - REPLACE_MARGIN)):
			pending = ""
			return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var err := document.append_from_buffer(bytes, "", state)
	if err != OK:
		_failed(id, error_string(err))
		return
	var part := document.generate_scene(state)
	if part == null:
		_failed(id, "Empty scene")
		return
	for object in part.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := object as MeshInstance3D
		var surface := str(mesh_node.name).get_slice("__", 0)
		var material = materials.get(surface)
		if material != null:
			mesh_node.material_override = material
		if surface == "mud" or surface == "forest_floor":
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if surface == "forest_floor" and id in ["approach", "creek", "crossing"]:
			mesh_node.layers |= Lake.REFLECTION_LAYER
	part.name = id
	grass.add_to_chunk(part, world.get("grass", {}).get(id, []))
	if not replace.is_empty():
		_unload_chunk(replace.id)
	add_child(part)
	loaded[id] = part
	far_trees[id].visible = false
	next_try.erase(id)
	pending = ""
	last_error = ""

func _background() -> void:
	# A distant canopy and a continuous forest floor survive while a chunk is in flight.
	_background_floor()
	var horizon := StandardMaterial3D.new()
	horizon.albedo_texture = FAR_FIR
	horizon.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	horizon.alpha_scissor_threshold = 0.32
	horizon.cull_mode = BaseMaterial3D.CULL_DISABLED
	horizon.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	horizon.billboard_keep_scale = true
	var card := QuadMesh.new()
	card.material = horizon
	card.size = Vector2(1, 1)
	for chunk in chunks:
		var transforms: Array[Transform3D] = []
		for tree in world.trees:
			var z := float(tree[1])
			if z < float(chunk.lo) or z >= float(chunk.hi):
				continue
			var x := float(tree[0])
			var h := float(tree[2])
			var ground := LakeLayout.ground_height(Vector2(x, z)) - GROUND_OFFSET
			transforms.append(Transform3D(Basis().scaled(Vector3(h * 0.40, h, 1)), Vector3(x, ground + h * .5, z)))
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = card
		multi.instance_count = transforms.size()
		for i in transforms.size():
			multi.set_instance_transform(i, transforms[i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		add_child(node)
		far_trees[chunk.id] = node

func _background_floor() -> void:
	var floor_mesh := SurfaceTool.new()
	floor_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := StandardMaterial3D.new()
	material.albedo_texture = materials.forest_floor.albedo_texture
	material.vertex_color_use_as_albedo = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var lo := Vector2(-30.0, -121.0 - HORIZON_MARGIN)
	var hi := Vector2(30, 14) + Vector2.ONE * HORIZON_MARGIN
	floor_mesh.set_material(material)
	_floor_sector(floor_mesh, lo, Vector2(hi.x, -72), 1, 1)
	_floor_sector(floor_mesh, Vector2(lo.x, -28), hi, 1, 1)
	_floor_sector(floor_mesh, Vector2(-7, -72), Vector2(hi.x, -28), 1, 1)
	_floor_sector(floor_mesh, Vector2(lo.x, -72), Vector2(-7, -28), 32, 60)
	floor_mesh.index()
	background_floor = _mesh(self, floor_mesh.commit(), Vector3.ZERO)
	background_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _floor_sector(mesh: SurfaceTool, lo: Vector2, hi: Vector2, columns: int, rows: int) -> void:
	var width := columns + 1
	var points := PackedVector3Array()
	for j in rows + 1:
		for i in columns + 1:
			var point := Vector2(lerpf(lo.x, hi.x, i / float(columns)), lerpf(lo.y, hi.y, j / float(rows)))
			points.append(Vector3(point.x, LakeLayout.ground_height(point) - GROUND_OFFSET, point.y))
	for j in rows:
		for i in columns:
			var first := j * width + i
			# Godot's front faces wind clockwise when viewed from above.
			for vertex in [first, first + 1, first + width, first + 1, first + width + 1, first + width]:
				var point := points[vertex]
				mesh.set_normal(Vector3.UP)
				mesh.set_uv(Vector2(point.x, point.z) * 0.5)
				mesh.set_color(Color(0.66, 0.67, 0.60))
				mesh.add_vertex(point)

func set_wet(value: float) -> void:
	if materials.is_empty() or absf(value - wetness) < 0.003:
		return
	wetness = value
	grass.material.set_shader_parameter("wetness", value)
	for key in ["rock", "mud", "wood"]:
		var mat: StandardMaterial3D = materials[key]
		var dry: StandardMaterial3D = SURFACES[key]
		mat.roughness = lerpf(dry.roughness, 0.34 if key == "mud" else 0.46, value)
		var light := lerpf(1.0, .80, value)
		mat.albedo_color = Color(light, light, light)
	lake.set_bank_wet(value)

func set_quest(wood: bool, tarp: bool, repaired: bool) -> void:
	wood_pile.visible = not wood
	supply_roll.visible = not tarp
	roof_patch.visible = repaired
	lamp_lit = repaired

func update_flame(elapsed: float, delta: float) -> void:
	if not lamp_lit and lamp_progress == 0.0:
		return
	lamp_progress = move_toward(lamp_progress, 1.0 if lamp_lit else 0.0, delta / LAMP_FADE_SECONDS)
	var ignition := smoothstep(0.0, 1.0, lamp_progress)
	var draft := 0.038 * sin(elapsed * 5.3) + 0.021 * sin(elapsed * 11.2)
	var flame_size := lerpf(UNLIT_FLAME_SCALE, 1.0, ignition)
	flame.scale = Vector3(flame_size, flame_size * (1.0 + draft), flame_size)
	fire_lamp.light_energy = 1.35 * ignition * (1.0 + 0.5 * draft)

func update_water(elapsed: float, rain: float, lighting: Dictionary) -> void:
	lake.update_water(elapsed, rain, lighting)
	coast.update_light(elapsed, rain, lighting)

func add_water_impact(point: Vector3, elapsed: float) -> void:
	lake.add_impact(point, elapsed)

func reset_water() -> void:
	lake.reset_water()

func set_provisions(provisions: Dictionary) -> void:
	household.update_contents(provisions)

func _mesh(parent: Node, mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	parent.add_child(instance)
	return instance

func _beam(parent: Node, a: Vector3, b: Vector3, width: float, depth: float, mat: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(width, a.distance_to(b), depth)
	box.material = mat
	var node := _mesh(parent, box, (a + b) * 0.5)
	node.quaternion = Quaternion(Vector3.UP, a.direction_to(b))
	return node

func _pole(parent: Node, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.height = a.distance_to(b)
	cylinder.top_radius = radius * .91
	cylinder.bottom_radius = radius
	cylinder.radial_segments = 10
	cylinder.rings = 1
	cylinder.material = mat
	var node := _mesh(parent, cylinder, (a+b)*.5)
	node.quaternion = Quaternion(Vector3.UP, a.direction_to(b))

func _landmarks() -> void:
	add_child(wood_pile)
	add_child(supply_roll)
	add_child(roof_patch)
	add_child(household)
	var wood: Material = materials.wood
	var bark: Material = materials.bark
	var branch_join := Wildlife.PERCH + Vector3(0.52, 0.0, 0.0)
	_pole(self, Wildlife.PERCH_TRUNK, branch_join, 0.068, bark)
	_pole(self, branch_join, Wildlife.PERCH - Vector3(0.43, 0.0, 0.0), 0.047, bark)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color("#4d736a")
	cloth.roughness = 0.76
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Salvage stacked on two stringers above the creek's flood line.
	wood_pile.position = Vector3(-8.6, 0, -53.35)
	for i in range(6):
		var height := .16 + (.22 if i >= 4 else 0.0)
		var z := -.46 + (i % 4) * .29 + (.15 if i >= 4 else 0.0)
		_pole(wood_pile, Vector3(-.72, height, z), Vector3(.83 + .06 * sin(i), height + .02, z+.025), .14, bark)
	lake.configure(wood, materials.rock)
	add_child(lake)
	_tower()
	supply_roll.position = Vector3(9, .38, -17)
	_pole(supply_roll, Vector3(-.54, 0, .0), Vector3(.54, 0, .0), .22, cloth)
	var strap := StandardMaterial3D.new()
	strap.albedo_color = Color("#62492e")
	for dx in [-.31, .31]:
		_pole(supply_roll, Vector3(dx,0,0),Vector3(dx+.07,0,0), .228,strap)
	_beam(self,Vector3(8.2,.18,-17),Vector3(9.8,.18,-17),.25,.60, wood)
	# Patched sloping roof with turned edges and transverse battens over the new canvas.
	for i in range(4):
		var x1 := 1.85 + i*.81
		var x2 := x1+.82
		var y1 := 3.65 - i*.396
		var y2 := y1-.396
		_beam(roof_patch,Vector3(x1,y1,-89.6),Vector3(x2,y2,-89.6),.045,2.7,cloth)
	for dz in [-1.25,0.,1.25]:
		_pole(roof_patch,Vector3(1.86,3.69,-89.6+dz),Vector3(5.03,2.13,-89.6+dz),.037, wood)
	lantern = CAMP_LANTERN.instantiate() as Node3D
	# The plate attaches to the lower face of the front beam beside the entry post.
	lantern.position = Vector3(4.13, 2.156, -86.90)
	add_child(lantern)
	var chimney := lantern.find_child("Chimney", true, false) as MeshInstance3D
	chimney.material_override = LANTERN_GLASS
	flame = lantern.find_child("Flame", true, false) as MeshInstance3D
	# Keep the light and flame registered from the first frame of the camp.
	flame.scale = Vector3.ONE * UNLIT_FLAME_SCALE
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fire_lamp.light_color = Color("#ffbc75")
	fire_lamp.light_energy = 0.0
	fire_lamp.light_specular = 0.45
	fire_lamp.omni_range = 4.0
	fire_lamp.position = Vector3(0, -0.392, 0)
	lantern.add_child(fire_lamp)

func _tower() -> void:
	var base := Node3D.new()
	base.position = Vector3(10.8,0,-15.1)
	add_child(base)
	var wood: Material = materials.wood
	var bark: Material = materials.bark
	for x in [-1.35,1.35]:
		for z in [-1.35,1.35]:
			_pole(base,Vector3(x,.01,z),Vector3(x*.84,6.9,z*.84),.15,bark)
	for sign_dir in [-1.0,1.0]:
		var d: float = sign_dir
		_beam(base,Vector3(-1.32,.4,d*1.32),Vector3(1.17,4.5,d*1.17),.12,.11,wood)
		_beam(base,Vector3(1.32,.4,d*1.32),Vector3(-1.17,4.5,d*1.17),.12,.11,wood)
		_beam(base,Vector3(d*1.32,.4,-1.32),Vector3(d*1.17,4.5,1.17),.12,.11,wood)
		_beam(base,Vector3(-1.49,5.72,1.22*d),Vector3(1.49,5.72,1.22*d),.11,.11,wood)
		_beam(base,Vector3(d*1.22,5.72,-1.49),Vector3(d*1.22,5.72,1.49),.11,.11,wood)
	for i in 13:
		var x := -1.48+i*.245
		_beam(base,Vector3(x,4.64,-1.5),Vector3(x,4.64,1.5),.236,.13,wood)
		var rise := 7.32 - absf(x)*.32
		_beam(base,Vector3(x,rise,-1.65),Vector3(x,rise,1.65),.27,.13,wood)
	for x in [-.28,.28]:
		_pole(base,Vector3(x,.02,-1.8),Vector3(x,5.2,-1.29),.063,wood)
	for i in range(1,15):
		_pole(base,Vector3(-.29,i*.32,-1.8+.036*i),Vector3(.29,i*.32,-1.8+.036*i),.04,wood)

