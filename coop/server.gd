extends SceneTree

const Rules = preload("res://rules.gd")
const Stones = preload("res://stones.gd")
const LakeLayout = preload("res://lake_layout.gd")
const Survival = preload("res://survival.gd")
const Weapons = preload("res://weapons.gd")
const CampDog = preload("res://camp_dog.gd")
const Wildlife = preload("res://wildlife.gd")
const WildPeople = preload("res://wild_people.gd")
const Spaceship = preload("res://spaceship.gd")
const PlayerMotion = preload("res://player_motion.gd")
const Atlas = preload("res://field_atlas.gd")
const Storage = preload("res://camp_storage.gd")
const Mining = preload("res://mining.gd")
const MinesLayout = preload("res://mines_layout.gd")
const PlacementWorld = preload("res://placement_world.gd")
const Placement = preload("res://placement.gd")
const Beds = preload("res://camp_beds.gd")
const Ferry = preload("res://lake_ferry.gd")
const Reeds = preload("res://lake_reeds.gd")
const Boar = preload("res://woodland_boar.gd")
const Sheep = preload("res://lake_sheep.gd")
const StorageWildlife = preload("res://storage_wildlife.gd")
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
var placement_grid: Dictionary
var ship_grid: Dictionary
var save_dir := ""
var next_connection := 1
var snapshot_in := 0.0
var save_in := SAVE_PERIOD
var dog_motion := CampDog.new()
var people_motion := WildPeople.new()
var people_config: Dictionary = {}

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
	if FileAccess.file_exists("res://wild_people_config.json"):
		var configured: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://wild_people_config.json"))
		if configured is Dictionary:
			people_config = configured
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
	_prepare_terrain_navigation()
	result = listener.listen(port, bind_address)
	if result != OK:
		push_error("房间服务器监听失败 %s:%s (%s)" % [bind_address, port, error_string(result)])
		quit(1)
		return
	print("ROOM_SERVER_READY ", bind_address, ":", port)

func _prepare_terrain_navigation() -> void:
	# Both actor types and every room share this static terrain. NPCs keep a
	# separate avoidance margin; installed furniture remains room-local.
	dog_motion.prepare_navigation(grid)
	people_motion.navigator.prepare_navigation(grid, dog_motion.navigation)

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
		_refresh_material_sources(room)
		_claim_legacy_materials(code)
		var rain := Rules.rain_at(room.data.elapsed)
		var grove_time := _grove_time(room.data)
		for id in room.actors:
			_tick_player(room, id, rain, grove_time, delta)
		if room.ship.pilot.is_empty() and (room.ship.slipping or room.ship.surface == "tree"):
			_tick_spaceship(room, {}, delta)
		_tick_stones(room, delta, code)
		_tick_storage(room, delta, code)
		if StorageWildlife.alive(room, "dog"):
			dog_motion.tick(room, grid, delta)
		if StorageWildlife.alive(room, "croc"):
			_tick_wildlife(code, room, delta)
		_tick_boar(code,room,delta)
		people_motion.tick(room, grid, minf(delta, 0.1))
		_resolve_knockouts(code, room)
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

func _tick_player(room: Dictionary, id: String, rain: float, grove_time: float, delta: float) -> void:
	var actor: Dictionary = room.actors[id]
	actor.input_age += delta
	if actor.input_age > IDLE_INPUT_TIMEOUT:
		actor.direction = Vector2.ZERO
		actor.lift = 0.0
	var piloting: bool = room.ship.pilot == id
	var personal: Dictionary = room.data.survival[id]
	if personal.health <= 0.0:
		actor.direction = Vector2.ZERO
		actor.lift = 0.0
	if not str(actor.get("bed","")).is_empty():
		if personal.health <= 0.0:
			Beds.wake_player(room,actor)
		else:
			Beds.place_player(room,actor)
			personal.health = minf(100.0,personal.health + Beds.HEAL_PER_SECOND * delta)
	elif piloting:
		_tick_spaceship(room, actor, delta)
	elif not _tick_storage_pose(room, actor, personal.health > 0.0, delta):
		var before: Vector2=actor.point
		PlayerMotion.step(actor, actor.direction, actor.lift, delta, grid, room.ship, ship_grid, grove_time,room.data.storage, room.data.get("ferryDepartedAt", -1.0), room.data.elapsed)
		if StorageWildlife.alive(room,"boar"):
			Boar.clear_body(actor,before,room.data.get("boar",{}),grid)
	if piloting:
		rain *= Rules.rain_exposure(actor.y)
	Survival.tick(room.data.survival[id], actor.point, room.data.quest.repaired and room.data.wildPeople.facility > 20.0, rain, delta, piloting)

func _resolve_knockouts(code: String, room: Dictionary) -> void:
	var changed := false
	var elapsed: float = room.data.elapsed
	for id: String in room.actors:
		var personal: Dictionary = room.data.survival[id]
		if float(personal.health) > 0.0:
			continue
		var actor: Dictionary = room.actors[id]
		if float(personal.downAt) < 0.0 or float(personal.downAt) > elapsed:
			personal.downAt = elapsed
			changed = true
			if room.ship.pilot == id:
				room.ship = Spaceship.from_save(room.data.ship, ship_grid, _grove_time(room.data))
				room.ship_velocity = Vector3.ZERO
				actor.merge(PlayerMotion.put_ashore(_parked_exit(room, room.ship)), true)
			_drop_carried(room, id)
			actor.erase("revivedAt")
			actor.erase("climbing")
			actor.erase("storageSeat")
			actor.direction = Vector2.ZERO
			actor.lift = 0.0
			actor.vx = 0.0
			actor.vz = 0.0
			actor.aimPitch = null
			personal.blocking = false
		if room.actors.size() == 1 or Survival.rescue_time_left(personal.downAt, elapsed) <= 0.0:
			var camp := _atlas_landing(room, id, WildPeople.HOME, [0.0, 0.9, 1.6, 2.4, 3.2, 4.6, 6.4, 8.0])
			if not camp.is_finite():
				var spawn := Rules.pair(world.spawn)
				camp = Vector3(spawn.x, LakeLayout.walk_height(spawn), spawn.y)
			actor.merge(PlayerMotion.put_ashore(camp), true)
			actor.y = camp.y
			actor.floorY = camp.y
			actor.grounded = true
			personal.health = Survival.RECOVERY_HEALTH
			personal.downAt = -1.0
			changed = true
			_recovery_notice(code, id, true, "已回到营地，可在棚内恢复健康")
	if changed:
		_checkpoint(code)

func _rescue(con: Dictionary, room: Dictionary, target: Variant) -> void:
	if target is not String or target == con.id or not room.actors.has(target):
		_recovery_notice(con.room, con.id, false, "靠近需要救援的队友")
		return
	var elapsed: float = room.data.elapsed
	var personal: Dictionary = room.data.survival[target]
	var down_at := float(personal.downAt)
	if float(personal.health) > 0.0 or Survival.rescue_time_left(down_at, elapsed) <= 0.0:
		_recovery_notice(con.room, con.id, false, "队友已不需要救援")
		return
	var actor: Dictionary = room.actors[con.id]
	var casualty: Dictionary = room.actors[target]
	var helper_at := Vector3(actor.point.x, actor.y, actor.point.y)
	var casualty_at := Vector3(casualty.point.x, casualty.y, casualty.point.y)
	if not Survival.within_rescue_reach(helper_at, casualty_at):
		_recovery_notice(con.room, con.id, false, "靠近需要救援的队友")
		return
	if (not casualty.grounded and not casualty.swimming) or room.ship.pilot == target:
		_recovery_notice(con.room, con.id, false, "等队友落稳后再救援")
		return
	var from := helper_at + Vector3.UP * PlayerMotion.eye_offset(actor.swimming)
	var to := casualty_at + Vector3.UP * Survival.rescue_contact_height(casualty.swimming)
	var solids := PlacementWorld.nearby(placement_grid, room.data.storage, actor.point, Survival.RESCUE_REACH + 1.5)
	if not Placement.trace(from, to, solids).is_empty() or Spaceship.blocks_sight(room.ship, from, to):
		_recovery_notice(con.room, con.id, false, "队友身前有遮挡")
		return
	personal.health = Survival.RECOVERY_HEALTH
	personal.downAt = -1.0
	if not _checkpoint(con.room):
		personal.health = 0.0
		personal.downAt = down_at
		_recovery_notice(con.room, con.id, false, "救援保存失败，请重试")
		return
	casualty.revivedAt = elapsed
	_publish(con.room)
	_recovery_notice(con.room, con.id, true, "已救起队友")
	_recovery_notice(con.room, target, true, "队友已将你救起")

func _recovery_notice(code: String, player: String, ok: bool, message: String) -> void:
	for peer: Dictionary in connections.values():
		if peer.room == code and peer.id == player:
			_send(peer.ws, {"t":"notice", "ok":ok, "site":"rescue", "text":message})
			return

func _message(con: Dictionary, msg: Dictionary) -> void:
	if con.room.is_empty():
		if msg.get("t") == "join":
			_join(con, msg)
		return
	var room: Dictionary = rooms[con.room]
	var actor: Dictionary = room.actors[con.id]
	var personal: Dictionary = room.data.survival[con.id]
	var kind: String = str(msg.get("t", ""))
	if kind == "atlas":
		_atlas_action(con, msg)
		return
	if kind == "person" and msg.get("action") == "respawn":
		_recovery_notice(con.room, con.id, false, "队友可以救援，时间到后自动回营")
		return
	if float(personal.health) <= 0.0 and kind != "motion":
		return
	if kind not in ["motion", "ship"] and room.ship.pilot == con.id:
		return
	if not str(actor.get("bed","")).is_empty() and kind != "motion":
		if kind == "lake" and msg.get("action") == "wake":
			Beds.wake_player(room,actor)
			_publish(con.room)
		return
	match kind:
		"motion":
			if con.get("snapshot_flow", false) and msg.get("snapshotAck", -1) == con.snapshot_sent:
				con.snapshot_acked = con.snapshot_sent
			if float(personal.health) <= 0.0:
				return
			for field in ["x", "z", "yaw"]:
				var v = msg.get(field)
				if (typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT) or not is_finite(float(v)):
					return
			actor.direction = Vector2(clampf(msg.x, -1, 1), clampf(msg.z, -1, 1)).limit_length()
			actor.crouchHeld = msg.get("crouch") == true
			actor.yaw = wrapf(msg.yaw, -PI, PI)
			var lift = msg.get("lift", 0.0)
			actor.lift = clampf(float(lift), -1.0, 1.0) if _finite_number(lift) else 0.0
			actor.input_age = 0.0
			var gun := Weapons.firearm(personal.weapon)
			personal.blocking = msg.get("blocking") == true and personal.shield and not gun
			var aim: Variant = msg.get("aimPitch")
			var can_aim: bool = gun and not actor.swimming and room.ship.pilot != con.id
			actor.aimPitch = clampf(float(aim), -1.44, 1.44) if can_aim and _finite_number(aim) else null
		"reed":
			_harvest_reeds(con,room,actor,personal,msg.get("id"))
		"lake":
			_lake_action(con, room, actor, personal, msg.get("action"))
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
		"storage":
			_storage_action(con, msg)
		"mine":
			_mining_action(con, msg)
		"dog":
			if msg.get("action") is String:
				_dog_action(con, msg.action)
		"sighting":
			_record_sighting(con, room, actor, personal, msg)
		"person":
			_wild_action(con, msg)
		"rescue":
			_rescue(con, room, msg.get("id"))

func _harvest_reeds(con: Dictionary, room: Dictionary, actor: Dictionary, personal: Dictionary, id: Variant) -> void:
	if not id is String or actor.get("onFerry",false) or not Reeds.reachable(id,actor.point,actor.y):
		return
	var elapsed: float = room.data.elapsed
	var prior_times: Dictionary = room.data.reedCuts
	if Reeds.cut(id,prior_times,elapsed):
		_send(con.ws,{"t":"notice","ok":false,"site":"reed","text":"这丛芦苇还在生长"})
		return
	if not Survival.can_carry(personal.bag,"reed_bundle",Survival.slot_count(room.data.backpackOwner == con.id)):
		_send(con.ws,{"t":"notice","ok":false,"site":"reed","text":"背包已满，先给芦苇束腾一格"})
		return
	var prior_bag: Dictionary = personal.bag
	personal.bag = prior_bag.duplicate()
	personal.bag.reed_bundle = int(prior_bag.get("reed_bundle",0)) + 1
	room.data.reedCuts = Reeds.from_save(prior_times,elapsed)
	room.data.reedCuts[id] = elapsed
	var ok := _checkpoint(con.room)
	if ok:
		_publish(con.room)
	else:
		personal.bag = prior_bag
		room.data.reedCuts = prior_times
	_send(con.ws,{"t":"notice","ok":ok,"site":"reed","text":"芦苇束 ×1 · 可添火或加工成编条" if ok else "存档写入失败，请稍后重试"})

func _lake_action(con: Dictionary, room: Dictionary, actor: Dictionary, personal: Dictionary, action: Variant) -> void:
	var elapsed: float = room.data.elapsed
	var departed: float = room.data.ferryDepartedAt
	var sheared: float = room.data.shearedAt
	var at_pier := Ferry.at_pier(actor.point, actor.y)
	var aboard: bool = actor.get("onFerry", false)
	var prior := actor.duplicate()
	var prior_wool := int(personal.bag.get("wool", 0))
	var message := ""
	match action:
		Beds.PORT, Beds.STARBOARD:
			if Beds.claimed(room,action):
				_send(con.ws,{"t":"notice","ok":false,"site":"lake","text":"这张铺位已经有人使用"})
				return
			if not Beds.sleep_player(room,con.id,action):
				_send(con.ws,{"t":"notice","ok":false,"site":"lake","text":"在篷内走近空铺位后可以躺下"})
				return
			message = "躺在船铺上休息 · E 起身"
		"board":
			if aboard or not at_pier or not Ferry.moored(elapsed, departed):
				return
			Ferry.place(actor, Ferry.boarding_spot(room.actors), Ferry.pose(elapsed, departed), LakeLayout.water_y())
			message = "已登上露天甲板 · WASD 走动，按住 Ctrl 进篷"
		"leave":
			if not aboard or not Ferry.moored(elapsed, departed):
				return
			actor.merge(PlayerMotion.spawn(Ferry.PIER), true)
			message = "已回到鹿鸣湖栈台"
		"sail":
			if not (aboard or at_pier) or not Ferry.moored(elapsed, departed):
				return
			room.data.ferryDepartedAt = elapsed
			message = "船工起桨，环湖一周后回到这座栈台"
		"shear":
			if not StorageWildlife.alive(room,"sheep") or not Sheep.reachable(actor.point, actor.y, elapsed, sheared):
				return
			if Sheep.shorn(elapsed, sheared):
				return
			if not Survival.can_carry(personal.bag, "wool", Survival.slot_count(room.data.backpackOwner == con.id)):
				_send(con.ws, {"t":"notice", "ok":false, "site":"lake", "text":"背包已满，请先腾出一格装羊毛"})
				return
			personal.bag.wool = prior_wool + 1
			room.data.shearedAt = elapsed
			message = "剪下一束羊毛，已放入背包"
		_:
			return
	var ok := _checkpoint(con.room)
	if not ok:
		room.actors[con.id] = prior
		if prior_wool > 0:
			personal.bag.wool = prior_wool
		else:
			personal.bag.erase("wool")
		room.data.shearedAt = sheared
		room.data.ferryDepartedAt = departed
		message = "存档写入失败，请稍后重试"
	else:
		_publish(con.room)
	_send(con.ws, {"t":"notice","ok":ok,"site":"lake","text":message})

func _record_sighting(con: Dictionary, room: Dictionary, actor: Dictionary, personal: Dictionary, msg: Dictionary) -> void:
	var species: Variant = msg.get("species")
	var pitch: Variant = msg.get("pitch")
	if species is not String or not Survival.SIGHTING_RANGE.has(species) or not Survival.finite_number(pitch):
		return
	var known: Array = personal.fieldGuide.animals
	var now := Time.get_ticks_msec()
	if species in known or now < int(con.get("sighting_next_ms", 0)):
		return
	con.sighting_next_ms = now + 300
	var eye := Vector3(actor.point.x, float(actor.y) + PlayerMotion.eye_offset(actor.swimming), actor.point.y)
	var target := StorageWildlife.sighting_position(room, species)
	if not target.is_finite() or eye.distance_squared_to(target) > float(Survival.SIGHTING_RANGE[species]) ** 2:
		return
	var forward := -Basis.from_euler(Vector3(clampf(pitch, -1.44, 1.51), actor.yaw, 0.0)).z
	if forward.dot(eye.direction_to(target)) < 0.68:
		return
	if species == "croc" and target.y < LakeLayout.water_y() - .08 and eye.y >= LakeLayout.water_y():
		return
	if Spaceship.Ground.sight_obstructed(eye, target, ship_grid, _grove_time(room.data)) or Spaceship.blocks_sight(room.ship, eye, target):
		return
	var midpoint := eye.lerp(target, 0.5)
	var solids := PlacementWorld.nearby({}, room.data.storage, Vector2(midpoint.x, midpoint.z), eye.distance_to(target) * 0.5 + 2.0)
	var obstruction := Placement.trace(eye, target, solids)
	if not obstruction.is_empty() and obstruction.id != "water":
		return
	known.append(species)
	if not _checkpoint(con.room):
		known.pop_back()
		return
	_publish(con.room)
	_send(con.ws, {"t": "notice", "ok": true, "site": "field-guide", "text": "图鉴已记录 · " + StorageWildlife.NAMES[species]})

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
	for key: String in ["ferryDepartedAt", "shearedAt"]:
		var last: Variant = data.get(key)
		data[key] = float(last) if Survival.finite_number(last) and last >= 0.0 and last <= data.elapsed else -1.0
	data.reedCuts = Reeds.from_save(data.get("reedCuts"),float(data.elapsed))
	data.stones = Stones.from_save(data.get("stones"))
	data.lineCut = data.get("lineCut", false) == true
	data.provisions = Survival.provisions_from_save(data.get("provisions"))
	data.storage = Storage.from_save(data.get("storage"), float(data.elapsed), grid)
	if data.get("campFurniturePlaced",false) != true:
		Storage.seed_furniture(data.storage,data.provisions)
		data.campFurniturePlaced = true
	if placement_grid.is_empty():
		placement_grid = PlacementWorld.static_grid(world)
	if not data.get("campBedPlaced",false):
		data.campBedPlaced = Storage.seed_bed(data.storage,placement_grid)
	if data.get("campFurnacePlaced",false) != true:
		data.campFurnacePlaced = Storage.seed_furnace(data.storage,placement_grid)
	data.mines = Mining.from_save(data.get("mines"),float(data.elapsed))
	data.boar = Boar.from_save(data.get("boar"),float(data.elapsed),grid)
	data.storageWildlife = StorageWildlife.from_save(data.get("storageWildlife"))
	if data.get("campWeaponsVersion", 0) == 0:
		for item: String in Weapons.CAMP_START:
			var point: Vector2 = Weapons.CAMP_START[item]
			var at := Vector3(point.x, LakeLayout.walk_height(point) + 0.008, point.y)
			data.provisions["camp-weapon-" + item] = Survival.provision(item, at, "ground")
		data.campWeaponsVersion = 1
	if data.get("campHelmetPlaced", false) != true:
		var point := Survival.CAMP_HELMET
		var at := Vector3(point.x, LakeLayout.walk_height(point) + 0.008, point.y)
		if not data.provisions.has("camp-helmet"):
			data.provisions["camp-helmet"] = Survival.provision("helmet", at, "ground")
		data.campHelmetPlaced = true
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
	data.atlasPins = Atlas.pins_from_save(data.get("atlasPins"))
	data.backpackOwner = backpack_owner
	_restore_materials(data)
	data.wildPeople = WildPeople.from_save(data.get("wildPeople"), data.elapsed, grid, people_config)
	data.dog = CampDog.from_save(data.get("dog"), personal, grid, data.quest.repaired == true, float(data.elapsed))
	if ship_grid.is_empty():
		ship_grid = Spaceship.collision_grid(world)
	var ship := Spaceship.from_save(data.get("ship"), ship_grid, _grove_time(data))
	data.ship = Spaceship.parked_save(ship)
	rooms[code] = {"data": data, "actors": {}, "impacts": [], "impactId": 0, "dog_route": {},
		"crocodile": Wildlife.crocodile(float(data.elapsed)), "ship": ship, "ship_velocity": Vector3.ZERO,
		"stone_sounds": [], "stone_sound_id": 0, "people_routes": {}}
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
				_welcome(con, room)
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
		var cave_floor := LakeLayout.Gallery.floor_at(stored,float(stored_height))
		var foothold := cave_floor if is_finite(cave_floor) else Spaceship.Ground.walk_height(stored, float(stored_height), ship_grid, _grove_time(room.data))
		foothold = PlacementWorld.floor_height(PlacementWorld.nearby(PlacementWorld.mine_grid(),room.data.storage,stored,3.15),
			stored,float(stored_height),foothold)
		var top := LakeLayout.walk_height(stored)
		var under_carving := LakeLayout.Coast.buddha.bounds.has_point(stored) and foothold < top - .23 \
			and Rules.obstacle_free_at(stored, grid, foothold)
		if (is_finite(cave_floor) or under_carving or foothold > top + 0.23) and absf(foothold - float(stored_height)) < 0.50:
			point = stored
			starting_height = foothold
	con.room = code
	con.id = id
	con.session = session_tag
	var actor := PlayerMotion.put_ashore(Vector3(point.x, starting_height, point.y))
	var saved_deck: Variant = home.get("ferryLocal")
	if saved_deck is Array and saved_deck.size() == 2 and Survival.finite_number(saved_deck[0]) and Survival.finite_number(saved_deck[1]):
		var local := Vector2(saved_deck[0],saved_deck[1])
		if Ferry.on_deck(local):
			if Ferry.obstructed(local) or Ferry.under_canopy(local) and not home.has("ferryCrouched"):
				local = Ferry.boarding_spot(room.actors)
			Ferry.place(actor, local, Ferry.pose(room.data.elapsed, room.data.ferryDepartedAt), LakeLayout.water_y())
	actor.merge({"direction": Vector2.ZERO, "yaw": home.get("yaw", PI), "slot": slot, "input_age": 0.0, "lift": 0.0})
	room.actors[id] = actor
	if not room.data.survival.has(id):
		room.data.survival[id] = Survival.initial_state()
	_claim_legacy_materials(code)
	_welcome(con, room)
	_resolve_knockouts(code, room)
	_publish(code)
	print("ROOM_JOIN ", code, " ", id, " peers=", room.actors.size())

func _welcome(con: Dictionary, room: Dictionary) -> void:
	_send(con.ws, {"t": "welcome", "id": con.id, "fieldAtlas": true})
	_atlas_pins(con, room)

func _atlas_pins(con: Dictionary, room: Dictionary, text := "") -> void:
	_send(con.ws, {"t": "atlas", "action": "pins", "ok": true,
		"pins": room.data.atlasPins.get(con.id, {}), "text": text})

func _atlas_error(con: Dictionary, action: String, text: String) -> void:
	_send(con.ws, {"t": "atlas", "action": action, "ok": false, "text": text})

func _atlas_action(con: Dictionary, msg: Dictionary) -> void:
	var action: Variant = msg.get("action")
	if not action is String:
		return
	var room: Dictionary = rooms[con.room]
	if action == "travel":
		_atlas_travel(con, room, msg.get("site"))
		return
	if action not in ["pin", "remove"] or not Atlas.pin_id_valid(msg.get("id")):
		return
	var id: String = msg.id
	var all_pins: Dictionary = room.data.atlasPins
	var before: Dictionary = all_pins.get(con.id, {})
	var after := before.duplicate()
	if action == "pin":
		var point := Atlas.read_point(msg)
		if not point.is_finite():
			_atlas_error(con, action, "请选择地图范围内的位置")
			return
		if not after.has(id) and after.size() >= Atlas.MAX_PINS:
			_atlas_error(con, action, "个人标记已满，请先删除一个")
			return
		after[id] = {"x": point.x, "z": point.y}
	else:
		after.erase(id)
	if after != before:
		var homes: Dictionary = room.data.homes.duplicate()
		if after.is_empty():
			all_pins.erase(con.id)
		else:
			all_pins[con.id] = after
		if not _checkpoint(con.room):
			room.data.homes = homes
			if before.is_empty():
				all_pins.erase(con.id)
			else:
				all_pins[con.id] = before
			_atlas_error(con, action, "标记保存失败，请重试")
			return
	_atlas_pins(con, room, "已放置个人标记" if action == "pin" else "已删除个人标记")

func _atlas_travel(con: Dictionary, room: Dictionary, site: Variant) -> void:
	if not site is String or not Atlas.LANDMARKS.has(site):
		_atlas_error(con, "travel", "请选择地图地标")
		return
	if room.data.survival[con.id].health <= 0.0:
		_atlas_error(con, "travel", "恢复行动后即可传送")
		return
	var piloting: bool = room.ship.pilot == con.id
	if piloting and not room.ship.landed:
		_atlas_error(con, "travel", "飞船停稳后即可传送")
		return
	var landmark: Dictionary = Atlas.LANDMARKS[site]
	var arrival := _atlas_landing(room, con.id, landmark.landing)
	if not arrival.is_finite():
		_atlas_error(con, "travel", "此处落脚点暂被占用")
		return
	var previous: Dictionary = room.actors[con.id]
	var actor := previous.duplicate()
	actor.merge(PlayerMotion.put_ashore(arrival), true)
	actor.erase("storageSeat")
	actor.erase("climbing")
	actor.merge({"direction": Vector2.ZERO, "lift": 0.0, "input_age": 0.0, "aimPitch": null}, true)
	var saved_homes: Dictionary = room.data.homes.duplicate()
	var saved_ship: Dictionary = room.data.ship
	var previous_ship: Dictionary = room.ship
	var previous_velocity: Vector3 = room.ship_velocity
	var personal: Dictionary = room.data.survival[con.id]
	var was_blocking: bool = personal.get("blocking", false)
	personal.blocking = false
	room.actors[con.id] = actor
	if piloting:
		room.ship = previous_ship.duplicate()
		room.ship.pilot = ""
		room.ship_velocity = Vector3.ZERO
		room.data.ship = Spaceship.parked_save(room.ship)
	if not _checkpoint(con.room):
		room.actors[con.id] = previous
		room.data.homes = saved_homes
		room.data.ship = saved_ship
		room.ship = previous_ship
		room.ship_velocity = previous_velocity
		personal.blocking = was_blocking
		_atlas_error(con, "travel", "传送位置保存失败，请重试")
		return
	var result := {"t": "atlas", "action": "travel", "site": site, "ok": true, "text": "已到达" + landmark.name,
		"at": [arrival.x, arrival.y, arrival.z]}
	if piloting:
		result.ship = room.ship
	_send(con.ws, result)
	_publish(con.room)

func _atlas_landing(room: Dictionary, id: String, center: Vector2, rings: Array = [0.0, 0.9, 1.6, 2.4, 3.2]) -> Vector3:
	var solids := PlacementWorld.nearby(PlacementWorld.mine_grid(), room.data.storage, center, float(rings.back()) + 2.5)
	for ring: float in rings:
		for step: int in (1 if ring == 0.0 else 8):
			var point := center + Vector2.from_angle(TAU * float(step) / 8.0) * ring
			if not Atlas.contains(point) or not Rules.free_at(point, grid):
				continue
			var floor_y := LakeLayout.walk_height(point)
			floor_y = PlacementWorld.floor_height(solids, point, floor_y, floor_y)
			if LakeLayout.surface_height(point) > floor_y + 0.025 or Spaceship.blocks_player(
					point + Vector2(8.0, 0), point, floor_y, floor_y + PlayerMotion.WALK_EYE, room.ship):
				continue
			if PlacementWorld.blocks_player(solids, point, floor_y):
				continue
			var safe := true
			for offset: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				if absf(LakeLayout.walk_height(point + offset * Rules.RADIUS) - floor_y) > 0.4:
					safe = false
			for peer_id: String in room.actors:
				var peer: Dictionary = room.actors[peer_id]
				if peer_id != id and absf(float(peer.y) - floor_y) < 1.6 and point.distance_to(peer.point) < 0.85:
					safe = false
			if safe:
				return Vector3(point.x, floor_y, point.y)
	return Vector3.INF

func _restore_position(point: Vector2, spawn: Vector2) -> Vector2:
	if point != point.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER):
		return spawn
	if Rules.free_at(point, grid, true):
		return point
	# An old save inside a scanned rock resumes on its visible upper face at the same coordinates.
	var rock := LakeLayout.East.Rocks.top(point)
	if rock > LakeLayout.ground_height(point) and Rules.static_free_at(point,grid):
		return point
	if LakeLayout.East.contains(point) and not LakeLayout.East.Rocks.clears(point,LakeLayout.East.height(point)):
		for radius: float in [.22,.45,.70,1.0,1.5]:
			for i in 12:
				var edge := (point+radius*Vector2.from_angle(i*TAU/12)).clamp(Rules.MIN_CORNER, Rules.MAX_CORNER)
				if Rules.free_at(edge,grid):
					return edge
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

func _drop_carried(room: Dictionary, player: String) -> void:
	var actor: Dictionary = room.actors[player]
	var stone := Stones.held_by(room.data.stones, player)
	if not stone.is_empty():
		_set_ground(room.data.stones[stone], stone, actor.point)
	var carried := Storage.held_by(room.data.storage, player)
	if not carried.is_empty():
		Storage.grounded(room.data.storage[carried], actor.point, actor.yaw)

func _leave(key: int) -> void:
	var con: Dictionary = connections[key]
	if not con.room.is_empty():
		var room: Dictionary = rooms[con.room]
		if room.ship.pilot == con.id:
			room.ship = Spaceship.from_save(room.data.ship, ship_grid, _grove_time(room.data))
			room.ship_velocity = Vector3.ZERO
			room.actors[con.id].merge(PlayerMotion.put_ashore(_parked_exit(room, room.ship)), true)
		_drop_carried(room, con.id)
		# Save the last position before evicting an empty room from memory.
		var saved := _checkpoint(con.room)
		room.actors.erase(con.id)
		if room.actors.is_empty() and saved:
			rooms.erase(con.room)
		else:
			_resolve_knockouts(con.room, room)
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
		if not Storage.held_by(room.data.storage, con.id).is_empty():
			_send(con.ws, {"t":"notice", "ok":false, "site":"storage", "text":"先放下手中的物件"})
			return
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
	if action=="whistle":
		var personal: Dictionary=room.data.survival[con.id]
		if personal.health<=0.0 or int(personal.bag.get("tusk_whistle",0))<1 or float(actor.get("whistleAt",-10.0))+4.0>float(room.data.elapsed):
			return
		actor.whistleAt=room.data.elapsed
		_actor_sound(room,actor,"tusk_whistle")
		var nearby: bool=StorageWildlife.alive(room,"dog") and dog.owner==con.id and CampDog.position(dog).distance_to(actor.point)<=36.
		if nearby:
			var old_mode: String=dog.mode
			dog.mode="follow"
			if not _checkpoint(con.room):
				dog.mode=old_mode
				_send(con.ws,{"t":"notice","ok":false,"site":"dog","text":"存档写入失败，请稍后再吹哨"})
				return
			room.dog_route.clear()
		_send(con.ws,{"t":"notice","ok":nearby,"site":"dog","text":"藏獒听见了哨声，正向你赶来" if nearby else "附近没有回应你的猎犬"})
		_publish(con.room)
		return
	if not StorageWildlife.alive(room, "dog") or action.is_empty() or action != CampDog.command(dog, con.id):
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
	if requested is not String or requested not in ["take", "eat_table", "drink_table", "eat", "put", "drop", "drink", "take_backpack", "wear", "remove_worn", "drop_worn"]:
		return
	var room: Dictionary = rooms[con.room]
	var actor: Dictionary = room.actors[con.id]
	if room.data.survival[con.id].health <= 0.0:
		return
	if requested == "take_backpack":
		_take_backpack(con, room, actor.point)
		return
	var before_state: Dictionary = room.data.survival[con.id]
	var before_provisions: Dictionary = room.data.provisions
	var state := before_state.duplicate(true)
	var provisions := before_provisions.duplicate()
	var slots := Survival.slot_count(room.data.backpackOwner == con.id)
	var result := _use_provision(requested, msg, actor, state, provisions, slots,room.data.storage)
	if not result.ok:
		_provision_notice(con, false, result.text)
		return
	room.data.survival[con.id] = state
	room.data.provisions = provisions
	if _checkpoint(con.room):
		if result.has("cue"):
			_actor_sound(room, actor, result.cue)
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
		_actor_sound(room, room.actors[con.id], "item_pickup")
		_publish(con.room)
		_provision_notice(con, true, "已背上背包，格子 +6")
	else:
		room.data.backpackOwner = ""
		_provision_notice(con, false, "存档写入失败，请稍后重试")

func _use_provision(action: String, msg: Dictionary, actor: Dictionary, state: Dictionary, provisions: Dictionary, slots: int, storage := {}) -> Dictionary:
	var point: Vector2 = actor.point
	if action in ["take", "eat_table", "drink_table"]:
		var id: Variant = msg.get("id")
		if id is not String or not provisions.has(id):
			return {"ok": false, "text": "物品已不在这里"}
		var record: Dictionary = provisions[id].duplicate()
		var reach_surface: String = "ground" if record.has("tableId") else record.surface
		if not Survival.can_reach(point, Survival.horizontal(record.at), reach_surface) or absf(float(record.at[1])-float(actor.y)) > 1.85:
			return {"ok": false, "text": "走近物品后再互动"}
		var item: String = record.item
		if action == "take":
			if not Survival.can_carry(state.bag, item, slots):
				return {"ok": false, "text": "背包已满"}
			state.bag[item] = int(state.bag.get(item, 0)) + 1
			Survival.record_food_in_guide(state, item)
		elif action == "drink_table":
			if not Survival.is_drinkable(item):
				return {"ok": false, "text": "这件物品不能喝"}
			if float(state.water) >= Survival.DRINK_THRESHOLD:
				return {"ok": false, "text": "现在不渴，溪水已保留"}
			Survival.drink(state)
		else:
			if not Survival.FOOD_STATS.has(item):
				return {"ok": false, "text": "按 E 捡起物品"}
			Survival.eat(state, item)
		var count := int(record.get("count", 1))
		if count > 1:
			record.count = count - 1
			provisions[id] = record
		else:
			provisions.erase(id)
		var verb := "捡起了" if action == "take" else "喝了一份" if action == "drink_table" else "吃掉了"
		return {"ok": true, "text": verb + Survival.ITEM_NAMES[item], "cue": "item_pickup" if action == "take" else _food_sound(item)}
	if action == "drink" and str(msg.get("item", "")).is_empty():
		var jug: Dictionary = storage.get("camp-water-jug",{})
		if jug.get("mode") != "ground" or not Storage.near(actor,jug,grid) or point.distance_squared_to(Survival.horizontal(jug.at)) > Survival.JUG_REACH ** 2:
			return {"ok": false, "text": "靠近水壶后再喝水"}
		if float(state.water) >= Survival.DRINK_THRESHOLD:
			return {"ok": false, "text": "现在不渴"}
		Survival.drink(state)
		return {"ok": true, "text": "喝了水，水分恢复", "cue": "drink_water"}
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
		return _place_provision(selected, actor, provisions, storage)
	if int(state.bag.get(selected, 0)) <= 0:
		return {"ok": false, "text": "背包里没有这件物品"}
	if action == "wear":
		if not clothing or bool(state.worn.get(selected, false)):
			return {"ok": false, "text": "先脱下同类衣物"}
		state.bag[selected] -= 1
		var displaced: String = Survival.HEAD_REPLACEMENT.get(selected, "")
		if bool(state.worn.get(displaced, false)):
			if not Survival.can_carry(state.bag, displaced, slots):
				return {"ok": false, "text": "背包没有空位收起" + Survival.ITEM_NAMES[displaced]}
			state.bag[displaced] = int(state.bag.get(displaced, 0)) + 1
			state.worn[displaced] = false
		state.worn[selected] = true
		return {"ok": true, "text": ("戴上了" if selected == "helmet" else "穿上了") + item_name}
	if clothing and action not in ["drop","put"]:
		return {"ok": false, "text": "衣物可以穿上或丢下"}
	if action == "drink":
		if not Survival.is_drinkable(selected):
			return {"ok": false, "text": "这件物品不能喝"}
		if float(state.water) >= Survival.DRINK_THRESHOLD:
			return {"ok": false, "text": "现在不渴，溪水已保留"}
		state.bag[selected] -= 1
		Survival.drink(state)
		return {"ok": true, "text": "喝了一份溪水，水分恢复", "cue": "drink_water"}
	if action == "eat":
		if not Survival.FOOD_STATS.has(selected):
			return {"ok": false, "text": "这件物品可在 B 营地住民中装备或用于照料"}
		state.bag[selected] -= 1
		Survival.eat(state, selected)
		return {"ok": true, "text": "吃掉了" + item_name, "cue": _food_sound(selected)}
	var surface := "table" if action == "put" else "ground"
	var result: Dictionary
	if surface == "table":
		var table := Storage.table_at(storage,point)
		if table.is_empty() or not Storage.near(actor,storage[table],grid):
			return {"ok": false, "text": "靠近桌子后再放一份"}
		var place := Storage.table_slot(storage,provisions,table)
		if not place.is_finite():
			return {"ok": false, "text": "桌上没有空位"}
		var id := Crypto.new().generate_random_bytes(8).hex_encode()
		while provisions.has(id):
			id = Crypto.new().generate_random_bytes(8).hex_encode()
		provisions[id] = Survival.provision(selected,place,"table" if table == Survival.CAMP_TABLE else "ground")
		provisions[id].tableId = table
		result = {"ok":true,"text":"放在木桌上：" + item_name}
	else:
		result = _place_provision(selected, actor, provisions, storage)
	if result.ok:
		state.bag[selected] -= 1
		if int(state.bag[selected]) <= 0:
			if state.get("weapon", "") == selected:
				state.weapon = ""
			if selected == "shield":
				state.shield = false
	return result

func _place_provision(item: String, actor: Dictionary, provisions: Dictionary, storage: Dictionary) -> Dictionary:
	var landing := _provision_drop_position(actor,provisions,storage,Survival.CLOTHING.has(item))
	if landing.is_empty():
		return {"ok":false,"text":"脚边没有空地"}
	var id := Crypto.new().generate_random_bytes(8).hex_encode()
	while provisions.has(id):
		id = Crypto.new().generate_random_bytes(8).hex_encode()
	provisions[id] = Survival.provision(item,landing.at,"ground")
	if not landing.id.is_empty():
		provisions[id].supportId = landing.id
	return {"ok":true,"text":"放下了" + Survival.ITEM_NAMES[item]}

func _provision_drop_position(actor: Dictionary, provisions: Dictionary, storage: Dictionary, clothing: bool) -> Dictionary:
	var point: Vector2 = actor.point
	var facing := Vector2(0.0, -0.58).rotated(-float(actor.yaw))
	for offset: Vector2 in [facing, facing.rotated(PI / 3.0), facing.rotated(-PI / 3.0), Vector2.ZERO]:
		var candidate := point + offset
		if candidate != candidate.clamp(Rules.MIN_CORNER, Rules.MAX_CORNER) or not Rules.free_at(candidate, grid):
			continue
		var drop_from := Vector3(candidate.x,float(actor.y)+.40,candidate.y)
		var landing := Storage.provision_landing(drop_from,storage,placement_grid,clothing)
		if landing.is_empty():
			continue
		var crowded := false
		for record: Dictionary in provisions.values():
			if Stones.unpack(record.at).distance_squared_to(landing.at) < .03:
				crowded = true
				break
		if not crowded:
			return landing
	if clothing:
		return Storage.provision_landing(Vector3(point.x,float(actor.y)+.40,point.y),storage,placement_grid,true)
	return {}

func _provision_notice(con: Dictionary, ok: bool, message: String) -> void:
	_send(con.ws, {"t": "notice", "ok": ok, "site": "provision", "text": message})

func _stone_action(con: Dictionary, msg: Dictionary) -> void:
	var room: Dictionary = rooms[con.room]
	var actor: Dictionary = room.actors[con.id]
	if room.data.survival[con.id].health <= 0.0:
		return
	var stones: Dictionary = room.data.stones
	var held := Stones.held_by(stones, con.id)
	var id := held
	var operation: Variant = msg.get("action")
	var action := ""
	match operation:
		"pick":
			if not held.is_empty() or not Storage.held_by(room.data.storage, con.id).is_empty() or msg.get("id") is not String or not stones.has(msg.id):
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
	var before_weapon: String = room.data.survival[con.id].get("weapon", "")
	var line_was_cut: bool = room.data.lineCut
	var result := ""
	match action:
		"pick":
			stone.mode = "held"
			stone.holder = con.id
			room.data.survival[con.id].weapon = ""
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
			stone.thrower = con.id
			stone.erase("holder")
	if _checkpoint(con.room):
		if action == "throw":
			_world_sound(room, "stone_throw", Stones.unpack(stone.at))
		elif action in ["grind", "pick"]:
			_actor_sound(room, actor, "mine_strike" if action == "grind" else "item_pickup")
		elif action == "drop":
			_stone_rest_sound(room, Stones.unpack(stone.at), 0.59)
		_publish(con.room)
		if not result.is_empty():
			_send(con.ws, {"t": "notice", "ok": true, "site": id, "text": result})
	else:
		stones[id] = before
		room.data.survival[con.id].weapon = before_weapon
		room.data.lineCut = line_was_cut
		_send(con.ws, {"t": "notice", "ok": false, "site": id, "text": "存档写入失败，请稍后重试"})

func _storage_action(con: Dictionary, msg: Dictionary) -> void:
	if not msg.get("action") is String:
		return
	var room: Dictionary = rooms[con.room]
	var old_storage: Dictionary = room.data.storage
	var old_personal: Dictionary = room.data.survival[con.id]
	var old_provisions: Dictionary = room.data.provisions
	var old_actor: Dictionary = room.actors[con.id]
	room.data.storage = old_storage.duplicate(true)
	room.data.survival[con.id] = old_personal.duplicate(true)
	room.data.provisions = old_provisions.duplicate()
	room.actors[con.id] = old_actor.duplicate()
	if placement_grid.is_empty():
		placement_grid = PlacementWorld.static_grid(world)
	var result := Storage.action(room, con.id, msg, grid, placement_grid)
	if result.ok and not _checkpoint(con.room):
		result = {"ok":false, "text":"存档写入失败，请稍后重试"}
	if result.ok:
		if msg.action in ["craft", "build", "dismantle", "place", "fuel", "smelt"]:
			_actor_sound(room, room.actors[con.id], "camp_work")
		elif msg.action in ["take", "store", "take_ingot", "carry"]:
			_actor_sound(room, room.actors[con.id], "item_pickup")
		_publish(con.room)
	else:
		room.data.storage = old_storage
		room.data.survival[con.id] = old_personal
		room.data.provisions = old_provisions
		room.actors[con.id] = old_actor
	_send(con.ws, {"t":"notice", "ok":result.ok, "site":"storage", "text":result.text})

func _mining_action(con: Dictionary, msg: Dictionary) -> void:
	var id: Variant = msg.get("id")
	if id is not String or not MinesLayout.data.has(id):
		return
	var room: Dictionary = rooms[con.room]
	var old_veins: Dictionary = room.data.mines
	var old_player: Dictionary = room.data.survival[con.id]
	var old_actor: Dictionary = room.actors[con.id]
	var veins := old_veins.duplicate(true)
	var personal := old_player.duplicate(true)
	var actor := old_actor.duplicate()
	var slots := Survival.slot_count(room.data.backpackOwner == con.id)
	var target := MinesLayout.gather(id)
	var solids := PlacementWorld.nearby(placement_grid,room.data.storage,actor.point)
	var result := Mining.extract(veins,id,personal,actor,room.data.elapsed,slots,target,solids)
	if result.ok:
		room.data.mines = veins
		room.data.survival[con.id] = personal
		room.actors[con.id] = actor
		if _checkpoint(con.room):
			_world_sound(room, "mine_strike", target)
			_publish(con.room)
		else:
			room.data.mines = old_veins
			room.data.survival[con.id] = old_player
			room.actors[con.id] = old_actor
			result = {"ok":false,"text":"存档写入失败，请稍后重试"}
	_send(con.ws, {"t":"notice","ok":result.ok,"site":"mine","text":result.text})


func _tick_storage(room: Dictionary, delta: float, code := "") -> void:
	var now: float = room.data.elapsed
	var records: Dictionary = room.data.storage
	for id: String in records.keys():
		var object: Dictionary = records[id]
		if object.mode == "held" and room.actors.has(object.holder):
			var owner: Dictionary = room.actors[object.holder]
			if room.data.survival[object.holder].health <= 0.0 or owner.swimming:
				Storage.grounded(object,owner.point,owner.yaw)
		if object.mode != "air":
			continue
		var previous := Stones.flight_position(object,now-delta)
		var at := Stones.flight_position(object,now)
		var point := Vector2(at.x,at.z)
		var last := Vector2(previous.x,previous.z)
		var radius: float = Storage.KINDS[object.kind].radius
		var damage := lerpf(13.0,30.0,minf(1.0,radius/0.8))
		if point != point.clamp(Rules.MIN_CORNER,Rules.MAX_CORNER) or (at.y < LakeLayout.walk_height(point)+2.0 and not Rules.obstacle_free_at(point,grid)):
			Storage.grounded(object,last,object.yaw)
		elif _thrown_hit(room, object, previous, at, radius, damage, code):
			Storage.grounded(object,point,object.yaw)
			_world_sound(room,"stone_wood",at,0.74)
		elif at.y <= maxf(LakeLayout.walk_height(point),LakeLayout.surface_height(point)):
			Storage.grounded(object,point,object.yaw)
			_stone_rest_sound(room,Stones.unpack(object.at),0.68)


func _tick_storage_pose(room: Dictionary, actor: Dictionary, able: bool, delta: float) -> bool:
	var records: Dictionary = room.data.get("storage", {})
	var ladder: Dictionary = records.get(actor.get("climbing",""),{})
	var chair: Dictionary = records.get(actor.get("storageSeat",""),{})
	if able and actor.lift <= 0.0 and ladder.get("mode") == "ground":
		var base := Stones.unpack(ladder.at)
		var heading := Vector2(0.0,-1.0).rotated(-float(ladder.yaw))
		actor.point = Vector2(base.x,base.z) + heading * 0.36
		actor.y = clampf(float(actor.y)+actor.direction.dot(Vector2(0,-1).rotated(-float(actor.yaw)))*delta*1.5,base.y,base.y+1.97)
	elif able and actor.lift <= 0.0 and actor.direction.is_zero_approx() and chair.get("mode") == "ground":
		var base := Stones.unpack(chair.at)
		actor.point = Vector2(base.x,base.z)
		actor.y = base.y + 0.04
	else:
		actor.erase("climbing")
		actor.erase("storageSeat")
		return false
	actor.grounded = true
	actor.swimming = false
	actor.vy = 0.0
	actor.vx = 0.0
	actor.vz = 0.0
	return true


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

static func _food_sound(item: String) -> String:
	match item:
		"water": return "drink_water"
		"apple": return "eat_apple"
		"bread", "crocodile_sandwich": return "eat_bread"
		_: return "eat_meat"

func _actor_sound(room: Dictionary, actor: Dictionary, cue: String) -> void:
	_world_sound(room, cue, Vector3(actor.point.x, actor.y + 1.28, actor.point.y))

func _world_sound(room: Dictionary, cue: String, at: Vector3, strength := 1.0) -> void:
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
		_world_sound(room, "stone_water", Vector3(at.x, surface, at.z), strength)
	else:
		var cue := "stone_wood" if LakeLayout.on_dock(point) else "stone_earth"
		_world_sound(room, cue, at, strength)

func _tick_stones(room: Dictionary, delta: float, code := "") -> void:
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
		if _thrown_hit(room, stone, previous, at, Stones.THROW_RADIUS, Stones.BLUNT_DAMAGE, code):
			_set_ground(stone, id, bounds)
			if LakeLayout.walk_height(bounds) <= LakeLayout.surface_height(bounds):
				stone.mode = "submerged"
			_world_sound(room, "stone_earth", at, 0.7)
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
			_world_sound(room, "stone_water", Vector3(point.x, surface, point.y))
		elif at.y <= ground:
			_set_ground(stone, id, bounds)
			_stone_rest_sound(room, Stones.unpack(stone.at))
		elif at.y < 2.0 and Rules.obstacle_free_at(previous_point, grid) and not Rules.obstacle_free_at(point, grid):
			_set_ground(stone, id, previous_point)
			_world_sound(room, "stone_rock", previous)

func _tick_boar(code: String, room: Dictionary, delta: float) -> void:
	if not StorageWildlife.alive(room,"boar"):
		var carcass: Dictionary=room.data.storage.get("corpse-boar",{})
		if not carcass.is_empty() and carcass.bag.is_empty() and float(room.data.elapsed)-float(carcass.deadAt)>=Boar.RESPAWN_TIME:
			room.data.storage.erase("corpse-boar")
			room.data.storageWildlife.boar=StorageWildlife.MAX_HEALTH.boar
			room.data.boar=Boar.start(room.data.elapsed)
		return
	var event:=Boar.tick(room,grid,delta)
	if event.has("cue"):
		_world_sound(room,event.cue,Boar.world_at(room.data.boar)+Vector3.UP*.48)
	if event.has("hurt"):
		var personal: Dictionary=room.data.survival[event.hurt]
		personal.health=maxf(0.,float(personal.health)-Boar.DAMAGE)
	if event.has("hurt") or event.has("warn"):
		var id: String=event.get("hurt",event.get("warn",""))
		for con: Dictionary in connections.values():
			if con.room==code and con.id==id:
				_send(con.ws,{"t":"notice","ok":false,"site":"boar","text":"被野猪撞伤了" if event.has("hurt") else "野猪压低了头，往侧面闪开"})

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

func _thrown_hit(room: Dictionary, object: Dictionary, previous: Vector3, at: Vector3,
		radius: float, blunt_damage: float, code: String) -> bool:
	var animal := StorageWildlife.room_hit(room, previous, at, radius)
	var nearest: float = animal.get("distance", INF)
	var victim := ""
	var zone := "body"
	for id: String in room.data.wildPeople.people:
		var npc: Dictionary = room.data.wildPeople.people[id]
		if npc.phase in ["dead", "gone", "released"]:
			continue
		var hit := WildPeople.ray_hit(npc, previous, at)
		if not hit.is_empty() and hit.distance < nearest:
			nearest = hit.distance
			victim = id
			zone = hit.zone
	var blunt: bool = int(object.get("edge", 0)) == 0
	var damage := blunt_damage if blunt else Stones.SHARP_DAMAGE
	if not victim.is_empty():
		WildPeople.harm(room.data.wildPeople, room.data.wildPeople.people[victim], damage, blunt, zone,
			str(object.get("thrower", "")), room.data.elapsed)
		return true
	if animal.is_empty():
		return false
	var contact := previous + previous.direction_to(at) * sqrt(nearest)
	if Spaceship.Ground.sight_obstructed(previous, contact, ship_grid, _grove_time(room.data)) or Spaceship.blocks_sight(room.ship, previous, contact):
		return false
	var message := StorageWildlife.apply_hit(room, animal, damage, grid)
	if message.is_empty():
		return false
	_world_sound(room, "animal_hit", contact)
	var thrower: String = object.get("thrower", "")
	for con: Dictionary in connections.values():
		if con.room == code and con.id == thrower:
			_send(con.ws, {"t": "notice", "ok": true, "site": "wildlife", "text": message})
			break
	return true

func _wild_action(con: Dictionary, msg: Dictionary) -> void:
	if msg.get("action") is not String:
		return
	var now_ms := Time.get_ticks_msec()
	if now_ms < int(con.get("person_next_ms", 0)):
		return
	con.person_next_ms = now_ms + 120
	var room: Dictionary = rooms[con.room]
	var attacking: bool = msg.action == "attack"
	if msg.action in ["attack", "equip", "shield"] and not Storage.held_by(room.data.storage, con.id).is_empty():
		_send(con.ws, {"t":"notice", "ok":false, "site":"storage", "text":"先放下手中的物件"})
		return
	var before_people: Dictionary = room.data.wildPeople.duplicate(true)
	var before_survival: Dictionary = room.data.survival.duplicate(true)
	var before_provisions: Dictionary = room.data.provisions.duplicate(true)
	var before_quest: Dictionary = room.data.quest.duplicate()
	var before_actor: Dictionary = room.actors[con.id].duplicate(true)
	var before_wildlife: Dictionary = room.data.storageWildlife.duplicate() if attacking else {}
	var before_storage: Dictionary = room.data.storage.duplicate() if attacking else {}
	var before_croc: Dictionary = room.crocodile.duplicate() if attacking else {}
	var result := people_motion.action(room, con.id, msg, grid, ship_grid)
	var changed: bool = room.data.wildPeople != before_people or room.data.survival != before_survival or room.data.provisions != before_provisions or room.actors[con.id] != before_actor or room.data.quest != before_quest
	if attacking:
		changed = changed or room.data.storageWildlife != before_wildlife
	if changed and not _checkpoint(con.room):
		room.data.wildPeople = before_people
		room.data.survival = before_survival
		room.data.provisions = before_provisions
		room.data.quest = before_quest
		room.actors[con.id] = before_actor
		if attacking:
			room.data.storageWildlife = before_wildlife
			room.data.storage = before_storage
			room.crocodile = before_croc
		result = {"ok": false, "text": "存档写入失败，操作未生效，请稍后重试"}
	elif changed:
		if result.ok:
			if result.has("animalContact"):
				_world_sound(room, "animal_hit", result.animalContact)
			elif msg.action in ["feed", "water", "gift"]:
				var npc: Dictionary = room.data.wildPeople.people.get(msg.get("id", ""), {})
				if not npc.is_empty():
					_world_sound(room, _food_sound("water" if msg.action == "water" else str(msg.get("item", "apple"))), Vector3(npc.x,npc.y+1.3,npc.z))
			elif msg.action in ["gather", "loot", "repair"]:
				_actor_sound(room, room.actors[con.id], "camp_work" if msg.action == "repair" else "item_pickup")
		_publish(con.room)
	if not result.text.is_empty():
		_send(con.ws, {"t": "notice", "site": "person", "ok": result.ok, "text": result.text})

# Source availability is world state. Collected material belongs only to its collector.
func _restore_materials(data: Dictionary) -> void:
	if data.get("materialVersion", 0) != 1:
		var pending := {"wood": 0, "tarp": 0}
		for item: String in pending:
			if data.quest.get(item, false) and not data.quest.repaired:
				pending[item] = 1
		var eligible: Array = data.survival.keys()
		for player: String in data.homes:
			if player.length() == 16 and player.is_valid_hex_number(false) and player not in eligible:
				eligible.append(player)
		data.materialLegacy = {"pending": pending, "eligible": eligible, "owner": "", "recipients": {}}
		data.materialSources = {}
		for item: String in pending:
			data.materialSources[item] = float(data.elapsed) + Survival.MATERIAL_RESTOCK if data.quest.get(item, false) else 0.0
		data.materialVersion = 1
	var saved: Variant = data.get("materialSources", {})
	var sources := {}
	for item: String in ["wood", "tarp"]:
		var time: Variant = saved.get(item, 0.0) if saved is Dictionary else 0.0
		sources[item] = maxf(0.0, float(time)) if Survival.finite_number(time) else 0.0
		data.quest[item] = float(sources[item]) > float(data.elapsed)
	data.materialSources = sources
	var legacy: Variant = data.get("materialLegacy", {})
	if legacy is not Dictionary:
		legacy = {}
	var pending: Variant = legacy.get("pending", {})
	data.materialLegacy = {"pending": {"wood": 1 if pending is Dictionary and pending.get("wood", 0) == 1 else 0,
		"tarp": 1 if pending is Dictionary and pending.get("tarp", 0) == 1 else 0},
		"eligible": legacy.get("eligible", []) if legacy.get("eligible") is Array else [],
		"owner": legacy.get("owner", "") if legacy.get("owner") is String else "",
		"recipients": legacy.get("recipients", {}) if legacy.get("recipients") is Dictionary else {}}

func _refresh_material_sources(room: Dictionary) -> void:
	for item: String in ["wood", "tarp"]:
		if room.data.quest.get(item, false) and float(room.data.elapsed) >= float(room.data.materialSources[item]):
			room.data.quest[item] = false

func _claim_legacy_materials(code: String) -> void:
	var room: Dictionary = rooms[code]
	var ledger: Dictionary = room.data.materialLegacy
	if int(ledger.pending.wood) + int(ledger.pending.tarp) <= 0:
		return
	for id: String in room.actors:
		if not str(ledger.owner).is_empty() and ledger.owner != id:
			continue
		if not ledger.eligible.is_empty() and id not in ledger.eligible:
			continue
		var before: Dictionary = room.data.survival[id].duplicate(true)
		var before_ledger := ledger.duplicate(true)
		var state: Dictionary = room.data.survival[id]
		ledger.owner = id
		var granted := false
		for item: String in ["wood", "tarp"]:
			if ledger.pending[item] == 1 and Survival.can_carry(state.bag, item, Survival.slot_count(room.data.backpackOwner == id)):
				state.bag[item] = int(state.bag.get(item, 0)) + 1
				ledger.pending[item] = 0
				ledger.recipients[item] = id
				granted = true
		if granted or ledger != before_ledger:
			if not _checkpoint(code):
				room.data.survival[id] = before
				room.data.materialLegacy = before_ledger
				return
			if granted:
				for con: Dictionary in connections.values():
					if con.room == code and con.id == id:
						_provision_notice(con, true, "营地保留的修屋材料已放入你的背包")
			return

func _act(con: Dictionary, site: String) -> void:
	var room: Dictionary = rooms[con.room]
	var actor: Dictionary = room.actors[con.id]
	if site not in ["wood", "tarp", "repair"] or not world.sites.has(site):
		return
	var result := "走近目标后再互动"
	var accepted := false
	var state: Dictionary = room.data.survival[con.id]
	if actor.point.distance_to(Rules.pair(world.sites[site])) <= Rules.INTERACT_RANGE:
		var before_quest: Dictionary = room.data.quest.duplicate()
		var before_sources: Dictionary = room.data.materialSources.duplicate()
		var before_state := state.duplicate(true)
		var prior_facility: float = room.data.wildPeople.facility
		if site == "repair":
			if room.data.quest.repaired and prior_facility >= 100.0:
				result = "屋顶完好，无需修补"
			elif int(state.bag.get("wood", 0)) < 1 or int(state.bag.get("tarp", 0)) < 1:
				result = "你的背包需要木料 1 份和防水布 1 份"
			else:
				state.bag.wood -= 1
				state.bag.tarp -= 1
				room.data.quest.repaired = true
				room.data.wildPeople.facility = 100.0
				accepted = true
				result = "已消耗你的木料与防水布，屋顶修复，营灯亮了"
		elif room.data.quest.get(site, false):
			result = "这处材料已取，约 %d 秒后可再拾取" % ceili(float(room.data.materialSources[site]) - float(room.data.elapsed))
		elif not Survival.can_carry(state.bag, site, Survival.slot_count(room.data.backpackOwner == con.id)):
			result = "背包已满"
		else:
			state.bag[site] = int(state.bag.get(site, 0)) + 1
			room.data.quest[site] = true
			room.data.materialSources[site] = float(room.data.elapsed) + Survival.MATERIAL_RESTOCK
			accepted = true
			result = Survival.ITEM_NAMES[site] + "已放入你的背包；此处材料稍后可再拾取"
		if accepted:
			if _checkpoint(con.room):
				_actor_sound(room, actor, "camp_work" if site == "repair" else "item_pickup")
				_publish(con.room)
			else:
				room.data.quest = before_quest
				room.data.materialSources = before_sources
				room.data.survival[con.id] = before_state
				room.data.wildPeople.facility = prior_facility
				accepted = false
				result = "存档写入失败，请稍后重试"
	_send(con.ws, {"t":"notice", "ok":accepted, "site":site, "text":result})

func _publish(code: String) -> void:
	var room: Dictionary = rooms[code]
	var actors := {}
	for id in room.actors:
		var a: Dictionary = room.actors[id]
		actors[id] = {"x": a.point.x, "y": a.y, "z": a.point.y, "vy": a.vy,
			"swimming": a.swimming, "yaw": a.yaw, "slot": a.slot, "worn": room.data.survival[id].worn,
			"grounded": a.get("grounded", not a.swimming), "vx": a.get("vx", 0.0), "vz": a.get("vz", 0.0), "waterVy": a.get("waterVy", 0.0)}
		var personal: Dictionary = room.data.survival[id]
		actors[id].bedroll=int(personal.bag.get("boar_bedroll",0))>0
		actors[id].whistle=int(personal.bag.get("tusk_whistle",0))>0
		actors[id].onFerry = a.get("onFerry", false)
		actors[id].crouched = a.get("crouched",false)
		actors[id].bed = a.get("bed","")
		if not actors[id].bed.is_empty():
			actors[id].bedYaw = a.bedYaw
		if actors[id].onFerry:
			actors[id].deck = [a.ferryLocal.x,a.ferryLocal.y]
		actors[id].climbing = not str(a.get("climbing","")).is_empty()
		actors[id].storageSeated = not str(a.get("storageSeat","")).is_empty()
		actors[id].merge({"weapon": personal.get("weapon", ""), "shield": personal.get("shield", false),
			"attackAt": personal.get("attackAt", -10.0), "attackWeapon": personal.get("attackWeapon", ""),
			"punchStep": personal.get("punchStep", 0), "attackPitch": personal.get("attackPitch", 0.0),
			"aimPitch": a.get("aimPitch"), "blocking": personal.get("blocking", false), "health": personal.health,
			"downAt": personal.downAt, "revivedAt": a.get("revivedAt", -1.0)})
	var grove_elapsed := _grove_time(room.data)
	var snapshot := {"t":"snapshot", "quest":room.data.quest, "elapsed":room.data.elapsed, "groveElapsed":grove_elapsed, "players":actors, "stones":room.data.stones, "lineCut":room.data.lineCut, "waterImpacts":room.impacts, "backpackOwner":room.data.backpackOwner, "dog":room.data.dog, "materialSources":room.data.materialSources}
	snapshot.stoneSounds = room.stone_sounds
	snapshot.storage = room.data.storage
	Mining.refresh(room.data.mines,float(room.data.elapsed))
	snapshot.mines = room.data.mines
	snapshot.boar = room.data.get("boar",{}) if StorageWildlife.alive(room,"boar") else {}
	snapshot.sheepAlive = StorageWildlife.alive(room, "sheep")
	snapshot.reedCuts = room.data.reedCuts
	snapshot.shearedAt = room.data.get("shearedAt", -1.0)
	snapshot.ferryDepartedAt = room.data.get("ferryDepartedAt", -1.0)
	snapshot.eagleAlive = StorageWildlife.alive(room, "eagle")
	if not StorageWildlife.alive(room, "dog"):
		snapshot.dog = {}
	snapshot.crocodile = Wildlife.crocodile_pose(room.crocodile) if StorageWildlife.alive(room, "croc") else {"dead":true}
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
			outgoing.wildPeople = WildPeople.snapshot(room.data.wildPeople, con.id, room.data.elapsed)
			if not personal.is_empty():
				outgoing.survival = Survival.snapshot(personal)
				var legacy: Dictionary = room.data.materialLegacy
				outgoing.survival.materialPending = legacy.pending if legacy.owner == con.id else {"wood": 0, "tarp": 0}
			if flow:
				outgoing.snapshotSeq = int(con.snapshot_sent) + 1
			if _send(con.ws, outgoing) and flow:
				con.snapshot_sent = outgoing.snapshotSeq

func _checkpoint(code: String) -> bool:
	var room: Dictionary = rooms[code]
	for id in room.actors:
		var a: Dictionary = room.actors[id]
		var home: Vector3 = a.get("bedExit",Vector3(a.point.x, a.y, a.point.y))
		if room.ship.pilot == id:
			home = _parked_exit(room, room.data.ship)
		room.data.homes[id] = {"x":home.x, "z":home.z, "yaw":a.yaw, "y":home.y}
		if a.get("onFerry", false) and room.ship.pilot != id:
			var local: Vector2 = Vector2(.055,0) if Beds.aboard(a.get("bed","")) else a.ferryLocal
			room.data.homes[id].ferryLocal = [local.x,local.y]
			room.data.homes[id].ferryCrouched = Ferry.under_canopy(local)
	var path := save_dir.path_join(code + ".json")
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	var saved: Dictionary = room.data.duplicate(true)
	Storage.settle_save(saved.storage, room.actors)
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
