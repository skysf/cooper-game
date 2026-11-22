extends "res://server.gd"

const ROOM := "resources"
const TOKEN_A := "000000000000000000000000000000a1"
const TOKEN_B := "000000000000000000000000000000b2"
const TABLE_NEAR := Vector2(2.54, -87.95)
const ProvisionScene = preload("res://provision_scene.gd")
var received := {}
var checks := []
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _send(ws: WebSocketPeer, msg: Dictionary) -> bool:
	if not received.has(ws.get_instance_id()):
		received[ws.get_instance_id()] = {}
	received[ws.get_instance_id()][msg.t] = msg.duplicate(true)
	return true

func _expect(ok: bool, label: String) -> void:
	checks.append({"ok": ok, "check": label})
	if not ok:
		failed += 1
		push_error(label)

func _connect(key: int, token: String) -> Dictionary:
	var con := {"ws": WebSocketPeer.new(), "room": "", "id": "", "rejected": false}
	connections[key] = con
	_join(con, {"room": ROOM, "token": token})
	return con

func _action(con: Dictionary, action: String, item := "", id := "") -> void:
	_provision_action(con, {"action": action, "item": item, "id": id})

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	save_dir = args[0]
	DirAccess.make_dir_recursive_absolute(save_dir)
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	var a := _connect(1, TOKEN_A)
	var b := _connect(2, TOKEN_B)
	var room: Dictionary = rooms[ROOM]
	room.actors[a.id].point = TABLE_NEAR
	room.actors[b.id].point = TABLE_NEAR
	var bag: Dictionary = room.data.survival[a.id].bag
	for amount in [4, 7, 10, 100]:
		var restored := Survival.state_from_save({"bag": {"water": amount, "wood": amount, "tarp": amount}, "combatMode": "lethal"})
		_expect(restored.bag.water == amount and restored.bag.wood == amount and restored.bag.tarp == amount and Survival.used_slots(restored.bag) == 3, "single stack and old counts survive: " + str(amount))
		_expect(not restored.has("combatMode") and not Survival.snapshot(restored).has("combatMode"), "legacy combat choice is absorbed: " + str(amount))
	var full := {"club": 1, "spear": 1, "shield": 1, "stone": 1, "cap": 1, "water": 10}
	_expect(Survival.used_slots(full) == 6 and Survival.can_carry(full, "water") and not Survival.can_carry(full, "wood"), "full bag still merges water but cannot add a new kind")
	_expect(not Survival.FOOD_STATS.has("water") and Survival.can_table("water"), "water is a drink and table supply, never food")
	bag.water = 10
	room.data.survival[a.id].water = 50.0
	_action(a, "drink", "water")
	_expect(room.data.survival[a.id].bag.water == 9 and room.data.survival[a.id].water == 82.0, "drinking one carried water consumes one and restores 32")
	room.data.survival[a.id].water = 100.0
	_action(a, "drink", "water")
	_expect(room.data.survival[a.id].bag.water == 9, "full hydration keeps carried water")
	var before: Dictionary = room.data.survival[a.id].duplicate(true)
	var writable := save_dir
	save_dir = save_dir.path_join(ROOM + ".json")
	room.data.survival[a.id].water = 50.0
	_action(a, "drink", "water")
	_expect(room.data.survival[a.id].bag.water == 9 and room.data.survival[a.id].water == 50.0, "failed save rolls back water and hydration together")
	save_dir = writable
	room.data.survival[a.id] = before
	_action(a, "put", "water")
	var water_id := ""
	for id: String in room.data.provisions:
		if room.data.provisions[id].item == "water":
			water_id = id
	_expect(not water_id.is_empty() and room.data.survival[a.id].bag.water == 8 and room.data.provisions[water_id].surface == "table", "placing water creates one real shared table item and deducts one")
	var scene := ProvisionScene.new()
	root.add_child(scene)
	scene.update_contents(room.data.provisions)
	_expect(scene.food_nodes.has(water_id) and scene.food_nodes[water_id].get_child_count() > 0, "table water instantiates the existing real jug GLB")
	_action(a, "take", "", water_id)
	_action(b, "take", "", water_id)
	_expect(room.data.survival[a.id].bag.water == 9 and room.data.survival[b.id].bag.get("water", 0) == 0 and not room.data.provisions.has(water_id), "two claimants cannot duplicate a water container")
	_action(a, "put", "water")
	for id: String in room.data.provisions:
		if room.data.provisions[id].item == "water":
			water_id = id
	room.data.survival[b.id].water = 20.0
	_action(b, "drink_table", "water", water_id)
	_action(a, "take", "", water_id)
	_expect(room.data.survival[b.id].water == 52.0 and room.data.survival[a.id].bag.water == 8 and not room.data.provisions.has(water_id), "table drink and pickup race conserves a single water portion")
	room.actors[a.id].point = Vector2.ZERO
	_action(a, "put", "water")
	_expect(room.data.survival[a.id].bag.water == 8, "distant table placement cannot spend water")
	room.actors[a.id].point = WildPeople.WATER
	var gathered := people_motion.action(room, a.id, {"action": "gather", "item": "water"}, grid)
	_expect(gathered.ok and room.data.survival[a.id].bag.water == 9 and not room.data.wildPeople.resources.has("water"), "shore gathering adds to the same water stack")
	var npc := WildPeople.make_person("care", 0, "male", WildPeople.HOME, room.data.elapsed)
	npc.phase = "captive"
	npc.water = 30.0
	room.data.wildPeople.people.care = npc
	room.actors[a.id].point = WildPeople.HOME + Vector2(0.2, 0)
	var care := people_motion.action(room, a.id, {"action": "water", "id": "care"}, grid)
	_expect(care.ok and npc.water == 62.0 and room.data.survival[a.id].bag.water == 8, "NPC care still consumes exactly one carried water")
	room.data.survival[a.id].bag.clear()
	room.data.survival[b.id].bag.clear()
	room.actors[a.id].point = Rules.pair(world.sites.wood)
	room.actors[b.id].point = Rules.pair(world.sites.wood)
	_act(a, "wood")
	_act(b, "wood")
	_expect(room.data.survival[a.id].bag.wood == 1 and room.data.survival[b.id].bag.get("wood", 0) == 0 and room.data.quest.wood, "wood source has one collector; no team inventory is granted")
	room.actors[b.id].point = Rules.pair(world.sites.tarp)
	_act(b, "tarp")
	room.actors[b.id].point = Rules.pair(world.sites.repair)
	_act(b, "repair")
	_expect(not room.data.quest.repaired and room.data.survival[b.id].bag.tarp == 1, "one player cannot spend the other player's wood")
	room.actors[a.id].point = TABLE_NEAR
	room.actors[b.id].point = TABLE_NEAR
	_action(b, "drop", "tarp")
	var tarp_id := ""
	for id: String in room.data.provisions:
		if room.data.provisions[id].item == "tarp":
			tarp_id = id
	_action(a, "take", "", tarp_id)
	_expect(room.data.survival[a.id].bag.get("tarp", 0) == 1 and room.data.survival[b.id].bag.tarp == 0, "materials share by actual dropped item pickup")
	room.actors[a.id].point = Rules.pair(world.sites.repair)
	save_dir = save_dir.path_join(ROOM + ".json")
	_act(a, "repair")
	_expect(not room.data.quest.repaired and room.data.survival[a.id].bag.wood == 1 and room.data.survival[a.id].bag.tarp == 1, "failed repair checkpoint restores both personal materials and roof")
	save_dir = writable
	_act(a, "repair")
	_expect(room.data.quest.repaired and room.data.survival[a.id].bag.wood == 0 and room.data.survival[a.id].bag.tarp == 0, "largest recipe is portable and initial repair consumes actor's wood1 tarp1")
	room.data.elapsed += Survival.MATERIAL_RESTOCK
	_refresh_material_sources(room)
	_expect(not room.data.quest.wood and not room.data.quest.tarp, "both physical material sources replenish after online cooldown")
	room.data.survival[a.id].bag.merge({"wood": 5, "tarp": 5}, true)
	room.data.wildPeople.facility = 50.0
	room.actors[a.id].point = WildPeople.HOME
	var repair := people_motion.action(room, a.id, {"action": "repair_facility"}, grid)
	_expect(repair.ok and room.data.wildPeople.facility == 75.0 and room.data.survival[a.id].bag.wood == 4 and room.data.survival[a.id].bag.tarp == 4, "later facility repair consumes acting player's materials too")
	var stale := people_motion.action(room, a.id, {"action": "stance"}, grid)
	_expect(not stale.ok and not room.data.survival[a.id].has("combatMode"), "retired stance packet cannot restore an independent mode")
	_expect(_checkpoint(ROOM), "current resource save checkpoints")
	rooms.erase(ROOM)
	_expect(_load_room(ROOM) and rooms[ROOM].data.survival[a.id].bag.wood == 4, "personal material quantities persist through full room reload")
	# Legacy one-time transfer: full existing owner waits; new players never receive duplicates.
	var legacy: Dictionary = rooms[ROOM].data.duplicate(true)
	legacy.erase("materialVersion")
	legacy.erase("materialSources")
	legacy.erase("materialLegacy")
	legacy.quest = {"wood": true, "tarp": true, "repaired": false}
	legacy.survival = {a.id: Survival.initial_state(), b.id: Survival.initial_state()}
	legacy.survival[a.id].bag = {"club": 1, "spear": 1, "shield": 1, "stone": 1, "cap": 1, "jacket": 1}
	_restore_materials(legacy)
	rooms[ROOM].data = legacy
	rooms[ROOM].actors = {a.id: PlayerMotion.spawn(TABLE_NEAR), b.id: PlayerMotion.spawn(TABLE_NEAR)}
	for actor: Dictionary in rooms[ROOM].actors.values():
		actor.yaw = 0.0
	_claim_legacy_materials(ROOM)
	_expect(legacy.materialLegacy.owner == a.id and legacy.materialLegacy.pending.wood == 1 and legacy.survival[b.id].bag.get("wood", 0) == 0, "full old owner reserves migration; no copy to second player")
	legacy.survival[a.id].bag.erase("club")
	legacy.survival[a.id].bag.erase("spear")
	_claim_legacy_materials(ROOM)
	_claim_legacy_materials(ROOM)
	_expect(legacy.survival[a.id].bag.wood == 1 and legacy.survival[a.id].bag.tarp == 1 and legacy.materialLegacy.pending.wood == 0, "freeing space claims old materials once")
	_expect(_checkpoint(ROOM), "migration checkpoint persists")
	rooms.erase(ROOM)
	_load_room(ROOM)
	_expect(rooms[ROOM].data.survival[a.id].bag.wood == 1 and rooms[ROOM].data.materialLegacy.pending.tarp == 0, "restart cannot regrant legacy balances")
	legacy.erase("materialVersion")
	legacy.quest.repaired = true
	_restore_materials(legacy)
	_expect(legacy.materialLegacy.pending.wood == 0 and legacy.materialLegacy.pending.tarp == 0, "already repaired legacy roofs do not reissue consumed materials")
	legacy.erase("materialVersion")
	legacy.survival = {}
	legacy.homes = {a.id: {"x": 1.9, "z": -87.9}}
	legacy.quest.repaired = false
	_restore_materials(legacy)
	_expect(legacy.materialLegacy.eligible == [a.id], "earliest position-only saves still reserve migration for their stable existing player")
	scene.queue_free()
	print("COOP_RESOURCE_FIX " + JSON.stringify({"checks": checks, "failed": failed, "total": checks.size()}))
	quit(0 if failed == 0 else 1)
