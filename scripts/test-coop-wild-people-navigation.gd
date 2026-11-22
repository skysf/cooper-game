extends SceneTree
const People = preload("res://wild_people.gd")
const Rules = preload("res://rules.gd")
var failed := false

func _initialize() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	var grid := Rules.collision_grid(world.obstacles)
	var motion := People.new()
	var cases := [
		["reported-round-rock-stall", Vector2(9.0000038, -79.6247101), Vector2(1.51969, -84.5275)],
		["east-raid-to-camp", Vector2(11.8, -72.6), People.HOME],
		["west-raid-to-camp", Vector2(-8.3, -76.0), People.HOME],
		["companion-to-lake-shore", People.HOME, People.WATER],
		["lake-to-fruit-through-woodland", People.WATER, People.FOOD],
		["injured-return-to-rest", People.FOOD, People.REST],
	]
	var report := []
	for scenario: Array in cases:
		var npc := People.make_person("nav", 0, "male", scenario[1], 0.0)
		var room := {"data": {"elapsed": 0.0}, "people_routes": {}}
		var steps := 0
		var safe := true
		while People.position(npc).distance_to(scenario[2]) > 0.35 and steps < 1400:
			var before := People.position(npc)
			room.data.elapsed += 0.1
			motion._drive(room, npc, scenario[2], 1.8, grid, 0.1)
			var after := People.position(npc)
			safe = safe and Rules.free_at(after, grid) and before.distance_to(after) <= 0.181
			steps += 1
		var passed: bool = People.position(npc).distance_to(scenario[2]) <= 0.35 and safe
		if not passed:
			failed = true
			push_error("Navigation failed: %s -> %s (%s), route=%s" % [scenario[0], People.position(npc), scenario[2], room.people_routes.get("nav", {})])
		report.append({"case": scenario[0], "seconds": steps * 0.1, "passed": passed, "collisionPreserved": safe})
	report.append(_retreat(motion, grid))
	print("COOP_WILD_NAVIGATION ", JSON.stringify(report))
	quit(1 if failed else 0)

func _retreat(motion, grid: Dictionary) -> Dictionary:
	var state := People.initial(0.0)
	state.raid.merge({"phase": "active", "startedAt": 0.0, "wave": 7}, true)
	var room := {"data": {"elapsed": 135.0, "wildPeople": state}, "actors": {}, "people_routes": {}}
	var starts := [Vector2(15.0, -69.0), Vector2(15.0, -69.0), People.HOME, Vector2(-3.3, -86.9)]
	for index in starts.size():
		var id := "person-%d" % (index + 1)
		var npc := People.make_person(id, 4, "male", starts[index], 0.0)
		if index < 2:
			npc.phase = "retreat"
		elif index == 3:
			npc.legR = 70.0
		state.people[id] = npc
	var steps := 0
	var safe := true
	while steps < 700 and state.people.values().any(func(npc: Dictionary) -> bool: return npc.phase != "gone"):
		room.data.elapsed += 0.1
		motion.tick(room, grid, 0.1)
		for npc: Dictionary in state.people.values():
			safe = safe and Rules.free_at(People.position(npc), grid)
		steps += 1
	var passed: bool = safe and People.snapshot(state, "", room.data.elapsed).people.is_empty() and room.people_routes.is_empty()
	if not passed:
		failed = true
		push_error("Raiders did not all clear the retreat boundary")
	return {"case": "group-raid-retreat-from-old-stop", "seconds": steps * 0.1, "passed": passed, "collisionPreserved": safe}
