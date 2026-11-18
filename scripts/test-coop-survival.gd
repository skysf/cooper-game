extends "res://server.gd"

# Run against the co-op project with --headless --script and a disposable save directory after --.
const ROOM := "survival-fixture"
const ALICE_TOKEN := "00000000000000000000000000000001"
const BOB_TOKEN := "00000000000000000000000000000002"
const REACHABLE := Vector2(2.54, -87.95)

var received := {}
var failures := 0

func _initialize() -> void:
	_verify.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _send(ws: WebSocketPeer, msg: Dictionary) -> void:
	var peer: int = ws.get_instance_id()
	if not received.has(peer):
		received[peer] = {}
	received[peer][msg.t] = msg.duplicate(true)

func _verify() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("Pass one writable temporary directory for the room fixture")
		quit(2)
		return
	save_dir = args[0]
	var fixture_path := save_dir.path_join(ROOM + ".json")
	if FileAccess.file_exists(fixture_path):
		push_error("Use an empty directory for the room fixture")
		quit(2)
		return
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	var legacy := FileAccess.open(fixture_path, FileAccess.WRITE)
	if legacy == null:
		push_error("Could not write legacy room fixture")
		quit(2)
		return
	legacy.store_string(JSON.stringify({"version": 1, "elapsed": 69.0, "homes": {}, "quest": {"wood": true, "tarp": false, "repaired": false}}))
	legacy.close()

	var alice := _connect(1, ALICE_TOKEN)
	var bob := _connect(2, BOB_TOKEN)
	var room: Dictionary = rooms[ROOM]
	var alice_id: String = alice.id
	var bob_id: String = bob.id
	_expect(room.data.quest.wood and room.data.provisions.size() == 4, "legacy saves preserve quest state and seed table once")
	room.actors[alice_id].point = REACHABLE
	room.actors[bob_id].point = REACHABLE
	_action(alice, "take", "", "apple-1")
	_action(bob, "take", "", "apple-1")
	_expect(_snapshot(alice).survival.bag.apple == 1 and _snapshot(bob).survival.bag.apple == 0, "two players cannot take the same food")
	_expect(_snapshot(alice).provisions == _snapshot(bob).provisions and not _snapshot(bob).players[alice_id].has("survival"), "table is shared and inventory is private")
	_expect(not _last_notice(bob).ok, "second claimant is rejected")

	_action(alice, "put", "apple")
	_expect(room.data.provisions.size() == 4 and room.data.survival[alice_id].bag.apple == 0, "food can be put back")
	var restored_apple := _find_food(room, "apple", "table", ["apple-2"])
	_action(bob, "take", "", restored_apple)
	_expect(room.data.survival[bob_id].bag.apple == 1, "one player's returned food can be taken by another")

	_action(alice, "take", "", "bread-1")
	room.data.survival[alice_id].hunger = 44.0
	_action(alice, "eat", "bread")
	_expect(room.data.survival[alice_id].hunger == 75.0 and room.data.survival[alice_id].bag.bread == 0, "eating carried bread consumes one and boosts hunger")
	_action(alice, "take", "", "bread-2")
	_action(alice, "drop", "bread")
	var dropped_bread := _find_food(room, "bread", "ground")
	room.data.survival[bob_id].hunger = 25.0
	_action(bob, "eat_table", "", dropped_bread)
	_expect(not room.data.provisions.has(dropped_bread) and room.data.survival[bob_id].hunger == 56.0, "dropped food can be eaten directly")

	room.actors[bob_id].point = Vector2(1.9, -84.0)
	room.data.survival[bob_id].water = 61.0
	_action(bob, "drink")
	_expect(room.data.survival[bob_id].water == 61.0 and not _last_notice(bob).ok, "cannot drink from the jug at a distance")
	room.actors[bob_id].point = REACHABLE
	_action(bob, "drink")
	_expect(room.data.survival[bob_id].water == 93.0, "nearby jug restores water")

	var writable := save_dir
	save_dir = fixture_path
	_action(alice, "take", "", "apple-2")
	_expect(room.data.provisions.has("apple-2") and room.data.survival[alice_id].bag.apple == 0 and not _last_notice(alice).ok, "failed checkpoint rolls back both table and bag")
	save_dir = writable
	_action(alice, "take", "", "apple-2")
	_expect(room.data.provisions.is_empty() and room.data.survival[alice_id].bag.apple == 1, "the same action can retry successfully")
	_action(bob, "eat", "apple")
	_expect(room.data.survival[bob_id].hunger == 75.0 and room.data.survival[bob_id].water == 100.0, "apple nutrition and saturation")

	_expect(Survival.used_slots({"apple": 16, "bread": 0}) == 6, "six bag slots allow a partial final stack")
	_expect(Survival.can_carry({"apple": 16, "bread": 0}, "apple") and not Survival.can_carry({"apple": 16, "bread": 0}, "bread"), "full bags can only add to a matching stack")
	_expect(not Survival.can_carry({"apple": 15, "bread": 3}, "apple"), "full stacks enforce bag capacity")
	var inside := Survival.initial_state()
	var outside := Survival.initial_state()
	Survival.tick(inside, REACHABLE, true, 1.0, 60.0)
	Survival.tick(outside, Vector2.ZERO, true, 1.0, 60.0)
	_expect(inside.mood > 65.0 and outside.mood < 65.0 and inside.hunger < 86.0 and inside.water < 82.0, "per-player weather comfort and gradual stat decay")

	_leave(1)
	_leave(2)
	_expect(not rooms.has(ROOM), "empty room can unload after successful checkpoint")
	alice = _connect(3, ALICE_TOKEN)
	_expect(_snapshot(alice).provisions.is_empty() and _snapshot(alice).survival.bag.apple == 1, "restart restores bag and depleted table")
	bob = _connect(4, BOB_TOKEN)
	_expect(_snapshot(bob).survival.bag.apple == 0 and _snapshot(bob).survival.water == 100.0, "another player's stats and inventory restore independently")
	if failures == 0:
		print("COOP_SURVIVAL_OK: legacy saves, contention, private bags, pickup, eating, drinking, drop, put, mood, rollback, restart")
	quit(0 if failures == 0 else 1)

func _connect(key: int, token: String) -> Dictionary:
	var con := {"ws": WebSocketPeer.new(), "room": "", "id": "", "rejected": false}
	connections[key] = con
	_message(con, {"t": "join", "room": ROOM, "token": token})
	return con

func _action(con: Dictionary, action: String, item: String = "", id: String = "") -> void:
	_message(con, {"t": "provision", "action": action, "item": item, "id": id})

func _snapshot(con: Dictionary) -> Dictionary:
	return received[con.ws.get_instance_id()].snapshot

func _last_notice(con: Dictionary) -> Dictionary:
	return received[con.ws.get_instance_id()].notice

func _find_food(room: Dictionary, item: String, surface: String, skip: Array = []) -> String:
	for id: String in room.data.provisions:
		var record: Dictionary = room.data.provisions[id]
		if record.item == item and record.surface == surface and id not in skip:
			return id
	return ""

func _expect(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		push_error(description)
