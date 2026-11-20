extends "res://server.gd"
## In-memory rooms using the production join, storage and tick handlers.
## --baseline verifies the previous defects actually reproduce before a fix.
const QA_WALL_ROOM := "nav-wall-qa"
const QA_DOOR_ROOM := "nav-door-qa"
const QA_ACTORS := ["00aabbccddeeff112233445566778899", "00aabbccddeeff1122334455667788aa"]
const QA_NPC := "terrain-companion"
const QA_TIME := 1.0 / 30.0
var observations := {}
var checks := {}
var replies := {}
var frames := {}
var failures := 0
var lane := {}

func _initialize() -> void:
	_verify_fit.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _checkpoint(_code: String) -> bool:
	return true

func _send(connection: WebSocketPeer, msg: Dictionary) -> bool:
	if msg.t == "notice":
		replies[connection.get_instance_id()] = msg.duplicate(true)
	elif msg.t == "snapshot":
		frames[connection.get_instance_id()] = msg.duplicate(true)
	return true

func _verify_fit() -> void:
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	save_dir = "/private/tmp/coop-ephemeral-navigation-%s" % Time.get_ticks_usec()
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	if has_method("_prepare_terrain_navigation"):
		var prepare_start := Time.get_ticks_usec()
		call("_prepare_terrain_navigation")
		observations.startupNavigationUs = Time.get_ticks_usec()-prepare_start
	var wall_player := _fixture_join(1, QA_WALL_ROOM)
	var door_player := _fixture_join(2, QA_DOOR_ROOM)
	if not rooms.has(QA_WALL_ROOM) or not rooms.has(QA_DOOR_ROOM):
		push_error("The in-memory rooms did not open")
		quit(2)
		return
	var wall_room: Dictionary = rooms[QA_WALL_ROOM]
	var door_room: Dictionary = rooms[QA_DOOR_ROOM]
	lane = _find_lane(wall_room, wall_player)
	if lane.is_empty():
		push_error("Could not find a usable work location on the current map")
		quit(2)
		return
	var wall := _fixture_build(wall_room,wall_player,"cabin_wall",lane.center)
	var floor_id := _fixture_build(door_room,door_player,"cabin_floor",lane.center)
	var door_height := LakeLayout.walk_height(lane.center) + 0.18
	var door := _fixture_build(door_room,door_player,"cabin_doorway",lane.center,door_height)
	_check(not wall.is_empty() and not floor_id.is_empty() and not door.is_empty(),"real placement creates wall and floor-supported doorway")
	if wall.is_empty() or floor_id.is_empty() or door.is_empty():
		quit(2)
		return
	_reset_walkers(wall_room,wall_player)
	_reset_walkers(door_room,door_player)
	var first := _observe_pair(wall_player,door_player,wall,door,floor_id,14.0)
	observations.walls = first
	_check(first.wall.dog.overlaps > 0 and first.wall.npc.overlaps > 0 if baseline else first.wall.dog.overlaps == 0 and first.wall.npc.overlaps == 0,
		"previous wall traversal is reproduced" if baseline else "solid wall blocks both actual bodies")
	_check(first.door.dog.crossed and first.door.npc.crossed, "both go through the real doorway")
	_check(first.door.dog.overlaps == 0 and first.door.npc.overlaps == 0, "door posts and lintel are individually observed")
	_check(first.door.dog.maxBelowDeck >= 0.13 and first.door.npc.maxBelowDeck >= 0.13 if baseline else first.door.dog.maxBelowDeck < 0.035 and first.door.npc.maxBelowDeck < 0.035,
		"previous below-floor foot origin is reproduced" if baseline else "dog and NPC reach the floor support height")
	if not baseline:
		_check(not first.wall.dog.centerCross and not first.wall.npc.centerCross and first.door.dog.centerCross and first.door.npc.centerCross,
			"both detour around the wall but go straight through the doorway")
	_check(first.wall.dog.crossed or first.wall.dog.lastSpeed < 0.15, "dog can detour or stop at an obstructed goal")
	_check(first.wall.npc.crossed or first.wall.npc.lastSpeed < 0.15, "companion can detour or stop at an obstructed goal")
	_reset_walkers(wall_room,wall_player)
	_reset_walkers(door_room,door_player)
	_observe_pair(wall_player,door_player,wall,door,floor_id,0.33)
	_fixture_at(wall_room,wall_player,lane.center + lane.normal * 1.06)
	_check(_fixture_request(wall_player,"carry",{"id":wall}) and wall_room.data.storage[wall].mode == "held", "wall is lifted with storage authority")
	_check(door_room.data.storage[door].mode == "ground", "lifting in room A leaves room B's doorway in place")
	_fixture_at(wall_room,wall_player,lane.goal)
	var held := _observe_pair(wall_player,door_player,wall,door,floor_id,9.0)
	observations.carried = held
	_check(held.wall.dog.centerCross and held.wall.npc.centerCross, "lifting clears the former wall for both agents")
	_check(held.door.dog.crossed and held.door.npc.crossed, "room B still goes through the door after room A changes")
	var moved_at := _put_elsewhere(wall_room,wall_player)
	_check(moved_at.is_finite() and wall_room.data.storage[wall].mode == "ground", "wall can be placed at a different valid spot")
	if moved_at.is_finite():
		_reset_walkers(wall_room,wall_player)
		_reset_walkers(door_room,door_player)
		var moved := _observe_pair(wall_player,door_player,wall,door,floor_id,9.0)
		observations.moved = moved
		_check(moved.wall.dog.centerCross and moved.wall.npc.centerCross and moved.wall.dog.overlaps == 0 and moved.wall.npc.overlaps == 0,
			"replacement stays at its new location and the old route opens")
	var basket := _fixture_place_low(wall_room, wall_player)
	_check(not basket.is_empty(),"low container is placed on the former wall route")
	if not basket.is_empty():
		_reset_walkers(wall_room,wall_player)
		_reset_walkers(door_room,door_player)
		var low := _observe_pair(wall_player,door_player,basket,door,floor_id,12.0)
		observations.low = low
		_check(low.wall.dog.overlaps > 0 and low.wall.npc.overlaps > 0 if baseline else low.wall.dog.overlaps == 0 and low.wall.npc.overlaps == 0,
			"previous low-furniture penetration is reproduced" if baseline else "a low container blocks both actual bodies")
		_check(low.wall.dog.maxY <= 0.045 and low.wall.npc.maxY <= 0.045,"furniture is not used as walkable floor")
		_fixture_at(wall_room,wall_player,lane.center + lane.normal * 1.0)
		_check(_fixture_request(wall_player,"carry",{"id":basket}), "low container can be picked up again")
		var other := _put_elsewhere(wall_room,wall_player)
		_check(other.is_finite(),"low container no longer occupies the route")
	var table := _place_existing(wall_room,wall_player,Survival.CAMP_TABLE)
	_check(not table.is_empty(),"tall camp table is moved to the route")
	if not table.is_empty():
		_reset_walkers(wall_room,wall_player)
		_reset_walkers(door_room,door_player)
		var high := _observe_pair(wall_player,door_player,table,door,floor_id,12.0)
		observations.table = high
		_check(high.wall.dog.overlaps > 0 and high.wall.npc.overlaps > 0 if baseline else high.wall.dog.overlaps == 0 and high.wall.npc.overlaps == 0,
			"previous table penetration is reproduced" if baseline else "table legs and underside block both actual bodies")
		_check(high.wall.dog.maxY <= 0.045 and high.wall.npc.maxY <= 0.045,"tall furniture is never stepped onto")
	_verify_floor_snapshots(door_room,door_player,floor_id,baseline)
	if not baseline:
		_verify_direct_footing()
	_check(not wall_room.data.storage.has(door) and not door_room.data.storage.has(wall), "two rooms keep isolated construction records")
	print("COOP_ROOM_NAV_FIT ",JSON.stringify({"baseline":baseline,"lane":{"goal":_pair(lane.goal),"start":_pair(lane.start),"center":_pair(lane.center),"yaw":lane.yaw},
		"checks":checks,"cases":observations,"failures":failures}))
	quit(0 if failures == 0 else 1)

func _fixture_join(index: int, room_code: String) -> Dictionary:
	var connection := {"ws":WebSocketPeer.new(),"room":"","id":"","rejected":false}
	connections[index] = connection
	_message(connection,{"t":"join","room":room_code,"token":QA_ACTORS[index-1]})
	return connection

func _check(passed: bool, label: String) -> void:
	checks[label] = passed
	if not passed:
		failures += 1
		print("FAIL ",label)

func _fixture_at(room: Dictionary, player: Dictionary, point: Vector2) -> void:
	room.actors[player.id].merge(PlayerMotion.spawn(point), true)
	room.actors[player.id].direction = Vector2.ZERO
	room.actors[player.id].lift = 0.0

func _aim(actor: Dictionary, point: Vector2, y: float, rotation: float) -> Dictionary:
	var offset := Vector3(point.x-actor.point.x,y-float(actor.y)-PlayerMotion.WALK_EYE,point.y-actor.point.y)
	return {"yaw":atan2(-offset.x,-offset.z),"pitch":atan2(offset.y,Vector2(offset.x,offset.z).length()),"rotation":rotation}

func _fixture_request(player: Dictionary, action: String, fields: Dictionary) -> bool:
	var msg := {"t":"storage","action":action}
	msg.merge(fields)
	var id: int = player.ws.get_instance_id()
	replies.erase(id)
	_message(player,msg)
	return replies.get(id,{}).get("ok",false)

func _find_lane(room: Dictionary, player: Dictionary) -> Dictionary:
	var goal := WildPeople.FOOD
	for direction: Vector2 in [Vector2(0,-1),Vector2(0,1),Vector2(1,0),Vector2(-1,0)]:
		var side := direction.orthogonal()
		for distance: float in [2.65, 2.8, 3.15]:
			var center := goal + direction * distance
			var start := goal + direction * (distance + 2.8)
			var clear := true
			for i in range(31):
				clear = clear and Rules.free_at(start.lerp(goal,i/30.0),grid)
			if not clear or not _can_detour(center,direction):
				continue
			var rotation := atan2(direction.x,direction.y)
			var builder := center + direction * 2.4
			if not Rules.free_at(builder,grid):
				continue
			_fixture_at(room,player,builder)
			var actor: Dictionary = room.actors[player.id]
			var aim := _aim(actor,center,LakeLayout.walk_height(center),rotation)
			var fits_wall := PlacementWorld.preview(placement_grid,room.data.storage,"",actor.point,actor.y,PlayerMotion.WALK_EYE,
				aim.yaw,aim.pitch,aim.rotation,false,"cabin_wall")
			var fits_floor := PlacementWorld.preview(placement_grid,room.data.storage,"",actor.point,actor.y,PlayerMotion.WALK_EYE,
				aim.yaw,aim.pitch,aim.rotation,false,"cabin_floor")
			if fits_wall.get("ok",false) and fits_floor.get("ok",false):
				return {"center":center,"goal":goal,"start":start,"normal":direction,"side":side,"yaw":rotation}
	return {}

func _can_detour(center: Vector2, direction: Vector2) -> bool:
	for side: float in [-1,1]:
		var open := true
		for i in range(-7,8):
			open = open and Rules.free_at(center+direction.orthogonal()*1.87*side+direction*(i*0.22),grid)
		if open:
			return true
	return false

func _fixture_build(room: Dictionary, player: Dictionary, kind: String, point: Vector2, y := INF) -> String:
	var previous: Array = room.data.storage.keys()
	_fixture_at(room,player,point+lane.normal*2.4)
	room.data.survival[player.id].bag = {"wood_plank":42}
	var aim := _aim(room.actors[player.id],point,y if is_finite(y) else LakeLayout.walk_height(point),lane.yaw)
	aim.recipe = kind
	if _fixture_request(player,"build",aim):
		for id: String in room.data.storage:
			if id not in previous and room.data.storage[id].kind == kind:
				return id
	return ""

func _fixture_place_low(room: Dictionary, player: Dictionary) -> String:
	var id := "camp-storage-2"
	var sampled: Dictionary = room.data.storage.get(id,{})
	if sampled.get("kind") != "wood_crate":
		return ""
	return _place_existing(room,player,id)

func _place_existing(room: Dictionary, player: Dictionary, id: String) -> String:
	var sampled: Dictionary = room.data.storage.get(id,{})
	if sampled.is_empty():
		return ""
	var old := Survival.horizontal(sampled.at)
	for offset: Vector2 in [Vector2(0,0.7),Vector2(0,-0.7),Vector2(0.65,0),Vector2(-0.65,0)]:
		if not Rules.free_at(old+offset,grid):
			continue
		_fixture_at(room,player,old+offset)
		if _fixture_request(player,"carry",{"id":id}):
			_fixture_at(room,player,lane.center + lane.normal * 2.4)
			var aim := _aim(room.actors[player.id],lane.center,LakeLayout.walk_height(lane.center),lane.yaw)
			return id if _fixture_request(player,"place",aim) else ""
	return ""

func _put_elsewhere(room: Dictionary, player: Dictionary) -> Vector2:
	for shift: Vector2 in [lane.side * 3.5, lane.side * -3.5, lane.side * 4.6, lane.side * -4.6]:
		var point: Vector2 = lane.center + shift
		var eye: Vector2 = point + lane.normal * 2.35
		if not Rules.free_at(eye,grid):
			continue
		_fixture_at(room,player,eye)
		var aim := _aim(room.actors[player.id],point,LakeLayout.walk_height(point),lane.yaw)
		if _fixture_request(player,"place",aim):
			return point
	return Vector2.INF

func _reset_walkers(room: Dictionary, player: Dictionary) -> void:
	_fixture_at(room,player,lane.goal)
	var npc := WildPeople.make_person(QA_NPC,1,"male",lane.start,room.data.elapsed)
	npc.phase = "companion"
	npc.order = "guard"
	npc.hunger = 45.0
	npc.water = 90.0
	npc.health = npc.maxHealth
	npc.yaw = lane.yaw
	room.data.wildPeople.raid.nextAt = 3000.0
	room.data.wildPeople.publicFood = false
	room.data.wildPeople.people = {QA_NPC:npc}
	room.people_routes = {}
	room.data.dog = {"x":lane.start.x,"z":lane.start.y,"yaw":lane.yaw,"speed":0.0,"owner":player.id,
		"mode":"follow","clip":"Stand","clipAt":room.data.elapsed}
	room.dog_route = {}

func _observe_pair(wall_player: Dictionary, door_player: Dictionary, wall: String, door: String, deck: String, seconds: float) -> Dictionary:
	var metrics := {"wall":{ "dog":_result(),"npc":_result() },"door":{ "dog":_result(),"npc":_result() }}
	var timings: Array[int] = []
	for tick in roundi(seconds/QA_TIME):
		timings.append(_world_tick())
		_observe(rooms[wall_player.room],metrics.wall,wall,"",tick)
		_observe(rooms[door_player.room],metrics.door,door,deck,tick)
	var sorted: Array[int] = timings.duplicate()
	sorted.sort()
	metrics["simTime"] = {"p95Us":sorted[ceili(sorted.size()*0.95)-1],"maxUs":sorted.back(),"ticksUs":timings}
	return metrics

func _world_tick() -> int:
	# Keep the two actual server actors while ticking without socket I/O.
	var peers := connections
	connections = {}
	var started := Time.get_ticks_usec()
	super._process(QA_TIME)
	connections = peers
	return Time.get_ticks_usec() - started

func _verify_floor_snapshots(room: Dictionary, player: Dictionary, deck: String, baseline: bool) -> void:
	_reset_walkers(room,player)
	room.data.dog.x = lane.center.x
	room.data.dog.z = lane.center.y
	room.data.dog.mode = "stay"
	var npc: Dictionary = room.data.wildPeople.people[QA_NPC]
	npc.x = lane.center.x
	npc.z = lane.center.y
	npc.phase = "captive"
	_world_tick()
	_publish(player.room)
	var frame: Dictionary = frames[player.ws.get_instance_id()]
	var transmitted_dog := float(frame.dog.get("y",LakeLayout.walk_height(lane.center)))
	var transmitted_npc := float(frame.wildPeople.people[QA_NPC].y)
	var before := frame.duplicate(true)
	var ground := LakeLayout.walk_height(lane.center)
	_check(absf(transmitted_dog-ground-(0 if baseline else 0.18))<0.005 and absf(transmitted_npc-ground-(0 if baseline else 0.18))<0.005,
		"room snapshot carries the measured floor height")
	_fixture_at(room,player,lane.center+lane.normal*0.94)
	_check(_fixture_request(player,"carry",{"id":deck}),"floor can be lifted while agents stand in the doorway")
	_world_tick()
	_publish(player.room)
	frame = frames[player.ws.get_instance_id()]
	_check(absf(float(frame.dog.get("y",ground))-ground)<0.005 and absf(float(frame.wildPeople.people[QA_NPC].y)-ground)<0.005,
		"agents drop to the terrain on the first tick after the floor is moved")
	observations.support = {"deckDogY":transmitted_dog,"deckNpcY":transmitted_npc,"afterDogY":frame.dog.get("y",ground),"afterNpcY":frame.wildPeople.people[QA_NPC].y}
	var old_saved: Dictionary = room.data.dog.duplicate()
	old_saved.erase("y")
	var previous := CampDog.from_save(old_saved,room.data.survival,grid,false,float(room.data.elapsed))
	_check(CampDog.position(previous).is_equal_approx(lane.center) and absf(float(previous.get("y",ground))-ground) < 0.005,
		"old dog save defaults to terrain with the saved X/Z")
	if "--visual" in OS.get_cmdline_user_args():
		_verify_visual_feet(before,frame,ground)

func _verify_visual_feet(before: Dictionary, after: Dictionary, ground: float) -> void:
	var net: Node = load("res://network.gd").new()
	var dog_view: Node3D = load("res://camp_dog_scene.gd").new()
	var npc_view: Node3D = load("res://wild_people_scene.gd").new()
	root.add_child(dog_view)
	root.add_child(npc_view)
	var eye := Vector3(lane.center.x,ground+1.67,lane.center.y+2.0)
	net._receive({"t":"welcome","id":before.players.keys()[0]})
	net._receive(JSON.parse_string(JSON.stringify(before)))
	var deck_dog_y: float = net.dog.y
	var deck_npc_y: float = net.wild_people.people[QA_NPC].y
	_check(absf(deck_dog_y-ground-0.18)<0.005 and absf(deck_npc_y-ground-0.18)<0.005,
		"the web client's network decoder preserves both JSON heights")
	dog_view.sync(net.dog,net.elapsed,net.dog_sample_time,QA_TIME)
	npc_view.sync(net.wild_people.people,net.elapsed,QA_TIME,eye)
	var npc_root: Node3D = npc_view.actors[QA_NPC].root
	_check(absf(dog_view.position.y-ground-0.18)<0.005 and absf(npc_root.position.y-ground-0.18)<0.005,
		"actual character views start on the floor from the snapshot")
	observations.visual = {"deckNetDogY":deck_dog_y,"deckNetNpcY":deck_npc_y,
		"deckDogRootY":dog_view.position.y,"deckNpcRootY":npc_root.position.y,"terrainY":ground}
	net._receive(JSON.parse_string(JSON.stringify(after)))
	dog_view.sync(net.dog,net.elapsed,net.dog_sample_time,QA_TIME)
	npc_view.sync(net.wild_people.people,net.elapsed,QA_TIME,eye)
	_check(absf(dog_view.position.y-ground)<0.005 and absf(npc_root.position.y-ground)<0.005,
		"actual character views drop to the terrain on the first new snapshot")
	observations.visual.merge({"afterNetDogY":net.dog.y,"afterNetNpcY":net.wild_people.people[QA_NPC].y,
		"afterDogRootY":dog_view.position.y,"afterNpcRootY":npc_root.position.y})
	var legacy := after.duplicate(true)
	legacy.dog.erase("y")
	net._receive(JSON.parse_string(JSON.stringify(legacy)))
	dog_view.sync(net.dog,net.elapsed,net.dog_sample_time,QA_TIME)
	_check(absf(dog_view.position.y-ground)<0.005, "a legacy dog frame without height renders on the terrain")
	observations.visual.legacyDogRootY = dog_view.position.y
	net.free()
	dog_view.queue_free()
	npc_view.queue_free()

func _verify_direct_footing() -> void:
	var footing: RefCounted = load("res://companion_footing.gd").new()
	var slope := Vector2(-51.4,-66.5)
	var slope_y := LakeLayout.walk_height(slope)
	var inland := slope.direction_to(LakeLayout.Coast.point("lookout"))
	var sloped_move: Vector3 = footing.move(slope,inland,0.08,grid,1.8,slope_y,Vector2(0.47,0.9))
	var expected := Rules.move(slope,inland,0.08,grid,false,1.8)
	_check(Vector2(sloped_move.x,sloped_move.z).is_equal_approx(expected) and absf(sloped_move.y-LakeLayout.walk_height(expected))<0.002,
		"coastal slope keeps the legacy terrain movement and correct foot height")
	var center := Vector2(9.1,-79.1)
	var base := LakeLayout.walk_height(center)
	var orientation := Basis.from_euler(Vector3(0.12,0.56,-0.06)).get_rotation_quaternion()
	var rotated := {"mode":"ground","kind":"cabin_floor","yaw":0.0,"at":[center.x,base,center.y],
		"rotation":[orientation.x,orientation.y,orientation.z,orientation.w]}
	footing.sync({"rotated":rotated},15.0)
	var transform := PlacementWorld.pose(rotated)
	var surface := transform * Vector3(0.71,0.18,-0.34)
	var outside := transform * Vector3(1.54,0.18,-0.34)
	var measured: float = footing.height(Vector2(surface.x,surface.z),surface.y-0.12)
	var away: float = footing.height(Vector2(outside.x,outside.z),outside.y-0.12)
	_check(absf(measured-surface.y)<0.002 and absf(away-LakeLayout.walk_height(Vector2(outside.x,outside.z)))<0.002,
		"rotated and sloping floor height uses the real panel face and its edges")
	var lower := {"mode":"ground","kind":"cabin_floor","yaw":lane.yaw,"at":[lane.center.x,0.0,lane.center.y]}
	var upper := lower.duplicate(true)
	upper.at[1] = 0.18
	footing.sync({"deck-a":lower,"deck-b":upper},16.0)
	var coming: Vector2 = lane.center+lane.normal*2.5
	var lifted := 0.0
	var height := 0.0
	for i in 90:
		var next: Vector3 = footing.move(coming,-lane.normal,QA_TIME,grid,1.8,height,Vector2(0.47,0.90))
		coming = Vector2(next.x,next.z)
		height = next.y
		lifted = maxf(lifted,height)
	_check(lifted <= 0.215 and (coming-lane.center).dot(lane.normal) > 0.25,"stacked deck cannot be climbed in one ground step")
	observations.probes = {"slopeY":sloped_move.y,"slopingDeckY":measured,"expectedDeckY":surface.y,
		"outsideDeckY":away,"stackedMaxY":lifted,"stackedStoppedAt":_pair(coming)}

func _result() -> Dictionary:
	return {"crossed":false,"centerCross":false,"overlaps":0,"maxBelowDeck":0.0,"maxY":-10.0,"lastSpeed":0.0,"last":[],"trace":[]}

func _observe(room: Dictionary, metrics: Dictionary, obstacle: String, deck: String, tick: int) -> void:
	var dog: Dictionary = room.data.dog
	var npc: Dictionary = room.data.wildPeople.people[QA_NPC]
	var parts: Array[Dictionary] = []
	var prop: Dictionary = room.data.storage.get(obstacle,{})
	if prop.get("mode") == "ground":
		parts = PlacementWorld.Placement.bodies(obstacle,PlacementWorld.profile(prop.kind),PlacementWorld.pose(prop))
	for tag: String in ["dog","npc"]:
		var probe: Dictionary = dog if tag == "dog" else npc
		var report: Dictionary = metrics[tag]
		var point := Vector2(probe.x,probe.z)
		var ground := LakeLayout.walk_height(point)
		var y: float = probe.get("y",ground)
		var proj: float = (point-lane.center).dot(lane.normal)
		var across: float = (point-lane.center).dot(lane.side)
		if report.last.size() == 2:
			report.lastSpeed = Vector2(report.last[0],report.last[1]).distance_to(point)/QA_TIME
		report.last = _pair(point)
		report.maxY = maxf(report.maxY,y)
		if not parts.is_empty():
			var size := AABB(Vector3(-.24,.05,-.39),Vector3(.48,.79,.78)) if tag == "dog" else AABB(Vector3(-.245,.05,-.245),Vector3(.49,1.62,.49))
			var transform := Transform3D(Basis(Vector3.UP,float(probe.yaw)),Vector3(point.x,y,point.y))
			var body := PlacementWorld.Placement.solid("agent",size,transform,0)
			for part: Dictionary in parts:
				if PlacementWorld.Placement.overlaps(part,body):
					report.overlaps += 1
					break
		if not report.crossed:
			report.crossed = proj < -0.45
			report.centerCross = report.centerCross or (absf(proj) < 0.12 and absf(across) < 0.28)
		if not deck.is_empty() and point.distance_to(lane.center) < 0.95:
			var deck_top := float(room.data.storage[deck].at[1])+0.18
			report.maxBelowDeck = maxf(report.maxBelowDeck,deck_top-y)
		if tick % 12 == 0:
			report.trace.append([roundf(tick*QA_TIME*100.0)/100.0,point.x,y,point.y,str(probe.get("clip",""))])

func _pair(point: Vector2) -> Array:
	return [point.x,point.y]
