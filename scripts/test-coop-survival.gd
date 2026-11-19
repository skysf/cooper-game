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

func _send(ws: WebSocketPeer, msg: Dictionary) -> bool:
	var peer: int = ws.get_instance_id()
	if not received.has(peer):
		received[peer] = {}
	received[peer][msg.t] = msg.duplicate(true)
	return true

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
	_expect(_snapshot(alice).survival.worn == Survival.initial_wear(), "legacy players start with all three clothes equipped")
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

	_expect(_snapshot(alice).backpackOwner.is_empty(), "an old room starts with its single backpack on the floor")
	room.actors[alice_id].point = Vector2(1.9, -84.0)
	_action(alice, "take_backpack")
	_expect(not _last_notice(alice).ok and room.data.backpackOwner.is_empty(), "the backpack cannot be taken from a distance")
	room.actors[alice_id].point = Survival.BACKPACK + Vector2(0.35, 0.0)
	room.actors[bob_id].point = room.actors[alice_id].point
	save_dir = fixture_path
	_action(alice, "take_backpack")
	_expect(not _last_notice(alice).ok and room.data.backpackOwner.is_empty(), "a failed save frees the backpack for the next try")
	save_dir = writable
	_action(alice, "take_backpack")
	_expect(_last_notice(alice).ok and _snapshot(alice).backpackOwner == alice_id and _snapshot(bob).backpackOwner == alice_id, "one pickup equips the owner and updates both players")
	_action(bob, "take_backpack")
	_expect(not _last_notice(bob).ok, "another player cannot take an equipped backpack")
	room.data.survival[alice_id].bag.apple = 18
	room.data.survival[bob_id].bag.apple = 18
	var by_pack := Survival.BACKPACK
	room.data.provisions["extra-apple"] = Survival.provision("apple", Vector3(by_pack.x, 0.04, by_pack.y), "ground")
	_action(bob, "take", "", "extra-apple")
	_expect(not _last_notice(bob).ok and room.data.provisions.has("extra-apple"), "a teammate without the backpack still has six slots")
	_action(alice, "take", "", "extra-apple")
	_expect(_last_notice(alice).ok and room.data.survival[alice_id].bag.apple == 19, "the equipped player can fill the extra space")
	room.data.survival[bob_id].bag.apple = 0

	var dock := Vector2(-10.45, -49.1)
	room.actors[alice_id].point = dock
	room.actors[bob_id].point = dock
	_action(alice, "remove_worn", "cap")
	_expect(_last_notice(alice).ok and not _snapshot(bob).players[alice_id].worn.cap and room.data.survival[alice_id].bag.cap == 1, "removing the cap consumes one inventory slot and is visible to the other player")
	_action(alice, "wear", "cap")
	_expect(_snapshot(bob).players[alice_id].worn.cap and room.data.survival[alice_id].bag.cap == 0, "wearing the cap consumes the carried item")
	_action(alice, "drop_worn", "pants")
	var dropped_pants := _find_food(room, "pants", "ground")
	_expect(_last_notice(alice).ok and not dropped_pants.is_empty() and not _snapshot(alice).survival.worn.pants, "equipped trousers can be dropped at the dock")
	_action(bob, "take", "", dropped_pants)
	_expect(_last_notice(bob).ok and room.data.survival[bob_id].bag.pants == 1 and not room.data.provisions.has(dropped_pants), "the other player can pick up dropped clothing")
	_action(bob, "eat", "pants")
	_expect(not _last_notice(bob).ok and room.data.survival[bob_id].bag.pants == 1, "clothes cannot be eaten")
	_action(bob, "drop", "pants")
	_expect(_last_notice(bob).ok and room.data.survival[bob_id].bag.pants == 0 and not _find_food(room, "pants", "ground").is_empty(), "clothing in the bag can also be dropped outside the cabin")

	_verify_wildlife(room, alice, bob)
	var waiting_spot := _verify_dog(room, alice, bob, fixture_path)
	_verify_player_travel()
	_verify_flight_surfaces()
	_verify_flight_thrust()
	var floating_site := _verify_spaceship(room, alice, bob)
	_leave(1)
	_expect(_snapshot(bob).ship.landed and _snapshot(bob).ship.onWater and _snapshot(bob).ship.pilot.is_empty(),
		"a disconnect in flight clears the pilot and restores the ship to the last water landing")
	_leave(2)
	_expect(not rooms.has(ROOM), "empty room can unload after successful checkpoint")
	alice = _connect(3, ALICE_TOKEN)
	_expect(_snapshot(alice).provisions.size() == 1 and not _snapshot(alice).survival.worn.pants and _snapshot(alice).survival.bag.apple == 19 and _snapshot(alice).backpackOwner == alice_id, "restart restores dropped and equipped clothing, the backpack and extra food")
	_expect(is_equal_approx(float(_snapshot(alice).survival.health), 82.0), "the bite's health loss survives a room restart")
	var saved_dog: Dictionary = _snapshot(alice).dog
	_expect(saved_dog.owner == alice_id and saved_dog.mode == "stay" and saved_dog.clip == CampDog.REST and CampDog.position(saved_dog).is_equal_approx(waiting_spot), "the adopted dog returns to its waiting spot and rest pose after restart")
	var stored_ship: Dictionary = _snapshot(alice).ship
	_expect(stored_ship.landed and stored_ship.onWater and Spaceship.point(stored_ship).is_equal_approx(floating_site)
		and _snapshot(alice).players[alice.id].swimming, "the ship and swimmer recover safely after a room restart")
	bob = _connect(4, BOB_TOKEN)
	_expect(_snapshot(bob).survival.bag.apple == 0 and _snapshot(bob).survival.water == 100.0, "another player's stats and inventory restore independently")
	if failures == 0:
		print("COOP_SURVIVAL_OK: provisions, equipment, wildlife, jump, swim, VTOL, water parking and restart")
	quit(0 if failures == 0 else 1)

func _connect(key: int, token: String) -> Dictionary:
	var con := {"ws": WebSocketPeer.new(), "room": "", "id": "", "rejected": false}
	connections[key] = con
	_message(con, {"t": "join", "room": ROOM, "token": token})
	return con

func _verify_player_travel() -> void:
	var rock_grid := Rules.collision_grid([{"type": "rock", "x": 0.0, "z": 2.0, "r": 0.20}])
	var walker := PlayerMotion.spawn(Vector2(-1.0, 2.0))
	for i in 40:
		PlayerMotion.step(walker, Vector2.RIGHT, 0.0, 1.0 / 60.0, rock_grid, {})
	_expect(walker.point.x > 0.9 and is_zero_approx(walker.y), "small rocks do not stop a walking player")
	var jump_top := 0.0
	for i in 90:
		PlayerMotion.step(walker, Vector2.ZERO, 1.0, 1.0 / 60.0, rock_grid, {})
		jump_top = maxf(jump_top, walker.y)
	_expect(jump_top > 0.65 and is_zero_approx(walker.y), "Space jumps once and lands even when held")
	var swimmer := PlayerMotion.spawn(Vector2(-26.0, -29.0))
	for i in 210:
		PlayerMotion.step(swimmer, Vector2.UP, 0.0, 1.0 / 60.0, {}, {})
	_expect(swimmer.swimming and swimmer.y + PlayerMotion.SWIM_EYE > LakeLayout.water_y(),
		"walking into the lake starts swimming at the surface")
	for i in 90:
		PlayerMotion.step(swimmer, Vector2.ZERO, -1.0, 1.0 / 60.0, {}, {})
	_expect(swimmer.y + PlayerMotion.SWIM_EYE < LakeLayout.water_y() - 0.25
		and swimmer.y > LakeLayout.ground_height(swimmer.point), "diving stops above the lakebed")
	for i in 100:
		PlayerMotion.step(swimmer, Vector2.ZERO, 1.0, 1.0 / 60.0, {}, {})
	_expect(is_equal_approx(swimmer.y, LakeLayout.water_y() - PlayerMotion.FLOAT_DEPTH), "Space returns the swimmer to the surface")
	for i in 240:
		PlayerMotion.step(swimmer, Vector2.DOWN, 0.0, 1.0 / 60.0, {}, {})
	_expect(not swimmer.swimming and swimmer.point.y > -32.0, "the swimmer can walk out onto the shore")

func _verify_spaceship(room: Dictionary, alice: Dictionary, bob: Dictionary) -> Vector2:
	var ship: Dictionary = room.ship
	var actor: Dictionary = room.actors[alice.id]
	_expect(Spaceship.can_park(Spaceship.PAD, ship_grid) and ship.landed and Spaceship.point(ship) == Spaceship.PAD,
		"legacy rooms place the ship in a clear area")
	actor.point = Spaceship.PAD + Vector2(2.95, 0)
	room.actors[bob.id].point = actor.point
	_message(alice, {"t": "ship", "action": "board"})
	_message(bob, {"t": "ship", "action": "board"})
	_expect(ship.pilot == alice.id and _snapshot(bob).ship.pilot == alice.id and not _last_notice(bob).ok,
		"only the first player gets the shared pilot seat")
	_pilot_motion(room, alice, Vector2.ZERO, 1, 400)
	_expect(not ship.landed and ship.y >= 28.0 and Spaceship.point(ship) == Spaceship.PAD, "the ship takes off vertically")
	_message(alice, {"t": "ship", "action": "exit"})
	_expect(not _last_notice(alice).ok and ship.pilot == alice.id, "the pilot cannot step out into midair")
	_pilot_motion(room, alice, Vector2.UP, 0, 44)
	_pilot_motion(room, alice, Vector2.ZERO, 0, 90)
	_expect(Spaceship.point(ship).distance_to(Spaceship.PAD) > 2.5 and ship.canLand, "the ship flies, brakes and hovers over a second clearing")
	_pilot_motion(room, alice, Vector2.ZERO, -1, 730)
	_expect(ship.landed and not ship.onWater and room.data.ship.z != Spaceship.PAD.y, "vertical landing records a new parking location")
	_message(alice, {"t": "ship", "action": "exit"})
	_expect(ship.pilot.is_empty() and not actor.swimming and Rules.free_at(actor.point, grid), "landed pilot exits next to the hull")
	_message(alice, {"t": "ship", "action": "board"})
	_pilot_motion(room, alice, Vector2.ZERO, 1, 430)
	var to_lake := LakeLayout.center() - Spaceship.point(ship)
	_pilot_motion(room, alice, to_lake.normalized(), 0, roundi(to_lake.length() * 60.0 / 11.0))
	_pilot_motion(room, alice, Vector2.ZERO, 0, 100)
	_expect(Spaceship.point(ship).distance_to(LakeLayout.center()) < 4.0 and ship.canLand,
		"the ship can fly over the lake and find room on the water")
	_pilot_motion(room, alice, Vector2.ZERO, -1, 750)
	var location := Spaceship.point(ship)
	_expect(ship.landed and ship.onWater and absf(ship.y - LakeLayout.water_y()) < 0.08,
		"descending onto the lake parks the ship at the surface")
	_pilot_motion(room, alice, Vector2.RIGHT, 0, 38)
	_expect(Spaceship.point(ship).is_equal_approx(location) and ship.onWater, "the parked ship stays afloat in place")
	_message(alice, {"t": "ship", "action": "exit"})
	_expect(ship.pilot.is_empty() and actor.swimming, "the pilot can disembark into the water")
	actor.y -= 0.9
	_message(alice, {"t": "ship", "action": "board"})
	_expect(not _last_notice(alice).ok and ship.pilot.is_empty(), "a diver needs to surface before boarding")
	actor.merge(PlayerMotion.spawn(actor.point), true)
	_message(alice, {"t": "ship", "action": "board"})
	_pilot_motion(room, alice, Vector2.ZERO, 1, 60)
	_expect(ship.pilot == alice.id and not ship.landed and ship.y > 2.5, "a swimmer can board and take off from the water")
	return location

func _verify_flight_surfaces() -> void:
	var ground := Spaceship.from_save({"x": Spaceship.PAD.x, "z": Spaceship.PAD.y, "yaw": PI}, ship_grid, 72.0)
	_expect(ground.landed and ground.surface == "land" and Spaceship.point(ground) == Spaceship.PAD,
		"older parked ships retain their clear position and heading")
	var rock := _descend_at(Vector2(1.782, 0.48))
	_expect(rock.ship.landed and not rock.slipped and rock.ship.surface == "rock"
		and rock.ship.y > 0.55 and absf(rock.ship.tiltZ) > 0.12,
		"the hull can settle at the angle of a broad rock")
	var rock_exit := Spaceship.dismount(rock.ship, grid, ship_grid, 72.0)
	_expect(rock_exit.is_finite() and rock_exit.y < float(rock.ship.y), "a pilot can step down from a landed rock")
	var birch := _descend_at(Vector2(-1.95, -89.82))
	_expect(birch.ship.landed and not birch.slipped and birch.ship.surface == "tree" and birch.ship.y > 5.0,
		"a mature birch crown supports a balanced approach")
	var restored := Spaceship.from_save(Spaceship.parked_save(birch.ship), ship_grid, 72.0)
	_expect(restored.landed and restored.surface == "tree"
		and Spaceship.position(restored).is_equal_approx(Spaceship.position(birch.ship)),
		"restarting a room resolves an elevated parking site against the same tree height")
	var spruce_at := Vector2(3.9, -37.62)
	var spruce := _descend_at(spruce_at)
	_expect(spruce.slipped and spruce.ship.landed and spruce.ship.y < 1.0
		and Spaceship.point(spruce.ship).distance_to(spruce_at) > 0.75,
		"an unbalanced crown sends the ship downhill until a lower surface supports it")
	var shoreline := _descend_at(Vector2(-24.95, -34.32))
	_expect(shoreline.ship.landed and shoreline.ship.y >= LakeLayout.water_y() - 0.02,
		"the hull reaches the shallow shore without parking under water")

func _descend_at(at: Vector2) -> Dictionary:
	var support := Spaceship.Ground.contact(at, 0.0, ship_grid, 72.0)
	var ship := Spaceship.from_save(null, ship_grid, 72.0)
	ship.merge({"x": at.x, "y": float(support.y) + 1.2, "z": at.y, "yaw": 0.0, "landed": false}, true)
	var velocity := Vector3.ZERO
	var slipped := false
	for i in 480:
		velocity = Spaceship.step(ship, velocity, Vector2.ZERO, -1.0, 0.0, 1.0 / 60.0, ship_grid, 72.0)
		slipped = slipped or ship.slipping
		if ship.landed:
			break
	return {"ship": ship, "slipped": slipped}

func _verify_flight_thrust() -> void:
	const DT := 1.0 / 60.0
	var ship := Spaceship.from_save(null, {})
	ship.yaw = 0.0
	var velocity := Spaceship.step(ship, Vector3.ZERO, Vector2.ZERO, 1.0, 0.0, DT, {})
	_expect(ship.thrust > 0.90 and is_zero_approx(ship.rearThrust), "pure vertical takeoff only powers the belly jets")
	ship.y = 8.0
	velocity = Spaceship.step(ship, Vector3.ZERO, Vector2.UP, 0.0, 0.0, DT, {})
	_expect(ship.rearThrust > 0.90 and ship.thrust < 0.5, "forward acceleration powers the rear bells and maintains lift")
	var accelerating: float = ship.rearThrust
	velocity = Spaceship.step(ship, Vector3(0.0, 0.0, -11.0), Vector2.UP, 0.0, 0.0, DT, {})
	_expect(ship.rearThrust > 0.40 and ship.rearThrust < accelerating, "forward thrust tapers while the pilot holds cruise speed")
	velocity = Spaceship.step(ship, velocity, Vector2.ZERO, 0.0, 0.0, DT, {})
	_expect(ship.thrust > 0.4 and is_zero_approx(ship.rearThrust), "forward coasting cannot activate rear jets and braking increases lift")
	velocity = Spaceship.step(ship, Vector3.ZERO, Vector2.RIGHT, 0.0, 0.0, DT, {})
	_expect(is_zero_approx(ship.rearThrust), "side thrust does not use the aft bells")
	velocity = Spaceship.step(ship, Vector3.ZERO, Vector2.UP, 1.0, 0.0, DT, {})
	_expect(ship.rearThrust > 0.90 and ship.thrust > 0.90, "climbing forward powers rear and belly streams together")
	velocity = Spaceship.step(ship, Vector3(0.0, -2.0, 0.0), Vector2.ZERO, -1.0, 0.0, DT, {})
	_expect(ship.thrust < 0.23 and is_zero_approx(ship.rearThrust), "steep descent uses a smaller belly plume")
	Spaceship.step(ship, velocity, Vector2.ZERO, 0.0, 0.0, DT, {})
	_expect(ship.thrust > 0.75 and is_zero_approx(ship.rearThrust), "arresting descent increases only the belly plume")

func _pilot_motion(room: Dictionary, player: Dictionary, move: Vector2, lift: float, frames: int) -> void:
	_message(player, {"t": "motion", "x": move.x, "z": move.y, "yaw": PI, "lift": lift})
	for i in frames:
		_tick_spaceship(room, room.actors[player.id], 1.0 / 60.0)

func _verify_dog(room: Dictionary, alice: Dictionary, bob: Dictionary, fixture_path: String) -> Vector2:
	_expect(_snapshot(alice).dog == _snapshot(bob).dog and _snapshot(alice).dog.clip == CampDog.STAND, "old rooms seed one shared mastiff at the porch")
	var ambient := room.duplicate(true)
	_step_dog(ambient, 82)
	_expect(CampDog.position(ambient.data.dog).distance_to(CampDog.HOME) > 0.35 and ambient.data.dog.clip == CampDog.WALK and ambient.data.dog.speed <= CampDog.WALK_SPEED + 0.01, "an unowned dog walks out from the porch at a walking pace")
	ambient.data.quest.repaired = true
	_step_dog(ambient, 120)
	_expect(ambient.data.dog.clip == CampDog.REST and CampDog.position(ambient.data.dog).distance_to(CampDog.HOME) < 0.15, "the dog returns to the porch for a rest after the lamp is lit")
	_step_dog(ambient, 140)
	_expect(CampDog.position(ambient.data.dog).distance_to(CampDog.HOME) > 0.35 and ambient.data.dog.clip != CampDog.REST, "a repaired camp still has a roaming dog after its rest")
	_message(alice, {"t": "dog", "action": "adopt"})
	_expect(not _last_notice(alice).ok and room.data.dog.owner.is_empty(), "adoption requires standing near the dog")
	var actor: Dictionary = room.actors[alice.id]
	actor.point = Vector2(5.02, -88.2)
	_message(alice, {"t": "dog", "action": "adopt"})
	_expect(not _last_notice(alice).ok and room.data.dog.owner.is_empty(), "a nearby player cannot adopt the dog through the wall")
	actor.point = Rules.pair(world.sites.repair)
	room.data.quest.tarp = true
	_message(alice, {"t": "act", "site": "repair"})
	_step_dog(room, 1)
	_expect(room.data.dog.clip == CampDog.DOWN, "repairing the roof and lighting the lamp starts the lie-down clip")
	_step_dog(room, 32)
	_expect(room.data.dog.clip == CampDog.REST, "the dog settles into the rest loop after lying down")
	actor.point = CampDog.HOME - Vector2(0.72, 0.0)
	room.actors[bob.id].point = actor.point
	var writable := save_dir
	save_dir = fixture_path
	_message(alice, {"t": "dog", "action": "adopt"})
	_expect(not _last_notice(alice).ok and room.data.dog.owner.is_empty(), "adoption rolls back if saving fails")
	save_dir = writable
	_message(alice, {"t": "dog", "action": "adopt"})
	_message(bob, {"t": "dog", "action": "adopt"})
	_message(bob, {"t": "dog", "action": "stay"})
	_expect(_snapshot(bob).dog.owner == alice.id and room.data.dog.mode == "follow", "only the first adopter can command the mastiff")
	_step_dog(room, 1)
	_expect(room.data.dog.clip == CampDog.RISE, "the dog gets up before following")
	_step_dog(room, 88)
	_expect(room.data.dog.clip == CampDog.REST, "an adopted dog also rests near its stationary owner in the repaired cabin")
	var goal := Vector2(5.65, -88.65)
	actor.point = goal
	_step_dog(room, 140)
	var dog_at := CampDog.position(room.data.dog)
	_expect(dog_motion.navigation != null and dog_at.x > 4.5 and dog_at.distance_to(goal) <= 2.0, "the dog follows around the cabin wall to within command range")
	_message(alice, {"t": "dog", "action": "stay"})
	_step_dog(room, 32)
	_expect(room.data.dog.mode == "stay" and room.data.dog.clip == CampDog.REST and CampDog.position(room.data.dog) == dog_at, "a waiting dog lies down at the requested spot")
	return dog_at

func _step_dog(room: Dictionary, frames: int) -> void:
	for i in frames:
		room.data.elapsed += 0.05
		dog_motion.tick(room, grid, 0.05)

func _verify_wildlife(room: Dictionary, alice: Dictionary, bob: Dictionary) -> void:
	_expect(_snapshot(alice).crocodile == _snapshot(bob).crocodile and _snapshot(alice).survival.health == 100.0, "both peers see one crocodile and legacy saves start with full health")
	var patrol := Wildlife.crocodile(0.0)
	var clips := {}
	var submarine := false
	for step in 1450:
		Wildlife.tick_crocodile(patrol, {}, grid, float(step) * 0.05, 0.05)
		clips[patrol.clip] = true
		if patrol.clip == "Swim" and patrol.underwater:
			submarine = submarine or Wildlife.crocodile_pose(patrol).at[1] < LakeLayout.water_y() - 0.65
	_expect(clips.has_all(["Idle", "Walk", "Swim", "Dive", "Surface"]) and submarine, "the crocodile patrols the shore, submerges and surfaces at the lake height")
	var actor: Dictionary = room.actors[alice.id]
	actor.point = Wildlife.BASK + Vector2(0.0, -2.1)
	_tick_wildlife(ROOM, room, 0.05)
	_expect(room.crocodile.clip == "Attack" and _last_notice(alice).site == "crocodile", "approaching the basking crocodile triggers a warning")
	actor.point = Wildlife.BASK + Vector2(0.0, -3.0)
	room.data.elapsed += 0.58
	_tick_wildlife(ROOM, room, 0.05)
	_expect(room.data.survival[alice.id].health == 100.0, "stepping back during the lunge avoids damage")

	room.crocodile = Wildlife.crocodile(room.data.elapsed)
	actor.point = Wildlife.BASK + Vector2(0.0, -1.3)
	_tick_wildlife(ROOM, room, 0.05)
	room.data.elapsed += 0.58
	_tick_wildlife(ROOM, room, 0.05)
	room.data.elapsed += 0.17
	_tick_wildlife(ROOM, room, 0.05)
	_publish(ROOM)
	_expect(_snapshot(alice).survival.health == 82.0 and _snapshot(bob).survival.health == 100.0, "the lunge damages only its victim once")
	_expect(_snapshot(bob).crocodile.clip == "Attack", "the second player sees the same lunge")
	var resting: Dictionary = room.data.survival[alice.id].duplicate(true)
	Survival.tick(resting, Survival.TABLE_CENTER, true, 0.0, 2.0)
	_expect(resting.health > 82.0, "a repaired shelter heals the player over time")

	var center := Vector3(Wildlife.BASK.x, LakeLayout.ground_height(Wildlife.BASK) + 0.25, Wildlife.BASK.y)
	room.data.stones["fixture-throw"] = {"mode": "air", "at": Stones.pack(center - Vector3.RIGHT * 0.5), "velocity": [10.0, 0.0, 0.0], "launch": room.data.elapsed}
	room.data.elapsed += 0.08
	_tick_stones(room, 0.08)
	_expect(room.data.stones["fixture-throw"].mode == "ground" and room.crocodile.clip == "Hit", "an actual flying stone triggers the crocodile's recoil")
	room.data.stones.erase("fixture-throw")

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
