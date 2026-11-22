extends "res://server.gd"

const ROOM := "lake-household"
const TOKEN_A := "000000000000000000000000000000a1"
const TOKEN_B := "000000000000000000000000000000b2"
var failed := false
var samples := {}

func _initialize() -> void:
	_verify.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _send(socket: WebSocketPeer, packet: Dictionary) -> bool:
	if packet.t == "snapshot":
		samples[socket.get_instance_id()] = packet.duplicate(true)
	return true

func check(value: bool, description: String) -> void:
	if not value:
		failed = true
	print("PASS " if value else "FAIL ",description)

func join_actor(key: int, token: String) -> Dictionary:
	var con := {"ws":WebSocketPeer.new(), "room":"", "id":"", "rejected":false}
	connections[key] = con
	_message(con,{"t":"join","room":ROOM,"token":token})
	return con

func _verify() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	save_dir = args[0].path_join(str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(save_dir)
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	ship_grid = Spaceship.collision_grid(world)
	var a := join_actor(1,TOKEN_A)
	var b := join_actor(2,TOKEN_B)
	var room: Dictionary = rooms[ROOM]
	var actor: Dictionary = room.actors[a.id]
	var peer: Dictionary = room.actors[b.id]
	var elapsed := 78.0
	room.data.elapsed = elapsed
	_message(a,{"t":"lake","action":"sail"})
	check(room.data.ferryDepartedAt == -1.0,"departure requires the pier or deck")
	actor.merge(PlayerMotion.spawn(Ferry.PIER),true)
	peer.merge(PlayerMotion.spawn(Ferry.PIER),true)
	_message(a,{"t":"lake","action":"board"})
	_message(b,{"t":"lake","action":"board"})
	_message(a,{"t":"lake","action":"sail"})
	var departed: float = room.data.ferryDepartedAt
	room.data.elapsed += 0.1
	_message(b,{"t":"lake","action":"sail"})
	check(actor.ferryLocal.distance_to(peer.ferryLocal) > .48,"two players board at separate positions")
	check(departed == elapsed and room.data.ferryDepartedAt == departed,"concurrent departure starts exactly one trip")
	_message(a,{"t":"lake","action":"leave"})
	check(actor.onFerry and peer.onFerry,"passengers cannot disembark onto the distant pier")
	var safe := true
	var held := true
	for i in 943:
		room.data.elapsed = elapsed + i * 0.05
		var boat := Ferry.pose(room.data.elapsed,departed)
		safe = safe and LakeLayout.lake_distance(boat.point) < 1.0
		PlayerMotion.step(actor,Vector2.ZERO,0.0,0.05,grid,room.ship,ship_grid,0.0,room.data.storage,departed,room.data.elapsed)
		var local := Ferry.local_point(actor.point,boat)
		held = held and actor.onFerry and not actor.swimming and local.distance_to(Ferry.ENTRY) < 0.009
		if i == 340:
			_checkpoint(ROOM)
			var home: Dictionary = room.data.homes[a.id]
			check(home.has("ferryLocal") and absf(home.ferryLocal[0]-Ferry.ENTRY.x)<0.001,"save records passenger position on the moving deck")
			_leave(1)
			a = join_actor(1,TOKEN_A)
			actor = room.actors[a.id]
			check(actor.onFerry and actor.point.distance_to(Ferry.world_point(Ferry.ENTRY,boat)) < 0.001,"reconnect restores a passenger on the moving hull")
	check(safe and held,"full oval remains on lake water and the deck carries a standing passenger")
	_message(a,{"t":"lake","action":"leave"})
	check(not actor.onFerry and actor.point.distance_to(Ferry.PIER)<0.001 and not actor.swimming,"landing returns the passenger to the dry pier")
	var sheep: Dictionary = Sheep.pose(room.data.elapsed,-1.0)
	var at: Vector3 = sheep.at
	for person: Dictionary in [actor,peer]:
		person.merge(PlayerMotion.spawn(Vector2(at.x,at.z)),true)
	var bag: Dictionary = room.data.survival[a.id].bag
	for key: String in ["bread","wood","tarp","water","herb","stone"]:
		bag[key] = 1
	_message(a,{"t":"lake","action":"shear"})
	check(room.data.shearedAt == -1.0 and not bag.has("wool"),"a full bag leaves the fleece on the animal")
	bag.erase("stone")
	_message(a,{"t":"lake","action":"shear"})
	_message(b,{"t":"lake","action":"shear"})
	check(bag.get("wool",0)==1 and room.data.survival[b.id].bag.get("wool",0)==0,"simultaneous shearing gives a single bundle")
	var shorn_at: float = room.data.shearedAt
	var held_pose := Sheep.pose(shorn_at+0.75,shorn_at)
	check(held_pose.clip == "Alert" and (held_pose.at as Vector3).distance_to(at) < .01,"shearing pauses the grazing animal in place")
	check(Sheep.shorn(shorn_at+Sheep.REGROW_SECONDS-.01,shorn_at) and not Sheep.shorn(shorn_at+Sheep.REGROW_SECONDS,shorn_at),"the fleece regrows on the room clock")
	var other: Dictionary = samples[b.ws.get_instance_id()]
	check(other.shearedAt == shorn_at and other.sheepAlive,"a second player receives the same coat state")
	var head := StorageWildlife.sighting_position(room,"sheep")
	var hit := StorageWildlife.room_hit(room,head+Vector3.UP*1.9,head-Vector3.UP*.09,.015)
	check(hit.get("species","")=="sheep","the live sheep is reachable by the existing hunting path")
	StorageWildlife.apply_hit(room,hit,99.0,grid)
	StorageWildlife.apply_hit(room,hit,99.0,grid)
	var corpse: Dictionary = room.data.storage["corpse-sheep"]
	check(not StorageWildlife.alive(room,"sheep") and corpse.shorn and corpse.bag == {"lamb_raw":2},"a shorn animal leaves one carcass with two lamb chops")
	_checkpoint(ROOM)
	var save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_dir.path_join(ROOM+".json")))
	var restored := Storage.from_save(save.storage,save.elapsed,grid)
	check(restored["corpse-sheep"].shorn and restored["corpse-sheep"].bag == corpse.bag and save.shearedAt == shorn_at,"reloaded storage preserves coat, meat and shearing time")
	var regrown := {"data":room.data.duplicate(true)}
	regrown.data.storage.erase("corpse-sheep")
	regrown.data.storageWildlife.sheep = 45.0
	regrown.data.elapsed = shorn_at + Sheep.REGROW_SECONDS
	StorageWildlife.apply_hit(regrown,hit,99.0,grid)
	check(regrown.data.storage["corpse-sheep"].bag == {"lamb_raw":2,"wool":1},"a full coat yields fleece alongside the lamb chops")
	var pos := Stones.unpack(corpse.at)
	peer.merge(PlayerMotion.spawn(Vector2(pos.x,pos.z)),true)
	room.data.elapsed += 1.0
	_message(b,{"t":"storage","action":"take","item":"lamb_raw","id":"corpse-sheep"})
	check(room.data.survival[b.id].bag.get("lamb_raw",0)==1,"existing storage interaction transfers an actual raw chop")
	for id: String in room.data.storage:
		var record: Dictionary = room.data.storage[id]
		if record.kind != "campfire":
			continue
		var fire := Stones.unpack(record.at)
		room.actors[b.id].merge(PlayerMotion.spawn(Vector2(fire.x+.65,fire.z)),true)
		record.fuelUntil = room.data.elapsed + 60.0
		_message(b,{"t":"storage","action":"craft","recipe":"lamb_grilled","id":id})
		break
	check(room.data.survival[b.id].bag.get("lamb_grilled",0)==1 and room.data.survival[b.id].bag.get("lamb_raw",0)==0,"a lit campfire cooks one raw lamb chop")
	_test_living_aboard(room,a,b)
	_test_camp_beds(room,a,b)
	_test_reed_harvest(room,a,b)
	_test_rigs()
	_test_passenger_headroom()
	quit(1 if failed else 0)

func _test_passenger_headroom() -> void:
	var hiker := preload("res://hiker.gd").new()
	root.add_child(hiker)
	hiker.outfit(1)
	hiker.wear_clothes({"helmet":true})
	var hat: MeshInstance3D = hiker.garments.helmet.find_children("*","MeshInstance3D",true,false)[0]
	var bounds := hat.get_aabb()
	for stance in ["Crouch","CrouchWalk","Sleep"]:
		var asleep: bool = stance == "Sleep"
		hiker.set_motion_state({"onFerry":true,"grounded":true,"crouched":not asleep,"bed":Beds.PORT if asleep else "",
			"vx":0.96 if stance=="CrouchWalk" else 0.0,"vz":0.0})
		var top := -INF
		for frame in 40:
			hiker.advance(.08,true)
			for corner in 8:
				top = maxf(top,(hat.global_transform*bounds.get_endpoint(corner)).y)
		check(top < (.48 if asleep else 1.04),"%s helmet remains within the fitted height above its support (%.3f m)" % [stance,top])
	hiker.free()

func _test_living_aboard(room: Dictionary, a: Dictionary, b: Dictionary) -> void:
	var actor: Dictionary = room.actors[a.id]
	var peer: Dictionary = room.actors[b.id]
	var boat := Ferry.pose(room.data.elapsed,-1.0)
	room.data.ferryDepartedAt = -1.0
	for slot: Vector2 in Ferry.BOARDING_SPOTS:
		check(Ferry.on_deck(slot) and not Ferry.obstructed(slot,false),"boarding spot clears canopy, crew and cargo "+str(slot))
	Ferry.place(actor,Vector2(-1.40,.10),boat,LakeLayout.water_y())
	var forward := Vector2.RIGHT.rotated(-float(boat.yaw))
	for i in 10:
		PlayerMotion.step(actor,forward,0,.04,grid,room.ship,{},0,{},-1,room.data.elapsed)
	check(not Ferry.under_canopy(actor.ferryLocal),"the canopy entrance stops a standing passenger")
	actor.crouchHeld = true
	for i in 34:
		PlayerMotion.step(actor,forward,0,.04,grid,room.ship,{},0,{},-1,room.data.elapsed)
	actor.crouchHeld = false
	PlayerMotion.step(actor,Vector2.ZERO,1,.04,grid,room.ship,{},0,{},-1,room.data.elapsed)
	check(actor.crouched and actor.grounded and actor.ferryLocal.x>-.4,"Ctrl opens the aisle and releasing it under canvas keeps headroom")
	Ferry.place(peer,actor.ferryLocal,boat,LakeLayout.water_y())
	_message(a,{"t":"lake","action":Beds.PORT})
	_message(b,{"t":"lake","action":Beds.PORT})
	check(actor.bed==Beds.PORT and peer.bed=="","one berth cannot accept two passengers")
	_message(b,{"t":"lake","action":Beds.STARBOARD})
	check(peer.bed==Beds.STARBOARD,"the second berth can be used concurrently")
	var personal: Dictionary = room.data.survival[a.id]
	personal.health=65
	room.data.ferryDepartedAt=room.data.elapsed-8.0
	for i in 60:
		room.data.elapsed += .05
		_tick_player(room,a.id,0,0,.05)
	check(actor.bed==Beds.PORT and personal.health>69 and actor.point.distance_to(Ferry.world_point(Beds.berth(Beds.PORT),Ferry.pose(room.data.elapsed,room.data.ferryDepartedAt)))<.01,"sleep heals and follows the underway berth")
	_message(a,{"t":"lake","action":"wake"})
	_message(b,{"t":"lake","action":"wake"})
	check(actor.crouched and not Ferry.outside_aisle(actor.ferryLocal) and actor.bed=="","waking puts the passenger in the low aisle")
	check(Ferry.obstructed(Vector2(-1.2,.54),true) and Ferry.obstructed(Vector2(1.3,-.48),true),"crouching cannot push a helmet through the low sides at either canopy entrance")
	personal.bag={}
	for angle: float in [-.6,.85,2.1]:
		var shore := LakeLayout.shore_at(angle,1.012)
		actor.merge(PlayerMotion.spawn(shore),true)
		a.person_next_ms=0
		_message(a,{"t":"person","action":"gather","item":"water"})
	check(personal.bag.get("water",0)==3 and not room.data.wildPeople.resources.has("water"),"three lake shores fill the same stack without a station")
	for dry: Vector2 in [Vector2(-10.4,-62.5),Vector2.ZERO,Vector2(-81,-45)]:
		actor.merge(PlayerMotion.spawn(dry),true)
		a.person_next_ms=0
		_message(a,{"t":"person","action":"gather","item":"water"})
	check(personal.bag.get("water",0)==3,"dry land, the old marker and the open sea do not supply lake water")

func _test_camp_beds(room: Dictionary, a: Dictionary, b: Dictionary) -> void:
	var id := "camp-first-cot"
	check(room.data.storage.has(id),"existing camps gain a first usable rope bed")
	if not room.data.storage.has(id):
		return
	var socket := Beds.socket(room,id)
	var near_cot: Vector2 = socket.point + Vector2(.90,0)
	room.actors[a.id].merge(PlayerMotion.spawn(near_cot),true)
	room.actors[b.id].merge(PlayerMotion.spawn(near_cot),true)
	_message(a,{"t":"storage","action":"sleep","id":id})
	_message(b,{"t":"storage","action":"sleep","id":id})
	check(room.actors[b.id].bed=="" and room.actors[a.id].bed==id,"two players reaching the same camp cot get one occupant")
	_message(b,{"t":"storage","action":"carry","id":id})
	check(room.actors[a.id].bed==id and room.data.storage[id].mode=="ground","a public bed receives the player and stays put while occupied")
	var personal: Dictionary=room.data.survival[a.id]
	personal.health=47
	_tick_player(room,a.id,0,0,.08)
	check(personal.health>47,"the camp cot uses the same health recovery as the ferry")
	_message(a,{"t":"lake","action":"wake"})
	check(room.actors[a.id].point.distance_to(near_cot)<.001,"wake returns the player to the accessible side")
	_message(b,{"t":"storage","action":"sleep","id":id})
	check(room.actors[b.id].bed==id,"the next player can use the same cot as soon as it is vacated")
	_message(b,{"t":"lake","action":"wake"})
	var state: Dictionary=room.data.wildPeople
	for phase: String in ["companion","captive"]:
		var npc := WildPeople.make_person("rest-"+phase,0,"female",near_cot+Vector2(1.05,0),room.data.elapsed)
		npc.phase=phase
		npc.health=42
		npc.hunger=80
		npc.water=82
		npc.mood=71
		state.people[npc.id]=npc
		var result := people_motion.action(room,a.id,{"action":"bed","id":npc.id},grid)
		check(result.ok and npc.get("bedGoal","")==id,"arrange an actual bed for "+phase)
		for i in 260:
			room.data.elapsed += .04
			people_motion.tick(room,grid,.04)
			if npc.has("bed"):
				break
		check(npc.get("bed","")==id and npc.clip=="Sleep" and npc.health>42 and npc.phase==phase,phase+" reaches the mattress, lies down and heals")
		_message(b,{"t":"storage","action":"sleep","id":id})
		check(room.actors[b.id].bed=="","a player cannot take the sleeping resident's place")
		var restored := WildPeople.from_save(state,room.data.elapsed,grid)
		check(restored.people[npc.id].get("bed","")==id,phase+" bed assignment survives save/load")
		people_motion.action(room,a.id,{"action":"bed","id":npc.id},grid)
		check(not npc.has("bedGoal") and not Beds.claimed(room,id),phase+" leaves and releases the bed")
		state.people.erase(npc.id)
	var target := Vector2(9.8,-82.2)
	var actor: Dictionary=room.actors[a.id]
	actor.merge(PlayerMotion.spawn(target+Vector2(0,2.4)),true)
	personal=room.data.survival[a.id]
	personal.bag={"wood_plank":4,"rope":2,"wool":1}
	var direction := Vector3(target.x-actor.point.x,LakeLayout.walk_height(target)-actor.y-PlayerMotion.WALK_EYE,target.y-actor.point.y)
	var before: int=room.data.storage.size()
	_message(a,{"t":"storage","action":"build","recipe":Beds.KIND,"yaw":atan2(-direction.x,-direction.z),"pitch":atan2(direction.y,Vector2(direction.x,direction.z).length()),"rotation":.45})
	check(room.data.storage.size()==before+1 and room.data.survival[a.id].bag.is_empty(),"the build action places a rotated cot and charges exactly one recipe")
	var restored_storage := Storage.from_save(room.data.storage,room.data.elapsed,grid)
	check(restored_storage.size()==room.data.storage.size() and restored_storage[id].kind==Beds.KIND,"built and shared beds persist as furniture")

func _test_rigs() -> void:
	for key: String in ["ferryman","herbalist","fleece","shorn","lamb","grilled","wool"]:
		var packed: PackedScene = load("res://props/lake_life/"+key+".glb")
		var model := packed.instantiate() as Node3D
		root.add_child(model)
		var meshes := model.find_children("*","MeshInstance3D",true,false)
		check(meshes.size()==1, key+" contains just its own game mesh")
		for part: MeshInstance3D in meshes:
			var painted := true
			for i in part.mesh.get_surface_count():
				var material: BaseMaterial3D = part.mesh.surface_get_material(i)
				painted = painted and material.vertex_color_use_as_albedo and material.vertex_color_is_srgb
			check(painted,key+" displays its vertex paint on every surface")
		var anims := model.find_children("*","AnimationPlayer",true,false)
		if not anims.is_empty():
			var anim: AnimationPlayer = anims[0]
			var clips := ["Graze","Walk","Alert","Collapse","Dead"] if key in ["fleece","shorn"] else ["Moored","CastOff","Row","Land"]
			var all_clips := true
			for clip: String in clips:
				all_clips = all_clips and anim.has_animation(clip)
			check(all_clips,key+" imports every authored action")
			if key in ["ferryman","herbalist"]:
				var sk: Skeleton3D = model.find_children("*","Skeleton3D",true,false)[0]
				anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				anim.play("Row")
				var blade_min := INF
				var blade_max := -INF
				var grip_error := 0.0
				var signx := 1.0 if key=="ferryman" else -1.0
				var pin := Vector3(signx*(.630 if signx>0 else .610),.895 if signx>0 else .844,.115)
				var oar := sk.find_bone("Oar")
				for step in 53:
					anim.seek(2.6*step/53.0,true)
					anim.advance(0.0)
					var xf := sk.get_bone_global_pose(oar) * sk.get_bone_global_rest(oar).affine_inverse()
					var base := xf * pin
					var tip := xf * (pin+Vector3.RIGHT*signx*2.16)
					blade_min = minf(blade_min,tip.y+Ferry.DECK-Ferry.WATERLINE)
					blade_max = maxf(blade_max,tip.y+Ferry.DECK-Ferry.WATERLINE)
					for arm: String in ["HandL","HandR"]:
						var palm := sk.get_bone_global_pose(sk.find_bone(arm)).origin
						grip_error = maxf(grip_error,(palm-base).cross((tip-base).normalized()).length())
				check(grip_error<.025 and blade_min<-.04 and blade_max>.21,"%s grips %.3f m from shaft, blade %.3f to %.3f m relative to water" % [key,grip_error,blade_min,blade_max])
		model.free()

func _test_reed_harvest(room: Dictionary, a: Dictionary, b: Dictionary) -> void:
	var id := "116"
	var bank: Vector2 = Reeds.centers[id]
	var pick := {"t":"reed","id":id}
	var player: Dictionary = room.data.survival[a.id]
	player.bag = {}
	room.actors[a.id].merge(PlayerMotion.spawn(Storage.WORKBENCH),true)
	_message(a,pick)
	check(room.data.reedCuts.is_empty() and player.bag.is_empty(),"a remote reed patch cannot be harvested")
	room.actors[a.id].merge(PlayerMotion.spawn(bank),true)
	room.actors[b.id].merge(PlayerMotion.spawn(bank),true)
	player.bag = {"rope":1,"wood":1,"herb":1,"club":1,"stone":1,"apple":1}
	room.data.backpackOwner = ""
	_message(a,pick)
	check(room.data.reedCuts.is_empty() and not player.bag.has("reed_bundle"),"full bag leaves reed heads standing")
	player.bag = {}
	var folder := save_dir
	save_dir = folder.path_join(ROOM+".json")
	_message(a,pick)
	save_dir = folder
	check(room.data.reedCuts.is_empty() and not player.bag.has("reed_bundle"),"failed checkpoint restores both reeds and inventory")
	_message(a,pick)
	_message(b,pick)
	check(player.bag.get("reed_bundle",0)==1 and not room.data.survival[b.id].bag.has("reed_bundle"),"two players picking one stand receive one bundle")
	var harvested: float = room.data.elapsed
	check(samples[b.ws.get_instance_id()].reedCuts.get(id,-1)==harvested,"other player receives the cut patch")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(ROOM+".json")))
	check(is_equal_approx(float(Reeds.from_save(saved.reedCuts,saved.elapsed).get(id,-1)),harvested) and saved.survival[a.id].bag.get("reed_bundle",0)==1,"saved stubble and player harvest survive together")
	check(Reeds.from_save(null,harvested).is_empty() and Reeds.from_save({"fake":1,id:harvested+1},harvested).is_empty(),"legacy and invalid reed records normalize")
	# A different stand remains harvestable while the first one regrows.
	room.actors[a.id].merge(PlayerMotion.spawn(Reeds.centers["-85"]),true)
	_message(a,{"t":"reed","id":"-85"})
	check(player.bag.get("reed_bundle",0)==2 and room.data.reedCuts.size()==2,"neighbouring patches and inventory stacks are independent")
	room.actors[a.id].merge(PlayerMotion.spawn(Storage.WORKBENCH),true)
	_message(a,{"t":"storage","action":"craft","recipe":"reed_strips"})
	var bag: Dictionary = room.data.survival[a.id].bag
	check(bag.get("reed_bundle",0)==1 and bag.get("wicker_strip",0)==2,"one bundle makes two usable weaving strips at the bench")
	_message(a,{"t":"storage","action":"craft","recipe":"rope"})
	check(room.data.survival[a.id].bag.get("rope",0)==1,"reed strips work in the existing rope recipe")
	var found_fire := false
	for key: String in room.data.storage:
		if room.data.storage[key].kind != "campfire": continue
		found_fire = true
		var fire := Stones.unpack(room.data.storage[key].at)
		room.actors[a.id].merge(PlayerMotion.spawn(Vector2(fire.x+.65,fire.z)),true)
		room.data.storage[key].fuelUntil = 0.0
		_message(a,{"t":"storage","action":"fuel","id":key,"item":"reed_bundle"})
		check(room.data.survival[a.id].bag.get("reed_bundle",0)==0 and is_equal_approx(room.data.storage[key].fuelUntil,harvested+15),"one bundle fuels a shared fire for 15 seconds")
		break
	check(found_fire,"a usable campfire is in the fixture")
	room.actors[b.id].merge(PlayerMotion.spawn(bank),true)
	room.data.elapsed = harvested+Reeds.REGROW_SECONDS-.01
	_message(b,pick)
	check(not room.data.survival[b.id].bag.has("reed_bundle"),"cut stalks stay unavailable until the room clock reaches regrowth")
	room.data.elapsed = harvested+Reeds.REGROW_SECONDS
	_message(b,pick)
	check(room.data.survival[b.id].bag.get("reed_bundle",0)==1 and room.data.reedCuts[id]==room.data.elapsed,"regrown reeds can be harvested again")
	check(_load_room(ROOM) and Reeds.cut(id,rooms[ROOM].data.reedCuts,rooms[ROOM].data.elapsed)
		and rooms[ROOM].data.survival[b.id].bag.get("reed_bundle",0)==1,"restarting the room reloads the same harvest and cut stand")
