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
		["companion-to-real-creek", People.HOME, People.WATER],
		["creek-to-fruit-through-woodland", People.WATER, People.FOOD],
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
	print("COOP_WILD_NAVIGATION ", JSON.stringify(report))
	quit(1 if failed else 0)
