extends "res://server.gd"

const ROOM := "woodland-boar-test"
var failures := 0
var snapshots: Dictionary={}
var notes: Dictionary={}

func _initialize() -> void:
	verify.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _send(ws: WebSocketPeer, packet: Dictionary) -> bool:
	if packet.t=="snapshot":snapshots[ws.get_instance_id()]=packet.duplicate(true)
	if packet.t=="notice":notes[ws.get_instance_id()]=packet.duplicate()
	return true

func check(ok: bool, label: String) -> void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func join_peer(index: int) -> Dictionary:
	var con:={"ws":WebSocketPeer.new(),"room":"","id":"","rejected":false}
	connections[index]=con
	_message(con,{"t":"join","room":ROOM,"token":"%032x"%index})
	return con

func advance(room: Dictionary, seconds: float, clips: Dictionary) -> void:
	for i in ceili(seconds*50.):
		room.data.elapsed+=.02
		_tick_boar(ROOM,room,.02)
		clips[room.data.boar.clip]=true

func travel(room: Dictionary, con: Dictionary, at: Vector2) -> void:
	room.actors[con.id].merge(PlayerMotion.spawn(at),true)

func command(con: Dictionary, fields: Dictionary) -> void:
	fields.t="storage"
	_message(con,fields)

func verify() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:quit(2);return
	save_dir=args[0].path_join(str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(save_dir)
	world=JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid=Rules.collision_grid(world.obstacles)
	ship_grid=Spaceship.collision_grid(world)
	var a:=join_peer(1)
	var b:=join_peer(2)
	var room: Dictionary=rooms[ROOM]
	var clips:={}
	var walker:=PlayerMotion.spawn(Boar.HOME+Vector2(.03,.12))
	Boar.clear_body(walker,Boar.HOME+Vector2(0,.8),room.data.boar,grid)
	check(Boar.position(room.data.boar).distance_to(walker.point)>.60,"walking into the animal leaves the player outside its torso")
	advance(room,33.,clips)
	check(clips.has_all(["Forage","Walk","LieDown","Rest","Rise"]),"unattended boar forages, walks, lies down, breathes and rises")
	var p:=Boar.HOME
	room.data.boar=Boar.start(room.data.elapsed)
	travel(room,a,p+Vector2(-4.,0))
	advance(room,.02,clips)
	check(room.data.boar.clip=="Warn" and room.stone_sounds.back().cue=="boar_warn","approach triggers a spatial warning before contact")
	var yaw: float=room.data.boar.yaw
	travel(room,a,p+Vector2(-4.,2.5))
	advance(room,2.9,clips)
	check(room.data.survival[a.id].health==100 and clips.has_all(["Charge","Run"]) and is_equal_approx(room.data.boar.yaw,yaw),"sidestep dodges a committed charge and boar breaks into a run")
	room.data.boar=Boar.start(room.data.elapsed)
	travel(room,a,p+Vector2(-3.6,0))
	advance(room,.9,clips)
	check(room.data.survival[a.id].health==100,"health stays intact during the warning")
	advance(room,2.0,clips)
	check(is_equal_approx(room.data.survival[a.id].health,100.-Boar.DAMAGE),"one contact damages its target exactly once")
	_publish(ROOM)
	var first: Dictionary=snapshots[a.ws.get_instance_id()]
	var second: Dictionary=snapshots[b.ws.get_instance_id()]
	check(first.boar==second.boar and first.stoneSounds==second.stoneSounds,"both room members receive identical boar positions, clips and sound events")
	room.data.boar=Boar.start(room.data.elapsed)
	room.actors[a.id].onFerry=true
	advance(room,.12,clips)
	check(room.data.boar.clip=="Forage","passengers do not draw ground attacks")
	room.actors[a.id].onFerry=false
	var height:=LakeLayout.walk_height(p)
	var hit:=StorageWildlife.room_hit(room,Vector3(p.x,height+.58,p.y-2),Vector3(p.x,height+.58,p.y+2),.06)
	check(hit.get("species")=="boar","normal wildlife ray tests hit the live mesh")
	StorageWildlife.apply_hit(room,hit,16,grid)
	check(room.data.boar.get("disturbed",false),"surviving a hit startles the boar")
	StorageWildlife.apply_hit(room,hit,90,grid)
	StorageWildlife.apply_hit(room,hit,90,grid)
	var corpse: Dictionary=room.data.storage.get("corpse-boar",{})
	check(corpse.get("bag")=={"boar_raw":2,"boar_hide":1,"boar_tusk":2} and not Storage.corpse_ready(corpse,room.data.elapsed),"one carcass exposes the right materials after its collapse")
	travel(room,a,p+Vector2(.76,0))
	advance(room,1.02,clips)
	for item: String in ["boar_raw","boar_hide","boar_tusk","boar_tusk","boar_raw"]:
		command(a,{"action":"take","id":"corpse-boar","item":item})
	check(room.data.survival[a.id].bag.get("boar_tusk",0)==2 and room.data.storage["corpse-boar"].bag.is_empty(),"harvesting uses the shared container and removes each unit once")
	advance(room,.04,clips)
	check(not StorageWildlife.alive(room,"boar"),"harvesting does not immediately replace a hunt")
	room.data.elapsed+=Boar.RESPAWN_TIME
	advance(room,.02,clips)
	check(StorageWildlife.alive(room,"boar") and not room.data.storage.has("corpse-boar"),"an emptied carcass yields a new animal after fifteen active minutes")
	travel(room,a,Storage.WORKBENCH)
	room.data.survival[a.id].bag={"boar_tusk":2,"boar_hide":2,"wool":1,"rope":3,"boar_raw":1}
	for item: String in ["boar_cloak","tusk_whistle","boar_bedroll"]:
		command(a,{"action":"craft","recipe":item})
	var bag: Dictionary=room.data.survival[a.id].bag
	check(bag.has_all(["boar_cloak","tusk_whistle","boar_bedroll"]) and not bag.has("rope"),"camp bench produces all three finished goods at their recipe costs")
	_message(a,{"t":"provision","action":"wear","item":"boar_cloak"})
	var personal: Dictionary=room.data.survival[a.id]
	var bare:=personal.duplicate(true)
	bare.worn.boar_cloak=false
	Survival.tick(personal,p,false,1.,10)
	Survival.tick(bare,p,false,1.,10)
	check(personal.worn.boar_cloak and personal.worn.jacket and personal.mood>bare.mood,"wearing the mantle over the jacket reduces the rain mood penalty")
	var dog: Dictionary=room.data.dog
	dog.owner=a.id
	dog.mode="stay"
	travel(room,a,CampDog.position(dog)+Vector2(8,0))
	room.data.survival[b.id].bag.tusk_whistle=1
	travel(room,b,CampDog.position(dog)+Vector2(7,0))
	_message(b,{"t":"dog","action":"whistle"})
	check(dog.mode=="stay","another player's whistle cannot claim the dog")
	_message(a,{"t":"dog","action":"whistle"})
	check(dog.mode=="follow" and room.stone_sounds.back().cue=="tusk_whistle","owner's audible whistle changes the real dog's navigation target")
	for id: String in room.data.storage:
		var rec: Dictionary=room.data.storage[id]
		if rec.kind=="campfire":
			travel(room,a,Vector2(rec.at[0]+.60,rec.at[2]))
			rec.fuelUntil=room.data.elapsed+60
			command(a,{"action":"craft","recipe":"boar_grilled","id":id})
			break
	check(room.data.survival[a.id].bag.get("boar_grilled",0)==1,"the shared campfire cooks the shoulder cut")
	var field:=Vector2(40.,-76.)
	travel(room,a,field)
	command(a,{"action":"build","recipe":"lay_bedroll","yaw":0,"pitch":-.79,"rotation":0})
	var bed:=""
	for id: String in room.data.storage:
		if room.data.storage[id].kind==Beds.BEDROLL:bed=id
	check(not bed.is_empty() and room.data.survival[a.id].bag.get("boar_bedroll",0)==0,"aimed field placement consumes the carried roll outside camp")
	if not bed.is_empty():
		var seat:=Beds.socket(room,bed)
		for con: Dictionary in [a,b]:travel(room,con,seat.point+Vector2(.58,0))
		command(a,{"action":"sleep","id":bed})
		command(b,{"action":"sleep","id":bed})
		command(b,{"action":"pack_bedroll","id":bed})
		check(room.actors[a.id].bed==bed and room.actors[b.id].bed=="" and room.data.storage.has(bed),"occupied bedding stays in place and accepts only one sleeper")
		_message(a,{"t":"lake","action":"wake"})
		for phase: String in ["captive","companion"]:
			var npc:=WildPeople.make_person("test-"+phase,0,"female",seat.point+Vector2(.82,0),room.data.elapsed)
			npc.phase=phase
			npc.health=45.
			npc.bedGoal=bed
			npc.bedStarted=room.data.elapsed
			room.data.wildPeople.people[npc.id]=npc
			var slept:=people_motion._rest_at_cot(room,npc,grid,.1)
			check(slept and npc.get("bed")==bed and npc.health>45.,phase+" sleeps, claims one place and recovers health on the hide")
			WildPeople._leave_cot(npc,room.data.elapsed)
		command(b,{"action":"pack_bedroll","id":bed})
		check(not room.data.storage.has(bed) and room.data.survival[b.id].bag.get("boar_bedroll",0)==1,"a free bed rolls up once and can be shared")
	check(_checkpoint(ROOM) and _load_room(ROOM) and rooms[ROOM].data.survival[a.id].worn.boar_cloak and rooms[ROOM].data.has("boar"),"room reload preserves equipment and wildlife")
	print("BOAR_CHECKS failures=",failures)
	quit(1 if failures else 0)
