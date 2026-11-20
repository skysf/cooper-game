extends "res://server.gd"
## Run once as the server and once as two real loopback clients.
## Server accepts the same --port and --save options as the game. Clients take --clients=PORT.
const PROFILE_A := "nav-cold-a"
const PROFILE_B := "nav-cold-b"
const PROFILE_DOG := Vector2(0.05,-81.0)
const PROFILE_START := Vector2(1.92,-81.0)
const PROFILE_NPC := "cold-nav-companion"
const PROFILE_TOKENS := ["e1906440ad987bb5fe9bb2afed1ba517","9e98403b048cdb13ea22b366f6712fbb"]
const PROFILE_DURATION_MS := 15500

class Peer extends "res://network.gd":
	var times: Array[int] = []

	func _receive(message: Dictionary) -> void:
		super._receive(message)
		if message.get("t") == "snapshot" and ready_in_room:
			times.append(Time.get_ticks_usec())

var server_ready := 0
var started := 0
var server_boot_work := 0
var client_port := ""
var frame_data: Array = []
var cold_navigation := {}
var first_paths := {}
var load_work := {}
var client := {}
var a: Peer
var b: Peer
var phase := 0
var first_motion := 0
var previous_notice := 0
var npc_start := Vector2.ZERO
var dog_start := Vector2.ZERO
var room_b_dog := ""
var id_b := ""
var next_room_at := 0

func _initialize() -> void:
	started = Time.get_ticks_usec()
	client_port = _option("--clients=")
	if not client_port.is_empty():
		Engine.max_fps = 60
		var url := "ws://127.0.0.1:"+client_port
		a = Peer.new()
		b = Peer.new()
		root.add_child.call_deferred(a)
		root.add_child.call_deferred(b)
		a.start_room(url,PROFILE_A,PROFILE_TOKENS[0])
		b.start_room(url,PROFILE_B,PROFILE_TOKENS[1])
		return
	var folder := _option("--save=")
	if folder.is_empty() or DirAccess.make_dir_recursive_absolute(folder) != OK or not _seed_room(folder):
		printerr("Use a fresh --save= directory for the cold navigation fixture")
		quit(2)
		return
	var before := Time.get_ticks_usec()
	super._initialize()
	server_ready = Time.get_ticks_usec()
	server_boot_work = server_ready-before

func _option(prefix: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""

func _seed_room(folder: String) -> bool:
	if FileAccess.file_exists(folder.path_join(PROFILE_A+".json")) or FileAccess.file_exists(folder.path_join(PROFILE_B+".json")):
		return false
	var id := (PROFILE_A+":"+PROFILE_TOKENS[0]).sha256_text().left(16)
	var person := WildPeople.make_person(PROFILE_NPC,1,"male",WildPeople.HOME,0.0)
	person.phase = "companion"
	person.water = 40.0
	person.hunger = 90.0
	var room_people := WildPeople.initial(0.0)
	room_people.people[PROFILE_NPC] = person
	var data := {"version":1,"elapsed":0.0,"quest":{"wood":false,"tarp":false,"repaired":false},
		"homes":{id:{"x":PROFILE_START.x,"z":PROFILE_START.y,"yaw":-PI/2}},
		"survival":{id:Survival.initial_state()},"wildPeople":room_people,
		"dog":{"owner":id,"mode":"stay","x":PROFILE_DOG.x,"z":PROFILE_DOG.y,"yaw":-PI/2}}
	var file := FileAccess.open(folder.path_join(PROFILE_A+".json"),FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func _load_room(code: String) -> bool:
	var before := Time.get_ticks_usec()
	var opened := super._load_room(code)
	load_work[code] = Time.get_ticks_usec()-before
	return opened

func _process(delta: float) -> bool:
	if not client_port.is_empty():
		return _profile_clients()
	if server_ready == 0:
		return false
	var dog_had_map: bool = dog_motion.navigation != null
	var npc_had_map: bool = people_motion.navigator.navigation != null
	var before := Time.get_ticks_usec()
	super._process(delta)
	var work := Time.get_ticks_usec()-before
	var online_rooms := 0
	for room: Dictionary in rooms.values():
		if not room.actors.is_empty():
			online_rooms += 1
	var at := before-server_ready
	_record_first_paths(at,work)
	if online_rooms > 0:
		frame_data.append([at,work,roundi(delta*1000000.0),online_rooms])
	if not dog_had_map and dog_motion.navigation != null:
		cold_navigation.dog = [at,work]
	if not npc_had_map and people_motion.navigator.navigation != null:
		cold_navigation.npc = [at,work]
	if Time.get_ticks_usec()-server_ready >= 1000*PROFILE_DURATION_MS:
		print("COOP_NAV_COLD_SERVER ",JSON.stringify({"bootWorkUs":server_boot_work,"roomLoadUs":load_work,
			"inGameNavigationBuildFramesUs":cold_navigation,"firstPathFramesUs":first_paths,"framesUs":frame_data}))
		quit(0)
	return false

func _record_first_paths(at: int, work: int) -> void:
	if first_paths.size() == 2 or not rooms.has(PROFILE_A):
		return
	var room: Dictionary = rooms[PROFILE_A]
	if not first_paths.has("dog") and room.dog_route.has("path"):
		first_paths.dog = [at,work]
	if not first_paths.has("npc") and room.people_routes.get(PROFILE_NPC,{}).has("path"):
		first_paths.npc = [at,work]

func _profile_clients() -> bool:
	var now := Time.get_ticks_usec()
	if now-started > 1000*PROFILE_DURATION_MS:
		printerr("Cold navigation clients stalled in phase ",phase," ",a.status," / ",b.status," ",JSON.stringify(client))
		quit(1)
		return false
	if not client.has("aFirstSnapshotUs") and a.ready_in_room:
		client.aFirstSnapshotUs = a.times.front()-started
		print("PROFILE_CLIENT_FIRST_SNAPSHOT a")
	if not client.has("bFirstSnapshotUs") and b.ready_in_room:
		client.bFirstSnapshotUs = b.times.front()-started
		print("PROFILE_CLIENT_FIRST_SNAPSHOT b")
	if phase in [1,2,3] and (not a.ready_in_room or not b.ready_in_room):
		return false
	match phase:
		0:
			if not a.ready_in_room or not b.ready_in_room:
				return false
			if a.players.size() != 1 or b.players.size() != 1 or a.dog.owner != a.self_id or not b.dog.owner.is_empty():
				_fail("cold rooms must start independently with the saved dog only in A")
				return false
			client.firstSnapshotsUs = [a.times.front()-started,b.times.front()-started]
			id_b = b.self_id
			room_b_dog = b.dog.owner
			npc_start = _where(a.wild_people.people[PROFILE_NPC])
			dog_start = _where(a.dog)
			client.inputSentUs = now-started
			previous_notice = a.notice_number
			a.interact_dog("follow")
			phase = 1
		1:
			if a.notice_number <= previous_notice or a.last_notice_site != "dog":
				return false
			if a.dog.mode != "follow":
				_fail("first gameplay response must begin dog follow")
				return false
			client.inputReplyUs = now-started
			print("PROFILE_CLIENT_FIRST_INPUT_REPLY")
			a.set_motion(Vector2.RIGHT,-PI/2)
			b.set_motion(Vector2.RIGHT,-PI/2)
			first_motion = now
			phase = 2
		2:
			var a_at := _where(a.players[a.self_id])
			if not client.has("firstMotionReplyUs") and a_at.x > PROFILE_START.x+0.10:
				client.firstMotionReplyUs = now-first_motion
			if a_at.x > 6.42:
				a.set_motion(Vector2.ZERO,-PI/2)
				b.set_motion(Vector2.ZERO,-PI/2)
				client.farWalkUs = now-first_motion
				phase = 3
		3:
			var own := _where(a.players[a.self_id])
			var dog := _where(a.dog)
			var person := _where(a.wild_people.people[PROFILE_NPC])
			if dog.distance_to(own) > 1.85 or dog.distance_to(dog_start) < 2.5 or person.distance_to(npc_start) < 1.8:
				return false
			if b.dog.owner != room_b_dog or b.wild_people.people.has(PROFILE_NPC):
				_fail("walking in room A must not change the actors in room B")
				return false
			client.dogFollowMeters = dog.distance_to(dog_start)
			client.npcWalkMeters = person.distance_to(npc_start)
			client.farWalkMeters = own.distance_to(PROFILE_START)
			client.dogReachedGap = dog.distance_to(own)
			a.set_motion(Vector2.ZERO,-PI/2)
			b.start_room("ws://127.0.0.1:"+client_port,PROFILE_A,PROFILE_TOKENS[1])
			next_room_at = now
			phase = 4
		4:
			if not b.ready_in_room or a.players.size() != 2:
				return false
			if b.self_id == id_b or b.dog.owner != a.self_id or not b.wild_people.people.has(PROFILE_NPC):
				_fail("room switch must establish the second identity and preserve the shared dog")
				return false
			client.switchRoomUs = now-next_room_at
			client.snapshotTimesUs = [_client_times(a),_client_times(b)]
			print("COOP_NAV_COLD_CLIENTS ",JSON.stringify(client))
			quit(0)
	return false

func _where(sample: Dictionary) -> Vector2:
	return Vector2(sample.x,sample.z)

func _client_times(peer: Peer) -> Array:
	var relative := []
	for value: int in peer.times:
		relative.append(value-started)
	return relative

func _fail(message: String) -> void:
	printerr(message)
	quit(1)
