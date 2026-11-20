extends "res://server.gd"
const ROOM := "single-stack"
const TOKEN_A := "000000000000000000000000000000a1"
const TOKEN_B := "000000000000000000000000000000b2"
const TABLE_NEAR := Vector2(2.54, -87.95)
var received := {}
var checks := []
var registry := []
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
func _provision(con: Dictionary, action: String, item := "", id := "") -> void:
	_provision_action(con, {"action": action, "item": item, "id": id})
func _person(con: Dictionary, action: String, item := "", id := "") -> void:
	con.person_next_ms = 0
	_wild_action(con, {"action": action, "item": item, "id": id})
func _find(room: Dictionary, item: String, surface: String) -> String:
	for id: String in room.data.provisions:
		var record: Dictionary = room.data.provisions[id]
		if record.item == item and record.surface == surface:
			return id
	return ""
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	save_dir = args[0]
	DirAccess.make_dir_recursive_absolute(save_dir)
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	var registry_ok := true
	for item: String in Survival.ITEM_NAMES:
		var item_ok := true
		for quantity: int in [4, 7, 10, Survival.MAX_ITEM_COUNT - 1, Survival.MAX_ITEM_COUNT]:
			var bag := {item: quantity}
			var loaded := Survival.state_from_save(JSON.parse_string(JSON.stringify({"bag": bag})))
			var entries := Survival.inventory_entries(loaded.bag)
			item_ok = item_ok and loaded.bag.get(item) == quantity and entries.size() == 1 and entries[0].item == item and entries[0].quantity == quantity and Survival.stack_slots(item, quantity) == 1 and Survival.used_slots(loaded.bag) == 1
		registry.append({"item": item, "quantities": [4, 7, 10, Survival.MAX_ITEM_COUNT - 1, Survival.MAX_ITEM_COUNT], "ok": item_ok})
		registry_ok = registry_ok and item_ok
	_expect(registry_ok, "every registered item keeps all quantities in one slot through JSON reload, including the count boundary")
	var invalid := Survival.state_from_save({"bag": {"apple": -4, "bread": INF, "herb": NAN, "club": Survival.MAX_ITEM_COUNT + 1, "unknown": 10}})
	_expect(invalid.bag.apple == 0 and invalid.bag.bread == 0 and invalid.bag.get("herb", 0) == 0 and invalid.bag.club == Survival.MAX_ITEM_COUNT and not invalid.bag.has("unknown"), "negative/nonfinite/unknown counts are rejected and oversized saves stay bounded")
	_expect(not Survival.can_carry({"apple": Survival.MAX_ITEM_COUNT}, "apple") and not Survival.can_carry({"apple": -1}, "apple") and not Survival.can_carry({"apple": 1.5}, "apple") and not Survival.can_carry({}, "unknown"), "overflow, invalid live counts and unknown additions are refused")
	var six := {"apple": 7, "herb": 7, "cap": 7, "club": 7, "shield": 7, "stone": 7}
	_expect(Survival.used_slots(six) == 6 and Survival.can_carry(six, "apple") and not Survival.can_carry(six, "bread"), "six different kinds fill the base bag while existing kinds still merge")
	var twelve := {}
	for item: String in Survival.ITEM_NAMES:
		if twelve.size() < 12:
			twelve[item] = 10
	_expect(Survival.used_slots(twelve) == 12 and Survival.can_carry(twelve, "apple", 12) and not Survival.can_carry(twelve, "tarp", 12) and Survival.state_from_save({"bag": twelve}, 12).bag == twelve, "expanded capacity is twelve kinds, with all their saved quantities intact")
	var a := _connect(1, TOKEN_A)
	var b := _connect(2, TOKEN_B)
	var room: Dictionary = rooms[ROOM]
	room.actors[a.id].point = TABLE_NEAR
	room.actors[b.id].point = TABLE_NEAR
	room.data.survival[a.id].bag = six.duplicate()
	room.data.survival[b.id].bag = {"cap": 4}
	_provision(a, "take", "", "apple-1")
	_provision(b, "take", "", "apple-1")
	_expect(room.data.survival[a.id].bag.apple == 8 and not room.data.provisions.has("apple-1") and room.data.survival[b.id].bag.get("apple", 0) == 0, "same-kind pickup succeeds in a full bag and cannot be claimed twice")
	_provision(a, "take", "", "bread-1")
	_expect(room.data.provisions.has("bread-1") and not room.data.survival[a.id].bag.has("bread"), "a new kind cannot enter a full bag or disappear from the table")
	room.data.survival[a.id].hunger = 40.0
	_provision(a, "eat", "apple")
	_expect(room.data.survival[a.id].bag.apple == 7 and room.data.survival[a.id].hunger == 59.0, "eat consumes one apple from the unified stack")
	_provision(a, "put", "apple")
	var id := _find(room, "apple", "table")
	_provision(a, "take", "", id)
	_expect(room.data.survival[a.id].bag.apple == 7 and Survival.used_slots(room.data.survival[a.id].bag) == 6, "put-one and pickup return the apple to its original stack")
	_provision(a, "drop", "apple")
	id = _find(room, "apple", "ground")
	_provision(a, "take", "", id)
	_expect(room.data.survival[a.id].bag.apple == 7 and not room.data.provisions.has(id), "drop-one and pickup preserve quantities and one slot")
	_provision(a, "remove_worn", "cap")
	_expect(room.data.survival[a.id].bag.cap == 8 and not room.data.survival[a.id].worn.cap, "removing worn clothing merges into its existing kind in a full bag")
	_provision(a, "wear", "cap")
	_expect(room.data.survival[a.id].bag.cap == 7 and room.data.survival[a.id].worn.cap, "wearing consumes one piece rather than the entire clothing stack")
	_provision(a, "drop", "cap")
	id = _find(room, "cap", "ground")
	_provision(b, "take", "", id)
	_expect(room.data.survival[a.id].bag.cap == 6 and room.data.survival[b.id].bag.cap == 5, "a dropped garment transfers one copy and merges with the recipient stack")
	var npc := WildPeople.make_person("helper", 0, "female", TABLE_NEAR + Vector2(.2, 0), room.data.elapsed)
	npc.phase = "companion"
	npc.weapon = ""
	npc.shield = false
	npc.hunger = 35
	npc.health = 50
	npc.legL = 30
	room.data.wildPeople.people.helper = npc
	_person(a, "equip", "club")
	_person(a, "shield")
	_expect(room.data.survival[a.id].weapon == "club" and room.data.survival[a.id].shield and room.data.survival[a.id].bag.club == 7 and room.data.survival[a.id].bag.shield == 7, "equipping selects a carried copy without consuming the weapon or shield stack")
	_person(a, "give_equipment", "club", "helper")
	_expect(npc.weapon == "club" and room.data.survival[a.id].bag.club == 6, "giving companion equipment transfers exactly one copy")
	_person(a, "take_equipment", "", "helper")
	_expect(npc.weapon == "" and room.data.survival[a.id].bag.club == 7 and Survival.used_slots(room.data.survival[a.id].bag) == 6, "taking companion equipment merges back even when all kind slots are full")
	_person(a, "treat", "", "helper")
	_expect(room.data.survival[a.id].bag.herb == 6 and WildPeople.relation(npc, a.id).treatments == 1, "treating consumes one herb package from the unified stack")
	room.actors[a.id].point = Vector2(WildPeople.SOURCES.herbs.x, WildPeople.SOURCES.herbs.z)
	var stock: int = room.data.wildPeople.resources.herbs.stock
	_person(a, "gather", "herbs")
	_expect(room.data.survival[a.id].bag.herb == 7 and room.data.wildPeople.resources.herbs.stock == stock - 1, "real herb source consumes one stock and merges into the same full-bag slot")
	room.actors[a.id].point = TABLE_NEAR
	_person(a, "feed", "apple", "helper")
	_expect(room.data.survival[a.id].bag.apple == 6 and npc.hunger > 35, "feeding a companion consumes one apple rather than its entire stack")
	var before_state: Dictionary = room.data.survival[a.id].duplicate(true)
	var before_provisions: Dictionary = room.data.provisions.duplicate(true)
	var writable := save_dir
	save_dir = save_dir.path_join(ROOM + ".json")
	_provision(a, "drop", "club")
	_expect(room.data.survival[a.id] == before_state and room.data.provisions == before_provisions, "failed checkpoint restores the stack and physical item together")
	save_dir = writable
	room.data.provisions["boundary-apple"] = Survival.provision("apple", Survival.free_table_slot(room.data.provisions), "table")
	room.data.survival[a.id].bag.apple = Survival.MAX_ITEM_COUNT
	_provision(a, "take", "", "boundary-apple")
	_expect(room.data.provisions.has("boundary-apple") and room.data.survival[a.id].bag.apple == Survival.MAX_ITEM_COUNT, "a pickup at count maximum does not overflow or consume the world item")
	_provision(a, "eat", "apple")
	_provision(a, "take", "", "boundary-apple")
	_expect(room.data.survival[a.id].bag.apple == Survival.MAX_ITEM_COUNT and not room.data.provisions.has("boundary-apple"), "consuming then picking up at the boundary conserves one unit")
	_expect(_checkpoint(ROOM), "unified stacks checkpoint")
	var before_a: Dictionary = room.data.survival[a.id].bag.duplicate()
	rooms.erase(ROOM)
	_load_room(ROOM)
	_expect(Survival.inventory_entries(rooms[ROOM].data.survival[a.id].bag) == Survival.inventory_entries(before_a) and rooms[ROOM].data.survival[b.id].bag.cap == 5, "full room restart preserves merged counts, ownership and equipment")
	print("COOP_INVENTORY_STACK " + JSON.stringify({"registry": registry, "checks": checks, "total": checks.size(), "failed": failed}))
	quit(0 if failed == 0 else 1)
