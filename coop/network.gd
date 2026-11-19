extends Node

const Rules = preload("res://rules.gd")
const PlayerMotion = preload("res://player_motion.gd")
const Spaceship = preload("res://spaceship.gd")
const SEND_INTERVAL := 0.075
const SNAPSHOT_TIMEOUT_MS := 4500
const RENDER_PAUSE_MS := 750
const RESUME_ROUND_TRIP_MS := 1000

var local_position := Vector2.ZERO
var player_motion := PlayerMotion.spawn(Vector2.ZERO)
var players: Dictionary = {}
var self_id := ""
var quest := {"wood": false, "tarp": false, "repaired": false}
var elapsed := 0.0
var grove_elapsed := 0.0
var rain := 0.0
var stones: Dictionary = {}
var line_cut := false
var water_impacts: Array = []
var stone_sounds: Array = []
var provisions: Dictionary = {}
var survival: Dictionary = {}
var dog: Dictionary = {}
var dog_sample_time := -1.0
var crocodile: Dictionary = {}
var ship: Dictionary = {}
var backpack_owner := ""
var backpack_enabled := false
var ready_in_room := false
var status := "尚未连接"
var last_notice := ""
var notice_number := 0
var room := ""

var _socket: WebSocketPeer
var _url := ""
var _token := ""
var _session := ""
var _direction := Vector2.ZERO
var _yaw := 0.0
var _lift := 0.0
var _grid: Dictionary
var _ship_grid: Dictionary
var _predicted_ship := {}
var _predicted_velocity := Vector3.ZERO
var _ship_correction := Vector3.ZERO
var _heading_correction := 0.0
var _reconnect_in := 0.0
var _send_in := 0.0
var _joined := false
var _connecting_age := 0.0
var _stopped := false
var _correction := Vector2.ZERO
var _height_correction := 0.0
var _last_snapshot_ms := 0
var _snapshot_seq := 0
var _last_process_ms := -1
var _resume_snapshot_until_ms := -1

func start_room(url: String, code: String, token: String = "") -> void:
	if _socket != null:
		_socket.close()
	room = code.strip_edges().to_lower()
	_url = url
	_stopped = not Rules.room_code_valid(room)
	if _stopped:
		status = "房间码请使用 1–24 位英文、数字、横线或下划线"
		return
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	_grid = Rules.collision_grid(world.obstacles)
	_ship_grid = Spaceship.collision_grid(world)
	local_position = Rules.pair(world.spawn)
	player_motion = PlayerMotion.spawn(local_position)
	grove_elapsed = 0.0
	_token = token if not token.is_empty() else _identity(false)
	_session = Crypto.new().generate_random_bytes(12).hex_encode()
	_connect_room()

func _identity(renew: bool) -> String:
	var existing := ""
	if OS.has_feature("web"):
		var storage = JavaScriptBridge.get_interface("sessionStorage")
		if storage != null and not renew:
			var value = storage.getItem("cooper-identity")
			if value != null:
				existing = str(value)
		if existing.length() != 32:
			existing = Crypto.new().generate_random_bytes(16).hex_encode()
			if storage != null:
				storage.setItem("cooper-identity", existing)
	else:
		var path := "user://coop-identity.txt"
		if FileAccess.file_exists(path) and not renew:
			existing = FileAccess.get_file_as_string(path).strip_edges()
		if existing.length() != 32:
			existing = Crypto.new().generate_random_bytes(16).hex_encode()
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null:
				file.store_string(existing)
	return existing

func _connect_room() -> void:
	_socket = WebSocketPeer.new()
	_joined = false
	_snapshot_seq = 0
	_resume_snapshot_until_ms = -1
	_send_in = 0.0
	_connecting_age = 0.0
	ready_in_room = false
	status = "正在连接房间 " + room
	if _socket.connect_to_url(_url) != OK:
		_retry()

func _retry(reason: String = "") -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	ready_in_room = false
	_direction = Vector2.ZERO
	players = {}
	stones = {}
	water_impacts = []
	stone_sounds = []
	provisions = {}
	survival = {}
	dog = {}
	dog_sample_time = -1.0
	crocodile = {}
	ship = {}
	_predicted_ship = {}
	_predicted_velocity = Vector3.ZERO
	_ship_correction = Vector3.ZERO
	_heading_correction = 0.0
	_lift = 0.0
	backpack_enabled = false
	backpack_owner = ""
	_reconnect_in = 1.5
	status = reason if not reason.is_empty() else "连接中断，正在重连 " + room

func is_piloting() -> bool:
	return ready_in_room and not self_id.is_empty() and ship.get("pilot", "") == self_id

func rendered_ship() -> Dictionary:
	if not ready_in_room:
		return {}
	return _predicted_ship if is_piloting() and not _predicted_ship.is_empty() else ship

func ship_camera_clearance(pivot: Vector3, offset: Vector3) -> float:
	return Spaceship.Ground.camera_clearance(pivot, offset, _ship_grid, grove_elapsed)

func set_motion(direction: Vector2, yaw: float, lift := 0.0) -> void:
	if not direction.is_equal_approx(_direction) or not is_equal_approx(_lift, lift):
		_send_in = 0.0
	_direction = direction.limit_length()
	_yaw = yaw
	_lift = lift

func interact_ship(action: String) -> void:
	if ready_in_room:
		_send({"t": "ship", "action": action})

func interact(site: String) -> void:
	if ready_in_room:
		_send({"t": "act", "site": site})

func interact_stone(action: String, id := "", yaw := 0.0, pitch := 0.0) -> void:
	if ready_in_room:
		_send({"t": "stone", "action": action, "id": id, "yaw": yaw, "pitch": pitch})

func interact_provision(action: String, item := "", id := "") -> void:
	if ready_in_room and not survival.is_empty():
		_send({"t": "provision", "action": action, "item": item, "id": id})

func interact_dog(action: String) -> void:
	if ready_in_room and not dog.is_empty():
		_send({"t": "dog", "action": action})

func _send(message: Dictionary) -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(message))

func _process(delta: float) -> void:
	if _url.is_empty() or _stopped:
		return
	var now_ms := Time.get_ticks_msec()
	var after_render_pause := _last_process_ms >= 0 and now_ms - _last_process_ms >= RENDER_PAUSE_MS
	_last_process_ms = now_ms
	if _socket == null:
		_reconnect_in -= delta
		if _reconnect_in <= 0.0:
			_connect_room()
		return
	_socket.poll()
	var connection := _socket.get_ready_state()
	if connection == WebSocketPeer.STATE_CLOSED:
		_retry("房间服务器暂时不可达，正在重连 " + room)
		return
	if not ready_in_room:
		_connecting_age += delta
		if _connecting_age > 9.0:
			_retry()
			return
	if connection != WebSocketPeer.STATE_OPEN:
		return
	if not _joined:
		_send({"t": "join", "room": room, "token": _token, "session": _session, "snapshotFlow": true})
		_joined = true
	while _socket != null and _socket.get_available_packet_count() > 0:
		var msg = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
		if msg is Dictionary:
			_receive(msg)
	if not ready_in_room:
		return
	var snapshot_age := now_ms - _last_snapshot_ms
	if after_render_pause and _resume_snapshot_until_ms < 0 and snapshot_age + RESUME_ROUND_TRIP_MS >= SNAPSHOT_TIMEOUT_MS:
		# A suspended render loop may resume before the WebSocket callback or its
		# next acknowledgement. Give the current connection one round trip.
		_resume_snapshot_until_ms = now_ms + RESUME_ROUND_TRIP_MS
		_send_in = 0.0
	if snapshot_age > SNAPSHOT_TIMEOUT_MS and now_ms >= _resume_snapshot_until_ms:
		_retry("队伍状态更新中断，正在重连 " + room)
		return
	elapsed += delta
	grove_elapsed += delta
	rain = Rules.rain_at(elapsed)
	if is_piloting():
		_predict_ship(delta)
	else:
		player_motion.point = local_position
		PlayerMotion.step(player_motion, _direction, _lift, delta, _grid, ship, _ship_grid, grove_elapsed)
		local_position = player_motion.point
	# Ease small drift until the next authoritative sample.
	var blend := minf(1.0, delta * 12.0)
	var correction := _correction * blend
	local_position += correction
	_correction -= correction
	var height_fix := _height_correction * blend
	player_motion.y += height_fix
	_height_correction -= height_fix
	_send_in -= delta
	if _send_in <= 0.0:
		var motion := {"t": "motion", "x": _direction.x, "z": _direction.y, "yaw": _yaw, "lift": _lift}
		if _snapshot_seq > 0:
			motion.snapshotAck = _snapshot_seq
		_send(motion)
		_send_in = SEND_INTERVAL

func _predict_ship(delta: float) -> void:
	if _predicted_ship.is_empty():
		return
	var blend := 1.0 - exp(-delta * 5.0)
	var correction := (_ship_correction * blend).limit_length(delta * 2.6)
	var heading_fix := clampf(_heading_correction * blend, -delta * 0.9, delta * 0.9)
	_predicted_ship.x += correction.x
	_predicted_ship.y += correction.y
	_predicted_ship.z += correction.z
	_predicted_ship.yaw = wrapf(float(_predicted_ship.yaw) + heading_fix, -PI, PI)
	_ship_correction -= correction
	_heading_correction -= heading_fix
	_predicted_velocity = Spaceship.step(_predicted_ship, _predicted_velocity, _direction, _lift,
		_yaw, delta, _ship_grid, grove_elapsed)
	_predicted_ship.v = [_predicted_velocity.x, _predicted_velocity.y, _predicted_velocity.z]

func _reconcile_ship(was_piloting: bool) -> void:
	if ship.get("pilot", "") != self_id:
		_predicted_ship = {}
		return
	var authoritative := Spaceship.position(ship)
	if not was_piloting or _predicted_ship.is_empty() or authoritative.distance_squared_to(Spaceship.position(_predicted_ship)) > 9.0:
		_predicted_ship = ship.duplicate()
		_predicted_velocity = Spaceship.velocity_sample(ship)
		_ship_correction = Vector3.ZERO
		_heading_correction = 0.0
		return
	# Remove snapshot drift over subsequent display frames without replacing the current camera pose.
	_ship_correction = authoritative - Spaceship.position(_predicted_ship)
	_heading_correction = angle_difference(float(_predicted_ship.yaw), float(ship.yaw)) if not ship.landed else 0.0

func _receive(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"welcome":
			self_id = msg.id
			status = "已连接 · " + room
		"snapshot":
			if self_id.is_empty() or not msg.players.has(self_id):
				return
			_snapshot_seq = int(msg.get("snapshotSeq", 0))
			players = msg.players
			_last_snapshot_ms = Time.get_ticks_msec()
			_resume_snapshot_until_ms = -1
			quest = msg.quest
			stones = msg.get("stones", {})
			line_cut = bool(msg.get("lineCut", false))
			water_impacts = msg.get("waterImpacts", [])
			stone_sounds = msg.get("stoneSounds", [])
			provisions = msg.get("provisions", {})
			survival = msg.get("survival", {})
			dog = msg.get("dog", {})
			dog_sample_time = float(msg.elapsed)
			crocodile = msg.get("crocodile", {})
			var was_piloting := is_piloting()
			ship = msg.get("ship", {})
			_reconcile_ship(was_piloting)
			backpack_enabled = msg.has("backpackOwner")
			backpack_owner = str(msg.get("backpackOwner", ""))
			elapsed = msg.elapsed
			grove_elapsed = float(msg.get("groveElapsed", 0.0))
			rain = Rules.rain_at(elapsed)
			var actor: Dictionary = players[self_id]
			var position_from_server := Vector2(actor.x, actor.z)
			var swimming: bool = actor.get("swimming", false)
			var height: float = actor.get("y", PlayerMotion.Lake.walk_height(position_from_server))
			if not ready_in_room or was_piloting or is_piloting() or local_position.distance_to(position_from_server) > 1.2:
				local_position = position_from_server
				_correction = Vector2.ZERO
				player_motion = PlayerMotion.spawn(local_position)
				player_motion.jumpHeld = _lift > 0.0
				player_motion.y = height
				player_motion.vy = float(actor.get("vy", 0.0))
				player_motion.swimming = swimming
				_height_correction = 0.0
			else:
				_correction = position_from_server - local_position
				if swimming != player_motion.swimming or absf(height - float(player_motion.y)) > 0.48:
					player_motion.swimming = swimming
					player_motion.y = height
					player_motion.vy = float(actor.get("vy", 0.0))
					_height_correction = 0.0
				else:
					_height_correction = height - float(player_motion.y)
			ready_in_room = true
		"notice":
			last_notice = msg.text
			notice_number += 1
		"reject":
			if msg.code == "identity":
				_token = _identity(true)
			_retry(str(msg.get("text", "房间未就绪")))
