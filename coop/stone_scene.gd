extends Node3D

const Stones = preload("res://stones.gd")
const WOOD = preload("res://materials/wood.tres")
const MODELS = {
	"round": preload("res://props/stone_round.glb"),
	"flat": preload("res://props/stone_flat.glb"),
	"sharp": preload("res://props/stone_sharp.glb"),
}
const CANVAS_SHADER = """
shader_type spatial;
render_mode cull_disabled;
uniform float room_time;
uniform float rain;
uniform bool weighed;
void vertex() {
	vec2 corner = UV - vec2(0.91, 0.73);
	float lifted = exp(-12.0 * dot(corner, corner));
	float wind = 0.015 + 0.010 * sin(room_time * 2.3 + VERTEX.z * 5.0);
	VERTEX.y += 0.009 * sin(VERTEX.x * 23.0 + VERTEX.z * 9.0);
	VERTEX.y += lifted * wind * (1.0 + rain * 1.8) * (weighed ? 0.1 : 1.0);
}
void fragment() {
	vec2 seam = min(UV, 1.0 - UV);
	float edge = smoothstep(0.010, 0.027, min(seam.x, seam.y));
	float weave = sin(UV.x * 170.0) * sin(UV.y * 150.0);
	ALBEDO = vec3(0.135, 0.202, 0.149) * mix(0.52, 1.0, edge) * (1.0 + 0.055 * weave - rain * 0.26);
	ROUGHNESS = 0.86 - rain * 0.27;
}
"""

var markers: Dictionary = {}
var cloth_material := ShaderMaterial.new()
var grip := Node3D.new()
var loose_rope: MeshInstance3D
var cut_rope: MeshInstance3D

func _ready() -> void:
	add_child(grip)
	grip.hide()
	_build_grip()
	var bench := MODELS["round"].instantiate() as Node3D
	bench.name = "Grindstone"
	bench.position = Vector3(Stones.GRIND.x, Stones.GRIND_HEIGHT, Stones.GRIND.y)
	bench.scale = Vector3(4.0, 2.2, 3.8)
	bench.rotation.y = -0.26
	add_child(bench)
	var shader := Shader.new()
	shader.code = CANVAS_SHADER
	cloth_material.shader = shader
	var tarp := PlaneMesh.new()
	tarp.size = Vector2(1.38, 1.08)
	tarp.subdivide_width = 13
	tarp.subdivide_depth = 10
	_mesh(tarp, cloth_material, Vector3(Stones.CANVAS.x - 0.57, 0.031, Stones.CANVAS.y - 0.25))
	var board := BoxMesh.new()
	board.size = Vector3(0.46, 0.10, 0.32)
	_mesh(board, WOOD, Vector3(Stones.ROPE.x, 0.045, Stones.ROPE.y))
	var hemp := StandardMaterial3D.new()
	hemp.albedo_color = Color("#866c4c")
	hemp.roughness = 0.97
	loose_rope = _mesh(_rope(false), hemp, Vector3(Stones.ROPE.x, 0.115, Stones.ROPE.y))
	cut_rope = _mesh(_rope(true), hemp, loose_rope.position)
	cut_rope.hide()

func _build_grip() -> void:
	var form := SphereMesh.new()
	form.radial_segments = 12
	form.rings = 6
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color("#5c6754")
	sleeve.roughness = 0.91
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color("#373931")
	glove.roughness = 0.93
	for part: Array in [
		[sleeve, Vector3(0.083, -0.117, 0.081), Vector3(0.095, 0.24, 0.09), 0.66],
		[glove, Vector3(0.014, -0.043, 0.023), Vector3(0.108, 0.066, 0.079), 0.40],
		[glove, Vector3(-0.038, -0.017, 0.033), Vector3(0.027, 0.052, 0.038), -0.21],
	]:
		var node := MeshInstance3D.new()
		node.mesh = form
		node.material_override = part[0]
		node.position = part[1]
		node.scale = part[2]
		node.rotation.z = part[3]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grip.add_child(node)

func _mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)
	return node

func _rope(cut: bool) -> ArrayMesh:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous := PackedVector3Array()
	for i in 65:
		var angle := float(i) * TAU * 3.24 / 64.0
		var radius := lerpf(0.055, 0.136, float(i) / 64.0)
		var center := Vector3(cos(angle) * radius, sin(angle * 0.15) * 0.006, sin(angle) * radius * 0.73)
		if cut and i >= 48:
			center.x += 0.047
		var rim := PackedVector3Array()
		for side in 5:
			var theta := TAU * float(side) / 5.0
			rim.append(center + Vector3(cos(angle) * cos(theta), sin(theta), sin(angle) * cos(theta)) * 0.007)
		if i > 0 and (i != 48 or not cut):
			for side in 5:
				var next := (side + 1) % 5
				for vertex: Vector3 in [previous[side], rim[side], previous[next], previous[next], rim[side], rim[next]]:
					mesh.add_vertex(vertex)
		previous = rim
	mesh.generate_normals()
	return mesh.commit()

func update_stones(stones: Dictionary, avatars: Dictionary, self_id: String, camera: Camera3D, elapsed: float, rain: float, line_cut: bool, local_hiker: Node3D = null) -> void:
	var weighed := false
	grip.hide()
	for id: String in markers:
		if not stones.has(id):
			markers[id].node.hide()
	for id: String in stones:
		var stone: Dictionary = stones[id]
		var model := "round"
		if Stones.flat(id):
			model = "sharp" if int(stone.edge) > 0 else "flat"
		var entry: Dictionary = markers.get(id, {})
		if entry.get("model") != model:
			if entry.has("node"):
				entry.node.queue_free()
			var source: PackedScene = MODELS[model]
			var instance := source.instantiate() as Node3D
			add_child(instance)
			entry = {"model": model, "node": instance}
			markers[id] = entry
		var node: Node3D = entry.node
		var at := Stones.unpack(stone.at)
		node.visible = true
		node.rotation = Vector3(0.0, float(id.hash() % 360) * 0.01745, 0.0)
		match stone.mode:
			"held":
				var holder: String = stone.holder
				if holder == self_id and local_hiker != null:
					at = local_hiker.held_item_position()
					node.rotation = local_hiker.rotation
				elif holder == self_id:
					at = camera.to_global(Vector3(0.25, -0.16, -0.50))
					node.rotation = camera.rotation + Vector3(-0.17, 0.28, -0.21)
					grip.global_transform = Transform3D(camera.global_basis, at)
					grip.show()
				elif avatars.has(holder):
					at = avatars[holder].held_item_position()
				else:
					node.hide()
			"air":
				at = Stones.flight_position(stone, elapsed)
				var age := maxf(elapsed - float(stone.launch), 0.0)
				node.rotation = Vector3(age * 9.0, age * 5.3, age * 3.0)
			"placed":
				weighed = true
			"submerged":
				node.visible = at.y > -0.42
		node.position = at
	cloth_material.set_shader_parameter("weighed", weighed)
	cloth_material.set_shader_parameter("room_time", elapsed)
	cloth_material.set_shader_parameter("rain", rain)
	loose_rope.visible = not line_cut
	cut_rope.visible = line_cut
