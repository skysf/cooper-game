extends Node3D

const GROUND = preload("res://materials/woodland_ground.gdshader")
const SURFACES := {"rock":preload("res://materials/rock.tres"), "mud":preload("res://materials/mud.tres")}
var materials := [{}, {}, {}, {}]
var displayed := {}
var stats := []
var callback: JavaScriptObject

func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-29.0, -40.0, 0.0)
	light.light_energy = 0.63
	add_child(light)
	var context := WorldEnvironment.new()
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color(0.12,0.20,0.21)
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color(0.58,0.65,0.67)
	sky.ambient_light_energy = 0.63
	context.environment = sky
	add_child(context)
	var camera := Camera3D.new()
	camera.fov = 59.0
	add_child(camera)
	camera.position = Vector3(-.88,.82,-77.61)
	camera.look_at(Vector3(-2.489,.48,-76.0))
	camera.make_current()

	for key: String in SURFACES:
		var source: StandardMaterial3D = SURFACES[key]
		var old_wet := source.duplicate() as StandardMaterial3D
		old_wet.roughness = 0.34 if key == "mud" else 0.46
		old_wet.albedo_color = Color(.80,.80,.80)
		var new_dry := ShaderMaterial.new()
		new_dry.shader = GROUND
		new_dry.set_shader_parameter("ground_color",source.albedo_texture)
		new_dry.set_shader_parameter("ground_normal",source.normal_texture)
		new_dry.set_shader_parameter("surface_data",source.roughness_texture)
		new_dry.set_shader_parameter("base_roughness", source.roughness)
		new_dry.set_shader_parameter("normal_depth", source.normal_scale)
		new_dry.set_shader_parameter("ao_light_affect", source.ao_light_affect)
		new_dry.set_shader_parameter("stone", key=="rock")
		var new_wet := new_dry.duplicate() as ShaderMaterial
		new_wet.set_shader_parameter("moisture",Vector2(.929066658,1.0))
		materials[0][key] = source
		materials[1][key] = new_dry
		materials[2][key] = old_wet
		materials[3][key] = new_wet
		displayed[key] = []
	for id in ["camp","approach"]:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_buffer(FileAccess.get_file_as_bytes("res://"+id+".bin"),"",state) != OK:
			push_error("Could not load the original " + id + " geometry")
			return
		var part := document.generate_scene(state)
		add_child(part)
		for node: MeshInstance3D in part.find_children("*","MeshInstance3D",true,false):
			var key := String(node.name).get_slice("__",0)
			node.visible = displayed.has(key)
			if node.visible:
				displayed[key].append(node)
	compare.call_deferred()

func apply_variant(mode: int) -> void:
	for key in displayed:
		for node: MeshInstance3D in displayed[key]:
			node.material_override = materials[mode][key]

func compare() -> void:
	for mode in [0,1,3,2,2,3,1,0]:
		apply_variant(mode)
		for frame in 16:
			await RenderingServer.frame_post_draw
		var times := PackedFloat64Array()
		var previous := Time.get_ticks_usec()
		for frame in 75:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			times.append(float(now-previous)/1000.0)
			previous = now
		times.sort()
		var label: String = ["previous-dry","revised-dry","previous-storm","revised-storm"][mode]
		stats.append({"variant":label,"p50_ms":times[37],"p95_ms":times[71],"max_ms":times[74]})
	JavaScriptBridge.eval("window.groundMaterialQA = "+JSON.stringify(stats))
	var api := JavaScriptBridge.get_interface("window")
	callback = JavaScriptBridge.create_callback(set_variant)
	api.setGroundVariant = callback

func set_variant(args: Array) -> void:
	if args.size() == 1 and int(args[0]) in [0,1,2,3]:
		apply_variant(int(args[0]))
