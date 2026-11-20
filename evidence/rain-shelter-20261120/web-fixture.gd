extends Node3D

const RAIN = preload("res://rain_streaks.gdshader")
const EYE := Vector3(-74.044518,22.51204,-29.55)
var material := ShaderMaterial.new()
var streaks := MultiMeshInstance3D.new()
var rows := 0
var stats := []
var callback: JavaScriptObject

func _ready() -> void:
	var camera := Camera3D.new()
	camera.fov = 72.0
	add_child(camera)
	camera.position = EYE
	camera.look_at(Vector3(-74.25, 19.382, -36.65))
	camera.make_current()

	streaks.position = EYE
	streaks.rotation.y = camera.rotation.y
	add_child(streaks)
	var quad := QuadMesh.new()
	quad.size = Vector2(.012,.20)
	quad.material = material
	material.shader = RAIN
	material.set_shader_parameter("wet",1.0)
	material.set_shader_parameter("fallen",94.5*15.0)
	var slope := streaks.basis.inverse() * Vector3(.1756787,0,-.2037430)
	material.set_shader_parameter("rain_slope",Vector2(slope.x,slope.z))
	var out := FileAccess.open("res://boxes.bin",FileAccess.READ)
	rows = out.get_32()
	var image := Image.create_from_data(4,rows,false,Image.FORMAT_RGBAF,out.get_buffer(16*16*rows))
	material.set_shader_parameter("shelter_boxes", ImageTexture.create_from_image(image))

	var rain := MultiMesh.new()
	rain.transform_format = MultiMesh.TRANSFORM_3D
	rain.use_custom_data = true
	rain.mesh = quad
	rain.instance_count = 960
	var rng := RandomNumberGenerator.new()
	rng.seed = 29121
	for i in rain.instance_count:
		rain.set_instance_transform(i,Transform3D.IDENTITY)
		rain.set_instance_custom_data(i,Color(rng.randf(),rng.randf(),rng.randf(),1))
	rain.custom_aabb = AABB(Vector3(-10,-3,-10),Vector3(20,13,20))
	streaks.multimesh = rain
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	compare.call_deferred()

func compare() -> void:
	for i in [0,rows,rows,0]:
		material.set_shader_parameter("shelter_rows",i)
		for frame in 17:
			await RenderingServer.frame_post_draw
		var times := PackedFloat64Array()
		var previous := Time.get_ticks_usec()
		for frame in 75:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			times.append(float(now-previous)/1000.0)
			previous = now
		times.sort()
		stats.append({"selected_proxies":i,"p50_ms":times[37],"p95_ms":times[71],"max_ms":times[74]})
	JavaScriptBridge.eval("window.rainShadeQA = "+JSON.stringify(stats))
	var api := JavaScriptBridge.get_interface("window")
	callback = JavaScriptBridge.create_callback(set_count)
	api.setRoofCount = callback

func set_count(args: Array) -> void:
	if args.size() == 1:
		var count := int(args[0])
		streaks.visible = count >= 0
		material.set_shader_parameter("shelter_rows", rows if count > 0 else 0)
