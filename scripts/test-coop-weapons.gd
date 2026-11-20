extends "res://server.gd"

const ROOM := "camp-weapon-test"
const ALICE := "00000000000000000000000000000004"
const BOB := "00000000000000000000000000000005"
var failures := 0
var checks := 0

func _initialize() -> void:
	_verify.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _send(_ws: WebSocketPeer, _msg: Dictionary) -> bool:
	return true

func _join_as(key: int, token: String) -> Dictionary:
	var con := {"ws": WebSocketPeer.new(), "room": "", "id": "", "rejected": false}
	connections[key] = con
	_join(con, {"room": ROOM, "token": token})
	return con

func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _give_position(room: Dictionary, con: Dictionary, point: Vector2) -> void:
	var actor: Dictionary = room.actors[con.id]
	actor.point = point
	actor.y = LakeLayout.walk_height(point)

func _person(con: Dictionary, msg: Dictionary) -> void:
	con.person_next_ms = 0
	_wild_action(con, msg)

func _attack(room: Dictionary, con: Dictionary, at: Vector3, time: float) -> void:
	var actor: Dictionary = room.actors[con.id]
	var eye := Vector3(actor.point.x, actor.y + PlayerMotion.WALK_EYE, actor.point.y)
	var direction := eye.direction_to(at)
	var yaw := atan2(-direction.x, -direction.z)
	actor.yaw = yaw
	room.data.elapsed = time
	_person(con, {"action": "attack", "yaw": yaw, "pitch": asin(direction.y)})

func _verify() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		quit(2)
		return
	save_dir = args[0]
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	var alice := _join_as(1, ALICE)
	var bob := _join_as(2, BOB)
	var room: Dictionary = rooms[ROOM]
	for item: String in Weapons.CAMP_START:
		var record: Dictionary = room.data.provisions.get("camp-weapon-" + item, {})
		var at: Vector2 = Survival.horizontal(record.at)
		_expect(record.item == item and record.surface == "ground" and Rules.free_at(at, grid)
			and at.distance_to(Rules.pair(world.spawn)) < 1.7, "Each starter weapon is reachable on the cabin approach")

	_give_position(room, alice, Vector2(0, -109))
	_provision_action(alice, {"action": "take", "id": "camp-weapon-rifle"})
	_expect(room.data.provisions.has("camp-weapon-rifle"), "Distant pickup is rejected")
	_give_position(room, alice, Weapons.CAMP_START.rifle)
	_give_position(room, bob, Weapons.CAMP_START.rifle)
	_provision_action(bob, {"action": "take", "id": "camp-weapon-rifle"})
	_provision_action(alice, {"action": "take", "id": "camp-weapon-rifle"})
	_expect(room.data.survival[bob.id].bag.rifle == 1 and not room.data.survival[alice.id].bag.has("rifle")
		and not room.data.provisions.has("camp-weapon-rifle"), "Either player can claim the only copy")
	_person(alice, {"action": "equip", "item": "rifle"})
	_expect(room.data.survival[alice.id].weapon == "", "A player must own a weapon to equip it")
	_person(bob, {"action": "equip", "item": "rifle"})
	_expect(room.data.survival[bob.id].weapon == "rifle", "Owned rifle equips")
	_provision_action(bob, {"action": "drop", "item": "rifle"})
	_expect(room.data.survival[bob.id].weapon == "" and room.data.survival[bob.id].bag.rifle == 0,
		"Dropping the last copy clears the equipped weapon")
	for id: String in room.data.provisions.keys():
		if room.data.provisions[id].item == "rifle":
			_provision_action(alice, {"action": "take", "id": id})
	_expect(room.data.survival[alice.id].bag.rifle == 1, "Another player can take the dropped weapon")
	_give_position(room, alice, Weapons.CAMP_START.katana)
	_provision_action(alice, {"action": "take", "id": "camp-weapon-katana"})
	_person(alice, {"action": "equip", "item": "katana"})
	_leave(2)
	_leave(1)
	alice = _join_as(3, ALICE)
	room = rooms[ROOM]
	_expect(room.data.survival[alice.id].weapon == "katana"
		and not room.data.provisions.has("camp-weapon-katana") and not room.data.provisions.has("camp-weapon-rifle")
		and room.data.provisions.has("camp-weapon-pistol"), "Reload remembers which starter weapons were taken and equipped")

	var shooter := Vector2(0.0, -81.0)
	_give_position(room, alice, shooter)
	var npc := WildPeople.make_person("test-target", 0, "female", shooter + Vector2(0, -1.9), 0.0)
	room.data.wildPeople.people[npc.id] = npc
	var at := Vector3(npc.x, 1.14, npc.z)
	_attack(room, alice, at, 10.0)
	_expect(is_equal_approx(npc.maxHealth - npc.health, 36.0), "Katana lands stronger than the 27 point spear")
	var health: float = npc.health
	_attack(room, alice, at, 10.14)
	_expect(npc.health == health, "Katana server cooldown prevents duplicate attacks")
	_attack(room, alice, at, 10.33)
	_expect(is_equal_approx(health - npc.health, 36.0), "A second katana attack lands after 0.32 seconds")

	npc.z = -69.0
	npc.health = npc.maxHealth
	_person(alice, {"action": "equip", "item": "rifle"})
	at.z = npc.z
	ship_grid = {}
	_attack(room, alice, at, 12.0)
	_expect(is_equal_approx(npc.maxHealth - npc.health, 58.0), "Rifle hits the center-sight target beyond melee range")
	npc.health = npc.maxHealth
	ship_grid = Spaceship.collision_grid({"obstacles": [{"x": 0.0, "z": -75.0, "r": 0.31, "type": "wall"}]})
	_attack(room, alice, at, 13.2)
	_expect(npc.health == npc.maxHealth, "The server stops the same shot at a wall")
	ship_grid = {}
	_attack(room, alice, at + Vector3.RIGHT * 1.5, 14.4)
	_expect(npc.health == npc.maxHealth, "A shot aimed beside the target misses")
	var ship: Dictionary = room.ship.duplicate()
	room.ship.merge({"x": 0.0, "y": 0.15, "z": -75.0, "yaw": 0.0}, true)
	_attack(room, alice, at, 15.6)
	_expect(npc.health == npc.maxHealth, "The parked ship also blocks the shot")
	room.ship = ship
	_give_position(room, alice, Weapons.CAMP_START.pistol)
	_provision_action(alice, {"action": "take", "id": "camp-weapon-pistol"})
	_person(alice, {"action": "equip", "item": "pistol"})
	_give_position(room, alice, shooter)
	_attack(room, alice, at, 17.0)
	_expect(is_equal_approx(npc.maxHealth - npc.health, 30.0), "Pistol reaches beyond melee and applies its own damage")

	var legacy := FileAccess.open(save_dir.path_join("weapon-legacy.json"), FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"version": 1, "elapsed": 69.0, "homes": {},
		"quest": {"wood": true, "tarp": false, "repaired": false}, "provisions": {}}))
	legacy.close()
	_expect(_load_room("weapon-legacy"), "The older room can load")
	var migrated: Dictionary = rooms["weapon-legacy"].data
	_expect(migrated.quest.wood and migrated.provisions.size() == 3 and migrated.campWeaponsVersion == 1,
		"Migration adds the three weapon pickups and preserves previous quest and table state")

	if failures == 0:
		print("COOP_WEAPONS_OK ", checks)
	quit(0 if failures == 0 else 1)
