extends SceneTree

const Audio = preload("res://camp_audio.gd")
const Face = preload("res://wild_face.gd")
const PeopleScene = preload("res://wild_people_scene.gd")
const Net = preload("res://network.gd")
var errors: Array[String] = []
var metrics := {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		push_error(label)

func check_rain_wrap(rain: AudioStreamPlayer) -> void:
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, &"Rain test")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, capture)
	rain.bus = AudioServer.get_bus_name(bus)
	rain.seek(rain.stream.get_length() - 0.24)
	await create_timer(0.10).timeout
	capture.clear_buffer()
	await create_timer(0.40).timeout
	var frames := capture.get_buffer(capture.get_frames_available())
	var hop := roundi(AudioServer.get_mix_rate() * 0.01)
	var levels := PackedFloat32Array()
	for start in range(0, frames.size() - hop + 1, hop):
		var power := 0.0
		for i in range(start, start + hop):
			power += frames[i].length_squared() * 0.5
		levels.append(linear_to_db(sqrt(power / hop)))
	levels.sort()
	check(rain.playing and rain.get_playback_position() < 1.0, "native rain wraps without restarting")
	check(levels.size() > 25 and levels[0] > -55 and levels[0] > levels[levels.size() / 2] - 12.0, "native stereo output remains audible across the rain seam")
	if not levels.is_empty():
		print("NATIVE_RAIN_WRAP ", JSON.stringify({"windows10ms":levels.size(),"quietestDb":levels[0],"medianDb":levels[levels.size() / 2]}))
	rain.bus = &"Master"
	AudioServer.remove_bus(bus)

func run() -> void:
	for key: String in PeopleScene.MODELS:
		var model: Node3D = load(PeopleScene.MODELS[key]).instantiate()
		var face := Face.new(model)
		check(face.skin != null and face.shapes.size() == 3 and not face.shapes.has(-1), key + " has three imported facial controls")
		var npc := {"id":key, "sex": "female" if key.begins_with("female") else "male", "phase":"resident", "speechAt":10.0}
		var opened := 0
		var silent := 0
		var blinks := 0
		for i in 500:
			var at := 10.0 + i * 0.02
			var pose := Face.pose(npc, at)
			face.apply(pose)
			if face.skin != null:
				check(absf(face.skin.get_blend_shape_value(face.shapes[0]) - pose.x) < .001, key + " drives the imported mesh")
			if i < 148:
				if pose.x > 0.55: opened += 1
				if pose.x < 0.04: silent += 1
			else:
				check(pose.x == 0.0 or at < 12.98, key + " closed after voice")
			if pose.z > 0.8: blinks += 1
		check(opened > 10 and silent > 8 and blinks >= 2, key + " opens, pauses, blinks")
		metrics[key] = {"loudFrames":opened,"quietFrames":silent,"closedEyeFrames":blinks}
		model.free()
	var audio := Audio.new()
	var camera := Camera3D.new()
	root.add_child(camera)
	root.add_child(audio)
	audio._camera = camera
	var net := Net.new()
	net.rain = 1.0
	net.elapsed = 80
	camera.position = Vector3(-11.0, 1.0, -52)
	net.crocodile = {"at":[-11.0,0,-52.5],"clip":"Swim","clipAt":79.5}
	var fire := {"f":{"kind":"campfire","at":[-10.0,0,-52.0],"mode":"ground","fuelUntil":83.0}}
	audio._ambient.update(audio,net,fire,0.2,camera.position)
	for key in ["rain","stream","croc","fire"]:
		var player = audio._ambient.players[key]
		check(player.playing and player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, key + " has an active looping voice")
	var rain: AudioStreamPlayer = audio._ambient.players["rain"]
	check(rain.stream.stereo, "rain keeps the two recorded channels")
	var outdoor_ear := camera.position
	for i in 24:
		camera.rotate_y(TAU / 24)
		camera.position = outdoor_ear + camera.basis.z * 3.55
		audio._ambient.update(audio,net,fire,0.2,outdoor_ear)
	check(rain.playing and absf(rain.volume_db - Audio.Ambience.LOOPS[&"rain"][1]) < 0.05, "shoulder camera orbit preserves outdoor rain level")
	await check_rain_wrap(rain)
	var underwater_ear := Vector3(-24.0, Audio.Lake.water_y() - 1.0, -50.0)
	for i in 12:
		audio._ambient.update(audio,net,fire,0.2,underwater_ear)
	check(rain.playing and rain.volume_db < -7.0, "submerged listener keeps the quieter rain loop")
	var mine_ear := Audio.Lake.Gallery.station("coal_mine", 29.0) + Vector3.UP * 1.6
	for i in 12:
		audio._ambient.update(audio,net,fire,0.2,mine_ear)
	check(rain.playing and rain.volume_db < -22.0, "rain fades at the resident's end of the mine")
	var before := audio._voice_cursor
	net.crocodile.clip = "Attack"
	net.crocodile.clipAt = net.elapsed
	audio._consume_croc(net.crocodile, net.elapsed, true)
	check(audio._voices[before].stream.resource_path.ends_with("croc_attack.wav"), "croc lunge plays attack")
	var next := audio._voice_cursor
	audio._consume_croc(net.crocodile,net.elapsed+.1,true)
	check(audio._voice_cursor == next, "croc attack deduplicated")
	net.rain = 0
	net.elapsed = 90
	camera.position = Vector3(70,8,-31)
	for i in 20: audio._ambient.update(audio,net,fire,0.2,camera.position)
	check(audio._ambient.gains.is_empty(), "extinguished, stopped or out of range loops fall silent")
	for cue: Array in Audio.CUES.values():
		for clip: AudioStreamWAV in cue[0]:
			check(not clip.stereo and clip.format == AudioStreamWAV.FORMAT_16_BITS and clip.get_length() > .04, clip.resource_path)
	for voice in audio._voices: voice.stop()
	for cue in ["npc_hit","animal_hit","eat_apple","eat_bread","drink_water","eat_meat","camp_work","mine_strike","item_pickup","melee_swing","stroke"]:
		var cursor := audio._voice_cursor
		audio._play(cue,camera.position,1,4)
		check(audio._voices[cursor].stream == Audio.CUES[cue][0][0], cue + " reaches the native mixer")
		audio._voices[cursor].stop()
	print("FACE_AND_WORLD_AUDIO ", JSON.stringify({"models":metrics,"errors":errors}))
	net.free()
	audio.free()
	camera.free()
	await create_timer(0.15).timeout
	quit(0 if errors.is_empty() else 1)
