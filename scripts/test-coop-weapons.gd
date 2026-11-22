extends "res://server.gd"

const ROOM := "camp-weapon-test"
const ALICE := "00000000000000000000000000000004"
const BOB := "00000000000000000000000000000005"
var failures := 0
var checks := 0
var packets := {}

func _initialize() -> void:
	_verify.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _send(ws: WebSocketPeer, msg: Dictionary) -> bool:
	var key := ws.get_instance_id()
	if not packets.has(key):
		packets[key] = {}
	packets[key][msg.t] = msg.duplicate(true)
	return true

func _join_as(key: int, token: String, code := ROOM) -> Dictionary:
	var con := {"ws": WebSocketPeer.new(), "room": "", "id": "", "rejected": false}
	connections[key] = con
	_join(con, {"room": code, "token": token})
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
	msg.t = "person"
	_message(con, msg)

func _attack(room: Dictionary, con: Dictionary, at: Vector3, time: float) -> void:
	var actor: Dictionary = room.actors[con.id]
	var eye := Vector3(actor.point.x, actor.y + PlayerMotion.WALK_EYE, actor.point.y)
	var direction := eye.direction_to(at)
	var yaw := atan2(-direction.x, -direction.z)
	room.data.elapsed = time
	_message(con, {"t": "motion", "x": 0.0, "z": 0.0, "yaw": yaw})
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

	_verify_animals(room, alice)
	_verify_headshots()

	var legacy := FileAccess.open(save_dir.path_join("weapon-legacy.json"), FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"version": 1, "elapsed": 69.0, "homes": {},
		"quest": {"wood": true, "tarp": false, "repaired": false}, "provisions": {}}))
	legacy.close()
	_expect(_load_room("weapon-legacy"), "The older room can load")
	var migrated: Dictionary = rooms["weapon-legacy"].data
	_expect(migrated.quest.wood and migrated.campWeaponsVersion == 1
		and migrated.provisions.has_all(["camp-weapon-katana", "camp-weapon-rifle", "camp-weapon-pistol"]),
		"Migration adds the three weapon pickups and preserves the previous quest")

	if failures == 0:
		print("COOP_WEAPONS_OK ", checks)
	quit(0 if failures == 0 else 1)

func _verify_animals(room: Dictionary, alice: Dictionary) -> void:
	var bob := _join_as(4, BOB)
	room.data.wildPeople.people.clear()
	var shooter := Vector2(0.0, -81.0)
	_give_position(room, alice, shooter)
	_person(alice, {"action": "equip", "item": "rifle"})
	room.crocodile.point = Vector2(0.0, -69.0)
	var crocodile := Stones.unpack(Wildlife.crocodile_pose(room.crocodile).at) + Vector3.UP * 0.22
	_attack(room, alice, crocodile, 18.0)
	_expect(room.data.storageWildlife.croc == 42.0 and room.crocodile.clip == "Hit",
		"Rifle damages the crocodile and plays its recoil")
	_attack(room, alice, crocodile, 18.5)
	_expect(room.data.storageWildlife.croc == 42.0, "A second shot inside the rifle cooldown does not damage wildlife")
	ship_grid = Spaceship.collision_grid({"obstacles": [{"x": 0.0, "z": -75.0, "r": 0.31, "type": "wall"}]})
	_attack(room, alice, crocodile, 19.2)
	_expect(room.data.storageWildlife.croc == 42.0, "A wall prevents a shot from damaging the crocodile")
	ship_grid = {}
	var writable_save_dir := save_dir
	save_dir = save_dir.path_join("missing-directory")
	_attack(room, alice, crocodile, 20.4)
	save_dir = writable_save_dir
	_expect(room.data.storageWildlife.croc == 42.0 and not room.data.storage.has("corpse-croc")
		and room.data.survival[alice.id].attackAt == 19.2, "Failed attack save restores wildlife health, corpse and cooldown")
	_attack(room, alice, crocodile, 20.5)
	_expect(not StorageWildlife.alive(room, "croc") and room.data.storage.get("corpse-croc", {}).get("bag", {}).get("crocodile_meat_raw") == 3,
		"A lethal rifle shot leaves one lootable crocodile corpse")
	var teammate: Dictionary = packets[bob.ws.get_instance_id()].snapshot
	_expect(teammate.crocodile == {"dead": true} and teammate.storage.has("corpse-croc"),
		"Another player sees the same crocodile death and corpse")

	_person(alice, {"action": "equip", "item": "pistol"})
	_give_position(room, alice, Vector2(-14.75, -61.5))
	for time: float in [25.0, 25.4]:
		var at: Vector3 = Wildlife.eagle(time).at + Vector3.UP * 0.24
		_attack(room, alice, at, time)
		_expect(room.data.storageWildlife.eagle == (12.0 if time == 25.0 else 0.0), "Pistol hits the moving eagle")
	_expect(room.data.storage.get("corpse-eagle", {}).has("fallFrom"), "A shot-down eagle starts its fall")

	_give_position(room, alice, shooter)
	var dog: Dictionary = room.data.dog
	dog.merge({"x": shooter.x, "z": shooter.y - 1.9, "yaw": 0.0, "clip": CampDog.IDLE}, true)
	var dog_at := Vector3(dog.x, LakeLayout.walk_height(CampDog.position(dog)) + 0.51, dog.z)
	_person(alice, {"action": "equip", "item": "katana"})
	_attack(room, alice, dog_at, 26.0)
	_expect(room.data.storageWildlife.dog == 28.0, "A close-range katana swing damages the mastiff")
	_throw_at_dog(room, alice, "camp-round")
	_expect(room.data.storageWildlife.dog == 12.0, "A thrown round stone deals blunt damage once")
	room.data.stones["camp-flat"].edge = 3
	_throw_at_dog(room, alice, "camp-flat")
	_expect(not StorageWildlife.alive(room, "dog") and room.data.storage.get("corpse-dog", {}).get("bag", {}).get("dog_meat") == 2,
		"A sharpened thrown stone can kill and yield the mastiff's loot")
	_publish(ROOM)
	teammate = packets[bob.ws.get_instance_id()].snapshot
	_expect(teammate.dog.is_empty() and not teammate.eagleAlive, "The remaining dead animals disappear for other players")
	_leave(4)
	_leave(3)
	_join_as(5, ALICE)
	var loaded: Dictionary = rooms[ROOM]
	_expect(loaded.data.storageWildlife == {"croc": 0.0, "eagle": 0.0, "dog": 0.0}
		and loaded.data.storage.has_all(["corpse-croc", "corpse-eagle", "corpse-dog"]),
		"Room reload keeps all three deaths and their shared corpses")

func _throw_at_dog(room: Dictionary, con: Dictionary, id: String) -> void:
	var stone: Dictionary = room.data.stones[id]
	_set_ground(stone, id, room.actors[con.id].point)
	_message(con, {"t": "stone", "action": "pick", "id": id})
	_message(con, {"t": "stone", "action": "throw", "yaw": 0.0, "pitch": -0.40})
	_expect(stone.mode == "air", "The regular pickup and throw messages launch the stone")
	const STEP := 1.0 / 60.0
	for frame in 30:
		room.data.elapsed += STEP
		_tick_stones(room, STEP, ROOM)
	_expect(stone.mode == "ground", "The stone stops at the animal")

func _verify_headshots() -> void:
	var alice := _join_as(6, ALICE, "headshot-test")
	var room: Dictionary = rooms[alice.room]
	var personal: Dictionary = room.data.survival[alice.id]
	personal.bag = {"katana": 1, "pistol": 1}
	var npc := WildPeople.make_person("shielded-target", 5, "female", Vector2(0.0, -82.9), 0.0)
	room.data.wildPeople.people[npc.id] = npc
	_give_position(room, alice, Vector2(0, -81))
	_person(alice, {"action": "equip", "item": "katana"})
	_attack(room, alice, Vector3(npc.x, 1.66, npc.z), 32.0)
	_expect(npc.health < npc.maxHealth and npc.health > 0.0, "A blade at head height deals ordinary damage")
	npc.health = npc.maxHealth
	_person(alice, {"action": "equip", "item": "pistol"})
	_attack(room, alice, Vector3(npc.x, 1.14, npc.z), 32.5)
	_expect(is_equal_approx(npc.maxHealth - npc.health, Weapons.stats("pistol").damage * 0.68),
		"The same gun hitting the body uses pistol damage with the usual defense")
	_attack(room, alice, Vector3(npc.x + 0.14, 0.40, npc.z), 33.0)
	_expect(npc.health > 0.0 and npc.legR > 0.0 and npc.legL == 0.0,
		"A bullet into the right leg applies damage and the existing leg injury")
	npc.health = npc.maxHealth
	_attack(room, alice, Vector3(npc.x, 1.68, npc.z), 33.5)
	_expect(npc.phase == "dead" and npc.health == 0.0 and npc.loot == {"spear": 1, "shield": 1},
		"One pistol headshot kills a full-health shielded raider and drops equipment once")

	room.crocodile.point = Vector2(0.0, -66.0)
	room.crocodile.yaw = 0.0
	_give_position(room, alice, Vector2(-5.0, -66.94))
	var croc_origin := Stones.unpack(Wildlife.crocodile_pose(room.crocodile).at)
	_attack(room, alice, croc_origin + Vector3(0.0, 0.27, -0.94), 34.0)
	_expect(not StorageWildlife.alive(room, "croc") and room.data.storage.has("corpse-croc"),
		"A pistol shot at the crocodile's head kills a full-health animal")

	room.data.dog.merge({"x": 1.0, "z": -77.0, "yaw": 0.0, "clip": CampDog.REST}, true)
	_give_position(room, alice, Vector2(-3.0, -77.39))
	_attack(room, alice, Vector3(1.0, 0.43, -77.39), 34.5)
	_expect(room.data.storageWildlife.dog == 64.0, "The parked ship blocks a shot lined up with the mastiff's head")
	room.data.dog.z = -75.0
	_give_position(room, alice, Vector2(-3.0, -75.39))
	_attack(room, alice, Vector3(1.0, 0.43, -75.39), 35.0)
	_expect(not StorageWildlife.alive(room, "dog") and room.data.storage.has("corpse-dog"),
		"The mastiff's settled head is hittable at its own height")

	const TIME := 70.0
	var bird := Wildlife.eagle(TIME)
	var facing := Basis(Vector3.UP, float(bird.yaw))
	var eagle_head: Vector3 = bird.at + facing * (Vector3(0.0, 0.62, -0.22) - StorageWildlife.EAGLE_PERCH_OFFSET * float(bird.contact))
	_give_position(room, alice, Vector2(-11.65, eagle_head.z))
	_attack(room, alice, eagle_head, TIME)
	_expect(not StorageWildlife.alive(room, "eagle") and room.data.storage.get("corpse-eagle", {}).has("fallFrom"),
		"The perched eagle dies to one pistol headshot and takes its usual fall")
