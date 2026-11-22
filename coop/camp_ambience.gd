extends RefCounted

const Lake = preload("res://lake_layout.gd")
const Stones = preload("res://stones.gd")
# Recording gain in dB and audible radius in metres.
const LOOPS := {
	&"rain": [preload("res://sounds/ai/forest_rain.wav"), 5.5, 0.0],
	&"stream": [preload("res://sounds/ai/valley_brook.wav"), 8.0, 15.0],
	&"croc": [preload("res://sounds/ai/croc_swim.wav"), -2.0, 19.0],
	&"fire": [preload("res://sounds/ai/camp_fire.wav"), 11.0, 12.0],
}
var players: Dictionary = {}
var gains: Dictionary = {}
var until_update := 0.0
var browser: JavaScriptObject

func setup(audio) -> void:
	if OS.has_feature("web"):
		browser = JavaScriptBridge.get_interface("CooperAmbience")
	for key: StringName in LOOPS:
		var clip: AudioStreamWAV = LOOPS[key][0]
		if browser != null:
			audio.register_browser_clip(browser, clip)
		elif key == &"rain":
			var rain := AudioStreamPlayer.new()
			rain.stream = clip
			audio.add_child(rain)
			players[key] = rain
		else:
			var player: AudioStreamPlayer3D = audio._make_player()
			player.stream = clip
			audio._set_range(player, LOOPS[key][2])
			players[key] = player

func reset() -> void:
	if browser != null:
		browser.stopAmbience()
	for player in players.values():
		player.stop()
	gains.clear()
	until_update = 0.0

static func water_source(eye: Vector3) -> Vector3:
	var creek: Dictionary = Lake.layout.creek
	var progress := clampf((eye.z - float(creek.firstZ)) / float(creek.spacing), 0, creek.steps)
	var x := lerpf(Lake.creek_sample(floorf(progress)).x, Lake.creek_sample(ceilf(progress)).x, fmod(progress, 1.0))
	var nearest := Vector3(x, Lake.water_y(), float(creek.firstZ) + progress * float(creek.spacing))
	for id: String in Lake.East.region.camps:
		var shore: Array = Lake.East.region.camps[id].water
		var spring := Vector3(shore[0], Lake.East.springs[id].level, shore[1])
		if eye.distance_squared_to(spring) < eye.distance_squared_to(nearest):
			nearest = spring
	return nearest

func update(audio, net, fire_props: Dictionary, delta: float, weather_ear: Vector3) -> void:
	until_update -= delta
	if until_update > 0.0:
		return
	var dt := minf(0.45, 0.1 - until_update)
	until_update = 0.1
	var eye: Vector3 = audio._camera.position
	var cover := Lake.Gallery.darkness(weather_ear)
	var at_water := Lake.surface_height(Vector2(weather_ear.x, weather_ear.z))
	var outdoors := (1.0 - 0.97 * cover) * (0.18 if weather_ear.y < at_water - 0.07 else 1.0)
	_mix(audio, &"rain", eye, float(net.rain) * outdoors, dt)
	_mix(audio, &"stream", water_source(eye), outdoors, dt)
	var croc: Dictionary = net.crocodile
	var swimming: bool = croc.get("clip", "") in ["Swim", "Dive", "Surface"]
	var croc_at := Stones.unpack(croc.at) if croc.has("at") else eye
	_mix(audio, &"croc", croc_at, (0.23 if croc.get("underwater", false) else 1.0) if swimming else 0.0, dt)
	var nearest := Vector3.INF
	for fire: Dictionary in fire_props.values():
		if fire.get("kind") != "campfire" or fire.get("mode") != "ground" or float(fire.get("fuelUntil", 0)) <= net.elapsed:
			continue
		var point := Stones.unpack(fire.at)
		if eye.distance_squared_to(point) < eye.distance_squared_to(nearest):
			nearest = point
	_mix(audio, &"fire", nearest if nearest.is_finite() else eye, 1.0 if nearest.is_finite() else 0.0, dt)

func _mix(audio, key: StringName, at: Vector3, level: float, dt: float) -> void:
	var spec: Array = LOOPS[key]
	var spatial: Vector2 = Vector2(1.0, 0.0) if key == &"rain" else audio._spatial(at, spec[2])
	var target := db_to_linear(float(spec[1])) * level * spatial.x
	var gain := lerpf(float(gains.get(key, 0.0)), target, 1.0 - exp(-dt * 6.5))
	if target == 0.0 and gain < 0.001:
		if not gains.erase(key):
			return
		gain = 0.0
	else:
		gains[key] = gain
	var clip: AudioStreamWAV = spec[0]
	if browser != null:
		browser.ambient(clip.resource_path.get_file(), gain, spatial.y)
	else:
		var player = players[key]
		if gain <= 0.0:
			player.stop()
			return
		if player is AudioStreamPlayer3D:
			# The engine already attenuates the positional loops.
			player.position = at
			gain /= maxf(spatial.x, 0.001)
		player.volume_db = linear_to_db(gain)
		if not player.playing:
			player.play()
