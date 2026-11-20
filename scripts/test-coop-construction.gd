extends "res://server.gd"

const ROOM := "cabin-qa"
const CLIENT_A := "00000000000000000000000000000001"
const CLIENT_B := "00000000000000000000000000000002"

var received := {}
var checks := 0
var failures := 0

func _initialize() -> void:
	_verify.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _send(peer: WebSocketPeer, message: Dictionary) -> bool:
	var key := peer.get_instance_id()
	if not received.has(key):
		received[key] = {}
	received[key][message.t] = message.duplicate(true)
	return true

func _join_fixture(index: int, token: String) -> Dictionary:
	var connection := {"ws":WebSocketPeer.new(),"room":"","id":"","rejected":false}
	connections[index] = connection
	_message(connection,{"t":"join","room":ROOM,"token":token})
	return connection

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + label)

func _request(connection: Dictionary, action: String, fields: Dictionary, channel := "storage") -> bool:
	var message := {"t":channel,"action":action}
	message.merge(fields)
	_message(connection,message)
	var reply: Dictionary = received[connection.ws.get_instance_id()].get("notice",{})
	if not reply.get("ok",false):
		print("REJECT ",action," ",fields.get("recipe",fields.get("id",""))," ",reply.get("text",""))
	return bool(reply.get("ok",false))

func _at(room: Dictionary, connection: Dictionary, point: Vector2) -> void:
	room.actors[connection.id].merge(PlayerMotion.spawn(point),true)

func _aim(actor: Dictionary, target: Vector3, rotation := 0.0, snap := false) -> Dictionary:
	var offset := target - Vector3(actor.point.x, float(actor.y)+PlayerMotion.WALK_EYE, actor.point.y)
	return {"yaw":atan2(-offset.x,-offset.z),"pitch":atan2(offset.y,Vector2(offset.x,offset.z).length()),
		"rotation":rotation,"snap":snap}

func _build(room: Dictionary, player: Dictionary, recipe: String, target: Vector3, snap := false) -> String:
	var known: Array = room.data.storage.keys()
	var fields := _aim(room.actors[player.id],target,0.0,snap)
	fields.recipe = recipe
	if _request(player,"build",fields):
		for id: String in room.data.storage:
			if id not in known and room.data.storage[id].kind == recipe:
				return id
	return ""

func _site(room: Dictionary, player: Dictionary) -> Vector2:
	placement_grid = PlacementWorld.static_grid(world)
	for x: float in [9.8,12.5,14.6,6.1,16.0]:
		for z: float in [-82.2,-78.2,-74.5,-87.4,-68.5]:
			var point := Vector2(x,z)
			var approach := point+Vector2(0,2.40)
			if not Rules.free_at(approach,grid):
				continue
			_at(room,player,approach)
			var actor: Dictionary = room.actors[player.id]
			var aim := _aim(actor,Vector3(point.x,LakeLayout.walk_height(point),point.y))
			var result := PlacementWorld.preview(placement_grid,room.data.storage,"",approach,actor.y,
				PlayerMotion.WALK_EYE,aim.yaw,aim.pitch,aim.rotation,false,"cabin_floor")
			if result.get("ok",false):
				return point
	return Vector2.INF

func _verify() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1 or DirAccess.make_dir_recursive_absolute(arguments[0]) != OK:
		quit(2)
		return
	save_dir = arguments[0]
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	var alice := _join_fixture(1,CLIENT_A)
	var bob := _join_fixture(2,CLIENT_B)
	var room: Dictionary = rooms[ROOM]
	_check(room.data.storage.has(Survival.CAMP_TABLE) and room.data.provisions["apple-1"].tableId == Survival.CAMP_TABLE,
		"one movable camp table owns the original tabletop food")
	_at(room,alice,Vector2(2.9,-88.25))
	_check(_request(alice,"carry",{"id":"camp-table-gnome"}),"decorative gnome can be picked up from the camp table")
	var fields := _aim(room.actors[alice.id],Vector3(2.99,Survival.TABLE_TOP,-88.84),.8)
	_check(_request(alice,"place",fields),"gnome can be rotated and placed at a new point on the tabletop")
	var gnome: Dictionary = room.data.storage["camp-table-gnome"]
	_check(absf(float(gnome.at[1])-Survival.TABLE_TOP) < .004 and gnome.supports.has(Survival.CAMP_TABLE),
		"table placement retains its elevation and physical support")
	_check(_request(alice,"carry",{"id":Survival.CAMP_TABLE}),"the original table can be moved with decorations above it")
	_check(float(room.data.storage["camp-table-gnome"].at[1]) < .10 and room.data.provisions["apple-1"].surface == "ground",
		"removing the table lets former tabletop objects settle and drops its original food")
	_check(_request(alice,"drop",{}),"an older drop request can still put down a held fixture")

	var center := _site(room,alice)
	_check(center.is_finite(),"the shared world offers an unobstructed cabin site")
	if not center.is_finite():
		_finish()
		return
	room.data.survival[alice.id].bag.wood_plank = 100
	var ground := LakeLayout.walk_height(center)
	var origin := Vector3(center.x,ground,center.y)
	var floor_id := _build(room,alice,"cabin_floor",origin)
	_check(not floor_id.is_empty() and int(room.data.survival[alice.id].bag.wood_plank) == 93,"authoritative build places a floor and spends its seven boards")
	if floor_id.is_empty():
		_finish()
		return
	var apple := _verify_stacked_furnishings(room,alice,bob,center,ground,floor_id)
	var wall_ids: Array[String] = []
	for side: Vector2 in [Vector2(0,1), Vector2(-1,0), Vector2(0,-1), Vector2(1,0)]:
		_at(room,alice,center+side*2.12)
		var target := origin+Vector3(side.x,.18,side.y)*Vector3(1.23,1.0,1.23)
		var wall_id := _build(room,alice,"cabin_doorway" if side.y > 0 else "cabin_wall",target,true)
		wall_ids.append(wall_id)
		_check(not wall_id.is_empty() and room.data.storage[wall_id].supports.has(floor_id),"wall or door frame snaps onto the deck at %s" % side)
	_at(room,alice,center+Vector2(0,2.54))
	var roof_id := _build(room,alice,"cabin_roof",origin+Vector3(0,2.33,1.43),true)
	_check(not roof_id.is_empty() and room.data.storage[roof_id].supports.has(wall_ids[0]) and room.data.storage[roof_id].supports.has(wall_ids[2]),
		"aiming at the upper wall from the ground seats the roof on both sides")
	var saved_boards: int = room.data.survival[alice.id].bag.wood_plank
	var count: int = room.data.storage.size()
	var collision := _build(room,alice,"cabin_floor",origin)
	_check(collision.is_empty() and int(room.data.survival[alice.id].bag.wood_plank) == saved_boards and room.data.storage.size() == count,
		"an invalid placement leaves inventory and the existing cabin unchanged")
	_check(received[bob.ws.get_instance_id()].snapshot.storage == room.data.storage,"the peer receives the same assembly and transforms")
	_verify_walk(room,center,ground)
	_leave(1)
	_leave(2)
	alice = _join_fixture(3,CLIENT_A)
	room = rooms[ROOM]
	_check(room.data.storage.has(roof_id) and absf(float(room.data.storage[roof_id].at[1])-ground-2.48) < .006
		and room.data.storage[roof_id].supports.has(wall_ids[2]),"a reloaded roof retains orientation, elevation and supports")
	var landed: Dictionary = room.data.provisions.get(apple,{})
	_check(landed.get("supportId") == floor_id and absf(float(landed.get("at",[0.0,INF])[1])-ground-.192) < .006,
		"table food that landed on the lower floor keeps its attachment and height after reconnect")
	if not landed.is_empty():
		_at(room,alice,Survival.horizontal(landed.at))
		room.actors[alice.id].y = ground + .18
		_check(_request(alice,"take",{"id":apple},"provision") and not room.data.provisions.has(apple),
			"the apple can be collected from the saved deck")
	_finish()

func _verify_stacked_furnishings(room: Dictionary, alice: Dictionary, bob: Dictionary,
		center: Vector2, ground: float, lower: String) -> String:
	var origin := Vector3(center.x,ground,center.y)
	_at(room,alice,center+Vector2(0,2.05))
	var upper := _build(room,alice,"cabin_floor",origin+Vector3.UP*.18)
	_check(not upper.is_empty() and room.data.storage[upper].supports.has(lower),
		"the upper deck has physical support from the lower deck")
	if upper.is_empty():
		return ""
	var table := room.data.storage[Survival.CAMP_TABLE] as Dictionary
	_at(room,bob,Survival.horizontal(table.at)+Vector2(.3,.50))
	_check(_request(bob,"carry",{"id":Survival.CAMP_TABLE}),"the second player carries the original table to the stack")
	_at(room,bob,center+Vector2(0,-1.97))
	var pose := _aim(room.actors[bob.id],origin+Vector3.UP*.36)
	var placed := _request(bob,"place",pose)
	_check(placed and room.data.storage[Survival.CAMP_TABLE].supports.has(upper),"the table rests on the upper deck")
	if not placed:
		return ""
	_at(room,bob,center+Vector2(0,-1.03))
	room.actors[bob.id].y = ground + .36
	room.data.survival[bob.id].bag.apple = 1
	_check(_request(bob,"put",{"item":"apple"},"provision"),"the second player places an apple on the elevated table")
	var apple := ""
	for id: String in room.data.provisions:
		if room.data.provisions[id].get("tableId") == Survival.CAMP_TABLE:
			apple = id
			break
	if apple.is_empty():
		return ""
	var top_y: float = room.data.provisions[apple].at[1]
	_check(absf(top_y-ground-.36-Survival.TABLE_TOP) < .006,"the apple touches the raised tabletop")
	_at(room,alice,center+Vector2(.9,.61))
	room.actors[alice.id].y = ground + .36
	room.actors[alice.id].yaw = PI
	room.data.survival[alice.id].bag.iron_ore = 1
	_check(_request(alice,"drop",{"item":"iron_ore"},"provision"),"an inventory ore can be dropped onto the built deck")
	var ore := ""
	for id: String in room.data.provisions:
		if room.data.provisions[id].get("item") == "iron_ore" and room.data.provisions[id].get("supportId") == upper:
			ore = id
			break
	_check(not ore.is_empty() and absf(float(room.data.provisions[ore].at[1])-ground-.372) < .006,
		"the dropped mesh contacts the upper deck at the correct height")
	_at(room,alice,center+Vector2(0,2.05))
	_at(room,bob,center+Vector2(0,-2.15))
	var before_storage: Dictionary = room.data.storage.duplicate(true)
	var before_provisions: Dictionary = room.data.provisions.duplicate(true)
	var before_bag: Dictionary = room.data.survival[alice.id].bag.duplicate()
	var saves := save_dir
	save_dir = saves.path_join("absent")
	_check(not _request(alice,"dismantle",{"id":upper}) and room.data.storage == before_storage
		and room.data.provisions == before_provisions and room.data.survival[alice.id].bag == before_bag,
		"a checkpoint failure restores the upper deck, both objects and the builder inventory")
	save_dir = saves
	_check(_request(alice,"dismantle",{"id":upper}),"dismantling an occupied upper deck resolves its dependencies")
	var settled: Dictionary = room.data.storage[Survival.CAMP_TABLE]
	var apple_on_table: Dictionary = room.data.provisions[apple]
	_check(settled.get("supports",[]).has(lower) and absf(float(settled.at[1])-ground-.18) < .006
		and apple_on_table.get("tableId") == Survival.CAMP_TABLE and absf(float(apple_on_table.at[1])-top_y+.18) < .006,
		"the table and apple descend together to the lower deck")
	_check(not ore.is_empty() and room.data.provisions[ore].get("supportId") == lower
		and absf(float(room.data.provisions[ore].at[1])-ground-.192) < .006,
		"the loose ore lands on the lower deck and records its new support")
	_at(room,bob,center+Vector2(0,-1.03))
	room.actors[bob.id].y = ground + .18
	_check(_request(bob,"carry",{"id":Survival.CAMP_TABLE}),"a teammate can lift the resettled table")
	var fallen: Dictionary = room.data.provisions[apple]
	_check(fallen.get("supportId") == lower and not fallen.has("tableId") and absf(float(fallen.at[1])-ground-.192) < .006,
		"food falls onto the deck beneath the removed table")
	_check(received[alice.ws.get_instance_id()].snapshot.provisions[apple] == fallen,
		"the other player receives the same apple contact and support")
	_at(room,bob,center+Vector2(0,-3.5))
	_check(_request(bob,"drop",{}),"the teammate puts the carried table back down away from the cabin")
	return apple

func _verify_walk(room: Dictionary, center: Vector2, ground: float) -> void:
	var through := PlayerMotion.spawn(center+Vector2(0,2.25))
	var blocked := PlayerMotion.spawn(center+Vector2(.93,2.25))
	for i in 50:
		PlayerMotion.step(through,Vector2(0,-1),0,1.0/60.0,grid,{},ship_grid,0,room.data.storage)
		PlayerMotion.step(blocked,Vector2(0,-1),0,1.0/60.0,grid,{},ship_grid,0,room.data.storage)
	_check(through.point.y < center.y+1.10 and absf(float(through.y)-ground-.18) < .015,"the real avatar can walk through the opening onto the floor")
	_check(blocked.point.y > center.y+1.58,"the neighboring solid wall blocks the same walk")

func _finish() -> void:
	print("CONSTRUCTION_AUTHORITY_QA checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
