extends Node3D

const Network = preload("res://network.gd")
const Terrain = preload("res://terrain.gd")
const Weather = preload("res://atmosphere.gd")
const Hud = preload("res://hud.gd")
const Hiker = preload("res://hiker.gd")
const Stones = preload("res://stones.gd")
const StoneScene = preload("res://stone_scene.gd")
const LakeLayout = preload("res://lake_layout.gd")
const Survival = preload("res://survival.gd")
const Weapons = preload("res://weapons.gd")
const FollowCamera = preload("res://follow_camera.gd")
const CampDog = preload("res://camp_dog.gd")
const CampDogScene = preload("res://camp_dog_scene.gd")
const WildlifeScene = preload("res://wildlife_scene.gd")
const WildPeople = preload("res://wild_people.gd")
const WildPeopleScene = preload("res://wild_people_scene.gd")
const FieldAtlasPanel = preload("res://field_atlas_panel.gd")
const WildPeoplePanel = preload("res://wild_people_panel.gd")
const Spaceship = preload("res://spaceship.gd")
const SpaceshipScene = preload("res://spaceship_scene.gd")
const PlayerMotion = preload("res://player_motion.gd")
const CampAudio = preload("res://camp_audio.gd")
const EYE_HEIGHT := PlayerMotion.WALK_EYE
const VIEW_FOV := 78.0
const MOUSE_SENSITIVITY := .00215
const NEAR := 2.5
const DEFAULT_WS := "ws://127.0.0.1:4184/room"

var net := Network.new()
var terrain := Terrain.new()
var atlas := FieldAtlasPanel.new()
var atlas_resume_lock := false
var weather := Weather.new()
var hud := Hud.new()
var stone_scene := StoneScene.new()
var camp_audio := CampAudio.new()
var camera := Camera3D.new()
var follow_camera := FollowCamera.new()
var camp_dog: Node3D
var wildlife := WildlifeScene.new()
var people_scene := WildPeopleScene.new()
var people_panel := WildPeoplePanel.new()
var people_open := false
var people_target := ""
var source_target := ""
var tracked_source := ""
var last_people_log := 0
var trace_wild := false
var spaceship := SpaceshipScene.new()
var local_hiker: Node3D
var third_person := false
var follow_arm := -1.0
var first_person_view: bool:
	get:
		return not third_person or sight_blend > 0.0
var sight_blend := 0.0
var eye_height := EYE_HEIGHT
var world: Dictionary
var sites: Dictionary = {}
var body_pos := Vector2(1.9,-85)
var yaw := -.08
var pitch := .10
var locked := false
var prefer_tarp := false
var avatars := {}
var plan := ""
var nearby := ""
var ws_url := DEFAULT_WS
var room_code := "pine"
var zone_base := "http://127.0.0.1:4184/coop/zones/"
var join_token := ""
var invite_url := ""
var hud_clock := 0.
var web := OS.has_feature("web")
var preview_warming := false
var web_join
var web_document
var telemetry_clock := 0.
var last_log := ""
var status_record: FileAccess
var last_flags := -1
var setup_ok := false
var field_entered := false
var leg_phase := 0.
var held_stone := ""
var pickup_stone := ""
var stone_action := ""
var grindstone_target := false
var newest_impact := 0
var water_room_time := -1.0
var backpack_open := false
var backpack_resume_lock := false
var displayed_provisions: Dictionary = {}
var food_target := ""
var jug_target := false
var backpack_target := false
var dog_target := false
var ship_target := false
var was_piloting := false
var chase_ship := true
var ship_view_yaw := PI
var ship_view_pitch := -0.14
var ship_camera_arm := -1.0

func _ready() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	follow_camera.configure(world)
	for key in world.sites:
		var p: Array = world.sites[key]
		sites[key] = Vector2(p[0],p[1])
	body_pos = Vector2(world.spawn[0],world.spawn[1])
	_read_join()
	add_child(camera)
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = VIEW_FOV
	camera.near = .07
	camera.far = 105
	camera.cull_mask &= ~WildPeopleScene.WARM_LAYER
	camera.current = true
	camera.position = Vector3(body_pos.x,EYE_HEIGHT,body_pos.y)
	camera.rotation = Vector3(pitch,yaw,0)
	terrain.configure(zone_base)
	add_child(terrain)
	terrain.update_focus(camera.position)
	add_child(weather)
	add_child(stone_scene)
	camp_audio.configure(world.route)
	add_child(camp_audio)
	add_child(wildlife)
	add_child(people_scene)
	add_child(spaceship)
	net.process_priority = -10
	add_child(net)
	net.start_room(ws_url,room_code,join_token)
	add_child(hud)
	add_child(atlas)
	atlas.close_requested.connect(_set_atlas.bind(false))
	atlas.travel_requested.connect(net.travel_to)
	atlas.pin_requested.connect(net.place_atlas_pin)
	atlas.remove_requested.connect(net.remove_atlas_pin)
	net.atlas_reply.connect(_atlas_reply)
	add_child(people_panel)
	people_panel.close_requested.connect(_set_people.bind(false))
	people_panel.action_requested.connect(_person_action)
	people_panel.locate_requested.connect(_locate_source)
	hud.resume_requested.connect(_capture)
	hud.invite_requested.connect(_invite)
	hud.backpack_close_requested.connect(_set_backpack.bind(false))
	hud.backpack_action_requested.connect(_use_backpack)
	if web:
		terrain.prepare_exhaust_warmup(spaceship.lift_jets[0].mesh, spaceship.lift_material)
		preview_warming = true
		_warm_character_preview.call_deferred()
	setup_ok = true

func _warm_character_preview() -> void:
	await terrain.wait_for_lantern_warmup()
	await _warm_world_views()
	await get_tree().process_frame
	var equipped_pack := _bag_slots() > Survival.SLOT_COUNT
	var slot := int(net.players.get(net.self_id, {}).get("slot", 1))
	hud.set_equipment(net.survival, equipped_pack, slot)
	await hud.character_preview.warm_up(hud.worn, equipped_pack, slot)
	await people_scene.warm_up()
	preview_warming = false

func _warm_world_views() -> void:
	# The default camp view cannot submit all the material variants seen on the trail.
	var preview := SubViewport.new()
	preview.size = Vector2i(160, 90)
	preview.world_3d = get_world_3d()
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(preview)
	var lens := Camera3D.new()
	lens.keep_aspect = camera.keep_aspect
	lens.fov = camera.fov
	lens.near = camera.near
	preview.add_child(lens)
	lens.make_current()
	var traveler := Hiker.new()
	preview.add_child(traveler)
	traveler.position = Vector3(-0.3, 0.0, -83.2)
	traveler.outfit(1)
	traveler.wear_clothes(Survival.initial_wear())
	traveler.wear_backpack(true)
	var rain_preview := MultiMeshInstance3D.new()
	rain_preview.multimesh = weather.rain.multimesh
	rain_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.add_child(rain_preview)
	rain_preview.position = Vector3(1.9, 1.7, -85.0)
	var lookout := LakeLayout.Coast.point("lookout")
	var eye := Vector3(lookout.x, LakeLayout.Coast.height(lookout) + EYE_HEIGHT, lookout.y)
	var views: Array[Array] = [
		[Vector3(1.9, 1.7, -85.0), Vector3(-4.0, 1.8, -80.0), 105.0],
		[Vector3(-3.0, 1.7, -80.5), Vector3(-18.0, 2.1, -80.5), 105.0],
		[Vector3(-10.0, 1.7, -79.0), Vector3(-15.0, 1.9, -68.0), 105.0],
		[Vector3(-14.0, 1.7, -75.0), Vector3(-25.0, 1.4, -58.0), 105.0],
		[eye, Vector3(lookout.x - 35.0, 0.0, lookout.y), 290.0],
		[eye, eye + Vector3(9.0, -1.6, -5.0), 290.0],
		[Vector3(-83.0, 14.2, -39.8), Vector3(-91.0, 12.6, -45.0), 290.0],
		[Vector3(-88.0, 6.1, -46.0), Vector3(-77.0, 4.3, -49.0), 290.0],
		[Vector3(-89.0, 1.7, -51.8), Vector3(-120.0, 0.5, -54.0), 290.0],
	]
	for view: Array in views:
		lens.position = view[0]
		lens.look_at(view[1])
		lens.far = view[2]
		preview.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
	preview.queue_free()
	await preview.tree_exited

func _read_join() -> void:
	if web:
		web_document = JavaScriptBridge.get_interface("document")
		web_join = JavaScriptBridge.get_interface("CooperJoin")
		trace_wild = bool(JavaScriptBridge.eval("Boolean(window.__CooperWildTrace)"))
		people_scene.trace_enabled = trace_wild
		net.trace_enabled = trace_wild
		if trace_wild:
			JavaScriptBridge.eval("window.__CooperWildCpu=[];window.__CooperWildEvents=[]")
		var join = web_join
		if join != null:
			if join.url != null and not str(join.url).is_empty():
				ws_url = str(join.url)
			if join.room != null and not str(join.room).is_empty():
				room_code = str(join.room)
			if join.token != null:
				join_token = str(join.token)
			if join.zoneBase != null and not str(join.zoneBase).is_empty():
				zone_base = str(join.zoneBase)
			else:
				zone_base = str(JavaScriptBridge.eval("location.origin+'/coop/zones/'"))
		invite_url = str(JavaScriptBridge.eval("location.origin+location.pathname")) + "?room=" + room_code.uri_encode()
		if join != null and join.inviteUrl != null and not str(join.inviteUrl).is_empty():
			invite_url = str(join.inviteUrl)
	else:
		var explicit_zones := false
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--room="):
				room_code = arg.trim_prefix("--room=")
			elif arg.begins_with("--url="):
				ws_url = arg.trim_prefix("--url=")
			elif arg.begins_with("--invite-url="):
				invite_url = arg.trim_prefix("--invite-url=")
			elif arg.begins_with("--token="):
				join_token = arg.trim_prefix("--token=")
			elif arg.begins_with("--qa-status-file="):
				var status_path := arg.trim_prefix("--qa-status-file=")
				if not FileAccess.file_exists(status_path):
					status_record = FileAccess.open(status_path, FileAccess.WRITE)
			elif arg.begins_with("--zone-base="):
				zone_base = arg.trim_prefix("--zone-base=")
				explicit_zones = true
		var authority := ws_url.replace("wss://","https://").replace("ws://","http://").get_slice("://",1).get_slice("/",0)
		var scheme := "https://" if ws_url.begins_with("wss:") else "http://"
		var origin := scheme + authority
		if invite_url.is_empty():
			invite_url = origin + "/coop/?room=" + room_code.uri_encode()
		if not explicit_zones:
			zone_base = origin + "/coop/zones/"

func _invite() -> void:
	if web:
		return
	hud.show_invite(invite_url)
	DisplayServer.clipboard_set(invite_url)

func _mouse_locked() -> bool:
	if web:
		return web_join != null and bool(web_join.pointerLocked)
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _capture() -> void:
	if backpack_open or people_open or atlas.is_open or not _playable() or _mouse_locked():
		return
	if not web:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _release() -> void:
	if web:
		if _mouse_locked():
			web_document.exitPointerLock()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	net.set_motion(Vector2.ZERO,yaw)
	net.aim_pitch = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and setup_ok and not web:
		_release()

func _set_atlas(open: bool) -> void:
	if atlas.is_open == open or open and not _playable():
		return
	if open:
		atlas_resume_lock = _mouse_locked() or backpack_open and backpack_resume_lock
	atlas.set_open(open)
	if open:
		_set_backpack(false)
		_set_people(false)
	hud.modal_open = open
	if web and web_join != null:
		web_join.setAtlasOpen(open)
	get_viewport().disable_3d = open
	if open:
		locked = false
		net.blocking = false
		_release()
	elif atlas_resume_lock and net.ready_in_room:
		if web and web_join != null:
			web_join.resumeFromAtlas()
		else:
			_capture()

func _atlas_reply(action: String, accepted: bool, text: String) -> void:
	atlas.reply(action, text)
	if action == "travel" and accepted:
		eye_height = float(net.player_motion.y) + PlayerMotion.eye_offset(net.player_motion.swimming)
		follow_arm = -1.0
		ship_camera_arm = -1.0
		_set_atlas(false)
		hud.say(text)

func _set_backpack(open: bool) -> void:
	if backpack_open == open:
		return
	if open and (not _playable() or net.is_piloting() or net.survival.is_empty()):
		return
	if open and people_open:
		_set_people(false)
	if open:
		backpack_resume_lock = _mouse_locked()
		hud.set_equipment(net.survival, _bag_slots() > Survival.SLOT_COUNT, int(net.players.get(net.self_id, {}).get("slot", 1)))
	backpack_open = open
	hud.set_backpack_open(open, net.survival.get("bag", {}), Survival.can_put(body_pos), _bag_slots())
	if web and web_join != null:
		web_join.setBackpackOpen(open or people_open)
	if open:
		_release()
	elif not web and backpack_resume_lock:
		_capture()

func _input(event: InputEvent) -> void:
	if not setup_ok or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_M and not (event.alt_pressed or event.ctrl_pressed or event.meta_pressed):
		_set_atlas(not atlas.is_open)
		get_viewport().set_input_as_handled()
		return
	if atlas.is_open:
		match event.physical_keycode:
			KEY_ESCAPE:
				_set_atlas(false)
			KEY_EQUAL, KEY_KP_ADD:
				atlas.zoom_step(true)
			KEY_MINUS, KEY_KP_SUBTRACT:
				atlas.zoom_step(false)
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if event.physical_keycode == KEY_B and not (event.alt_pressed or event.ctrl_pressed or event.meta_pressed):
		_set_people(not people_open)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and people_open:
		_set_people(false)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_TAB and not (event.alt_pressed or event.ctrl_pressed or event.meta_pressed) and (backpack_open or not net.survival.is_empty()):
		_set_backpack(not backpack_open)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and backpack_open:
		_set_backpack(false)
		get_viewport().set_input_as_handled()

func _use_backpack(action: String, item: String) -> void:
	if backpack_open:
		if action == "equip":
			net.interact_person("unequip" if net.survival.get("weapon") == item else "equip", item)
		else:
			net.interact_provision(action, item)

func _set_people(open: bool) -> void:
	if people_open == open or open and (not _playable() or net.is_piloting()):
		return
	if open and backpack_open:
		_set_backpack(false)
	people_open = open
	hud.modal_open = open
	people_panel.set_open(open, people_target if open else "")
	if web and web_join != null:
		web_join.setBackpackOpen(open or backpack_open)
	if open:
		_release()
		net.blocking = false
		locked = false
		net.set_motion(Vector2.ZERO, yaw)
		people_panel.refresh(net.wild_people, net.survival, body_pos, net.elapsed, net.last_notice, net.notice_number)

func _person_action(action: String, item: String, id: String) -> void:
	if people_open:
		net.interact_person(action, item, id)

func _locate_source(source: String) -> void:
	tracked_source = source
	_set_people(false)
	hud.say("已定位" + WildPeople.SOURCES[source].name + "；循罗盘走近后按 F")

func _attack() -> void:
	var weapon: String = net.survival.get("weapon", "")
	var attack_yaw := yaw
	var attack_pitch := pitch
	if not first_person_view:
		var reach: float = Weapons.stats(weapon).reach
		var look := Basis.from_euler(Vector3(_follow_pitch(), yaw, 0.0))
		var destination := camera.position - look.z * (maxf(5.0, reach) + maxf(follow_arm, 0.0))
		var nearest := INF
		for npc: Dictionary in net.wild_people.get("people", {}).values():
			var hit := WildPeople.ray_hit(npc, camera.position, destination)
			if not hit.is_empty() and float(hit.distance) < nearest:
				nearest = hit.distance
		if nearest < INF:
			destination = camera.position - look.z * sqrt(nearest)
		var origin := Vector3(body_pos.x, float(net.player_motion.y) + PlayerMotion.eye_offset(net.player_motion.swimming), body_pos.y)
		var direction := origin.direction_to(destination)
		attack_yaw = atan2(-direction.x, -direction.z)
		attack_pitch = asin(clampf(direction.y, -1.0, 1.0))
	net.attack_person(yaw, attack_yaw, attack_pitch)

func _look_fov(weapon: String) -> float:
	return lerpf(VIEW_FOV, Weapons.stats(weapon).get("aim_fov", VIEW_FOV), smoothstep(0.0, 1.0, sight_blend))

func _bag_slots() -> int:
	return Survival.slot_count(net.backpack_enabled and not net.backpack_owner.is_empty() and net.backpack_owner == net.self_id)

func _unhandled_input(event: InputEvent) -> void:
	if not setup_ok or backpack_open or people_open or atlas.is_open:
		return
	if event is InputEventMouseMotion and _mouse_locked():
		var motion: Vector2 = event.screen_relative
		var fov := _look_fov(net.survival.get("weapon", ""))
		var sensitivity := MOUSE_SENSITIVITY * tan(deg_to_rad(fov * 0.5)) / tan(deg_to_rad(VIEW_FOV * 0.5))
		yaw = wrapf(yaw - motion.x * sensitivity, -PI, PI)
		pitch = clampf(pitch - motion.y * sensitivity, -1.44, 1.51)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _mouse_locked() and not net.is_piloting():
			if not held_stone.is_empty():
				net.interact_stone("throw", "", yaw, _follow_pitch() if third_person else pitch)
			else:
				_attack()
		else:
			_capture()
	elif event is InputEventKey and event.pressed and not event.echo:
		if locked and net.is_piloting() and event.physical_keycode != KEY_ESCAPE:
			if event.physical_keycode == KEY_E:
				net.interact_ship("exit")
			elif event.physical_keycode == KEY_V:
				chase_ship = not chase_ship
				ship_camera_arm = -1.0
			return
		match event.physical_keycode:
			KEY_ESCAPE:
				if not web:
					_release()
			KEY_E:
				if locked:
					if not people_target.is_empty():
						_set_people(true)
					elif ship_target and net.ship.get("pilot", "") == "":
						net.interact_ship("board")
					elif backpack_target:
						net.interact_provision("take_backpack")
					elif net.provisions.has(food_target):
						net.interact_provision("take", str(net.provisions[food_target].item), food_target)
					elif dog_target:
						var action := CampDog.command(net.dog, net.self_id)
						if not action.is_empty():
							net.interact_dog(action)
					elif not pickup_stone.is_empty():
						net.interact_stone("pick", pickup_stone)
					elif grindstone_target:
						_show_grindstone_help()
					elif not nearby.is_empty():
						net.interact(nearby)
			KEY_F:
				if locked and not dog_target:
					if net.survival.get("health", 100.0) <= 0.0:
						net.interact_person("respawn")
					elif not source_target.is_empty():
						net.interact_person("gather", source_target)
					elif not food_target.is_empty():
						var item: String = net.provisions[food_target].item
						if Survival.is_drinkable(item):
							net.interact_provision("drink_table", item, food_target)
						elif Survival.FOOD_STATS.has(item):
							net.interact_provision("eat_table", item, food_target)
					elif jug_target:
						net.interact_provision("drink")
					elif not stone_action.is_empty():
						net.interact_stone("context")
					elif grindstone_target:
						_show_grindstone_help()
					elif not pickup_stone.is_empty():
						hud.say("按 E 捡起扁石片" if Stones.flat(pickup_stone) else "按 E 捡起圆石")
			KEY_G:
				if locked and not held_stone.is_empty():
					net.interact_stone("drop")
			KEY_Q:
				if locked:
					prefer_tarp = not prefer_tarp
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_6, KEY_7, KEY_8:
				if locked:
					net.interact_person("equip", Weapons.KEYS[event.physical_keycode])
			KEY_5:
				if locked:
					net.interact_person("shield")
			KEY_V:
				if locked:
					third_person = not third_person
					follow_arm = -1.0

func _physics_process(_delta: float) -> void:
	if not setup_ok:
		return
	locked = _mouse_locked() and not backpack_open and not people_open and not atlas.is_open
	if locked and _playable():
		field_entered = true
	var move := Vector2.ZERO
	var lift := 0.0
	var piloting := net.is_piloting()
	var right_mouse := locked and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var firearm := Weapons.firearm(net.survival.get("weapon", ""))
	net.blocking = right_mouse and not firearm
	net.aim_pitch = pitch if right_mouse and firearm and _can_aim(piloting, net.player_motion.swimming) else null
	if locked and net.ready_in_room and net.survival.get("health", 100.0) > 0.0 and (field_entered or piloting or terrain.is_focus_ready()):
		var sideways := float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
		var forward := float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))
		move = Vector2(sideways, -forward).rotated(-ship_view_yaw if piloting else -yaw).limit_length()
		lift = float(Input.is_physical_key_pressed(KEY_SPACE))
		if piloting or net.player_motion.swimming:
			lift -= float(Input.is_physical_key_pressed(KEY_C))
	net.set_motion(move, yaw, lift)

func _can_aim(piloting: bool, swimming: bool) -> bool:
	return (locked and net.ready_in_room and not (piloting or swimming)
		and net.survival.get("health", 0.0) > 0.0 and held_stone.is_empty())

func _process(delta: float) -> void:
	if not setup_ok:
		return
	var trace_start := Time.get_ticks_usec() if trace_wild else 0
	var trace_marks: Variant = [] if trace_wild else null
	locked = _mouse_locked() and not backpack_open and not people_open and not atlas.is_open
	if people_open and not net.ready_in_room:
		_set_people(false)
	if backpack_open and not net.ready_in_room:
		_set_backpack(false)
	if atlas.is_open:
		atlas.sync(net.self_id, net.players, net.local_position, yaw, net.atlas_pins, net.atlas_available and net.ready_in_room)
	if locked and not net.ready_in_room:
		_release()
		locked = false
	if not net.ready_in_room:
		field_entered = false
	var previous := body_pos
	if net.ready_in_room:
		body_pos = net.local_position
	var piloting := net.is_piloting()
	var swimming: bool = net.ready_in_room and net.player_motion.swimming
	var weapon: String = net.survival.get("weapon", "")
	if Weapons.firearm(weapon) and _can_aim(piloting, swimming):
		var aimed := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		sight_blend = move_toward(sight_blend, float(aimed), delta * 7.5)
	else:
		sight_blend = 0.0
	hud.set_weapon_view(weapon, sight_blend, locked)
	var actor_height := float(net.player_motion.y) if net.ready_in_room else LakeLayout.walk_height(body_pos)
	if piloting != was_piloting:
		follow_arm = -1.0
		ship_camera_arm = -1.0
		if piloting:
			yaw = float(net.ship.yaw)
			pitch = -0.14
			ship_view_yaw = yaw
			ship_view_pitch = pitch
			chase_ship = true
		else:
			eye_height = actor_height + PlayerMotion.eye_offset(swimming)
		was_piloting = piloting
	spaceship.sync(net.rendered_ship(), net.elapsed, delta, piloting)
	var stride := minf(body_pos.distance_to(previous),.18)
	leg_phase += stride * 4.7
	var bob := sin(leg_phase*2.) * .019 * clampf(stride / maxf(delta,.001),0.,1.)
	var height := actor_height + PlayerMotion.eye_offset(swimming) + bob
	eye_height = lerpf(eye_height, height, minf(delta * 15.0, 1.0))
	var eye := Vector3(body_pos.x, eye_height, body_pos.y)
	if piloting:
		_update_ship_camera(delta)
	else:
		var view_eye := eye.lerp(Vector3(body_pos.x, height - bob, body_pos.y), sight_blend)
		_update_camera(view_eye, delta, swimming, _look_fov(weapon))
	var coastal_view := smoothstep(34.0, 73.0, -camera.position.x)
	camera.far = lerpf(105.0, 290.0, coastal_view)
	terrain.update_focus(spaceship.position if piloting else eye)
	if net.ready_in_room:
		terrain.grove.set_room_time(net.grove_elapsed)
	var wood := bool(net.quest.get("wood",false))
	var tarp := bool(net.quest.get("tarp",false))
	var repaired := bool(net.quest.get("repaired",false))
	var flags := int(wood) + int(tarp)*2 + int(repaired)*4
	if flags != last_flags:
		last_flags = flags
		terrain.set_quest(wood,tarp,repaired)
	terrain.update_flame(net.elapsed, delta)
	terrain.set_wet(net.rain)
	var camera_water := LakeLayout.surface_height(Vector2(camera.position.x, camera.position.z))
	weather.update_weather(camera.position, ship_view_yaw if piloting else yaw, net.elapsed, net.rain,
		repaired, camera.position.y < camera_water - 0.035, camera_water - camera.position.y, coastal_view)
	_update_water()
	if trace_wild:
		trace_marks.append(["world", Time.get_ticks_usec() - trace_start])
	_sync_hikers(delta)
	if trace_wild:
		trace_marks.append(["hikers", Time.get_ticks_usec() - trace_start])
	_update_stones()
	camp_audio.update_world(net, avatars, camera, spaceship.position, delta, locked)
	_update_provisions()
	_update_dog(delta)
	_update_ship_target()
	wildlife.sync(net.crocodile if net.ready_in_room else {}, net.elapsed, eye, delta)
	if trace_wild:
		trace_marks.append(["other_scene", Time.get_ticks_usec() - trace_start])
	people_scene.sync(net.wild_people.get("people", {}) if net.ready_in_room and not preview_warming else {}, net.elapsed, delta, camera.position, people_target)
	if trace_wild:
		trace_marks.append(["people", Time.get_ticks_usec() - trace_start])
	people_scene.sync_sources(net.wild_people, camera.position)
	people_scene.equip_players(net.players, avatars, net.self_id, camera,
		null if first_person_view else local_hiker, delta, net.elapsed, swimming or piloting, sight_blend)
	if trace_wild:
		trace_marks.append(["gear_sources", Time.get_ticks_usec() - trace_start])
	_update_people_target()
	var own_bag: Dictionary = net.survival.get("bag", {})
	var own_wood := int(own_bag.get("wood", 0)) > 0
	var own_tarp := int(own_bag.get("tarp", 0)) > 0
	nearby = _reachable(wood,tarp,repaired and net.wild_people.get("facility", 100.0) >= 100.0)
	plan = _goal(own_wood,own_tarp)
	hud_clock -= delta
	telemetry_clock -= delta
	if hud_clock <= 0.0:
		hud_clock = .12
		var state := _state()
		hud.refresh(state,plan,sites[plan]-body_pos,_interaction_prompt(own_wood and own_tarp))
		people_panel.refresh(net.wild_people, net.survival, body_pos, net.elapsed, net.last_notice, net.notice_number)
		if not tracked_source.is_empty():
			var source: Dictionary = WildPeople.SOURCES[tracked_source]
			var offset := Vector2(source.x, source.z) - body_pos
			hud.bearing.text = source.name
			hud.bearing_distance.text = "%d m" % roundi(offset.length())
			var relative := wrapf(atan2(-offset.x, -offset.y) - yaw, -PI, PI)
			hud.bearing_arrow.text = "↑" if absf(relative) < .32 else "身后" if absf(relative) > 2.72 else "←" if relative > 0 else "→"
		if telemetry_clock <= 0.0:
			telemetry_clock = .25
			if trace_wild:
				trace_marks.append(["hud", Time.get_ticks_usec() - trace_start])
			_publish(state)
			if trace_wild:
				trace_marks.append(["publish", Time.get_ticks_usec() - trace_start])
	if trace_wild:
		var total := Time.get_ticks_usec() - trace_start
		if total > 8000:
			var sample := {"wall": Time.get_unix_time_from_system() * 1000.0, "event": "client-frame", "totalUs": total, "stages": trace_marks, "elapsed": net.elapsed}
			JavaScriptBridge.eval("window.__CooperWildCpu.push(" + JSON.stringify(sample) + ");if(window.__CooperWildCpu.length>512)window.__CooperWildCpu.shift()")

func _follow_pitch() -> float:
	return clampf(pitch - 0.32, -0.73, 0.14)

func _update_ship_camera(delta := 1.0 / 60.0) -> void:
	var turn_blend := 1.0 - exp(-delta * 24.0)
	ship_view_yaw = wrapf(lerp_angle(ship_view_yaw, yaw, turn_blend), -PI, PI)
	ship_view_pitch = lerpf(ship_view_pitch, pitch, turn_blend)
	var view_pitch := clampf(ship_view_pitch - 0.19, -0.91, 0.18) if chase_ship else clampf(ship_view_pitch, -0.84, 0.91)
	camera.basis = Basis.from_euler(Vector3(view_pitch, ship_view_yaw, 0.0))
	if chase_ship:
		var pivot: Vector3 = spaceship.position + Vector3.UP * 1.22
		var offset := camera.basis.z * 6.65
		var clear := net.ship_camera_clearance(pivot, offset)
		if ship_camera_arm < 0.0:
			ship_camera_arm = clear
		else:
			ship_camera_arm = lerpf(ship_camera_arm, clear, 1.0 - exp(-delta * (26.0 if clear < ship_camera_arm else 7.0)))
		camera.position = pivot + offset.normalized() * ship_camera_arm
	else:
		camera.position = spaceship.cockpit_eye()
	camera.fov = VIEW_FOV
	camera.near = 0.07

func _update_ship_target() -> void:
	ship_target = false
	if net.ship.is_empty() or not net.ready_in_room or net.is_piloting() or not terrain.is_focus_ready():
		return
	if not net.ship.landed or body_pos.distance_squared_to(Spaceship.point(net.ship)) > Spaceship.BOARD_RANGE ** 2:
		return
	var direction := camera.position.direction_to(spaceship.position + Vector3.UP * 0.85)
	ship_target = (-camera.basis.z).dot(direction) > 0.86

func _update_camera(eye: Vector3, delta: float, swimming := false, fov := VIEW_FOV) -> void:
	if first_person_view:
		camera.position = eye
		camera.rotation = Vector3(pitch, yaw, 0.0)
		camera.fov = fov
		camera.near = 0.07
		return
	var basis := Basis.from_euler(Vector3(_follow_pitch(), yaw, 0.0))
	var pivot := eye + Vector3.DOWN * (0.10 if swimming else EYE_HEIGHT - 1.06)
	var offset := basis.z * 3.55 + basis.x * 0.71
	if swimming and eye.y < LakeLayout.water_y() - 0.055:
		offset.y = minf(offset.y, LakeLayout.water_y() - 0.055 - pivot.y)
	var clear := follow_camera.clear_distance(pivot, offset)
	follow_arm = clear if follow_arm < 0.0 else minf(clear, lerpf(follow_arm, clear, minf(delta * 9.0, 1.0)))
	camera.position = pivot + offset.normalized() * follow_arm
	camera.basis = basis
	camera.fov = lerpf(112.0, VIEW_FOV, smoothstep(0.75, 3.0, follow_arm))
	camera.near = 0.04

func _update_stones() -> void:
	stone_scene.update_stones(net.stones, avatars, net.self_id, camera, net.elapsed, net.rain, net.line_cut, local_hiker if third_person else null, net.player_motion.swimming)
	held_stone = Stones.held_by(net.stones, net.self_id)
	pickup_stone = ""
	stone_action = ""
	grindstone_target = false
	if not net.ready_in_room or not terrain.is_focus_ready():
		return
	var forward := -camera.basis.z
	var grind_at := Vector3(Stones.GRIND.x, Stones.GRIND_HEIGHT, Stones.GRIND.y)
	var grind_facing := forward.dot(camera.position.direction_to(grind_at))
	grindstone_target = body_pos.distance_squared_to(Stones.GRIND) <= 3.3 ** 2 and grind_facing > 0.96
	if not held_stone.is_empty():
		stone_action = Stones.context_action(held_stone, net.stones[held_stone], body_pos, net.line_cut)
		if grindstone_target and stone_action != "grind":
			stone_action = ""
		if stone_action == "press":
			for stone: Dictionary in net.stones.values():
				if stone.mode == "placed":
					stone_action = ""
					break
		return
	var best := grind_facing if grindstone_target else 0.90
	for id: String in net.stones:
		var stone: Dictionary = net.stones[id]
		if not Stones.is_pickable(stone):
			continue
		var at := Stones.unpack(stone.at)
		if body_pos.distance_squared_to(Vector2(at.x, at.z)) > Stones.PICKUP_REACH ** 2:
			continue
		var facing := forward.dot(camera.position.direction_to(at))
		if facing > best:
			pickup_stone = id
			best = facing

func _update_water() -> void:
	terrain.update_water(net.elapsed, net.rain, {
		"sun_direction": weather.sun_direction, "moon_direction": weather.moon_direction,
		"sun_energy": weather.sun_energy,
		"sky_zenith": weather.sky_zenith, "sky_horizon": weather.sky_horizon,
		"sun_color": weather.sun_color, "moon_color": weather.moon_color, "cloud_cover": weather.cloud_cover,
		"twilight": weather.twilight, "evening_weight": weather.evening_weight,
		"underwater": weather.underwater,
	})
	if not net.ready_in_room or net.elapsed + 0.15 < water_room_time:
		if newest_impact > 0:
			terrain.reset_water()
		newest_impact = 0
	water_room_time = net.elapsed
	for impact: Dictionary in net.water_impacts:
		if int(impact.id) > newest_impact:
			terrain.add_water_impact(Stones.unpack(impact.point), float(impact.at))
			newest_impact = int(impact.id)

func _update_provisions() -> void:
	if displayed_provisions != net.provisions:
		displayed_provisions = net.provisions
		terrain.set_provisions(displayed_provisions)
	food_target = ""
	jug_target = false
	backpack_target = false
	var pack_available := net.ready_in_room and net.backpack_enabled and net.backpack_owner.is_empty()
	terrain.household.show_ground_backpack(pack_available)
	if not net.ready_in_room or not terrain.is_focus_ready() or net.survival.is_empty():
		return
	var best := 0.985
	var forward := -camera.basis.z
	for id: String in net.provisions:
		var food: Dictionary = net.provisions[id]
		var at := Stones.unpack(food.at)
		if not Survival.can_reach(body_pos, Vector2(at.x, at.z), str(food.surface)):
			continue
		var aim_point: Vector3 = terrain.household.pickup_point(id, at, camera.position, forward)
		var score := forward.dot(camera.position.direction_to(aim_point))
		if score > best:
			food_target = id
			best = score
	if Survival.can_drink(body_pos):
		var jug := Vector3(Survival.JUG.x, Survival.TABLE_TOP + 0.14, Survival.JUG.y)
		var score := forward.dot(camera.position.direction_to(jug))
		if score > best:
			food_target = ""
			jug_target = true
			best = score
	if pack_available and Survival.can_reach(body_pos, Survival.BACKPACK, "ground"):
		var pack := Vector3(Survival.BACKPACK.x, 0.28, Survival.BACKPACK.y)
		if forward.dot(camera.position.direction_to(pack)) > best:
			food_target = ""
			jug_target = false
			backpack_target = true

func _update_dog(delta: float) -> void:
	dog_target = false
	var state := net.dog if net.ready_in_room else {}
	if state.is_empty() and camp_dog == null:
		return
	if camp_dog == null:
		camp_dog = CampDogScene.new()
		add_child(camp_dog)
	camp_dog.sync(state, net.elapsed, net.dog_sample_time, delta)
	if state.is_empty() or not terrain.is_focus_ready() or backpack_target or not food_target.is_empty() or jug_target:
		return
	if body_pos.distance_squared_to(CampDog.position(state)) > CampDog.REACH * CampDog.REACH:
		return
	var down: bool = camp_dog.clip in [CampDog.DOWN, CampDog.REST]
	var at := camp_dog.position + Vector3.UP * (0.36 if down else 0.52)
	dog_target = (-camera.basis.z).dot(camera.position.direction_to(at)) > 0.976
	if dog_target and not pickup_stone.is_empty():
		var stone := Stones.unpack(net.stones[pickup_stone].at)
		dog_target = camera.position.distance_squared_to(at) < camera.position.distance_squared_to(stone)

func _interaction_prompt(can_fix: bool) -> String:
	if not net.is_piloting() and net.survival.get("health", 100.0) <= 0.0:
		return "F    失去行动力，倒地满12秒后返回营地"
	if not people_target.is_empty():
		var npc: Dictionary = net.wild_people.people[people_target]
		return "E    %s · %s · 健康 %d%%\n左腿伤 %d / 右腿伤 %d · 查看照料、制服与缴获" % [npc.name, WildPeople.PHASE_NAMES.get(npc.phase, npc.phase), roundi(100.0 * npc.health / npc.maxHealth), roundi(npc.legL), roundi(npc.legR)]
	if not source_target.is_empty():
		return "F    %s · 采集一份（库存 %d）" % [WildPeople.SOURCES[source_target].name, net.wild_people.resources[source_target].stock]
	if net.is_piloting():
		if net.ship.onWater:
			return "水面停泊    空格  起飞    E  下机"
		if net.ship.landed:
			match str(net.ship.get("surface", "land")):
				"rock": return "石头上停稳    空格  起飞    E  下机"
				"tree": return "树上停稳    空格  起飞    E  下机"
				_: return "空格  起飞    E  下机"
		var height := maxf(0.0, spaceship.position.y - LakeLayout.ground_height(Spaceship.point(net.ship)))
		var landing := "下方不稳，飞船下落中" if net.ship.get("slipping", false) else "C  下降"
		if not net.ship.canLand and not net.ship.get("slipping", false):
			landing = "C  下降 · 下方不稳"
		return "飞行高度 %.1f m    %s" % [height, landing]
	if ship_target:
		if not PlayerMotion.boardable(net.ship, net.player_motion):
			return "空格    上浮到水面后登机" if net.ship.onWater else "靠近同一高度后登机"
		return "E    登上飞船" if net.ship.pilot.is_empty() else "飞船 · 队友正在驾驶"
	if backpack_target:
		return "E    捡起并背上背包"
	if not food_target.is_empty():
		var item: String = net.provisions[food_target].item
		if Survival.is_drinkable(item):
			return "%s    E  拾取    F  喝" % Survival.ITEM_NAMES[item]
		return "%s    E  拾取    F  吃" % Survival.ITEM_NAMES[item] if Survival.FOOD_STATS.has(item) else "E    捡起%s" % Survival.ITEM_NAMES[item]
	if jug_target:
		return "F    喝水"
	if dog_target:
		match CampDog.command(net.dog, net.self_id):
			"adopt": return "E    收养藏獒"
			"follow": return "E    让藏獒跟随"
			"stay": return "E    让藏獒待命"
		return "藏獒 · 已有人照料"
	if not pickup_stone.is_empty():
		return "E    捡起扁石片" if Stones.flat(pickup_stone) else "E    捡起苔藓圆石"
	match stone_action:
		"grind": return "F    磨利手里的扁石片"
		"press": return "F    用石块压住帆布角"
		"cut": return "F    割一段麻绳做营地拉绳"
	if grindstone_target:
		return _grindstone_prompt()
	if net.player_motion.swimming:
		var depth := maxf(0.0, LakeLayout.water_y() - (float(net.player_motion.y) + PlayerMotion.SWIM_EYE))
		return "水下 %.1f m    空格 上浮" % depth if depth > 0.05 else "C    下潜"
	return _action(nearby, can_fix)

func _update_people_target() -> void:
	people_target = ""
	source_target = ""
	if not net.ready_in_room or net.is_piloting():
		return
	var forward := -camera.basis.z
	var best := 0.925
	for id: String in net.wild_people.get("people", {}):
		var npc: Dictionary = net.wild_people.people[id]
		if body_pos.distance_to(WildPeople.position(npc)) > 3.0:
			continue
		var at := Vector3(npc.x, npc.get("y", 0), npc.z)
		at += Vector3(0, 0.24, 0.25).rotated(Vector3.UP, npc.yaw) if npc.phase in ["down", "dead"] else Vector3.UP * 1.12
		var score := forward.dot(camera.position.direction_to(at))
		if score > best:
			people_target = id
			best = score
	if people_target.is_empty():
		for key: String in WildPeople.SOURCES:
			var source: Dictionary = WildPeople.SOURCES[key]
			if body_pos.distance_to(Vector2(source.x, source.z)) <= WildPeople.REACH:
				source_target = key
	for entry: Dictionary in net.wild_people.get("log", []):
		if entry.id > last_people_log:
			last_people_log = entry.id
			if net.elapsed - entry.at < 8.0:
				hud.say(entry.text)

func _grindstone_prompt() -> String:
	if held_stone.is_empty():
		return "固定磨石    先找地上的扁石片，按 E 捡起"
	if not Stones.flat(held_stone):
		return "磨石    按 G 放下圆石，再捡扁石片"
	if int(net.stones[held_stone].edge) == 3:
		return "磨石    手里的石片已经磨利"
	if stone_action == "grind":
		return "按 F 磨利手里的扁石片"
	return "拿着扁石片走近磨石"

func _show_grindstone_help() -> void:
	if not held_stone.is_empty():
		hud.say(_grindstone_prompt())
		return
	var nearest := Vector2.ZERO
	var distance := INF
	for id: String in net.stones:
		var stone: Dictionary = net.stones[id]
		if not Stones.flat(id) or not Stones.is_pickable(stone):
			continue
		var offset := Vector2(stone.at[0], stone.at[2]) - body_pos
		var length := offset.length()
		if length < distance:
			distance = length
			nearest = offset
	if distance == INF:
		hud.say("先找一块扁石片，按 E 捡起")
		return
	var angle := wrapf(atan2(-nearest.x, -nearest.y) - yaw, -PI, PI)
	var direction: String = ["前方", "左边", "身后", "右边"][posmod(roundi(angle / (PI * 0.5)), 4)]
	hud.say("扁石片在%s，约 %d 米。走近后低头按 E 捡起" % [direction, maxi(1, roundi(distance))])

func _reachable(wood: bool, tarp: bool, repaired: bool) -> String:
	if not net.ready_in_room or not terrain.is_focus_ready():
		return ""
	for id in ["wood","tarp","repair"]:
		var handled: bool = wood if id=="wood" else (tarp if id=="tarp" else repaired)
		if not handled and body_pos.distance_squared_to(sites[id]) < NEAR*NEAR:
			return id
	return ""

func _goal(wood: bool,tarp: bool) -> String:
	if wood and tarp:
		return "repair"
	if wood:
		return "tarp"
	if tarp:
		return "wood"
	var slot := int(net.players.get(net.self_id,{}).get("slot",1))
	return "tarp" if (posmod(slot-1,2)==1) != prefer_tarp else "wood"

func _action(site: String, can_fix: bool) -> String:
	match site:
		"wood": return "E    拾取溪谷木料"
		"tarp": return "E    收起防水布"
		"repair": return "E    修好屋顶并点灯" if can_fix else "修补木棚需要木料和防水布"
	return ""

func _sync_hikers(delta: float) -> void:
	for key in avatars.keys():
		if not net.ready_in_room or not net.players.has(key) or key==net.self_id:
			avatars[key].queue_free()
			avatars.erase(key)
	if not net.ready_in_room:
		if local_hiker != null:
			local_hiker.queue_free()
			local_hiker = null
		return
	var piloting := net.is_piloting()
	var hiker_visible := chase_ship if piloting else not first_person_view
	if hiker_visible and local_hiker == null:
		local_hiker = Hiker.new()
		add_child(local_hiker)
		local_hiker.position = Vector3(body_pos.x, net.player_motion.y, body_pos.y)
		var self_data: Dictionary = net.players.get(net.self_id, {})
		local_hiker.outfit(int(self_data.get("slot",1)))
	if local_hiker != null:
		local_hiker.visible = hiker_visible
		local_hiker.wear_clothes(net.survival.get("worn", Survival.initial_wear()))
		local_hiker.wear_backpack(not piloting and net.backpack_enabled and net.backpack_owner == net.self_id)
		if piloting:
			_seat_hiker(local_hiker)
		else:
			_stand_hiker(local_hiker, Vector3(body_pos.x, net.player_motion.y, body_pos.y))
			local_hiker.set_motion_state(net.player_motion)
			local_hiker.heading = yaw
			local_hiker.holding = not Stones.held_by(net.stones, net.self_id).is_empty() or not str(net.survival.get("weapon", "")).is_empty()
			local_hiker.shielding = net.survival.get("shield", false)
			local_hiker.blocking = net.blocking
			local_hiker.advance(delta, true)
	for key in net.players:
		if key==net.self_id:
			continue
		var data: Dictionary = net.players[key]
		var at := Vector3(data.x, data.get("y", LakeLayout.walk_height(Vector2(data.x, data.z))), data.z)
		if not avatars.has(key):
			var hiker := Hiker.new()
			add_child(hiker)
			hiker.position = at
			hiker.outfit(int(data.get("slot",2)))
			avatars[key] = hiker
		var person = avatars[key]
		var is_pilot: bool = key == net.ship.get("pilot", "")
		person.wear_clothes(data.get("worn", Survival.initial_wear()))
		person.wear_backpack(not is_pilot and net.backpack_owner == key)
		if is_pilot:
			_seat_hiker(person)
			person.show()
		else:
			_stand_hiker(person, at)
			person.set_motion_state(data)
			person.heading = float(data.get("yaw", 0.0))
			person.holding = not Stones.held_by(net.stones, key).is_empty() or not str(data.get("weapon", "")).is_empty()
			person.shielding = data.get("shield", false)
			person.blocking = data.get("blocking", false)
			person.advance(delta)
			person.visible = Vector2(person.position.x, person.position.z).distance_squared_to(body_pos) > 0.20

func _seat_hiker(hiker: Node3D) -> void:
	if hiker.get_parent() != spaceship.seat:
		hiker.reparent(spaceship.seat, false)
		hiker.set_seated(true)

func _stand_hiker(hiker: Node3D, at: Vector3) -> void:
	if hiker.get_parent() != self:
		hiker.reparent(self, false)
		hiker.set_seated(false)
		hiker.position = at
	hiker.target = at

func _playable() -> bool:
	return net.ready_in_room and (field_entered or terrain.is_focus_ready()) and not preview_warming

func _state() -> Dictionary:
	var button_rect := hud.enter.get_global_rect()
	var panel_rect := hud.panel.get_global_rect()
	var invite_rect := hud.invite.get_global_rect()
	var equipment_tab := hud.character_tab.get_global_rect()
	var viewport := get_viewport().get_visible_rect().size
	return {
		"ready": _playable(),
		"atlas": atlas.observables(),
		"connected":net.ready_in_room, "locked":locked, "room":room_code, "selfId":net.self_id,
		"members":net.players.size(), "players":net.players, "remoteAvatars":avatars.size(), "playerMotion":_motion_observables(), "localPhysics":{"grounded":net.player_motion.get("grounded", true), "vy":net.player_motion.get("vy", 0.0), "vx":net.player_motion.get("vx", 0.0), "vz":net.player_motion.get("vz", 0.0), "waterVy":net.player_motion.get("waterVy", 0.0)}, "x":body_pos.x, "z":body_pos.y,
		"yaw":yaw, "pitch":pitch, "quest":net.quest, "elapsed":net.elapsed, "rain":net.rain,
		"dayPart":weather.day_part, "stones":net.stones, "heldStone":held_stone, "pickupStone":pickup_stone,
		"stoneAction":stone_action, "lineCut":net.line_cut, "waterImpacts":net.water_impacts,
		"survival":net.survival, "provisions":net.provisions, "inventoryPanel":hud.inventory_observables(), "provisionScene":terrain.household.observables(net.provisions), "backpackOpen":backpack_open, "bagSlots":_bag_slots(),
		"equipmentOpen":backpack_open and hud.character_page.visible,
		"equipmentTabRect":[equipment_tab.position.x,equipment_tab.position.y,equipment_tab.size.x,equipment_tab.size.y],
		"backpackOwner": net.backpack_owner, "backpackTarget": backpack_target,
		"thirdPerson": chase_ship if net.is_piloting() else third_person,
		"weaponView": {"aim": sight_blend, "fov": camera.fov, "firstPerson": first_person_view, "scope": hud.scope_overlay.visible},
		"dog": net.dog, "dogTarget": dog_target,
		"wildPeople": net.wild_people, "peopleTarget": people_target, "peopleOpen": people_open, "sourceTarget": source_target, "peoplePanel": people_panel.observables(), "peopleWarmupMs": people_scene.warmup_ms, "peopleWarmupCount": people_scene.warmup_count, "peoplePoolHits": people_scene.pool_hits, "peopleColdCreates": people_scene.cold_creates, "peoplePoolByKey": people_scene.pool_by_key, "peopleColdByKey": people_scene.cold_by_key,
		"ship": net.ship, "shipPiloting": net.is_piloting(), "shipTarget": ship_target,
		"shipCameraYaw": ship_view_yaw,
		"fps": Engine.get_frames_per_second(),
		"swimming": net.player_motion.swimming and not net.is_piloting(), "y": net.player_motion.y,
		"canPutProvision":Survival.can_put(body_pos), "foodTarget":food_target, "jugTarget":jug_target,
		"groveElapsed":net.grove_elapsed, "grove":terrain.grove.render_state(),
		"groveHint":terrain.grove.observe(camera.position, -camera.basis.z) if net.ready_in_room else "",
		"sheltered":bool(net.quest.get("repaired",false)) and absf(body_pos.x-1.9)<2.6 and absf(body_pos.y+89.6)<2.7,
		"zone":terrain.focus_zone(), "resident":terrain.resident_count(), "focusReady":terrain.is_focus_ready(),
		"lanternWarmupMs": terrain.lantern_warmup_ms,
		"previewWarming": preview_warming,
		"previewWarmupBuildMs": hud.character_preview.warmup_build_ms,
		"previewWarmupDrawMs": hud.character_preview.warmup_draw_ms,
		"terrainError":terrain.last_error, "nearby":nearby, "target":plan,
		"status":net.status, "notice":net.last_notice, "noticeNo":net.notice_number,
		"inviteShown":bool(web_join.inviteVisible) if web and web_join != null else hud.link_field.visible, "inviteRect":[invite_rect.position.x,invite_rect.position.y,invite_rect.size.x,invite_rect.size.y],
		"panelRect":[panel_rect.position.x,panel_rect.position.y,panel_rect.size.x,panel_rect.size.y],
		"viewport":[viewport.x,viewport.y], "enterRect":[button_rect.position.x,button_rect.position.y,button_rect.size.x,button_rect.size.y]
	}

func _publish(state: Dictionary) -> void:
	if web:
		JavaScriptBridge.eval("window.CooperStatus = "+JSON.stringify(state),true)
	else:
		var stages: Array[String] = []
		for tree in state.grove:
			stages.append(tree.id + "=" + tree.stage)
		var signature := "%s/%s/%s/%s/%s/%s/%s/%s" % [state.connected,state.ready,state.zone,state.members,last_flags,state.status,state.terrainError,stages]
		if signature != last_log:
			last_log = signature
			var line := "COOP_STATE " + JSON.stringify(state)
			print(line)
			if status_record != null:
				state["websocketUrl"] = ws_url
				state["zoneBase"] = zone_base
				state["inviteUrl"] = invite_url
				status_record.store_line("COOP_STATE " + JSON.stringify(state))
				status_record.flush()

func _motion_observables() -> Dictionary:
	var output := {}
	if local_hiker != null and local_hiker.visible:
		output[net.self_id] = local_hiker.motion_observables()
	for id: String in avatars:
		output[id] = avatars[id].motion_observables()
	return output
