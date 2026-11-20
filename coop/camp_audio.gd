extends Node3D

const Lake = preload("res://lake_layout.gd")
const Network = preload("res://network.gd")
const Stones = preload("res://stones.gd")

const VOICE_COUNT := 8
const ENGINE_RANGE := 54.0
const ENGINE_LOOP = preload("res://sounds/engine-loop.wav")
# Each cue stores its clip variations, gain in dB and hearing distance in metres.
const CUES := {
	&"trail": [[preload("res://sounds/step-trail-1.wav"), preload("res://sounds/step-trail-2.wav")], -12.0, 16.0],
	&"leaves": [[preload("res://sounds/step-leaves-1.wav"), preload("res://sounds/step-leaves-2.wav")], -11.0, 16.0],
	&"wood": [[preload("res://sounds/step-wood-1.wav"), preload("res://sounds/step-wood-2.wav")], -11.0, 18.0],
	&"wade": [[preload("res://sounds/step-wade-1.wav"), preload("res://sounds/step-wade-2.wav")], -11.0, 18.0],
	&"stroke": [[preload("res://sounds/swim-stroke-1.wav"), preload("res://sounds/swim-stroke-2.wav")], -13.0, 19.0],
	&"dive": [[preload("res://sounds/swim-deep.wav")], -12.0, 14.0],
	&"swim_entry": [[preload("res://sounds/swim-entry.wav")], -9.0, 24.0],
	&"stone_throw": [[preload("res://sounds/stone-throw.wav")], -11.0, 18.0],
	&"stone_earth": [[preload("res://sounds/stone-earth.wav")], -10.0, 27.0],
	&"stone_wood": [[preload("res://sounds/stone-wood.wav")], -10.0, 28.0],
	&"stone_rock": [[preload("res://sounds/stone-rock.wav")], -11.0, 29.0],
	&"stone_water": [[preload("res://sounds/stone-water.wav")], -10.0, 29.0],
	&"engine_start": [[preload("res://sounds/engine-start.wav")], -11.0, ENGINE_RANGE],
	&"engine_stop": [[preload("res://sounds/engine-stop.wav")], -12.0, ENGINE_RANGE],
	&"rifle": [[preload("res://sounds/rifle-shot.wav")], -8.0, 68.0],
	&"pistol": [[preload("res://sounds/pistol-shot.wav")], -10.0, 43.0],
}

enum Pose {AIR, GROUND, SWIM, PILOT}

class Gait:
	var at: Vector3
	var pose: int
	var travel := 0.0
	var stride := 0.28
	var idle := 0.0
	var splash_cooldown := 0.0

	func _init(at_: Vector3, pose_: int) -> void:
		at = at_
		pose = pose_

var _route: Array
var _voices: Array[AudioStreamPlayer3D] = []
var _priority := PackedInt32Array()
var _voice_cursor := 0
var _engine: AudioStreamPlayer3D
var _browser: JavaScriptObject
var _camera: Camera3D
var _gaits: Dictionary[String, Gait] = {}
var _last_roster: Dictionary = {}
var _last_stone_sound := 0
var _last_weapon_attack := {}
var _last_room_time := -1.0
var _joined := false
var _enabled := false
var _engine_on := false
var _engine_gain := 0.0
var _engine_load := 0.0
var _next_browser_engine_update := 0.0

func configure(route: Array) -> void:
	_route = route

func _ready() -> void:
	if OS.has_feature("web") and bool(JavaScriptBridge.eval("Boolean(window.CooperAudio)", true)):
		_browser = JavaScriptBridge.get_interface("CooperAudio")
	if _browser != null:
		_browser.configure(VOICE_COUNT)
		_register_browser_clip(ENGINE_LOOP)
		for cue: Array in CUES.values():
			for clip: AudioStreamWAV in cue[0]:
				_register_browser_clip(clip)
		return
	_priority.resize(VOICE_COUNT)
	for index in VOICE_COUNT:
		_voices.append(_make_player())
	_engine = _make_player()
	_engine.stream = ENGINE_LOOP
	_set_range(_engine, ENGINE_RANGE)

func _make_player() -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.attenuation_filter_db = 0.0
	player.max_db = 0.0
	add_child(player)
	return player

func _register_browser_clip(clip: AudioStreamWAV) -> void:
	_browser.register(clip.resource_path.get_file(), clip.mix_rate, Marshalls.raw_to_base64(clip.data))

func _set_range(player: AudioStreamPlayer3D, distance: float) -> void:
	player.unit_size = distance * 0.21
	player.max_distance = distance

func update_world(net: Network, avatars: Dictionary, camera: Camera3D, ship_at: Vector3,
		delta: float, controls_active: bool) -> void:
	_camera = camera
	if not net.ready_in_room or net.elapsed + 0.5 < _last_room_time:
		if _joined:
			_reset_room()
		if not net.ready_in_room:
			return
	_last_room_time = net.elapsed
	var entering := not _joined or not _enabled
	_joined = true
	_enabled = _enabled or controls_active
	_consume_stones(net.stone_sounds, net.elapsed, not entering and _enabled)
	_consume_shots(net.players, net.elapsed, not entering and _enabled)
	if not _enabled:
		return
	_update_engine(net.ship, ship_at, delta, entering)
	if not is_same(_last_roster, net.players):
		_last_roster = net.players
		for id: String in _gaits.keys():
			if not net.players.has(id):
				_gaits.erase(id)
	var local := net.player_motion
	var self_at := Vector3(net.local_position.x, local.y, net.local_position.y)
	var pilot := str(net.ship.get("pilot", ""))
	_track(net.self_id, self_at, _pose(self_at, float(local.vy), local.swimming, pilot == net.self_id),
		delta, true, controls_active)
	for id: String in avatars:
		var avatar: Node3D = avatars[id]
		var sample: Dictionary = net.players[id]
		var sample_at := Vector3(sample.x, sample.get("y", avatar.position.y), sample.z)
		var pose := _pose(sample_at, float(sample.get("vy", 0.0)), bool(sample.get("swimming", false)), pilot == id)
		_track(id, avatar.position, pose, delta, false, true)

func _reset_room() -> void:
	_joined = false
	_last_room_time = -1.0
	_last_stone_sound = 0
	_last_weapon_attack.clear()
	_last_roster = {}
	_gaits.clear()
	_engine_on = false
	_engine_gain = 0.0
	_engine_load = 0.0
	_next_browser_engine_update = 0.0
	if _browser != null:
		_browser.silence()
	else:
		_engine.stop()
		for player in _voices:
			player.stop()

func _consume_stones(events: Array, elapsed: float, audible: bool) -> void:
	for event: Dictionary in events:
		var id := int(event.id)
		if id <= _last_stone_sound:
			continue
		_last_stone_sound = id
		if audible and elapsed - float(event.at) <= 0.55:
			_play(StringName(event.cue), Stones.unpack(event.point), float(event.get("strength", 1.0)), 3)

func _consume_shots(players: Dictionary, elapsed: float, audible: bool) -> void:
	for id: String in _last_weapon_attack.keys():
		if not players.has(id):
			_last_weapon_attack.erase(id)
	for id: String in players:
		var player: Dictionary = players[id]
		var weapon: String = player.get("attackWeapon", "")
		var attack_at := float(player.get("attackAt", -10.0))
		if weapon not in ["rifle", "pistol"] or attack_at <= float(_last_weapon_attack.get(id, -10.0)):
			continue
		_last_weapon_attack[id] = attack_at
		if audible and elapsed - attack_at <= 0.35:
			_play(StringName(weapon), Vector3(player.x, player.y + 1.40, player.z), 1.0, 3)

func _pose(at: Vector3, vy: float, swimming: bool, piloting: bool) -> int:
	if piloting:
		return Pose.PILOT
	if swimming:
		return Pose.SWIM
	var floor_y := Lake.walk_height(Vector2(at.x, at.z))
	return Pose.GROUND if absf(vy) < 0.24 and at.y <= floor_y + 0.11 else Pose.AIR

func _track(id: String, at: Vector3, pose: int, delta: float, local: bool, walking_allowed: bool) -> void:
	if not _gaits.has(id):
		_gaits[id] = Gait.new(at, pose)
		return
	var gait: Gait = _gaits[id]
	var motion := at - gait.at
	var before := gait.pose
	gait.at = at
	gait.pose = pose
	gait.splash_cooldown = maxf(gait.splash_cooldown - delta, 0.0)
	var priority := 2 if local else 1
	var strength := 1.18 if local else 0.83
	var plausible := motion.length() < maxf(0.87, delta * 7.0)
	if pose != before or not plausible:
		gait.travel = 0.0
		gait.stride = 0.28
		if pose == Pose.SWIM and before != Pose.SWIM and (plausible or before == Pose.PILOT) and gait.splash_cooldown <= 0.0:
			_play(&"swim_entry", Vector3(at.x, Lake.water_y(), at.z), strength, 3)
			gait.splash_cooldown = 0.81
			gait.stride = 0.65
		elif pose == Pose.GROUND and before == Pose.AIR and plausible and walking_allowed:
			_play(_surface(Vector2(at.x, at.z)), at, strength * 0.89, priority)
			gait.stride = 1.12
		return
	if not walking_allowed or pose == Pose.PILOT or pose == Pose.AIR:
		return
	var distance := motion.length() if pose == Pose.SWIM else Vector2(motion.x, motion.z).length()
	if distance < 0.32 * delta:
		gait.idle += delta
		if gait.idle > 0.22:
			gait.travel = 0.0
			gait.stride = 0.30
		return
	gait.idle = 0.0
	gait.travel += minf(distance, delta * 5.0)
	if gait.travel < gait.stride:
		return
	gait.travel -= gait.stride
	if pose == Pose.SWIM:
		var deep := at.y < Lake.water_y() - 0.57
		var source := at + Vector3.UP * (0.17 if deep else 0.23)
		_play(&"dive" if deep else &"stroke", source, strength, priority)
		gait.stride = 0.80
	else:
		_play(_surface(Vector2(at.x, at.z)), at, strength, priority)
		gait.stride = 1.12

func _surface(point: Vector2) -> StringName:
	if Lake.on_dock(point):
		return &"wood"
	if Lake.surface_height(point) > Lake.ground_height(point) + 0.023:
		return &"wade"
	for index in range(_route.size() - 1):
		var left: Array = _route[index]
		var right: Array = _route[index + 1]
		if point.y >= float(right[2]) or index == _route.size() - 2:
			# Matches the 8 metre wide trail strip baked from the world route.
			var blend := smoothstep(0.0, 1.0, inverse_lerp(float(left[2]), float(right[2]), point.y))
			var center := lerpf(float(left[1]), float(right[1]), blend)
			return &"trail" if absf(point.x - center) <= 4.0 else &"leaves"
	return &"leaves"

func _update_engine(ship: Dictionary, at: Vector3, delta: float, entering: bool) -> void:
	var powered := not str(ship.get("pilot", "")).is_empty()
	if powered != _engine_on and not entering:
		_play(&"engine_start" if powered else &"engine_stop", at, 1.0, 4)
	_engine_on = powered
	if not powered and _engine_gain == 0.0:
		return
	var lift_thrust := float(ship.get("thrust", 0.0 if ship.get("landed", true) else 0.62))
	var rear_thrust := float(ship.get("rearThrust", 0.0))
	var thrust := clampf(maxf(lift_thrust, rear_thrust * 0.93), 0.0, 1.0)
	_engine_load = lerpf(_engine_load, thrust, 1.0 - exp(-3.3 * delta))
	_engine_gain = lerpf(_engine_gain, float(powered), 1.0 - exp((-3.3 if powered else -7.0) * delta))
	if not powered and _engine_gain <= 0.008:
		_engine_gain = 0.0
		_engine_load = 0.0
		if _browser != null:
			_browser.stopEngine()
		else:
			_engine.stop()
		return
	var db := lerpf(-19.0, -10.0, _engine_load) + linear_to_db(maxf(_engine_gain, 0.001))
	var pitch := lerpf(0.90, 1.20, _engine_load)
	if _browser != null:
		_next_browser_engine_update -= delta
		if _next_browser_engine_update <= 0.0:
			_next_browser_engine_update = 0.045
			var spatial := _spatial(at, ENGINE_RANGE)
			_browser.engine(ENGINE_LOOP.resource_path.get_file(), db_to_linear(db) * spatial.x, pitch, spatial.y)
	else:
		_engine.position = at
		_engine.pitch_scale = pitch
		_engine.volume_db = db
		if not _engine.playing:
			_engine.play()

func _spatial(at: Vector3, reach: float) -> Vector2:
	var offset := at - _camera.position
	var distance := offset.length()
	var gain := minf(1.0, reach * 0.21 / maxf(distance, 0.001)) * maxf(0.0, 1.0 - distance / reach)
	var pan := _camera.basis.x.dot(offset / maxf(distance, 0.001)) * 0.90
	return Vector2(gain, pan)

func _play(cue: StringName, at: Vector3, strength: float, priority: int) -> void:
	if not CUES.has(cue):
		return
	var details: Array = CUES[cue]
	var reach: float = details[2]
	if _camera.position.distance_squared_to(at) >= reach * reach:
		return
	var clips: Array = details[0]
	var clip: AudioStreamWAV = clips[randi() % clips.size()]
	var db: float = details[1] + linear_to_db(strength) + randf_range(-0.8, 0.8)
	var pitch := randf_range(0.93, 1.07) if priority < 4 else 1.0
	if _browser != null:
		var spatial := _spatial(at, reach)
		_browser.play(clip.resource_path.get_file(), db_to_linear(db) * spatial.x, pitch, spatial.y, priority)
		return
	var slot := _voice_slot(priority)
	if slot < 0:
		return
	var player := _voices[slot]
	_priority[slot] = priority
	_voice_cursor = (slot + 1) % VOICE_COUNT
	player.stop()
	player.position = at
	player.stream = clip
	_set_range(player, reach)
	player.volume_db = db
	player.pitch_scale = pitch
	player.play()

func _voice_slot(priority: int) -> int:
	var reusable := -1
	for index in VOICE_COUNT:
		var slot := (index + _voice_cursor) % VOICE_COUNT
		if not _voices[slot].playing:
			return slot
		if _priority[slot] < priority and reusable < 0:
			reusable = slot
	return reusable
