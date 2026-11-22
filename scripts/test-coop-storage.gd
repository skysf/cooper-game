extends "res://server.gd"

const ROOM := "storage-qa"
const ALICE := "0000000000000000000000000000000a"
const BOB := "0000000000000000000000000000000b"
const CAPACITIES := {"wicker_basket":4, "wood_crate":8, "military_crate":12, "wood_barrel":10, "wood_barrel_tall":14}
const WORK_POSITIONS := [Vector2(2.54,-87.95), Vector2(2.2,-89.25), Vector2(1.08,-88.72), Vector2(3.4,-87.63), Vector2(3.7,-90.23), Vector2(1.7,-86.19), Vector2(4.63,-87.72)]
var packets := {}
var checks := 0
var failures := 0
var fixture := ""

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

func _connect(key: int, token: String) -> Dictionary:
	var con := {"ws":WebSocketPeer.new(), "room":"", "id":"", "rejected":false}
	connections[key] = con
	_message(con,{"t":"join", "room":ROOM, "token":token})
	return con

func _snapshot(con: Dictionary) -> Dictionary:
	return packets[con.ws.get_instance_id()].snapshot

func _expect(condition: bool, desc: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL ", desc)
	else:
		print("PASS ", desc)

func _act_storage(con: Dictionary, action: String, id := "", fields := {}) -> bool:
	var msg := {"t":"storage","action":action,"id":id}
	msg.merge(fields,true)
	return _do(con,msg)

func _do(con: Dictionary, msg: Dictionary) -> bool:
	var sent: Dictionary = packets[con.ws.get_instance_id()]
	sent.erase("notice")
	_message(con,msg)
	return bool(sent.get("notice",{}).get("ok",false))

func _last_text(con: Dictionary) -> String:
	return str(packets[con.ws.get_instance_id()].get("notice",{}).get("text",""))

func _at(room: Dictionary, con: Dictionary, p: Vector2, yaw := 0.0) -> void:
	room.actors[con.id].merge(PlayerMotion.put_ashore(Vector3(p.x,LakeLayout.walk_height(p),p.y)),true)
	room.actors[con.id].yaw = yaw
	room.actors[con.id].direction = Vector2.ZERO
	room.actors[con.id].lift = 0.0

func _at_object(room: Dictionary, con: Dictionary, id: String) -> void:
	_at(room,con,Survival.horizontal(room.data.storage[id].at))

func _item(room: Dictionary, con: Dictionary, item: String) -> int:
	return int(room.data.survival[con.id].bag.get(item,0))

func _object(room: Dictionary, kind: String, nth := 0) -> String:
	for id: String in room.data.storage:
		if room.data.storage[id].kind == kind:
			if nth == 0:
				return id
			nth -= 1
	return ""

func _stored(room: Dictionary, id: String, item: String) -> int:
	return int(room.data.storage.get(id,{}).get("bag",{}).get(item,0))

func _find_provision(room: Dictionary, item: String, count: int, table_id := "") -> String:
	for id: String in room.data.provisions:
		var p: Dictionary = room.data.provisions[id]
		if p.item == item and int(p.get("count",1)) == count and p.get("tableId","") == table_id and p.surface == "ground":
			return id
	return ""

func _verify() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("Use one isolated directory for room fixture")
		quit(2)
		return
	save_dir = args[0]
	fixture = save_dir.path_join(ROOM+".json")
	if FileAccess.file_exists(fixture):
		push_error("Use an empty fixture directory")
		quit(2)
		return
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	var f := FileAccess.open(fixture,FileAccess.WRITE)
	f.store_string(JSON.stringify({"version":1,"elapsed":69.0,"homes":{},"quest":{"wood":false,"tarp":false,"repaired":false}}))
	f.close()

	var alice := _connect(1,ALICE)
	var bob := _connect(2,BOB)
	if alice.room.is_empty() or bob.room.is_empty():
		push_error("Fixture did not join")
		quit(2)
		return
	var room: Dictionary = rooms[ROOM]
	var camp_fixtures:=["camp-first-cot","camp-iron-furnace","camp-table","camp-table-babushka","camp-table-gnome","camp-water-jug"]
	var expected_ids:=camp_fixtures.duplicate()
	for index in Storage.START.size():
		expected_ids.append("camp-storage-%d"%index)
	_expect(_snapshot(alice).storage == _snapshot(bob).storage and room.data.storage.has_all(expected_ids)
		and room.data.storage.size()==expected_ids.size(),"legacy room has one shared set of containers, furniture, cot and furnace")
	_verify_capacities(room,alice)
	_verify_transactions(room,alice,bob)
	var moved := _verify_carry_throw(room,alice,bob)
	var salvage := _verify_salvage(room,alice)
	var fuel_until := _verify_fuel(room,alice,bob)
	var furniture := _verify_furniture(room,alice,bob)
	var provision := _verify_table(room,alice,furniture.table)
	_verify_croc(room,alice,bob)

	_leave(1)
	_leave(2)
	_expect(not rooms.has(ROOM),"empty room unloads after safe save")
	alice = _connect(3,ALICE)
	bob = _connect(4,BOB)
	room = rooms[ROOM]
	_expect(not room.data.storage.has(salvage.removed) and room.data.provisions.has(salvage.spill)
		and int(room.data.provisions.get(salvage.spill,{}).get("count",0)) == 3,
		"legacy default basket stays dismantled and loose wicker stack retains all three after reload")
	_expect(_stored(room,moved,"bread") == 2 and room.data.storage.get(moved,{}).get("mode") == "ground","thrown crate and both stored breads survive reload")
	_expect(is_equal_approx(float(room.data.storage[_object(room,"campfire")].fuelUntil),fuel_until),"campfire fuel remains shared after reload")
	var sign: Dictionary = room.data.storage.get(furniture.sign,{})
	_expect(sign.get("owner") == alice.id and sign.get("text") == "眺望湖边 安静","sign ownership and sanitized text persist")
	_expect(room.data.provisions.get(provision,{}).get("tableId") == furniture.table and room.data.storage.has(furniture.table),"provision stays associated with its crafted table")
	if room.data.storage.has(furniture.table) and room.data.provisions.has(provision):
		_at_object(room,bob,furniture.table)
		_expect(_act_storage(bob,"carry",furniture.table),"teammate can carry crafted table")
		var dropped: Dictionary = room.data.provisions.get(provision,{})
		var drop_point := Survival.horizontal(dropped.at)
		_expect(not dropped.has("tableId") and absf(float(dropped.at[1])-LakeLayout.walk_height(drop_point)-.012) < .0001,
			"carrying a reloaded table puts its physical provision on the ground")
	_expect(not StorageWildlife.alive(room,"croc") and _stored(room,"corpse-croc","crocodile_hide") == 1,"crocodile death and remaining loot survive reload")
	print("STORAGE_AUTHORITY_QA checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)

func _verify_capacities(room: Dictionary, alice: Dictionary) -> void:
	for kind: String in CAPACITIES:
		var id := _object(room,kind)
		var known: Dictionary = room.data.storage[id].bag.duplicate()
		_at_object(room,alice,id)
		var capacity: int = CAPACITIES[kind]
		_expect(Storage.KINDS[kind].capacity == capacity,"capacity declaration for " + kind)
		var n := known.size()
		var store_ok := true
		var overflow := ""
		for item: String in Survival.ITEM_NAMES:
			if known.has(item):
				continue
			if n >= capacity:
				overflow = item
				break
			room.data.survival[alice.id].bag = {item:1}
			store_ok = _act_storage(alice,"store",id,{"item":item}) and store_ok
			n += 1
		_expect(store_ok and Survival.used_slots(room.data.storage[id].bag) == capacity,"actual store path fills " + kind)
		room.data.survival[alice.id].bag = {overflow:1,"apple":1}
		_expect(not _act_storage(alice,"store",id,{"item":overflow}) and _item(room,alice,overflow) == 1
			and _act_storage(alice,"store",id,{"item":"apple"}) and _stored(room,id,"apple") == 2,"full " + kind + " rejects new kinds and merges existing kinds")
		room.data.storage[id].bag = known

func _verify_transactions(room: Dictionary, alice: Dictionary, bob: Dictionary) -> void:
	var id := _object(room,"wicker_basket")
	_at_object(room,alice,id)
	room.data.survival[alice.id].bag = {"apple":1}
	var real_folder := save_dir
	save_dir = fixture
	var failed_store := _act_storage(alice,"store",id,{"item":"apple"})
	_expect(not failed_store and _last_text(alice).contains("存档") and _item(room,alice,"apple") == 1 and _stored(room,id,"apple") == 0,"save failure rolls back store")
	save_dir = real_folder
	_expect(_act_storage(alice,"store",id,{"item":"apple"}) and _item(room,alice,"apple") == 0
		and _snapshot(bob).storage[id].bag.apple == 1,"retry commits once and shares basket contents")
	_at(room,bob,Vector2(16,-73))
	room.data.survival[bob.id].bag = {}
	_expect(not _act_storage(bob,"take",id,{"item":"apple"}) and _stored(room,id,"apple") == 1,"remote client cannot take from basket")
	_at_object(room,bob,id)
	room.data.survival[bob.id].bag = {"bread":1,"herb":1,"water":1,"wood":1,"wood_plank":1,"tarp":1}
	_expect(not _act_storage(bob,"take",id,{"item":"apple"}) and _stored(room,id,"apple") == 1,"full player cannot withdraw another kind")
	room.data.survival[bob.id].bag = {}
	save_dir = fixture
	_expect(not _act_storage(bob,"take",id,{"item":"apple"}) and _item(room,bob,"apple") == 0 and _stored(room,id,"apple") == 1,"save failure rolls back withdraw")
	save_dir = real_folder
	_expect(_act_storage(bob,"take",id,{"item":"apple"}) and not _act_storage(alice,"take",id,{"item":"apple"})
		and _item(room,bob,"apple") == 1 and _item(room,alice,"apple") == 0 and _stored(room,id,"apple") == 0,"two peer withdrawals of last item conserve quantity")

func _verify_carry_throw(room: Dictionary, alice: Dictionary, bob: Dictionary) -> String:
	var id := _object(room,"wood_crate")
	_at_object(room,alice,id)
	room.data.survival[alice.id].bag = {"bread":2}
	_expect(_act_storage(alice,"store",id,{"item":"bread"}) and _act_storage(alice,"store",id,{"item":"bread"}),"store two items in crate")
	_at_object(room,bob,id)
	_expect(_act_storage(alice,"carry",id) and Storage.held_by(room.data.storage,alice.id) == id, "taking crate carries original object")
	_expect(not _act_storage(bob,"take",id,{"item":"bread"}) and not _act_storage(bob,"carry",id) and _stored(room,id,"bread") == 2,"teammate cannot withdraw or carry already held crate")
	_at(room,alice,Vector2(9.0,-81.5))
	_at(room,bob,Vector2(16,-73))
	_expect(_act_storage(alice,"throw",id,{"pitch":0.0,"yaw":0.0}) and room.data.storage[id].mode == "air"
		and _snapshot(bob).storage[id].mode == "air" and _stored(room,id,"bread") == 2,"throw starts a shared flight with identical contents")
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	_expect(disk.storage[id].mode == "ground" and int(disk.storage[id].bag.bread) == 2,"mid-flight checkpoint retains contents in settled disk state")
	for _frame in 140:
		room.data.elapsed += 1.0/60.0
		_tick_storage(room,1.0/60.0)
		if room.data.storage[id].mode == "ground":
			break
	_expect(room.data.storage[id].mode == "ground" and _stored(room,id,"bread") == 2,"thrown crate lands with both stored items")
	_at_object(room,bob,id)
	room.data.survival[bob.id].bag = {}
	_expect(_act_storage(bob,"take",id,{"item":"bread"}) and _item(room,bob,"bread") == 1
		and _act_storage(bob,"store",id,{"item":"bread"}) and _stored(room,id,"bread") == 2,"landed crate supports teammate withdrawal and return")
	return id

func _verify_salvage(room: Dictionary, alice: Dictionary) -> Dictionary:
	var id := _object(room,"wicker_basket",1)
	_at_object(room,alice,id)
	room.data.survival[alice.id].bag = {"rope":2}
	for _i in 2:
		_act_storage(alice,"store",id,{"item":"rope"})
	room.data.survival[alice.id].bag = {"apple":1,"bread":1,"water":1,"herb":1,"club":1,"stone":1}
	var folder := save_dir
	save_dir = fixture
	_expect(not _act_storage(alice,"dismantle",id) and room.data.storage.has(id) and _stored(room,id,"rope") == 2,"failed save rolls back dismantle and original storage")
	save_dir = folder
	_expect(_act_storage(alice,"dismantle",id) and not room.data.storage.has(id) and _item(room,alice,"wood_plank") == 0,"basket dismantle does not yield planks")
	var wicker_id := _find_provision(room,"wicker_strip",3)
	_expect(not wicker_id.is_empty() and not _find_provision(room,"rope",2).is_empty(),"full inventory spills three woven strips and all original rope as separate stacks")
	return {"removed":id,"spill":wicker_id}

func _verify_fuel(room: Dictionary, alice: Dictionary, bob: Dictionary) -> float:
	var fire := _object(room,"campfire")
	_at_object(room,bob,fire)
	room.data.survival[bob.id].bag = {"wood_plank":1}
	var clock: float = room.data.elapsed
	_expect(_act_storage(bob,"fuel",fire,{"item":"wood_plank"}) and _item(room,bob,"wood_plank") == 0 and
		is_equal_approx(room.data.storage[fire].fuelUntil,clock+float(Storage.FUEL_ITEMS.wood_plank)),"plank fuel consumes one item and starts visible fire time")
	var barrel := _object(room,"wood_barrel")
	_at_object(room,alice,barrel)
	room.data.survival[alice.id].bag = {"tarp":2}
	for _i in 2:
		_act_storage(alice,"store",barrel,{"item":"tarp"})
	_expect(_act_storage(alice,"carry",barrel),"can carry a barrel to fire")
	_at_object(room,alice,fire)
	var baseline: float = room.data.storage[fire].fuelUntil
	_expect(_act_storage(alice,"burn",barrel) and not room.data.storage.has(barrel)
		and is_equal_approx(room.data.storage[fire].fuelUntil,baseline+float(Storage.KINDS.wood_barrel.fuel))
		and not _find_provision(room,"tarp",2).is_empty(),"burn consumes whole wooden barrel, extends fuel, unloads original items")
	return float(room.data.storage[fire].fuelUntil)

func _craft(room: Dictionary, con: Dictionary, recipe: String, contents: Dictionary) -> String:
	var original: Dictionary = room.data.storage.duplicate()
	var point := Vector2.INF
	var angle := 0.0
	for sample: Vector2 in WORK_POSITIONS:
		for heading in [0.0,PI/2,PI,-PI/2,PI/4]:
			_at(room,con,sample,float(heading))
			var actor: Dictionary = room.actors[con.id]
			if Storage._camp_recipe(actor,grid) and Storage._find_spot(room.data.storage,actor,grid,recipe).is_finite():
				point = sample
				angle = float(heading)
				break
		if point.is_finite():
			break
	if not point.is_finite():
		_expect(false,"no viable workshop fixture position for " + recipe)
		return ""
	_at(room,con,point,angle)
	room.data.survival[con.id].bag = contents.duplicate()
	var success := _act_storage(con,"craft","",{"recipe":recipe})
	var new_id := ""
	for id: String in room.data.storage:
		if not original.has(id) and room.data.storage[id].kind == recipe:
			new_id = id
	var remainder := 0
	for item: String in contents:
		remainder += _item(room,con,item)
	_expect(success and not new_id.is_empty() and remainder == 0,"craft " + recipe + " consumes exact recipe and makes one world object: " + _last_text(con))
	return new_id

func _verify_furniture(room: Dictionary, alice: Dictionary, bob: Dictionary) -> Dictionary:
	var ids := {"table":_craft(room,alice,"wood_table",{"wood_plank":4}),
		"chair":_craft(room,alice,"wood_chair",{"wood_plank":3}),
		"ladder":_craft(room,alice,"rope_ladder",{"wood_plank":3,"rope":1}),
		"sign":_craft(room,alice,"wood_sign",{"wood_plank":2})}
	if ids.sign.is_empty() or ids.chair.is_empty() or ids.ladder.is_empty():
		return ids
	_at_object(room,alice,ids.sign)
	_at_object(room,bob,ids.sign)
	var input := "  眺望湖边" + String.chr(0x202e) + " 安静" + String.chr(10) + "  "
	_expect(_act_storage(alice,"rename",ids.sign,{"text":input}) and _snapshot(bob).storage[ids.sign].text == "眺望湖边 安静","owner writes sanitized sign text and teammate sees it")
	_expect(not _act_storage(bob,"rename",ids.sign,{"text":"别人的字"}) and room.data.storage[ids.sign].text == "眺望湖边 安静","teammate cannot edit another player's sign")
	_at_object(room,bob,ids.chair)
	var sit := _act_storage(bob,"use",ids.chair)
	var actor: Dictionary = room.actors[bob.id]
	_expect(sit and _tick_storage_pose(room,actor,true,1.0/60.0) and actor.get("storageSeat") == ids.chair,"chair enables real seated actor pose")
	actor.direction = Vector2.LEFT
	_expect(not _tick_storage_pose(room,actor,true,1.0/60.0) and not actor.has("storageSeat"),"moving stands up from chair")
	_at_object(room,bob,ids.ladder)
	var climb := _act_storage(bob,"use",ids.ladder)
	actor = room.actors[bob.id]
	var base: float = actor.y
	actor.direction = Vector2(0,-1).rotated(-float(actor.yaw))
	for _i in 36:
		_tick_storage_pose(room,actor,true,1.0/60.0)
	_expect(climb and actor.get("climbing") == ids.ladder and actor.y > base + .6,"rope ladder use makes movement ascend")
	actor.lift = 1.0
	_expect(not _tick_storage_pose(room,actor,true,1.0/60.0) and not actor.has("climbing"),"jump releases rope ladder")
	return ids

func _verify_table(room: Dictionary, alice: Dictionary, table: String) -> String:
	if table.is_empty():
		return ""
	_at_object(room,alice,table)
	if not _act_storage(alice,"carry",table):
		_expect(false,"can transport crafted table")
		return ""
	_at(room,alice,Vector2(8.0,-82.2))
	if not _act_storage(alice,"drop",table):
		_expect(false,"crafted table can be placed on a separate clearing: " + _last_text(alice))
		return ""
	_at_object(room,alice,table)
	room.data.survival[alice.id].bag = {"wood_plank":1}
	var placed := _do(alice,{"t":"provision","action":"put","item":"wood_plank"})
	var id := _find_provision(room,"wood_plank",1,table)
	_expect(placed and not id.is_empty() and _item(room,alice,"wood_plank") == 0,
		"new table accepts a real rendered non-food provision: " + _last_text(alice))
	return id

func _verify_croc(room: Dictionary, alice: Dictionary, bob: Dictionary) -> void:
	var position := Stones.unpack(Wildlife.crocodile_pose(room.crocodile).at) + Vector3.UP*.22
	var hit := StorageWildlife.hit(room,position+Vector3.LEFT,position+Vector3.RIGHT,.08,101.0,grid)
	var corpse: Dictionary = room.data.storage.get("corpse-croc",{})
	_expect(hit and not StorageWildlife.alive(room,"croc") and int(corpse.get("bag",{}).get("crocodile_meat_raw",0)) == 3,
		"real crocodile hit yields one corpse with three raw cuts")
	if corpse.is_empty():
		return
	_at_object(room,alice,"corpse-croc")
	_at_object(room,bob,"corpse-croc")
	room.data.survival[alice.id].bag = {"bread":1}
	var time: float = room.data.elapsed
	_expect(is_equal_approx(float(corpse.get("landAt", -1.0)), time + Storage.CROC_COLLAPSE_SECONDS)
		and not _act_storage(alice,"take","corpse-croc",{"item":"crocodile_meat_raw"})
		and not _act_storage(bob,"take","corpse-croc",{"item":"crocodile_meat_raw"})
		and _stored(room,"corpse-croc","crocodile_meat_raw") == 3,
		"both teammates wait for the shoreline crocodile to finish collapsing")
	var resumed := Storage.from_save({"corpse-croc":corpse}, time + 0.32, grid)
	var restored: Dictionary = resumed.get("corpse-croc",{})
	_expect(not Storage.corpse_ready(restored,time + 0.32)
		and Storage.corpse_ready(restored,time + Storage.CROC_COLLAPSE_SECONDS),
		"a reloaded active crocodile collapse preserves the same handoff time")
	var old := corpse.duplicate()
	old.erase("landAt")
	var migrated := Storage.from_save({"corpse-croc":old},time,grid)
	_expect(Storage.corpse_ready(migrated.get("corpse-croc",{}),time),
		"legacy crocodile corpses load with settled loot")
	var wet := {"data":{"storage":{},"elapsed":time}}
	StorageWildlife._leave_corpse(wet,"croc",{"point":LakeLayout.center(),"yaw":0.0},grid)
	var dry: Dictionary = wet.data.storage.get("corpse-croc",{})
	var landing := Survival.horizontal(dry.at)
	_expect(Storage.corpse_ready(dry,time) and Rules.free_at(landing,grid)
		and LakeLayout.walk_height(landing) > LakeLayout.surface_height(landing),
		"water crocodile death leaves a settled corpse at an accessible shore point")
	room.data.elapsed = time + Storage.CROC_COLLAPSE_SECONDS
	_expect(_act_storage(alice,"take","corpse-croc",{"item":"crocodile_meat_raw"}) and _stored(room,"corpse-croc","crocodile_meat_raw") == 2
		and not _act_storage(alice,"store","corpse-croc",{"item":"bread"}),"players harvest corpse loot and cannot deposit provisions")
	var fire := _object(room,"campfire")
	_at_object(room,alice,fire)
	_expect(_act_storage(alice,"craft",fire,{"recipe":"crocodile_meat_grilled"}) and _item(room,alice,"crocodile_meat_grilled") == 1,"lit fire grills one raw crocodile cut")
	_at(room,alice,WORK_POSITIONS[0])
	_expect(_act_storage(alice,"craft","",{"recipe":"crocodile_sandwich"}) and _item(room,alice,"crocodile_sandwich") == 1
		and _item(room,alice,"crocodile_meat_grilled") == 0 and _item(room,alice,"bread") == 0,"workbench assembles sandwich from grilled meat and bread")
