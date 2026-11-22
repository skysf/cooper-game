extends SceneTree

const People = preload("res://wild_people.gd")
const Lake = preload("res://lake_layout.gd")
const Rules = preload("res://rules.gd")
const Atlas = preload("res://field_atlas.gd")
const Motion = preload("res://player_motion.gd")
var errors: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		push_error(label)

func walk_from_camp(grid: Dictionary) -> void:
	var trail: Array = Lake.East.region.trails[0]
	var actor := Motion.spawn(Vector2(1.9,-85))
	var guide := preload("res://wild_people_navigation.gd").new()
	var route := {}
	var elapsed := 0.0
	for xy: Array in trail.slice(0,8):
		var goal := Vector2(xy[0],xy[1])
		for tick in 900:
			if actor.point.distance_to(goal)<.18:
				break
			var next := guide._waypoint(actor.point,goal,route,grid,elapsed)
			Motion.step(actor,actor.point.direction_to(next),0,.06,grid,{})
			elapsed += .06
		check(actor.point.distance_to(goal)<.20,"On foot from the old camp to "+str(goal))
	check(actor.point.x>72 and is_zero_approx(Lake.ground_height(Vector2(29,-85))),"Crosses the old east boundary continuously")

func _initialize() -> void:
	var ai := People.new()
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	var grid := Rules.collision_grid(world.obstacles)
	walk_from_camp(grid)
	var state := People.initial(0,{"firstRaid":7200.0})
	var room := {"data":{"wildPeople":state,"elapsed":0.0,"provisions":{},"quest":{"repaired":true}},
		"people_routes":{},"actors":{},"ship":{"pilot":""}}
	check(Atlas.EXTENT.x * Atlas.EXTENT.y == 87246,"Playable rectangle doubles")
	for site: String in Atlas.LANDMARKS:
		var at: Vector2 = Atlas.LANDMARKS[site].landing
		check(Atlas.contains(at) and Rules.free_at(at,grid),"Clear landmark "+site)
	var recorded := {}
	var outdoor := {}
	var restored := false
	for tick in 3950:
		var now := tick*.08
		room.data.elapsed = now
		room.actors["visitor"] = {"point": Vector2(90,-53) if now<4 else Vector2(265,-56)}
		ai.tick(room,grid,.08)
		for npc: Dictionary in state.people.values():
			if npc.phase!="resident":
				continue
			recorded[npc.homeMine+"/"+npc.duty] = true
			if npc.duty in People.Caves.OUTSIDE and npc.leg==3 and npc.workUntil>now:
				var expected: Array = Lake.East.region.camps[npc.homeMine][npc.duty]
				check(People.position(npc).distance_to(Vector2(expected[0],expected[1]))<2.15,"Uses outdoor source")
				outdoor[npc.homeMine+"/"+npc.duty] = true
		if tick==525:
			var loaded := People.from_save(JSON.parse_string(JSON.stringify(state)),now,grid)
			check(loaded.people.size()==4,"Four residents survive save and load")
			for id: String in state.people:
				check(absf(float(loaded.people[id].y)-float(state.people[id].y))<.06 and loaded.people[id].leg==state.people[id].leg and loaded.people[id].duty==state.people[id].duty,"Restores work and vertical level "+id)
			state = loaded
			room.data.wildPeople = state
			room.people_routes = {}
			restored = true
	for id: String in state.caves:
		var camp: Dictionary = state.caves[id]
		check(camp.crafted==2 and camp.fires>=2,id+" makes equipment and renews the fire")
		for duty: String in People.Caves.OUTSIDE:
			check(outdoor.has(id+"/"+duty),id+" leaves, works at and returns from "+duty)
	var snapshot := People.snapshot(state,"visitor",room.data.elapsed)
	check(snapshot.people.size()==4 and snapshot.caves==People.snapshot(state,"visitor2",room.data.elapsed).caves,"Two viewers see the same settlement")
	print("EASTERN_LIFE ",JSON.stringify({"camps":state.caves,"outdoor":outdoor.keys(),"duties":recorded.keys(),"reloaded":restored,"errors":errors}))
	quit(0 if errors.is_empty() else 1)
