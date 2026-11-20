extends "res://server.gd"

const ROOM := "mining-qa"
const FURNACE := "camp-iron-furnace"

var messages := {}
var checks := 0
var failures := 0

func _initialize() -> void:
	_verify.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _send(peer: WebSocketPeer, message: Dictionary) -> bool:
	var key := peer.get_instance_id()
	if not messages.has(key):
		messages[key] = {}
	messages[key][message.t] = message.duplicate(true)
	return true

func _join_as(index: int, token: String) -> Dictionary:
	var connection := {"ws":WebSocketPeer.new(),"room":"","id":"","rejected":false}
	connections[index] = connection
	_message(connection,{"t":"join","room":ROOM,"token":token})
	return connection

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print(("PASS " if value else "FAIL ") + label)

func _request(connection: Dictionary, msg: Dictionary) -> bool:
	_message(connection,msg)
	return bool(messages.get(connection.ws.get_instance_id(),{}).get("notice",{}).get("ok",false))

func _mine_as(connection: Dictionary, id: String) -> bool:
	return _request(connection,{"t":"mine","id":id})

func _furnace_as(connection: Dictionary, action: String) -> bool:
	return _request(connection,{"t":"storage","action":action,"id":FURNACE})

func _move_to_vein(room: Dictionary, connection: Dictionary, id: String) -> bool:
	var cave := MinesLayout.pose(id)
	var target := MinesLayout.gather(id)
	var local := cave.affine_inverse()*target
	var actor: Dictionary = room.actors[connection.id]
	var colliders := MinesLayout.solids(id)
	for dz: float in [0.0,-.46,.46,-.81,.81]:
		var approach := cave*Vector3(0.0,0.0,local.z+dz)
		var point := Vector2(approach.x,approach.z)
		var ground := LakeLayout.walk_height(point)
		actor.merge(PlayerMotion.spawn(point),true)
		actor.y = PlacementWorld.floor_height(colliders,point,target.y,ground)
		if Mining.reachable(actor,target,colliders):
			return true
	return false

func _move_to_fixture(room: Dictionary, player: Dictionary, id: String) -> void:
	var center := Survival.horizontal(room.data.storage[id].at)
	room.actors[player.id].merge(PlayerMotion.spawn(center + Vector2(-.84,.60)),true)

func _verify() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		quit(2)
		return
	save_dir = args[0]
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	const A := "00000000000000000000000000000101"
	const B := "00000000000000000000000000000102"
	var alice := _join_as(1,A)
	var bob := _join_as(2,B)
	var room: Dictionary = rooms[ROOM]
	_check(room.data.storage.has(FURNACE),"the room places one supported furnace near the camp")
	_check(not _mine_as(alice,"coal_mine"),"a player at camp cannot extract ore remotely")
	_check(_move_to_vein(room,alice,"coal_mine") and _move_to_vein(room,bob,"coal_mine"),"two players can reach the actual coal face")
	_check(_mine_as(alice,"coal_mine") and not _mine_as(alice,"coal_mine"),"coal is awarded once per pick cycle")
	_check(_mine_as(bob,"coal_mine") and room.data.mines.coal_mine.stock == 12,"both players draw from the same coal seam")
	var peer: Dictionary = messages[bob.ws.get_instance_id()].snapshot
	_check(peer.mines == room.data.mines,"both clients receive the current stock")
	_check(_move_to_vein(room,alice,"iron_mine"),"the actual iron face has a standing approach")
	room.data.elapsed += 1.0
	_check(_mine_as(alice,"iron_mine"),"a player can extract an iron ore from the iron mine")
	room.data.elapsed += 1.0
	_check(_mine_as(alice,"iron_mine") and room.data.survival[alice.id].bag.iron_ore == 2,"two ore pieces enter the normal bag stack")
	room.data.elapsed += 1.0
	var path := save_dir
	save_dir = path.path_join("missing-directory")
	_check(not _mine_as(alice,"iron_mine") and room.data.survival[alice.id].bag.iron_ore == 2 and room.data.mines.iron_mine.stock == 8,
		"a failed ore save rolls back both inventory and the shared ore stock")
	save_dir = path
	_move_to_fixture(room,bob,"camp-storage-6")
	var fuel := _request(bob,{"t":"storage","action":"fuel","id":"camp-storage-6","item":"coal"})
	_check(fuel and absf(float(room.data.storage["camp-storage-6"].fuelUntil)-float(room.data.elapsed)-155.0)<.001
		and not room.data.survival[bob.id].bag.has("coal"),"coal alone fuels the campfire for the authored duration")
	_move_to_fixture(room,alice,FURNACE)
	_move_to_fixture(room,bob,FURNACE)
	_check(_furnace_as(alice,"smelt") and not room.data.survival[alice.id].bag.has("coal")
		and not room.data.survival[alice.id].bag.has("iron_ore"),"the furnace reserves two ore and one coal")
	var ready: float = room.data.storage[FURNACE].batchReady
	_check(not _furnace_as(bob,"take_ingot") and not _furnace_as(bob,"carry"),"an active batch cannot be collected or moved early")
	_leave(1)
	_leave(2)
	bob = _join_as(3,B)
	room = rooms[ROOM]
	_check(is_equal_approx(float(room.data.storage[FURNACE].batchReady),ready) and room.data.mines.iron_mine.stock == 8,
		"rejoining restores the active batch and excavated ore")
	room.data.elapsed = ready
	_check(_furnace_as(bob,"take_ingot") and not _furnace_as(bob,"take_ingot") and room.data.survival[bob.id].bag.iron_ingot == 1,
		"a teammate can collect exactly one finished ingot")
	room.data.elapsed = float(room.data.mines.iron_mine.nextAt)
	_publish(ROOM)
	_check(room.data.mines.iron_mine.stock == 9,"room time reveals one fresh ore on the shared seam")
	print("MINING_AUTHORITY_QA checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
