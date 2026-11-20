extends Node

signal atlas_reply(action: String, accepted: bool, text: String)

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
var storage: Dictionary = {}
var mines: Dictionary = {}
var storage_available := false
var eagle_alive := true
var survival: Dictionary = {}
var dog: Dictionary = {}
var dog_sample_time := -1.0
var crocodile: Dictionary = {}
var wild_people: Dictionary = {}
var blocking := false
var aim_pitch: Variant = null
var trace_enabled := false
var ship: Dictionary = {}
var backpack_owner := ""
var backpack_enabled := false
var ready_in_room := false
var status := "尚未连接"
var last_notice := ""
var last_notice_site := ""
var notice_number := 0
var room := ""
var atlas_available := false
var atlas_pins: Dictionary = {}

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
	atlas_available = false
	atlas_pins = {}
	stones = {}
	water_impacts = []
	stone_sounds = []
	provisions = {}
	storage = {}
	storage_available = false
	eagle_alive = true
	survival = {}
	dog = {}
	dog_sample_time = -1.0
	crocodile = {}
	wild_people = {}
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

func rescue_player(id: String) -> void:
	if ready_in_room and not id.is_empty():
		_send({"t": "rescue", "id": id})

func travel_to(site: String) -> void:
	if ready_in_room and atlas_available:
		set_motion(Vector2.ZERO, _yaw)
		blocking = false
		aim_pitch = null
		_send_motion()
		_send({"t": "atlas", "action": "travel", "site": site})

func place_atlas_pin(point: Vector2) -> void:
	if ready_in_room and atlas_available:
		var id := Crypto.new().generate_random_bytes(8).hex_encode()
		_send({"t": "atlas", "action": "pin", "id": id, "x": snappedf(point.x, 0.1), "z": snappedf(point.y, 0.1)})

func remove_atlas_pin(id: String) -> void:
	if ready_in_room and atlas_available:
		_send({"t": "atlas", "action": "remove", "id": id})

func interact(site: String) -> void:
	if ready_in_room:
		_send({"t": "act", "site": site})

func interact_stone(action: String, id := "", yaw := 0.0, pitch := 0.0) -> void:
	if ready_in_room:
		_send({"t": "stone", "action": action, "id": id, "yaw": yaw, "pitch": pitch})

func interact_provision(action: String, item := "", id := "") -> void:
	if ready_in_room and not survival.is_empty():
		_send({"t": "provision", "action": action, "item": item, "id": id})

func mine(id: String) -> void:
	if ready_in_room:
		_send({"t":"mine","id":id})

func interact_storage(action: String, fields: Dictionary = {}) -> void:
	if ready_in_room and storage_available:
		var message := fields.duplicate()
		message.t = "storage"
		message.action = action
		_send(message)

func interact_dog(action: String) -> void:
	if ready_in_room and not dog.is_empty():
		_send({"t": "dog", "action": action})

func interact_person(action: String, item := "", id := "", yaw := 0.0, pitch := 0.0) -> void:
	if ready_in_room:
		_send({"t": "person", "action": action, "item": item, "id": id, "yaw": yaw, "pitch": pitch})

func attack_person(body_yaw: float, sight_yaw: float, sight_pitch: float) -> void:
	if ready_in_room:
		_yaw = body_yaw
		_send_motion()
		interact_person("attack", "", "", sight_yaw, sight_pitch)

func _send_motion() -> void:
	var motion := {"t": "motion", "x": _direction.x, "z": _direction.y, "yaw": _yaw, "lift": _lift,
		"blocking": blocking, "aimPitch": aim_pitch}
	if _snapshot_seq > 0:
		motion.snapshotAck = _snapshot_seq
	_send(motion)
	_send_in = SEND_INTERVAL

func _send(message: Dictionary) -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(message))

func _process(delta: float) -> void:
	var trace_start := Time.get_ticks_usec() if trace_enabled else 0
	var trace_packets := 0
	var trace_bytes := 0
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
		var packet := _socket.get_packet()
		var msg = JSON.parse_string(packet.get_string_from_utf8())
		if trace_enabled:
			trace_packets += 1
			trace_bytes += packet.size()
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
	elif not player_motion.get("climbing", false) and not player_motion.get("storageSeated", false):
		player_motion.point = local_position
		var able: bool = survival.get("health", 100.0) > 0.0
		PlayerMotion.step(player_motion, _direction if able else Vector2.ZERO, _lift if able else 0.0,
			delta, _grid, ship, _ship_grid, grove_elapsed, storage)
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
		_send_motion()
	if trace_enabled:
		var total := Time.get_ticks_usec() - trace_start
		if total > 4000:
			var sample := {"wall": Time.get_unix_time_from_system() * 1000.0, "event": "network-frame", "totalUs": total, "packets": trace_packets, "bytes": trace_bytes, "elapsed": elapsed}
			JavaScriptBridge.eval("window.__CooperWildCpu.push(" + JSON.stringify(sample) + ");if(window.__CooperWildCpu.length>512)window.__CooperWildCpu.shift()")

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
			atlas_available = msg.get("fieldAtlas", false) == true
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
			storage = msg.get("storage", {})
			mines = msg.get("mines",{})
			storage_available = msg.has("storage")
			eagle_alive = msg.get("eagleAlive", true)
			var was_down: bool = survival.get("health", 100.0) <= 0.0
			survival = msg.get("survival", {})
			var down: bool = survival.get("health", 100.0) <= 0.0
			dog = msg.get("dog", {})
			dog_sample_time = float(msg.elapsed)
			crocodile = msg.get("crocodile", {})
			wild_people = msg.get("wildPeople", {})
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
			if not ready_in_room or was_down != down or was_piloting or is_piloting() or local_position.distance_to(position_from_server) > 1.2:
				local_position = position_from_server
				_correction = Vector2.ZERO
				player_motion = PlayerMotion.spawn(local_position)
				player_motion.jumpHeld = _lift > 0.0
				player_motion.y = height
				player_motion.vy = float(actor.get("vy", 0.0))
				player_motion.swimming = swimming
				player_motion.grounded = actor.get("grounded", not swimming)
				player_motion.vx = actor.get("vx", 0.0)
				player_motion.vz = actor.get("vz", 0.0)
				player_motion.waterVy = actor.get("waterVy", 0.0)
				_height_correction = 0.0
			else:
				_correction = position_from_server - local_position
				if swimming != player_motion.swimming or absf(height - float(player_motion.y)) > 0.48:
					player_motion.swimming = swimming
					player_motion.grounded = actor.get("grounded", not swimming)
					player_motion.waterVy = actor.get("waterVy", 0.0)
					player_motion.y = height
					player_motion.vy = float(actor.get("vy", 0.0))
					_height_correction = 0.0
				else:
					_height_correction = height - float(player_motion.y)
			player_motion.climbing = actor.get("climbing", false)
			player_motion.storageSeated = actor.get("storageSeated", false)
			ready_in_room = true
		"atlas":
			_receive_atlas(msg)
		"notice":
			last_notice = msg.text
			last_notice_site = str(msg.get("site", ""))
			notice_number += 1
		"reject":
			if msg.code == "identity":
				_token = _identity(true)
			_retry(str(msg.get("text", "房间未就绪")))

func _receive_atlas(msg: Dictionary) -> void:
	var action := str(msg.get("action", ""))
	var accepted: bool = msg.get("ok", false) == true
	if action == "pins" and accepted and msg.get("pins") is Dictionary:
		atlas_pins = msg.pins
	elif action == "travel" and accepted:
		var at: Array = msg.at
		local_position = Vector2(at[0], at[2])
		player_motion = PlayerMotion.put_ashore(Vector3(at[0], at[1], at[2]))
		_direction = Vector2.ZERO
		_lift = 0.0
		_correction = Vector2.ZERO
		_height_correction = 0.0
		if msg.get("ship") is Dictionary:
			var was_piloting := is_piloting()
			ship = msg.ship
			_reconcile_ship(was_piloting)
	atlas_reply.emit(action, accepted, str(msg.get("text", "")))
