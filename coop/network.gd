extends Node

const Rules = preload("res://rules.gd")
const SEND_INTERVAL := 0.075

var local_position := Vector2.ZERO
var players: Dictionary = {}
var self_id := ""
var quest := {"wood": false, "tarp": false, "repaired": false}
var elapsed := 0.0
var grove_elapsed := 0.0
var rain := 0.0
var stones: Dictionary = {}
var line_cut := false
var water_impacts: Array = []
var provisions: Dictionary = {}
var survival: Dictionary = {}
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
var _grid: Dictionary
var _reconnect_in := 0.0
var _send_in := 0.0
var _joined := false
var _connecting_age := 0.0
var _stopped := false
var _correction := Vector2.ZERO
var _last_snapshot_ms := 0

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
	local_position = Rules.pair(world.spawn)
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
	provisions = {}
	survival = {}
	_reconnect_in = 1.5
	status = reason if not reason.is_empty() else "连接中断，正在重连 " + room

func set_motion(direction: Vector2, yaw: float) -> void:
	if not direction.is_equal_approx(_direction):
		_send_in = 0.0
	_direction = direction.limit_length()
	_yaw = yaw

func interact(site: String) -> void:
	if ready_in_room:
		_send({"t": "act", "site": site})

func interact_stone(action: String, id := "", yaw := 0.0, pitch := 0.0) -> void:
	if ready_in_room:
		_send({"t": "stone", "action": action, "id": id, "yaw": yaw, "pitch": pitch})

func interact_provision(action: String, item := "", id := "") -> void:
	if ready_in_room and not survival.is_empty():
		_send({"t": "provision", "action": action, "item": item, "id": id})

func _send(message: Dictionary) -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(message))

func _process(delta: float) -> void:
	if _url.is_empty() or _stopped:
		return
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
		_send({"t": "join", "room": room, "token": _token, "session": _session})
		_joined = true
	while _socket != null and _socket.get_available_packet_count() > 0:
		var msg = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
		if msg is Dictionary:
			_receive(msg)
	if not ready_in_room:
		return
	if Time.get_ticks_msec() - _last_snapshot_ms > 4500:
		_retry("队伍状态更新中断，正在重连 " + room)
		return
	elapsed += delta
	rain = Rules.rain_at(elapsed)
	local_position = Rules.move(local_position, _direction, delta, _grid)
	# Ease small drift until the next authoritative sample.
	var correction := _correction * minf(1.0, delta * 12.0)
	local_position += correction
	_correction -= correction
	_send_in -= delta
	if _send_in <= 0.0:
		_send({"t": "motion", "x": _direction.x, "z": _direction.y, "yaw": _yaw})
		_send_in = SEND_INTERVAL

func _receive(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"welcome":
			self_id = msg.id
			status = "已连接 · " + room
		"snapshot":
			if self_id.is_empty() or not msg.players.has(self_id):
				return
			players = msg.players
			_last_snapshot_ms = Time.get_ticks_msec()
			quest = msg.quest
			stones = msg.get("stones", {})
			line_cut = bool(msg.get("lineCut", false))
			water_impacts = msg.get("waterImpacts", [])
			provisions = msg.get("provisions", {})
			survival = msg.get("survival", {})
			elapsed = msg.elapsed
			grove_elapsed = float(msg.get("groveElapsed", 0.0))
			rain = Rules.rain_at(elapsed)
			var actor: Dictionary = players[self_id]
			var position_from_server := Vector2(actor.x, actor.z)
			if not ready_in_room or local_position.distance_to(position_from_server) > 1.2:
				local_position = position_from_server
				_correction = Vector2.ZERO
			else:
				_correction = position_from_server - local_position
			ready_in_room = true
		"notice":
			last_notice = msg.text
			notice_number += 1
		"reject":
			if msg.code == "identity":
				_token = _identity(true)
			_retry(str(msg.get("text", "房间未就绪")))
