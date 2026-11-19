extends SceneTree

const Rules = preload("res://rules.gd")
const Stones = preload("res://stones.gd")
const LakeLayout = preload("res://lake_layout.gd")
const Survival = preload("res://survival.gd")
const CampDog = preload("res://camp_dog.gd")
const Wildlife = preload("res://wildlife.gd")
const Spaceship = preload("res://spaceship.gd")
const PlayerMotion = preload("res://player_motion.gd")
const MAX_PLAYERS := 4
const SPAWN_OFFSETS := [Vector2.ZERO, Vector2(-1.25, 0), Vector2(1.25, 0), Vector2(0, 1.4)]
const SNAPSHOT_PERIOD := 0.10
const SAVE_PERIOD := 4.0
const IDLE_INPUT_TIMEOUT := 0.45
const STONE_SOUND_TIME := 1.0
const MAX_STONE_SOUNDS := 16

var listener := TCPServer.new()
var connections: Dictionary = {}
var rooms: Dictionary = {}
var world: Dictionary
var grid: Dictionary
var ship_grid: Dictionary
var save_dir := ""
var next_connection := 1
var snapshot_in := 0.0
var save_in := SAVE_PERIOD
var dog_motion := CampDog.new()

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
		var grove_time := _grove_time(room.data)
		for id in room.actors:
			var actor: Dictionary = room.actors[id]
			actor.input_age += delta
			if actor.input_age > IDLE_INPUT_TIMEOUT:
				actor.direction = Vector2.ZERO
				actor.lift = 0.0
			var piloting: bool = room.ship.pilot == id
			if piloting:
				_tick_spaceship(room, actor, delta)
			else:
				PlayerMotion.step(actor, actor.direction, actor.lift, delta, grid, room.ship, ship_grid, grove_time)
			Survival.tick(room.data.survival[id], actor.point, room.data.quest.repaired, rain, delta, piloting)
		if room.ship.pilot.is_empty() and (room.ship.slipping or room.ship.surface == "tree"):
			_tick_spaceship(room, {}, delta)
		_tick_stones(room, delta)
		dog_motion.tick(room, grid, delta)
		_tick_wildlife(code, room, delta)
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
	var kind: String = str(msg.get("t", ""))
	if kind not in ["motion", "ship"] and rooms[con.room].ship.pilot == con.id:
		return
	match kind:
		"motion":
			if con.get("snapshot_flow", false) and msg.get("snapshotAck", -1) == con.snapshot_sent:
				con.snapshot_acked = con.snapshot_sent
			for field in ["x", "z", "yaw"]:
				var v = msg.get(field)
				if (typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT) or not is_finite(float(v)):
					return
			actor.direction = Vector2(clampf(msg.x, -1, 1), clampf(msg.z, -1, 1)).limit_length()
			actor.yaw = wrapf(msg.yaw, -PI, PI)
			var lift = msg.get("lift", 0.0)
			actor.lift = clampf(float(lift), -1.0, 1.0) if _finite_number(lift) else 0.0
			actor.input_age = 0.0
		"ship":
			if msg.get("action") is String:
				_spaceship_action(con, msg.action)
		"act":
			if msg.get("site") is String:
				_act(con, msg.site)
		"stone":
			_stone_action(con, msg)
		"provision":
			_provision_action(con, msg)
		"dog":
			if msg.get("action") is String:
				_dog_action(con, msg.action)

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
	var saved_owner: Variant = data.get("backpackOwner", "")
	var backpack_owner := ""
	if saved_owner is String and saved_owner.length() == 16 and saved_owner.is_valid_hex_number(false) and saved_states is Dictionary and saved_states.has(saved_owner):
		backpack_owner = saved_owner
	if saved_states is Dictionary:
		for player: String in saved_states:
			if player.length() == 16 and player.is_valid_hex_number(false):
				personal[player] = Survival.state_from_save(saved_states[player], Survival.slot_count(player == backpack_owner))
	data.survival = personal
	data.backpackOwner = backpack_owner
	data.dog = CampDog.from_save(data.get("dog"), personal, grid, data.quest.repaired == true, float(data.elapsed))
	if ship_grid.is_empty():
		ship_grid = Spaceship.collision_grid(world)
	var ship := Spaceship.from_save(data.get("ship"), ship_grid, _grove_time(data))
	data.ship = Spaceship.parked_save(ship)
	rooms[code] = {"data": data, "actors": {}, "impacts": [], "impactId": 0, "dog_route": {},
		"crocodile": Wildlife.crocodile(float(data.elapsed)), "ship": ship, "ship_velocity": Vector3.ZERO,
		"stone_sounds": [], "stone_sound_id": 0}
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
	con.snapshot_flow = msg.get("snapshotFlow", false) == true
	con.snapshot_sent = 0
	con.snapshot_acked = 0
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
				room.actors[id].lift = 0.0
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
	var stored := Vector2(home.get("x", spawn.x), home.get("z", spawn.y))
	var point := _restore_position(stored, spawn)
	var starting_height := LakeLayout.walk_height(point)
	var stored_height: Variant = home.get("y")
	if Spaceship.float_value(stored_height) and stored == stored.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER):
		var foothold := Spaceship.Ground.walk_height(stored, float(stored_height), ship_grid, _grove_time(room.data))
		if foothold > LakeLayout.walk_height(stored) + 0.23 and absf(foothold - float(stored_height)) < 0.50:
			point = stored
			starting_height = foothold
	con.room = code
	con.id = id
	con.session = session_tag
	var actor := PlayerMotion.put_ashore(Vector3(point.x, starting_height, point.y))
	actor.merge({"direction": Vector2.ZERO, "yaw": home.get("yaw", PI), "slot": slot, "input_age": 0.0, "lift": 0.0})
	room.actors[id] = actor
	if not room.data.survival.has(id):
		room.data.survival[id] = Survival.initial_state()
	_send(con.ws, {"t":"welcome", "id":id})
	_publish(code)
	print("ROOM_JOIN ", code, " ", id, " peers=", room.actors.size())

func _restore_position(point: Vector2, spawn: Vector2) -> Vector2:
	if Rules.free_at(point, grid, true):
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

func _send(ws: WebSocketPeer, msg: Dictionary) -> bool:
	return ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.send_text(JSON.stringify(msg)) == OK

func _reject(con: Dictionary, code: String, message: String) -> void:
	con.rejected = true
	_send(con.ws, {"t":"reject", "code":code, "text":message})

func _leave(key: int) -> void:
	var con: Dictionary = connections[key]
	if not con.room.is_empty():
		var room: Dictionary = rooms[con.room]
		if room.ship.pilot == con.id:
			room.ship = Spaceship.from_save(room.data.ship, ship_grid, _grove_time(room.data))
			room.ship_velocity = Vector3.ZERO
			room.actors[con.id].merge(PlayerMotion.put_ashore(_parked_exit(room, room.ship)), true)
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

func _tick_spaceship(room: Dictionary, actor: Dictionary, delta: float) -> void:
	var ship: Dictionary = room.ship
	var was_landed: bool = ship.landed
	room.ship_velocity = Spaceship.step(ship, room.ship_velocity, actor.get("direction", Vector2.ZERO),
		actor.get("lift", 0.0), actor.get("yaw", ship.yaw), delta, ship_grid, _grove_time(room.data))
	if not actor.is_empty():
		actor.point = Spaceship.point(ship)
		actor.y = ship.y
	if ship.landed and (not was_landed or ship.surface == "tree"):
		room.data.ship = Spaceship.parked_save(ship)

func _grove_time(data: Dictionary) -> float:
	return float(data.elapsed) - float(data.groveStartedAt)

func _parked_exit(room: Dictionary, ship: Dictionary) -> Vector3:
	var at := Spaceship.dismount(ship, grid, ship_grid, _grove_time(room.data))
	if at.is_finite():
		return at
	# A detached pilot must have a walkable return point even if the last landing was high in a tree.
	var below := _restore_position(Spaceship.exit_point(ship), Rules.pair(world.spawn))
	return Vector3(below.x, LakeLayout.walk_height(below), below.y)

func _spaceship_action(con: Dictionary, action: String) -> void:
	var room: Dictionary = rooms[con.room]
	var ship: Dictionary = room.ship
	var actor: Dictionary = room.actors[con.id]
	var message := ""
	var accepted := false
	if action == "board":
		if not ship.pilot.is_empty():
			message = "飞船正在由队友驾驶"
		elif not ship.landed or actor.point.distance_to(Spaceship.point(ship)) > Spaceship.BOARD_RANGE:
			message = "靠近停稳的飞船再登机"
		elif not PlayerMotion.boardable(ship, actor):
			message = "先上浮到水面，再按 E 登机" if ship.onWater else "靠近同一高度后再登机"
		elif not Stones.held_by(room.data.stones, con.id).is_empty():
			message = "先按 G 放下手里的石块"
		else:
			ship.pilot = con.id
			actor.point = Spaceship.point(ship)
			actor.y = ship.y
			actor.yaw = ship.yaw
			actor.swimming = false
			actor.vy = 0.0
			message = "已登机，按空格垂直起飞"
			accepted = true
	elif action == "exit" and ship.pilot == con.id:
		if not ship.landed:
			message = "先按 C 降落，再按 E 下机"
		else:
			var exit := Spaceship.dismount(ship, grid, ship_grid, _grove_time(room.data))
			if not exit.is_finite():
				message = "这里没有落脚点，先换地方停靠"
			else:
				ship.pilot = ""
				actor.merge(PlayerMotion.put_ashore(exit), true)
				room.data.ship = Spaceship.parked_save(ship)
				message = "已下机"
				accepted = true
	if accepted:
		actor.direction = Vector2.ZERO
		actor.lift = 0.0
		_publish(con.room)
	if not message.is_empty():
		_send(con.ws, {"t": "notice", "ok": accepted, "site": "spaceship", "text": message})

func _dog_action(con: Dictionary, action: String) -> void:
	var room: Dictionary = rooms[con.room]
	var dog: Dictionary = room.data.dog
	var actor: Dictionary = room.actors[con.id]
	if action.is_empty() or action != CampDog.command(dog, con.id):
		return
	if not dog_motion.can_reach(dog, actor.point, grid):
		_send(con.ws, {"t": "notice", "ok": false, "site": "dog", "text": "走近藏獒再互动"})
		return
	var previous := dog.duplicate()
	if action == "adopt":
		dog.owner = con.id
	dog.mode = "stay" if action == "stay" else "follow"
	if not _checkpoint(con.room):
		room.data.dog = previous
		_send(con.ws, {"t": "notice", "ok": false, "site": "dog", "text": "存档写入失败，请稍后重试"})
		return
	room.dog_route.clear()
	_publish(con.room)
	var text := {"adopt": "藏獒愿意跟着你了", "follow": "藏獒开始跟随", "stay": "藏獒会在这里等你"}
	_send(con.ws, {"t": "notice", "ok": true, "site": "dog", "text": text[action]})

func _provision_action(con: Dictionary, msg: Dictionary) -> void:
	var requested: Variant = msg.get("action")
	if requested is not String or requested not in ["take", "eat_table", "eat", "put", "drop", "drink", "take_backpack", "wear", "remove_worn", "drop_worn"]:
		return
	var room: Dictionary = rooms[con.room]
	var actor: Dictionary = room.actors[con.id]
	if requested == "take_backpack":
		_take_backpack(con, room, actor.point)
		return
	var before_state: Dictionary = room.data.survival[con.id]
	var before_provisions: Dictionary = room.data.provisions
	var state := before_state.duplicate(true)
	var provisions := before_provisions.duplicate()
	var slots := Survival.slot_count(room.data.backpackOwner == con.id)
	var result := _use_provision(requested, msg, actor, state, provisions, slots)
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

func _take_backpack(con: Dictionary, room: Dictionary, point: Vector2) -> void:
	if not room.data.backpackOwner.is_empty():
		_provision_notice(con, false, "背包已有人拾取")
		return
	if not Survival.can_reach(point, Survival.BACKPACK, "ground"):
		_provision_notice(con, false, "走近背包后再拾取")
		return
	room.data.backpackOwner = con.id
	if _checkpoint(con.room):
		_publish(con.room)
		_provision_notice(con, true, "已背上背包，格子 +6")
	else:
		room.data.backpackOwner = ""
		_provision_notice(con, false, "存档写入失败，请稍后重试")

func _use_provision(action: String, msg: Dictionary, actor: Dictionary, state: Dictionary, provisions: Dictionary, slots: int) -> Dictionary:
	var point: Vector2 = actor.point
	if action in ["take", "eat_table"]:
		var id: Variant = msg.get("id")
		if id is not String or not provisions.has(id):
			return {"ok": false, "text": "物品已不在这里"}
		var record: Dictionary = provisions[id]
		if not Survival.can_reach(point, Survival.horizontal(record.at), record.surface):
			return {"ok": false, "text": "走近物品后再互动"}
		var item: String = record.item
		if action == "take":
			if not Survival.can_carry(state.bag, item, slots):
				return {"ok": false, "text": "背包已满"}
			state.bag[item] = int(state.bag.get(item, 0)) + 1
		else:
			if not Survival.FOOD_STATS.has(item):
				return {"ok": false, "text": "按 E 捡起衣物"}
			Survival.eat(state, item)
		provisions.erase(id)
		var verb := "捡起了" if action == "take" else "吃掉了"
		return {"ok": true, "text": verb + Survival.ITEM_NAMES[item]}
	if action == "drink":
		if not Survival.can_drink(point):
			return {"ok": false, "text": "靠近水壶后再喝水"}
		if float(state.water) >= Survival.DRINK_THRESHOLD:
			return {"ok": false, "text": "现在不渴"}
		state.water = minf(Survival.MAX_STAT, float(state.water) + Survival.DRINK_GAIN)
		return {"ok": true, "text": "喝了水，水分恢复"}
	var selected: Variant = msg.get("item")
	if selected is not String or not Survival.ITEM_NAMES.has(selected):
		return {"ok": false, "text": "请先选择物品"}
	var item_name: String = Survival.ITEM_NAMES[selected]
	var clothing := Survival.CLOTHING.has(selected)
	if action in ["remove_worn", "drop_worn"]:
		if not clothing or not bool(state.worn.get(selected, false)):
			return {"ok": false, "text": "请先选择身上的衣物"}
		if action == "remove_worn":
			if not Survival.can_carry(state.bag, selected, slots):
				return {"ok": false, "text": "背包已满，可以直接丢下"}
			state.bag[selected] = int(state.bag.get(selected, 0)) + 1
			state.worn[selected] = false
			return {"ok": true, "text": "脱下了" + item_name}
		state.worn[selected] = false
		return _place_provision(selected, actor, provisions, "ground")
	if int(state.bag.get(selected, 0)) <= 0:
		return {"ok": false, "text": "背包里没有这件物品"}
	if action == "wear":
		if not clothing or bool(state.worn.get(selected, false)):
			return {"ok": false, "text": "先脱下同类衣物"}
		state.bag[selected] -= 1
		state.worn[selected] = true
		return {"ok": true, "text": "穿上了" + item_name}
	if clothing and action != "drop":
		return {"ok": false, "text": "衣物可以穿上或丢下"}
	if action == "eat":
		state.bag[selected] -= 1
		Survival.eat(state, selected)
		return {"ok": true, "text": "吃掉了" + item_name}
	var surface := "table" if action == "put" else "ground"
	if surface == "table" and not Survival.can_put(point):
		return {"ok": false, "text": "靠近桌子后再放回食物"}
	var result := _place_provision(selected, actor, provisions, surface)
	if result.ok:
		state.bag[selected] -= 1
	return result

func _place_provision(item: String, actor: Dictionary, provisions: Dictionary, surface: String) -> Dictionary:
	var place := Vector3.INF
	if surface == "table":
		place = Survival.free_table_slot(provisions)
	else:
		place = _provision_drop_position(actor, provisions, Survival.CLOTHING.has(item))
	if not place.is_finite():
		return {"ok": false, "text": "桌上没有空位" if surface == "table" else "脚边没有空地"}
	var id := Crypto.new().generate_random_bytes(8).hex_encode()
	while provisions.has(id):
		id = Crypto.new().generate_random_bytes(8).hex_encode()
	provisions[id] = Survival.provision(item, place, surface)
	var verb := "放回桌上" if surface == "table" else "放下了"
	return {"ok": true, "text": verb + Survival.ITEM_NAMES[item]}

func _provision_drop_position(actor: Dictionary, provisions: Dictionary, clothing := false) -> Vector3:
	var point: Vector2 = actor.point
	var facing := Vector2(0.0, -0.58).rotated(-float(actor.yaw))
	for offset: Vector2 in [facing, facing.rotated(PI / 3.0), facing.rotated(-PI / 3.0), Vector2.ZERO]:
		var candidate := point + offset
		if candidate != candidate.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER) or not Rules.free_at(candidate, grid):
			continue
		var height := LakeLayout.walk_height(candidate)
		var surface := LakeLayout.surface_height(candidate)
		if height <= surface and not clothing:
			continue
		var crowded := false
		for record: Dictionary in provisions.values():
			if record.surface == "ground" and candidate.distance_squared_to(Survival.horizontal(record.at)) < 0.03:
				crowded = true
				break
		if not crowded:
			return Vector3(candidate.x, maxf(height, surface) + 0.012, candidate.y)
	if clothing:
		return Vector3(point.x, maxf(LakeLayout.walk_height(point), LakeLayout.surface_height(point)) + 0.012, point.y)
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
			var hand_height := float(actor.y) + (0.18 if actor.swimming else 1.28)
			stone.at = Stones.pack(Vector3(point.x, hand_height, point.y) + direction * 0.30)
			stone.velocity = Stones.pack(direction * (10.6 if Stones.flat(id) else 9.2) + Vector3.UP * 1.1)
			stone.launch = room.data.elapsed
			stone.mode = "air"
			stone.erase("holder")
	if _checkpoint(con.room):
		if action == "throw":
			_record_stone_sound(room, "stone_throw", Stones.unpack(stone.at))
		elif action == "drop":
			_stone_rest_sound(room, Stones.unpack(stone.at), 0.59)
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

func _record_stone_sound(room: Dictionary, cue: String, at: Vector3, strength := 1.0) -> void:
	room.stone_sound_id += 1
	var sounds: Array = room.stone_sounds
	if sounds.size() == MAX_STONE_SOUNDS:
		sounds.pop_front()
	sounds.append({"id": room.stone_sound_id, "cue": cue, "point": Stones.pack(at),
		"at": room.data.elapsed, "strength": strength})

func _stone_rest_sound(room: Dictionary, at: Vector3, strength := 1.0) -> void:
	var point := Vector2(at.x, at.z)
	var surface := LakeLayout.surface_height(point)
	if at.y < surface:
		_record_stone_sound(room, "stone_water", Vector3(at.x, surface, at.z), strength)
	else:
		var cue := "stone_wood" if LakeLayout.on_dock(point) else "stone_earth"
		_record_stone_sound(room, cue, at, strength)

func _tick_stones(room: Dictionary, delta: float) -> void:
	var elapsed: float = room.data.elapsed
	while not room.impacts.is_empty() and elapsed - float(room.impacts[0].at) > 2.8:
		room.impacts.pop_front()
	while not room.stone_sounds.is_empty() and elapsed - float(room.stone_sounds[0].at) > STONE_SOUND_TIME:
		room.stone_sounds.pop_front()
	for id: String in room.data.stones:
		var stone: Dictionary = room.data.stones[id]
		if stone.mode != "air":
			continue
		var at := Stones.flight_position(stone, elapsed)
		var point := Vector2(at.x, at.z)
		var previous := Stones.flight_position(stone, elapsed - delta)
		var previous_point := Vector2(previous.x, previous.z)
		var bounds := point.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER)
		if Wildlife.stone_hit(room.crocodile, previous, at, elapsed):
			_set_ground(stone, id, bounds)
			if LakeLayout.walk_height(bounds) <= LakeLayout.surface_height(bounds):
				stone.mode = "submerged"
			_record_stone_sound(room, "stone_earth", at, 0.66)
			continue
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
			_record_stone_sound(room, "stone_water", Vector3(point.x, surface, point.y))
		elif at.y <= ground:
			_set_ground(stone, id, bounds)
			_stone_rest_sound(room, Stones.unpack(stone.at))
		elif at.y < 2.0 and Rules.obstacle_free_at(previous_point, grid) and not Rules.obstacle_free_at(point, grid):
			_set_ground(stone, id, previous_point)
			_record_stone_sound(room, "stone_rock", previous)

func _tick_wildlife(code: String, room: Dictionary, delta: float) -> void:
	var on_foot: Dictionary = room.actors
	if not room.ship.pilot.is_empty():
		on_foot = on_foot.duplicate()
		on_foot.erase(room.ship.pilot)
	var event := Wildlife.tick_crocodile(room.crocodile, on_foot, grid, float(room.data.elapsed), delta)
	if event.is_empty():
		return
	var hurt: bool = event.has("bit")
	var player: String = event.bit if hurt else event.warn
	if hurt:
		var personal: Dictionary = room.data.survival[player]
		personal.health = maxf(0.0, float(personal.health) - Wildlife.BITE_DAMAGE)
	for con: Dictionary in connections.values():
		if con.room == code and con.id == player:
			var message := "被鳄鱼咬伤，回营可以恢复" if hurt else "鳄鱼要扑过来了，往后退"
			_send(con.ws, {"t": "notice", "ok": false, "site": "crocodile", "text": message})

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
		actors[id] = {"x": a.point.x, "y": a.y, "z": a.point.y, "vy": a.vy,
			"swimming": a.swimming, "yaw": a.yaw, "slot": a.slot, "worn": room.data.survival[id].worn}
	var grove_elapsed := _grove_time(room.data)
	var snapshot := {"t":"snapshot", "quest":room.data.quest, "elapsed":room.data.elapsed, "groveElapsed":grove_elapsed, "players":actors, "stones":room.data.stones, "lineCut":room.data.lineCut, "waterImpacts":room.impacts, "backpackOwner":room.data.backpackOwner, "dog":room.data.dog}
	snapshot.stoneSounds = room.stone_sounds
	snapshot.crocodile = Wildlife.crocodile_pose(room.crocodile)
	var velocity: Vector3 = room.ship_velocity
	snapshot.ship = room.ship.duplicate()
	snapshot.ship.v = [velocity.x, velocity.y, velocity.z]
	for con in connections.values():
		if con.room == code:
			var flow: bool = con.get("snapshot_flow", false)
			# A stalled renderer keeps one unconsumed snapshot. The next send samples
			# the current room, leaving notices and requests on their original path.
			if flow and con.snapshot_sent != con.snapshot_acked:
				continue
			var personal: Dictionary = room.data.survival.get(con.id, {})
			var outgoing := snapshot.duplicate()
			outgoing.provisions = room.data.provisions
			if not personal.is_empty():
				outgoing.survival = Survival.snapshot(personal)
			if flow:
				outgoing.snapshotSeq = int(con.snapshot_sent) + 1
			if _send(con.ws, outgoing) and flow:
				con.snapshot_sent = outgoing.snapshotSeq

func _checkpoint(code: String) -> bool:
	var room: Dictionary = rooms[code]
	for id in room.actors:
		var a: Dictionary = room.actors[id]
		var home := Vector3(a.point.x, a.y, a.point.y)
		if room.ship.pilot == id:
			home = _parked_exit(room, room.data.ship)
		room.data.homes[id] = {"x":home.x, "z":home.z, "yaw":a.yaw, "y":home.y}
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
