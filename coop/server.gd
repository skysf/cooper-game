extends SceneTree

const Rules = preload("res://rules.gd")
const Stones = preload("res://stones.gd")
const LakeLayout = preload("res://lake_layout.gd")
const Survival = preload("res://survival.gd")
const MAX_PLAYERS := 4
const SPAWN_OFFSETS := [Vector2.ZERO, Vector2(-1.25, 0), Vector2(1.25, 0), Vector2(0, 1.4)]
const SNAPSHOT_PERIOD := 0.10
const SAVE_PERIOD := 4.0
const IDLE_INPUT_TIMEOUT := 0.45

var listener := TCPServer.new()
var connections: Dictionary = {}
var rooms: Dictionary = {}
var world: Dictionary
var grid: Dictionary
var save_dir := ""
var next_connection := 1
var snapshot_in := 0.0
var save_in := SAVE_PERIOD

func _initialize() -> void:
	Engine.max_fps = 60
	var port := 4185
	var bind_address := "127.0.0.1"
	save_dir = ProjectSettings.globalize_path("user://rooms")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--bind="):
			bind_address = arg.trim_prefix("--bind=")
		elif arg.begins_with("--save="):
			save_dir = ProjectSettings.globalize_path(arg.trim_prefix("--save="))
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	if not world.has("sites") or not world.has("obstacles"):
		push_error("缺少世界清单")
		quit(1)
		return
	grid = Rules.collision_grid(world.obstacles)
	var result := DirAccess.make_dir_recursive_absolute(save_dir)
	if result != OK:
		push_error("无法创建房间存档目录 " + save_dir)
		quit(1)
		return
	result = listener.listen(port, bind_address)
	if result != OK:
		push_error("房间服务器监听失败 %s:%s (%s)" % [bind_address, port, error_string(result)])
		quit(1)
		return
	print("ROOM_SERVER_READY ", bind_address, ":", port)

func _process(delta: float) -> bool:
	while listener.is_connection_available():
		var tcp := listener.take_connection()
		tcp.set_no_delay(true)
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 8192
		ws.max_queued_packets = 64
		if ws.accept_stream(tcp) == OK:
			connections[next_connection] = {"ws": ws, "room": "", "id": "", "last_packet_ms": Time.get_ticks_msec(), "rejected": false}
			next_connection += 1
	for key in connections.keys():
		var con: Dictionary = connections[key]
		var ws: WebSocketPeer = con.ws
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_leave(key)
			continue
		var grace_ms := 10000 if con.room.is_empty() else 30000
		if Time.get_ticks_msec() - int(con.last_packet_ms) > grace_ms:
			ws.close(1000, "connection idle")
			_leave(key)
			continue
		if con.rejected or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		for n in mini(ws.get_available_packet_count(), 24):
			var bytes := ws.get_packet()
			if bytes.size() > 1024:
				ws.close(1009, "message too large")
				break
			var msg = JSON.parse_string(bytes.get_string_from_utf8())
			if msg is Dictionary:
				con.last_packet_ms = Time.get_ticks_msec()
				_message(con, msg)
			if con.rejected:
				break
	for code in rooms:
		var room: Dictionary = rooms[code]
		if room.actors.is_empty():
			continue
		room.data.elapsed += delta
		var rain := Rules.rain_at(room.data.elapsed)
		for id in room.actors:
			var actor: Dictionary = room.actors[id]
			actor.input_age += delta
			if actor.input_age > IDLE_INPUT_TIMEOUT:
				actor.direction = Vector2.ZERO
			actor.point = Rules.move(actor.point, actor.direction, delta, grid)
			Survival.tick(room.data.survival[id], actor.point, room.data.quest.repaired, rain, delta)
		_tick_stones(room, delta)
	snapshot_in -= delta
	save_in -= delta
	if snapshot_in <= 0.0:
		for code in rooms:
			if not rooms[code].actors.is_empty():
				_publish(code)
		snapshot_in = SNAPSHOT_PERIOD
	if save_in <= 0.0:
		for code in rooms.keys():
			if _checkpoint(code) and rooms[code].actors.is_empty():
				rooms.erase(code)
		save_in = SAVE_PERIOD
	return false

func _message(con: Dictionary, msg: Dictionary) -> void:
	if con.room.is_empty():
		if msg.get("t") == "join":
			_join(con, msg)
		return
	var actor: Dictionary = rooms[con.room].actors[con.id]
	match msg.get("t", ""):
		"motion":
			for field in ["x", "z", "yaw"]:
				var v = msg.get(field)
				if (typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT) or not is_finite(float(v)):
					return
			actor.direction = Vector2(clampf(msg.x, -1, 1), clampf(msg.z, -1, 1)).limit_length()
			actor.yaw = wrapf(msg.yaw, -PI, PI)
			actor.input_age = 0.0
		"act":
			if msg.get("site") is String:
				_act(con, msg.site)
		"stone":
			_stone_action(con, msg)
		"provision":
			_provision_action(con, msg)

func _load_room(code: String) -> bool:
	var path := save_dir.path_join(code + ".json")
	var data := {"version": 1, "elapsed": 0.0, "groveStartedAt": 0.0, "quest": {"wood":false,"tarp":false,"repaired":false}, "homes": {}}
	if FileAccess.file_exists(path):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (saved is Dictionary and saved.get("version") == 1 and saved.get("homes") is Dictionary and saved.get("quest") is Dictionary and saved.quest.has_all(["wood", "tarp", "repaired"])):
			return false
		var elapsed = saved.get("elapsed")
		if not ((elapsed is float or elapsed is int) and is_finite(float(elapsed)) and elapsed >= 0.0):
			return false
		# Existing rooms keep their weather and quest progress, and start the grove on first visit.
		var grove_start = saved.get("groveStartedAt", elapsed)
		if not ((grove_start is float or grove_start is int) and is_finite(float(grove_start)) and grove_start >= 0.0 and grove_start <= elapsed):
			return false
		data = saved
		data.groveStartedAt = grove_start
	data.stones = Stones.from_save(data.get("stones"))
	data.lineCut = data.get("lineCut", false) == true
	data.provisions = Survival.provisions_from_save(data.get("provisions"))
	var personal := {}
	var saved_states: Variant = data.get("survival")
	if saved_states is Dictionary:
		for player: String in saved_states:
			if player.length() == 16 and player.is_valid_hex_number(false):
				personal[player] = Survival.state_from_save(saved_states[player])
	data.survival = personal
	rooms[code] = {"data": data, "actors": {}, "impacts": [], "impactId": 0}
	return true

func _join(con: Dictionary, msg: Dictionary) -> void:
	var code = msg.get("room")
	var token = msg.get("token")
	if not (code is String and Rules.room_code_valid(code) and token is String and token.length() == 32 and token.is_valid_hex_number(false)):
		_reject(con, "format", "房间码或玩家标识无效")
		return
	if not rooms.has(code) and not _load_room(code):
		_reject(con, "storage", "无法读取房间存档")
		return
	var room: Dictionary = rooms[code]
	var id: String = (code + ":" + token).sha256_text().left(16)
	var session_tag = msg.get("session", "")
	if not (session_tag is String and session_tag.length() <= 64):
		_reject(con, "format", "会话标识无效")
		return
	# During Wi-Fi changes a dead TCP connection may linger. A reconnect
	# from the same running client takes over its existing actor and slot.
	if room.actors.has(id) and not session_tag.is_empty():
		for older in connections.values():
			if older.room == code and older.id == id and older.get("session") == session_tag:
				older.room = ""
				older.rejected = true
				older.ws.close(1000, "connection replaced")
				con.room = code
				con.id = id
				con.session = session_tag
				room.actors[id].direction = Vector2.ZERO
				_send(con.ws, {"t":"welcome", "id":id})
				_publish(code)
				return
	if room.actors.has(id):
		_reject(con, "identity", "此玩家已在线，正在分配新身份")
		return
	if room.actors.size() >= MAX_PLAYERS:
		_reject(con, "full", "房间已满（4人），正在等候空位")
		return
	var slot := 1
	var taken := {}
	for actor in room.actors.values():
		taken[actor.slot] = true
	while taken.has(slot):
		slot += 1
	var spawn: Vector2 = Rules.pair(world.spawn) + SPAWN_OFFSETS[slot - 1]
	var home: Dictionary = room.data.homes.get(id, {})
	var point := _restore_position(Vector2(home.get("x", spawn.x), home.get("z", spawn.y)), spawn)
	con.room = code
	con.id = id
	con.session = session_tag
	room.actors[id] = {"point": point, "direction": Vector2.ZERO, "yaw": home.get("yaw", PI), "slot": slot, "input_age": 0.0}
	if not room.data.survival.has(id):
		room.data.survival[id] = Survival.initial_state()
	_send(con.ws, {"t":"welcome", "id":id})
	_publish(code)
	print("ROOM_JOIN ", code, " ", id, " peers=", room.actors.size())

func _restore_position(point: Vector2, spawn: Vector2) -> Vector2:
	if Rules.free_at(point, grid):
		return point
	# A player saved before the grove was planted can resume beside the new trunk.
	for tree in world.get("grove", {}).get("trees", []):
		var center := Vector2(tree.x, tree.z)
		var clearance := float(tree.radius) + Rules.RADIUS
		var offset := point - center
		if offset.length_squared() >= clearance * clearance:
			continue
		if offset.is_zero_approx():
			offset = spawn - center
		var beside_trunk := center + offset.normalized() * (clearance + 0.05)
		if Rules.free_at(beside_trunk, grid):
			return beside_trunk
	return spawn

func _send(ws: WebSocketPeer, msg: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))

func _reject(con: Dictionary, code: String, message: String) -> void:
	con.rejected = true
	_send(con.ws, {"t":"reject", "code":code, "text":message})

func _leave(key: int) -> void:
	var con: Dictionary = connections[key]
	if not con.room.is_empty():
		var room: Dictionary = rooms[con.room]
		var id := Stones.held_by(room.data.stones, con.id)
		if not id.is_empty():
			var actor: Dictionary = room.actors[con.id]
			_set_ground(room.data.stones[id], id, actor.point)
		# Save the last position before evicting an empty room from memory.
		var saved := _checkpoint(con.room)
		room.actors.erase(con.id)
		if room.actors.is_empty() and saved:
			rooms.erase(con.room)
		else:
			_publish(con.room)
		print("ROOM_LEAVE ", con.room, " ", con.id)
	connections.erase(key)

func _provision_action(con: Dictionary, msg: Dictionary) -> void:
	var requested: Variant = msg.get("action")
	if requested is not String or requested not in ["take", "eat_table", "eat", "put", "drop", "drink"]:
		return
	var room: Dictionary = rooms[con.room]
	var actor: Dictionary = room.actors[con.id]
	var before_state: Dictionary = room.data.survival[con.id]
	var before_provisions: Dictionary = room.data.provisions
	var state := before_state.duplicate(true)
	var provisions := before_provisions.duplicate()
	var result := _use_provision(requested, msg, actor, state, provisions)
	if not result.ok:
		_provision_notice(con, false, result.text)
		return
	room.data.survival[con.id] = state
	room.data.provisions = provisions
	if _checkpoint(con.room):
		_publish(con.room)
		_provision_notice(con, true, result.text)
	else:
		room.data.survival[con.id] = before_state
		room.data.provisions = before_provisions
		_provision_notice(con, false, "存档写入失败，请稍后重试")

func _use_provision(action: String, msg: Dictionary, actor: Dictionary, state: Dictionary, provisions: Dictionary) -> Dictionary:
	var point: Vector2 = actor.point
	if action in ["take", "eat_table"]:
		var id: Variant = msg.get("id")
		if id is not String or not provisions.has(id):
			return {"ok": false, "text": "食物已不在这里"}
		var record: Dictionary = provisions[id]
		if not Survival.can_reach(point, Survival.horizontal(record.at), record.surface):
			return {"ok": false, "text": "走近食物后再互动"}
		var food: String = record.item
		if action == "take":
			if not Survival.can_carry(state.bag, food):
				return {"ok": false, "text": "背包已满"}
			state.bag[food] += 1
		else:
			Survival.eat(state, food)
		provisions.erase(id)
		var verb := "捡起了" if action == "take" else "吃掉了"
		return {"ok": true, "text": verb + Survival.ITEM_NAMES[food]}
	if action == "drink":
		if not Survival.can_drink(point):
			return {"ok": false, "text": "靠近水壶后再喝水"}
		if float(state.water) >= Survival.DRINK_THRESHOLD:
			return {"ok": false, "text": "现在不渴"}
		state.water = minf(Survival.MAX_STAT, float(state.water) + Survival.DRINK_GAIN)
		return {"ok": true, "text": "喝了水，水分恢复"}
	var selected: Variant = msg.get("item")
	if selected is not String or not Survival.ITEM_NAMES.has(selected) or int(state.bag[selected]) <= 0:
		return {"ok": false, "text": "背包里没有这份食物"}
	var item_name: String = Survival.ITEM_NAMES[selected]
	if action == "eat":
		state.bag[selected] -= 1
		Survival.eat(state, selected)
		return {"ok": true, "text": "吃掉了" + item_name}
	var surface := "ground"
	var place := Vector3.INF
	if action == "put":
		if not Survival.can_put(point):
			return {"ok": false, "text": "靠近桌子后再放回食物"}
		surface = "table"
		place = Survival.free_table_slot(provisions)
	else:
		place = _provision_drop_position(actor, provisions)
	if not place.is_finite():
		return {"ok": false, "text": "桌上没有空位" if surface == "table" else "脚边没有空地"}
	var id := Crypto.new().generate_random_bytes(8).hex_encode()
	while provisions.has(id):
		id = Crypto.new().generate_random_bytes(8).hex_encode()
	state.bag[selected] -= 1
	provisions[id] = Survival.provision(selected, place, surface)
	var verb := "放回桌上" if surface == "table" else "放下了"
	return {"ok": true, "text": verb + item_name}

func _provision_drop_position(actor: Dictionary, provisions: Dictionary) -> Vector3:
	var point: Vector2 = actor.point
	var facing := Vector2(0.0, -0.58).rotated(-float(actor.yaw))
	for offset: Vector2 in [facing, facing.rotated(PI / 3.0), facing.rotated(-PI / 3.0), Vector2.ZERO]:
		var candidate := point + offset
		if candidate != candidate.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER) or not Rules.free_at(candidate, grid):
			continue
		var height := LakeLayout.walk_height(candidate)
		if height <= LakeLayout.surface_height(candidate):
			continue
		var crowded := false
		for record: Dictionary in provisions.values():
			if record.surface == "ground" and candidate.distance_squared_to(Survival.horizontal(record.at)) < 0.03:
				crowded = true
				break
		if not crowded:
			return Vector3(candidate.x, height + 0.012, candidate.y)
	return Vector3.INF

func _provision_notice(con: Dictionary, ok: bool, message: String) -> void:
	_send(con.ws, {"t": "notice", "ok": ok, "site": "provision", "text": message})

func _stone_action(con: Dictionary, msg: Dictionary) -> void:
	var room: Dictionary = rooms[con.room]
	var actor: Dictionary = room.actors[con.id]
	var stones: Dictionary = room.data.stones
	var held := Stones.held_by(stones, con.id)
	var id := held
	var operation: Variant = msg.get("action")
	var action := ""
	match operation:
		"pick":
			if not held.is_empty() or msg.get("id") is not String or not stones.has(msg.id):
				return
			id = msg.id
			var target: Dictionary = stones[id]
			var at := Stones.unpack(target.at)
			if target.mode not in ["ground", "placed", "submerged"] or at.y < -0.42 or actor.point.distance_to(Vector2(at.x, at.z)) > Stones.PICKUP_REACH:
				return
			action = "pick"
		"context":
			if held.is_empty():
				return
			action = Stones.context_action(held, stones[held], actor.point, room.data.lineCut)
			if action == "press":
				for other: Dictionary in stones.values():
					if other.mode == "placed":
						return
		"drop", "throw":
			if held.is_empty():
				return
			action = operation
	if action.is_empty():
		return
	var stone: Dictionary = stones[id]
	var before := stone.duplicate()
	var line_was_cut: bool = room.data.lineCut
	var result := ""
	match action:
		"pick":
			stone.mode = "held"
			stone.holder = con.id
			result = "捡起石片" if Stones.flat(id) else "捡起苔藓石"
		"drop":
			_set_ground(stone, id, _in_front(actor))
			result = "放下石块"
		"press":
			_set_ground(stone, id, Stones.CANVAS)
			stone.at[1] += 0.018
			stone.mode = "placed"
			result = "用石块压住了帆布角"
		"grind":
			stone.edge = 3
			result = "磨出了新的刃口"
		"cut":
			stone.edge -= 1
			room.data.lineCut = true
			result = "割开麻绳，留出一段营地拉绳"
		"throw":
			var aim_yaw: Variant = msg.get("yaw")
			var aim_pitch: Variant = msg.get("pitch")
			if not _finite_number(aim_yaw) or not _finite_number(aim_pitch):
				return
			var aim := Basis.from_euler(Vector3(clampf(float(aim_pitch), -1.25, 1.45), wrapf(float(aim_yaw), -PI, PI), 0.0))
			var direction := -aim.z
			var point: Vector2 = actor.point
			stone.at = Stones.pack(Vector3(point.x, 1.28 + LakeLayout.walk_height(point), point.y) + direction * 0.30)
			stone.velocity = Stones.pack(direction * (10.6 if Stones.flat(id) else 9.2) + Vector3.UP * 1.1)
			stone.launch = room.data.elapsed
			stone.mode = "air"
			stone.erase("holder")
	if _checkpoint(con.room):
		_publish(con.room)
		if not result.is_empty():
			_send(con.ws, {"t": "notice", "ok": true, "site": id, "text": result})
	else:
		stones[id] = before
		room.data.lineCut = line_was_cut
		_send(con.ws, {"t": "notice", "ok": false, "site": id, "text": "存档写入失败，请稍后重试"})

func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _in_front(actor: Dictionary) -> Vector2:
	var point: Vector2 = actor.point
	var target := point + Vector2(0.0, -0.6).rotated(-float(actor.yaw))
	if target == target.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER) and Rules.free_at(target, grid):
		return target
	return point

func _set_ground(stone: Dictionary, id: String, point: Vector2) -> void:
	stone.mode = "ground"
	stone.at = Stones.pack(Vector3(point.x, LakeLayout.walk_height(point) + Stones.ground_height(id), point.y))
	stone.erase("holder")
	stone.erase("launch")
	stone.erase("velocity")

func _tick_stones(room: Dictionary, delta: float) -> void:
	var elapsed: float = room.data.elapsed
	while not room.impacts.is_empty() and elapsed - float(room.impacts[0].at) > 2.8:
		room.impacts.pop_front()
	for id: String in room.data.stones:
		var stone: Dictionary = room.data.stones[id]
		if stone.mode != "air":
			continue
		var at := Stones.flight_position(stone, elapsed)
		var point := Vector2(at.x, at.z)
		var previous := Stones.flight_position(stone, elapsed - delta)
		var previous_point := Vector2(previous.x, previous.z)
		var bounds := point.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER)
		var standing_ground := LakeLayout.walk_height(point)
		var ground := standing_ground + Stones.ground_height(id)
		var surface := LakeLayout.surface_height(point)
		if standing_ground <= surface and at.y <= maxf(ground, surface):
			if previous.y > surface and at.y < surface:
				var contact := previous.lerp(at, clampf(inverse_lerp(previous.y, at.y, surface), 0.0, 1.0))
				var contact_point := Vector2(contact.x, contact.z)
				if LakeLayout.surface_height(contact_point) >= surface:
					point = contact_point
			_set_ground(stone, id, point)
			stone.mode = "submerged"
			room.impactId += 1
			room.impacts.append({"id": room.impactId, "point": Stones.pack(Vector3(point.x, surface, point.y)), "at": elapsed})
		elif at.y <= ground:
			_set_ground(stone, id, bounds)
		elif at.y < 2.0 and Rules.obstacle_free_at(previous_point, grid) and not Rules.obstacle_free_at(point, grid):
			_set_ground(stone, id, previous_point)

func _act(con: Dictionary, site: String) -> void:
	var room: Dictionary = rooms[con.room]
	var actor: Dictionary = room.actors[con.id]
	if site not in ["wood", "tarp", "repair"] or not world.sites.has(site):
		return
	var result := "走近目标后再互动"
	var accepted := false
	var key := "repaired" if site == "repair" else site
	var quest: Dictionary = room.data.quest
	if actor.point.distance_to(Rules.pair(world.sites[site])) <= Rules.INTERACT_RANGE:
		if quest.get(key, false):
			result = "队伍已完成这项操作"
		elif site == "repair" and not (quest.wood and quest.tarp):
			result = "修屋顶需要木料和防水布"
		else:
			quest[key] = true
			if _checkpoint(con.room):
				accepted = true
				result = {"wood":"木料已加入队伍物资", "tarp":"防水布已加入队伍物资", "repair":"屋顶已修复，营灯亮了"}[site]
				_publish(con.room)
			else:
				quest[key] = false
				result = "存档写入失败，请稍后重试"
	_send(con.ws, {"t":"notice", "ok":accepted, "site":site, "text":result})

func _publish(code: String) -> void:
	var room: Dictionary = rooms[code]
	var actors := {}
	for id in room.actors:
		var a: Dictionary = room.actors[id]
		actors[id] = {"x":a.point.x,"z":a.point.y,"yaw":a.yaw,"slot":a.slot}
	var grove_elapsed := float(room.data.elapsed) - float(room.data.groveStartedAt)
	var snapshot := {"t":"snapshot", "quest":room.data.quest, "elapsed":room.data.elapsed, "groveElapsed":grove_elapsed, "players":actors, "stones":room.data.stones, "lineCut":room.data.lineCut, "waterImpacts":room.impacts}
	for con in connections.values():
		if con.room == code:
			var personal: Dictionary = room.data.survival.get(con.id, {})
			var outgoing := snapshot.duplicate()
			outgoing.provisions = room.data.provisions
			if not personal.is_empty():
				outgoing.survival = Survival.snapshot(personal)
			_send(con.ws, outgoing)

func _checkpoint(code: String) -> bool:
	var room: Dictionary = rooms[code]
	for id in room.actors:
		var a: Dictionary = room.actors[id]
		room.data.homes[id] = {"x":a.point.x, "z":a.point.y, "yaw":a.yaw}
	var path := save_dir.path_join(code + ".json")
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	var saved: Dictionary = room.data.duplicate(true)
	for id: String in saved.stones:
		var stone: Dictionary = saved.stones[id]
		if stone.mode == "held" and room.actors.has(stone.holder):
			_set_ground(stone, id, room.actors[stone.holder].point)
		elif stone.mode == "air":
			var at := Stones.unpack(stone.at)
			_set_ground(stone, id, Vector2(at.x, at.z).clamp(Rules.MIN_CORNER, Rules.MAX_CORNER))
	file.store_string(JSON.stringify(saved))
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok and DirAccess.rename_absolute(temp, path) == OK

func _finalize() -> void:
	for code in rooms:
		_checkpoint(code)
