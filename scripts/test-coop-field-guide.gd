extends "res://server.gd"

const ROOM := "field-guide"
const INGREDIENT := "crocodile_meat_raw"

var checks_failed := 0

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _send(_ws: WebSocketPeer, _msg: Dictionary) -> bool:
	return true

func _expect(condition: bool, label: String) -> void:
	if not condition:
		checks_failed += 1
		push_error(label)

func _join_player(index: int) -> Dictionary:
	var con := {"ws": WebSocketPeer.new(), "room": "", "id": "", "rejected": false}
	connections[index] = con
	_join(con, {"room": ROOM, "token": "%032x" % index})
	return con

func _observe(con: Dictionary, species: String, pitch: float) -> void:
	con.sighting_next_ms = 0
	_message(con, {"t": "sighting", "species": species, "pitch": pitch})

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	save_dir = args[0]
	DirAccess.make_dir_recursive_absolute(save_dir)
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	placement_grid = PlacementWorld.static_grid(world)
	var a := _join_player(1)
	var b := _join_player(2)
	var room: Dictionary = rooms[ROOM]
	var actor: Dictionary = room.actors[a.id]
	var state: Dictionary = room.data.survival[a.id]
	var guide: Dictionary = state.fieldGuide
	_expect(guide.animals.is_empty() and not guide.cooking, "a new player starts with no guide entries")
	_expect(Survival.state_from_save({"bag": {INGREDIENT: 1}}).fieldGuide.cooking, "legacy owners of an ingredient recover its recipes")
	actor.point = Vector2(0, -81)
	actor.y = LakeLayout.walk_height(actor.point)
	room.data.dog.merge({"x": 0.0, "z": -83.0, "y": LakeLayout.walk_height(Vector2(0, -83)),
		"yaw": 0.0, "clip": CampDog.STAND}, true)
	var target := StorageWildlife.sighting_position(room, "dog")
	var pitch := atan2(target.y - float(actor.y) - PlayerMotion.WALK_EYE, 2.0)
	actor.yaw = PI
	_observe(a, "dog", pitch)
	_expect(guide.animals.is_empty(), "an animal behind the player does not unlock")
	actor.yaw = 0.0
	room.data.storage["sight-wall"] = Storage._record("cabin_wall", Vector2(0, -82), 0.0)
	_observe(a, "dog", pitch)
	_expect(guide.animals.is_empty(), "an animal behind a wall does not unlock")
	room.data.storage.erase("sight-wall")
	var writable := save_dir
	save_dir = save_dir.path_join(ROOM + ".json")
	_observe(a, "dog", pitch)
	_expect(guide.animals.is_empty(), "a failed checkpoint rolls back the sighting")
	save_dir = writable
	_observe(a, "dog", pitch)
	_observe(a, "dog", pitch)
	_expect(guide.animals == ["dog"] and room.data.survival[b.id].fieldGuide.animals.is_empty(), "one sighting unlocks exactly one card for its observer")

	var camp := actor.point as Vector2
	actor.point = Vector2(-9.0, -58.65)
	actor.y = LakeLayout.walk_height(actor.point)
	var eye := Vector3(actor.point.x, actor.y + PlayerMotion.WALK_EYE, actor.point.y)
	room.crocodile.underwater = true
	_expect(not StorageWildlife.sighting_position(room, "croc").is_finite(), "turning toward a submerged crocodile has no visible target")
	room.crocodile.underwater = false
	var to_croc := StorageWildlife.sighting_position(room, "croc") - eye
	actor.yaw = atan2(-to_croc.x, -to_croc.z)
	_observe(a, "croc", atan2(to_croc.y, Vector2(to_croc.x, to_croc.z).length()))
	_expect(guide.animals == ["dog", "croc"], "a crocodile visible from shore unlocks its own card")
	actor.point = camp
	actor.y = LakeLayout.walk_height(camp)

	var carcass := Storage._record("corpse_croc", Vector2(1.0, -81.0), 0.0)
	carcass.bag = {INGREDIENT: 1}
	room.data.storage["guide-carcass"] = carcass
	_message(a, {"t": "storage", "action": "take", "id": "guide-carcass", "item": INGREDIENT})
	state = room.data.survival[a.id]
	_expect(state.fieldGuide.cooking and state.bag.get(INGREDIENT, 0) == 1, "harvesting meat unlocks the recipes")
	_message(a, {"t": "provision", "action": "eat", "item": INGREDIENT})
	_expect(room.data.survival[a.id].bag.get(INGREDIENT, 0) == 0, "the ingredient can be consumed before reloading")
	rooms.erase(ROOM)
	_expect(_load_room(ROOM), "room reloads after the field guide checkpoint")
	var restored: Dictionary = rooms[ROOM].data.survival
	_expect(restored[a.id].fieldGuide == {"animals": ["croc", "dog"], "cooking": true} and not restored[b.id].fieldGuide.cooking,
		"sightings and recipes persist separately per player")
	print("COOP_FIELD_GUIDE ", "OK" if checks_failed == 0 else "FAILED")
	quit(0 if checks_failed == 0 else 1)
