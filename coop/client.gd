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
const Wildlife = preload("res://wildlife.gd")
const WoodlandBoarScene=preload("res://woodland_boar_scene.gd")
const LakeLifeScene = preload("res://lake_life_scene.gd")
const Beds = preload("res://camp_beds.gd")
const Ferry = preload("res://lake_ferry.gd")
const FieldAtlas = preload("res://field_atlas.gd")
const Reeds = preload("res://lake_reeds.gd")
const Sheep = preload("res://lake_sheep.gd")
const WildlifeScene = preload("res://wildlife_scene.gd")
const StorageWildlife = preload("res://storage_wildlife.gd")
const WildPeople = preload("res://wild_people.gd")
const WildPeopleScene = preload("res://wild_people_scene.gd")
const FieldAtlasPanel = preload("res://field_atlas_panel.gd")
const WildPeoplePanel = preload("res://wild_people_panel.gd")
const Spaceship = preload("res://spaceship.gd")
const SpaceshipScene = preload("res://spaceship_scene.gd")
const PlayerMotion = preload("res://player_motion.gd")
const CampAudio = preload("res://camp_audio.gd")
const Storage = preload("res://camp_storage.gd")
const StorageScene = preload("res://camp_storage_scene.gd")
const StoragePanel = preload("res://camp_storage_panel.gd")
const Placement = preload("res://placement.gd")
const PlacementWorld = preload("res://placement_world.gd")
const MinesLayout = preload("res://mines_layout.gd")
const MinesScene = preload("res://mines_scene.gd")
const Mining = preload("res://mining.gd")
const EYE_HEIGHT := PlayerMotion.WALK_EYE
const VIEW_FOV := 78.0
const MOUSE_SENSITIVITY := .00215
const NEAR := 2.5
const DEFAULT_WS := "ws://127.0.0.1:4184/room"

var net := Network.new()
var terrain := Terrain.new()
var atlas := FieldAtlasPanel.new()
var weather := Weather.new()
var hud := Hud.new()
var stone_scene := StoneScene.new()
var storage_scene := StorageScene.new()
var mines_scene := MinesScene.new()
var mine_target := ""
var rescue_target := ""
var storage_panel := StoragePanel.new()
var storage_target := ""
var held_storage := ""
var storage_notice := -1
var placement_grid: Dictionary
var placement: Dictionary = {}
var placement_rotation := 0.0
var placement_item := ""
var construction_recipe := ""
var camp_audio := CampAudio.new()
var camera := Camera3D.new()
var next_sighting_ms := 0
var sighting_retry: Dictionary = {}
var follow_camera := FollowCamera.new()
var camp_dog: Node3D
var wildlife := WildlifeScene.new()
var forest_boar:=WoodlandBoarScene.new()
var lake_life := LakeLifeScene.new()
var reed_target := ""
var lake_target := ""
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
var on_houseboat := false
var boat_panorama := false
var follow_arm := -1.0
var first_person_view: bool:
	get:
		return not boat_panorama if on_houseboat else not third_person or sight_blend > 0.0
var sight_blend := 0.0
var eye_offset := EYE_HEIGHT
var world: Dictionary
var sites: Dictionary = {}
var body_pos := Vector2(1.9,-85)
var yaw := -.08
var pitch := .10
var locked := false
var menu_open := true
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
var preview_progress := {"stage": "lighting"}
var web_join
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
var resume_after_panel := false
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
	placement_grid = PlacementWorld.static_grid(world)
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
	camera.far = Weather.LANDSCAPE_FAR
	camera.cull_mask &= ~WildPeopleScene.WARM_LAYER
	camera.current = true
	camera.position = Vector3(body_pos.x,EYE_HEIGHT,body_pos.y)
	camera.rotation = Vector3(pitch,yaw,0)
	terrain.configure(zone_base)
	add_child(terrain)
	terrain.update_focus(camera.position)
	add_child(weather)
	add_child(stone_scene)
	add_child(storage_scene)
	add_child(mines_scene)
	camp_audio.configure(world.route)
	add_child(camp_audio)
	add_child(wildlife)
	add_child(forest_boar)
	add_child(lake_life)
	lake_life.blade_entered_water.connect(terrain.add_water_impact)
	lake_life.blade_entered_water.connect(camp_audio.oar_entry)
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
	add_child(storage_panel)
	storage_panel.close_requested.connect(_set_storage.bind(false))
	storage_panel.action_requested.connect(_storage_panel_action)
	add_child(people_panel)
	people_panel.close_requested.connect(_set_people.bind(false))
	people_panel.action_requested.connect(_person_action)
	people_panel.locate_requested.connect(_locate_source)
	hud.resume_requested.connect(_capture)
	hud.invite_requested.connect(_invite)
	hud.backpack_close_requested.connect(_set_backpack.bind(false))
	hud.backpack_action_requested.connect(_use_backpack)
	hud.camp_page_requested.connect(_open_camp_page)
	hud.habitat_requested.connect(_open_habitat)
	if web:
		terrain.prepare_exhaust_warmup(spaceship.lift_jets[0].mesh, spaceship.lift_material)
		preview_warming = true
		_warm_character_preview.call_deferred()
	setup_ok = true

func _warm_character_preview() -> void:
	await terrain.wait_for_lantern_warmup()
	var preview := await _warm_world_views()
	preview_progress = {"stage": "character"}
	await get_tree().process_frame
	var equipped_pack := _bag_slots() > Survival.SLOT_COUNT
	var slot := int(net.players.get(net.self_id, {}).get("slot", 1))
	hud.set_equipment(net.survival, equipped_pack, slot)
	await hud.character_preview.warm_up(hud.worn, equipped_pack, slot)
	preview_progress = {"stage": "people", "total": WildPeopleScene.MODELS.size() * WildPeopleScene.WARMUP_PER_MODEL}
	await people_scene.warm_up()
	# Looking toward the lake first activates a separate reflection layer.
	# Draw both banks with that camera mask once streamed ground is available.
	var lens := preview.get_camera_3d()
	lens.cull_mask = terrain.lake.reflection_camera.cull_mask
	lens.far = terrain.lake.reflection_camera.far
	lens.fov = 100.0
	var lake := LakeLayout.center()
	var surface := Vector3(lake.x, LakeLayout.water_y(), lake.y)
	for offset: Vector3 in [Vector3(25.0, -1.6, -22.0), Vector3(-12.0, -1.6, 11.0)]:
		lens.position = surface + offset
		lens.look_at(surface + Vector3.UP)
		preview.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
	preview.queue_free()
	await preview.tree_exited
	preview_warming = false

func _warm_world_views() -> SubViewport:
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
	# Cave rock and lantern surfaces need the local point-light and shadow variants
	# that only appear once a route takes the player past the trail fork.
	for id: String in MinesLayout.data:
		var mine: Dictionary = MinesLayout.data[id]
		var passage := MinesLayout.pose(id)
		var route: Array = mine.route
		var entrance := MinesLayout.vector(route.back())
		var approach := MinesLayout.vector(route[maxi(0,route.size()-19)])
		views.append([approach + Vector3.UP * EYE_HEIGHT, entrance + Vector3.UP * 1.05, 290.0])
		var floor: Array = mine.floor
		var middle: Array = floor[(floor.size()*2)/3]
		var at := passage * Vector3(middle[2],float(middle[1]) + EYE_HEIGHT,middle[0])
		views.append([at, MinesLayout.gather(id), 290.0])
		views.append([at, entrance + Vector3.UP * 0.9, 290.0])
	preview_progress = {"stage": "world", "done": 0, "total": views.size()}
	for view: Array in views:
		lens.position = view[0]
		lens.look_at(view[1])
		lens.far = view[2]
		preview.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		preview_progress.done += 1
	traveler.queue_free()
	rain_preview.queue_free()
	return preview

func _read_join() -> void:
	if web:
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
	if _panel_open() or not _playable() or _mouse_locked():
		return
	if not web:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _release() -> void:
	locked = false
	if web:
		if web_join != null:
			web_join.releasePointer()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	net.set_motion(Vector2.ZERO,yaw)
	net.aim_pitch = null

func _set_menu_open(open: bool) -> void:
	if menu_open == open:
		return
	menu_open = open
	if web and web_join != null:
		web_join.setMenuOpen(open)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and setup_ok and not web:
		_release()

func _panel_open() -> bool:
	return backpack_open or people_open or atlas.is_open or storage_panel.is_open

func _sync_panels() -> void:
	var open := _panel_open()
	hud.modal_open = people_open or atlas.is_open or storage_panel.is_open
	if web and web_join != null:
		web_join.setPanelOpen(open, atlas.is_open)
	if open:
		resume_after_panel = resume_after_panel or _mouse_locked()
		net.blocking = false
		_release()
		return
	var resume := resume_after_panel
	resume_after_panel = false
	if resume and _playable():
		if web and web_join != null:
			web_join.resumeFromPanel()
		else:
			_capture()

func _close_panel() -> bool:
	if atlas.is_open:
		_set_atlas(false)
	elif storage_panel.is_open:
		_set_storage(false)
	elif people_open:
		_set_people(false)
	elif backpack_open:
		_set_backpack(false)
	else:
		return false
	return true

func _set_atlas(open: bool) -> void:
	if atlas.is_open == open or open and not _playable():
		return
	atlas.set_open(open)
	if open:
		_set_storage(false)
		_set_backpack(false)
		_set_people(false)
	get_viewport().disable_3d = open
	_sync_panels()

func _atlas_reply(action: String, accepted: bool, text: String, site: String) -> void:
	atlas.reply(action, text)
	if action == "travel" and accepted:
		eye_offset = PlayerMotion.eye_offset(net.player_motion.swimming)
		var landmark: Dictionary = FieldAtlas.LANDMARKS.get(site,{})
		if landmark.has("view"):
			var view: Vector2 = landmark.view
			if site=="boar_wood" and not net.boar.is_empty():
				view=Vector2(net.boar.x,net.boar.z)
			var delta: Vector2 = view-net.local_position
			yaw = atan2(-delta.x,-delta.y)
			pitch = atan2(LakeLayout.ground_height(view)+float(landmark.viewHeight)-float(net.player_motion.y)-eye_offset,delta.length())
		elif site in ["island", "buddha"]:
			var monument := LakeLayout.Coast.buddha
			var target: Vector2 = monument.pose.origin if site == "island" else monument.pose * Vector2(4.43,16.96)
			var toward: Vector2 = target - net.local_position
			yaw = atan2(-toward.x, -toward.y)
			var target_y := monument.sole_y + (31.0 if site == "island" else 2.28)
			pitch = atan2(target_y - float(net.player_motion.y) - eye_offset, toward.length())
		follow_arm = -1.0
		ship_camera_arm = -1.0
		_set_atlas(false)
		hud.say(text)

func _set_backpack(open: bool) -> void:
	if backpack_open == open:
		return
	if open and (not _playable() or net.is_piloting() or net.survival.is_empty()):
		return
	backpack_open = open
	if open:
		_set_people(false)
		_set_storage(false)
		hud.set_equipment(net.survival, _bag_slots() > Survival.SLOT_COUNT, int(net.players.get(net.self_id, {}).get("slot", 1)))
	hud.set_backpack_open(open, net.survival.get("bag", {}), _can_put_on_table(), _bag_slots())
	_sync_panels()

func _open_camp_page(page: String) -> void:
	match page:
		"map": _set_atlas(true)
		"storage":
			var target: Dictionary = net.storage.get(storage_target, {})
			if not target.is_empty() and int(Storage.KINDS[target.kind].capacity) > 0:
				_open_storage_object(storage_target)
			else:
				hud.say("靠近并看向可储物的容器")
		"people": _set_people(true)
		"field": _set_backpack(false)
		"room": _open_camp_menu()

func _open_habitat(site: String) -> void:
	_set_atlas(true)
	if atlas.is_open:
		atlas.view.focus_landmark(site)

func _open_camp_menu() -> void:
	resume_after_panel = false
	_close_panel()
	_set_menu_open(true)
	_release()

func _input(event: InputEvent) -> void:
	if not setup_ok or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		if event.alt_pressed or event.ctrl_pressed or event.meta_pressed:
			return
		if event.shift_pressed:
			_open_camp_menu()
		elif not _close_panel() and not construction_recipe.is_empty():
			construction_recipe = ""
			placement.clear()
		get_viewport().set_input_as_handled()
		return
	if event.physical_keycode == KEY_M and not (event.alt_pressed or event.ctrl_pressed or event.meta_pressed):
		_set_atlas(not atlas.is_open)
		get_viewport().set_input_as_handled()
		return
	if atlas.is_open:
		match event.physical_keycode:
			KEY_EQUAL, KEY_KP_ADD:
				atlas.zoom_step(true)
			KEY_MINUS, KEY_KP_SUBTRACT:
				atlas.zoom_step(false)
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if storage_panel.is_open:
		return
	if event.physical_keycode == KEY_K and not (event.alt_pressed or event.ctrl_pressed or event.meta_pressed):
		_set_storage(true, "craft")
		get_viewport().set_input_as_handled()
		return
	if event.physical_keycode == KEY_B and not (event.alt_pressed or event.ctrl_pressed or event.meta_pressed):
		_set_people(not people_open)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_TAB and not (event.alt_pressed or event.ctrl_pressed or event.meta_pressed) and (backpack_open or not net.survival.is_empty()):
		_set_backpack(not backpack_open)
		get_viewport().set_input_as_handled()

func _use_backpack(action: String, item: String) -> void:
	if backpack_open:
		if action=="whistle":
			net.interact_dog("whistle")
			_set_backpack(false)
		elif action=="unroll":
			if not held_storage.is_empty() or not held_stone.is_empty():
				hud.say("先放下手中的物件")
				return
			_set_backpack(false)
			_storage_panel_action("build_preview",{"recipe":"lay_bedroll"})
		elif action == "equip":
			net.interact_person("unequip" if net.survival.get("weapon") == item else "equip", item)
		else:
			net.interact_provision(action, item)

func _set_people(open: bool) -> void:
	if people_open == open or open and (not _playable() or net.is_piloting()):
		return
	people_open = open
	if open:
		_set_backpack(false)
		_set_storage(false)
	people_panel.set_open(open, people_target if open else "")
	_sync_panels()
	if open:
		people_panel.refresh(net.wild_people, net.survival, body_pos, net.elapsed, net.last_notice, net.notice_number)

func _set_storage(open: bool, mode := "storage", id := "") -> void:
	if storage_panel.is_open == open or open and (not _playable() or not net.storage_available or net.is_piloting()):
		return
	storage_panel.set_open(open, mode, id)
	if open:
		_set_backpack(false)
		_set_people(false)
		storage_panel.sync(net.storage, net.survival.get("bag", {}), net.elapsed, net.self_id, _bag_slots())
	_sync_panels()


func _storage_panel_action(action: String, fields: Dictionary) -> void:
	if action == "build_preview":
		if not held_storage.is_empty() or not held_stone.is_empty():
			storage_panel.feedback("先放下手中的物件")
			return
		construction_recipe = fields.recipe
		placement_rotation = 0.0
		_set_storage(false)
		return
	net.interact_storage(action, fields)
	if action in ["use", "carry"]:
		_set_storage(false)


func _open_storage_object(id: String) -> void:
	if not net.storage.has(id):
		return
	var kind: String = net.storage[id].kind
	match kind:
		Beds.KIND, Beds.BEDROLL: net.interact_storage("sleep", {"id":id})
		"campfire": _set_storage(true, "fire", id)
		"iron_furnace": _set_storage(true, "furnace", id)
		"wood_sign": _set_storage(true, "sign", id)
		_:
			_set_storage(true, "storage" if Storage.KINDS[kind].capacity > 0 else "fixture", id)


func _can_carry_storage_target() -> bool:
	var record: Dictionary = net.storage.get(storage_target, {})
	return record.get("mode") == "ground" and Storage.KINDS[record.kind].carry


func _person_action(action: String, item: String, id: String) -> void:
	if people_open:
		net.interact_person(action, item, id)
		if action == "chat":
			_set_people(false)

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
		var firearm := Weapons.firearm(weapon)
		var look := Basis.from_euler(Vector3(_follow_pitch(), yaw, 0.0))
		var destination := camera.position - look.z * (maxf(5.0, reach) + maxf(follow_arm, 0.0))
		var bird := Wildlife.eagle(wildlife.flight_time) if net.eagle_alive and wildlife.flight_time >= 0.0 else {}
		var sheep := Sheep.pose(net.elapsed,net.sheared_at) if net.sheep_alive else {}
		var animal := StorageWildlife.ray_hit({"croc": net.crocodile, "eagle": bird, "dog": net.dog, "boar":net.boar, "sheep":sheep},
			camera.position, destination, 0.0, firearm, net.elapsed)
		var nearest: float = animal.get("distance", INF)
		for npc: Dictionary in net.wild_people.get("people", {}).values():
			var hit := WildPeople.ray_hit(npc, camera.position, destination, firearm)
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

func _can_put_on_table() -> bool:
	return not Storage.table_at(net.storage,body_pos).is_empty()


func _bag_slots() -> int:
	return Survival.slot_count(net.backpack_enabled and not net.backpack_owner.is_empty() and net.backpack_owner == net.self_id)

func _unhandled_input(event: InputEvent) -> void:
	if not setup_ok or _panel_open():
		return
	if event is InputEventMouseMotion and _mouse_locked():
		var motion: Vector2 = event.screen_relative
		var fov := _look_fov(net.survival.get("weapon", ""))
		var sensitivity := MOUSE_SENSITIVITY * tan(deg_to_rad(fov * 0.5)) / tan(deg_to_rad(VIEW_FOV * 0.5))
		yaw = wrapf(yaw - motion.x * sensitivity, -PI, PI)
		pitch = clampf(pitch - motion.y * sensitivity, -1.55, 1.51)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _mouse_locked() and not net.is_piloting():
			if net.survival.get("health", 100.0) <= 0.0:
				return
			if not construction_recipe.is_empty():
				_confirm_placement()
			elif not held_storage.is_empty():
				var object: Dictionary = net.storage.get(held_storage,{})
				if Storage.KINDS.get(object.get("kind",""),{}).get("throwable",true):
					net.interact_storage("throw", {"yaw":yaw,"pitch":_follow_pitch() if third_person else pitch})
				else:
					_confirm_placement()
			elif not held_stone.is_empty():
				net.interact_stone("throw", "", yaw, _follow_pitch() if third_person else pitch)
			else:
				_attack()
		else:
			_capture()
	elif event is InputEventKey and event.pressed and not event.echo:
		if locked and net.is_piloting():
			if event.physical_keycode == KEY_E:
				net.interact_ship("exit")
			elif event.physical_keycode == KEY_V:
				chase_ship = not chase_ship
				ship_camera_arm = -1.0
			return
		match event.physical_keycode:
			KEY_E:
				if locked and net.survival.get("health", 100.0) > 0.0:
					if not str(net.player_motion.get("bed","")).is_empty():
						net.interact_lake("wake")
					elif Beds.aboard(lake_target):
						net.interact_lake(lake_target)
					elif not rescue_target.is_empty():
						net.rescue_player(rescue_target)
					elif net.storage.has(storage_target) and (held_storage.is_empty() or net.storage[storage_target].kind == "campfire"):
						_open_storage_object(storage_target)
					elif not held_storage.is_empty():
						_open_storage_object(held_storage)
					elif not people_target.is_empty():
						_set_people(true)
					elif lake_target in ["board","leave","shear"]:
						net.interact_lake(lake_target)
					elif not reed_target.is_empty() and not Reeds.cut(reed_target,net.reed_cuts,net.elapsed):
						net.harvest_reeds(reed_target)
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
				if locked and not dog_target and net.survival.get("health", 100.0) > 0.0:
					if (on_houseboat or lake_target == "board") and Ferry.moored(net.elapsed,net.ferry_departure):
						net.interact_lake("sail")
					elif not mine_target.is_empty():
						net.mine(mine_target)
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
				if locked and net.survival.get("health", 100.0) > 0.0:
					if not held_storage.is_empty() or not construction_recipe.is_empty():
						_confirm_placement()
					elif not Stones.held_by(net.stones, net.self_id).is_empty():
						net.interact_stone("drop")
					elif jug_target:
						net.interact_storage("carry", {"id":"camp-water-jug"})
					elif net.storage.get(storage_target,{}).get("kind","")==Beds.BEDROLL:
						net.interact_storage("pack_bedroll",{"id":storage_target})
					elif _can_carry_storage_target():
						net.interact_storage("carry", {"id": storage_target})
					elif net.provisions.has(food_target):
						net.interact_provision("take", str(net.provisions[food_target].item), food_target)
			KEY_R:
				if locked and (not held_storage.is_empty() or not construction_recipe.is_empty()):
					placement_rotation = wrapf(placement_rotation + deg_to_rad(15.0),-PI,PI)
				elif locked and source_target == "water" and str(net.player_motion.get("bed","")).is_empty():
					net.interact_person("gather","water")
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
					if on_houseboat:
						boat_panorama = not boat_panorama
					else:
						third_person = not third_person
					follow_arm = -1.0

func _placement_input() -> Dictionary:
	return {"yaw":yaw, "pitch":_follow_pitch() if third_person else pitch, "rotation":placement_rotation,
		"snap":Input.is_physical_key_pressed(KEY_SHIFT)}

func _update_placement(feet: float, active: bool) -> void:
	if placement_item != held_storage:
		placement_item = held_storage
		if not placement_item.is_empty():
			placement_rotation = float(net.storage[placement_item].yaw)
	if not active or (held_storage.is_empty() and construction_recipe.is_empty()):
		placement.clear()
		storage_scene.show_placement("",placement)
		return
	var kind: String = Storage.RECIPES.get(construction_recipe,{}).get("kind","") if held_storage.is_empty() else net.storage[held_storage].kind
	var aim := _placement_input()
	placement = PlacementWorld.preview(placement_grid,net.storage,held_storage,body_pos,feet,
		PlayerMotion.WALK_EYE,aim.yaw,aim.pitch,aim.rotation,aim.snap,kind)
	if placement.get("ok",false) and net.players.size() > 1:
		var parts := Placement.bodies(held_storage,PlacementWorld.profile(kind),placement.pose)
		for id: String in net.players:
			if id == net.self_id:
				continue
			var other: Dictionary = net.players[id]
			if PlacementWorld.blocks_player(parts,Vector2(other.x,other.z),other.y):
				placement.ok = false
				placement.reason = "player"
				break
	storage_scene.show_placement(kind,placement)

func _confirm_placement() -> void:
	_update_placement(float(net.player_motion.y),true)
	if not placement.get("ok",false):
		hud.say(Storage.place_hint(placement.get("reason","no_surface")))
		return
	var action := _placement_input()
	if held_storage.is_empty():
		if construction_recipe=="lay_bedroll" and int(net.survival.get("bag",{}).get("boar_bedroll",0))<1:
			construction_recipe=""
			return
		action.recipe = construction_recipe
		net.interact_storage("build",action)
	else:
		action.id = held_storage
		net.interact_storage("place",action)

func _physics_process(_delta: float) -> void:
	if not setup_ok:
		return
	locked = _mouse_locked() and not _panel_open()
	if locked and _playable():
		field_entered = true
		_set_menu_open(false)
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
	net.set_motion(move, yaw, lift, locked and on_houseboat and Input.is_physical_key_pressed(KEY_CTRL))

func _can_aim(piloting: bool, swimming: bool) -> bool:
	return (locked and net.ready_in_room and not (piloting or swimming or on_houseboat) and str(net.player_motion.get("bed","")).is_empty()
		and net.survival.get("health", 0.0) > 0.0 and held_stone.is_empty())

func _process(delta: float) -> void:
	if not setup_ok:
		return
	var trace_start := Time.get_ticks_usec() if trace_wild else 0
	var trace_marks: Variant = [] if trace_wild else null
	locked = _mouse_locked() and not _panel_open()
	if people_open and not net.ready_in_room:
		_set_people(false)
	if backpack_open and not net.ready_in_room:
		_set_backpack(false)
	if storage_panel.is_open and not net.ready_in_room:
		_set_storage(false)
	if atlas.is_open:
		atlas.sync(net.self_id, net.players, net.local_position, yaw, net.atlas_pins, net.atlas_available and net.ready_in_room)
	if locked and not net.ready_in_room:
		_release()
		locked = false
	if not net.ready_in_room:
		field_entered = false
		_set_menu_open(true)
	var previous := body_pos
	if net.ready_in_room:
		body_pos = net.local_position
	var piloting := net.is_piloting()
	var swimming: bool = net.ready_in_room and net.player_motion.swimming
	var down: bool = net.ready_in_room and net.survival.get("health", 100.0) <= 0.0
	var aboard: bool = net.ready_in_room and net.player_motion.get("onFerry",false) and not piloting
	if aboard != on_houseboat:
		on_houseboat = aboard
		boat_panorama = false
		follow_arm = -1.0
		if aboard:
			var toward := LakeLayout.center() - body_pos
			yaw = atan2(-toward.x,-toward.y)
			pitch = -0.05
			eye_offset = PlayerMotion.CROUCH_EYE if net.player_motion.get("crouched",false) else PlayerMotion.WALK_EYE
	var sleeping := not str(net.player_motion.get("bed","")).is_empty()
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
			eye_offset = PlayerMotion.eye_offset(swimming)
		was_piloting = piloting
	spaceship.sync(net.rendered_ship(), net.elapsed, delta, piloting)
	var stride := minf(body_pos.distance_to(previous),.18)
	leg_phase += stride * 4.7
	var bob := sin(leg_phase*2.) * .019 * clampf(stride / maxf(delta,.001),0.,1.)
	var view_height := 0.45 if down and not swimming else PlayerMotion.eye_offset(swimming)
	if sleeping:
		view_height = .32
	elif aboard and net.player_motion.get("crouched",false):
		view_height = PlayerMotion.CROUCH_EYE
	# The visible body and the lens must rise on the same jump sample. Smooth only stance and gait.
	eye_offset = lerpf(eye_offset, view_height + bob, 1.0 - exp(-delta * 15.0))
	var eye := Vector3(body_pos.x, actor_height + eye_offset, body_pos.y)
	if sleeping:
		eye += Vector3.BACK.rotated(Vector3.UP,net.player_motion.bedYaw)*.67
	if aboard and net.player_motion.get("crouched",false):
		eye.y = minf(eye.y,actor_height+PlayerMotion.CROUCH_EYE+.07)
	if piloting:
		_update_ship_camera(delta)
	elif aboard and boat_panorama:
		var hull := Ferry.pose(net.elapsed,net.ferry_departure)
		var pivot := Vector3(hull.point.x, LakeLayout.water_y()+1.77, hull.point.y)
		var angle := clampf(-pitch+.19,.12,.88)
		var offset := Vector3(0,sin(angle),cos(angle)).rotated(Vector3.UP,yaw)*5.7
		var clear := follow_camera.clear_distance(pivot,offset)
		camera.position = pivot + offset.normalized()*clear
		camera.look_at(pivot+Vector3.DOWN*.35)
		camera.fov = VIEW_FOV
		camera.near = .045
	else:
		var view_eye := eye.lerp(Vector3(body_pos.x, actor_height + view_height, body_pos.y), sight_blend)
		_update_camera(view_eye, delta, swimming, _look_fov(weapon))
	var coastal_view := smoothstep(34.0, 73.0, -camera.position.x)
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
	weather.set_rain_roofs(net.storage)
	weather.update_weather(camera.position, net.elapsed, net.rain,
		repaired, camera.position.y < camera_water - 0.035, camera_water - camera.position.y, coastal_view)
	_update_water()
	if trace_wild:
		trace_marks.append(["world", Time.get_ticks_usec() - trace_start])
	_sync_hikers(delta)
	if trace_wild:
		trace_marks.append(["hikers", Time.get_ticks_usec() - trace_start])
	_update_stones()
	var camp_props := mines_scene.camp_props(net.storage, net.wild_people.get("caves", {}))
	var weather_ear := spaceship.cockpit_eye() if piloting else eye
	camp_audio.update_world(net, avatars, camera, weather_ear, spaceship.position, delta, locked, camp_props)
	_update_provisions()
	_update_dog(delta)
	_update_ship_target()
	storage_scene.sync(camp_props, net.players, net.self_id, camera, first_person_view, net.elapsed, net.rain)
	held_storage = Storage.held_by(net.storage, net.self_id)
	storage_target = storage_scene.target(net.storage, body_pos, actor_height, camera,placement_grid) if _playable() and not piloting else ""
	mine_target = _find_mine(actor_height) if _playable() and not piloting and not swimming else ""
	rescue_target = _find_rescue_target(Vector3(body_pos.x, actor_height, body_pos.y), swimming) if _playable() and not piloting and not down else ""
	_update_placement(actor_height,locked and _playable() and not piloting and not swimming and not down)
	if construction_recipe=="lay_bedroll" and int(net.survival.get("bag",{}).get("boar_bedroll",0))<1:
		construction_recipe=""
	forest_boar.sync(net.boar,net.elapsed,delta,camera.position)
	lake_life.sync(net.ready_in_room and net.lake_household, net.ferry_departure, net.elapsed, net.sheep_alive, net.sheared_at, camera.position)
	terrain.lake.reeds.sync(net.reed_cuts,net.elapsed)
	reed_target = Reeds.target(body_pos,actor_height,camera.position,-camera.basis.z) if net.reeds_available and _playable() and not piloting and not down and not on_houseboat else ""
	lake_target = _lake_target(actor_height) if _playable() and not piloting and not down else ""
	wildlife.sync(net.crocodile if net.ready_in_room else {}, net.elapsed, eye, delta, net.eagle_alive)
	if trace_wild:
		trace_marks.append(["other_scene", Time.get_ticks_usec() - trace_start])
	people_scene.sync(net.wild_people.get("people", {}) if net.ready_in_room and not preview_warming else {}, net.elapsed, delta, camera.position, people_target)
	if trace_wild:
		trace_marks.append(["people", Time.get_ticks_usec() - trace_start])
	people_scene.sync_sources(net.wild_people, camera.position)
	people_scene.equip_players(net.players, avatars, net.self_id, camera,
		local_hiker, delta, net.elapsed, swimming or piloting or sleeping or aboard and first_person_view or net.player_motion.get("storageSeated", false), sight_blend)
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
		if locked and _playable() and not (piloting or down):
			_observe_wildlife(eye)
		terrain.grass.set_ground_cover(net.storage,camera.position)
		for id: String in net.mines:
			mines_scene.set_remaining(id, int(net.mines[id].stock))
		var state := _state()
		if trace_wild:
			state.faces = people_scene.face_samples()
		hud.refresh(state,plan,sites[plan]-body_pos,_interaction_prompt(own_wood and own_tarp))
		people_panel.refresh(net.wild_people, net.survival, body_pos, net.elapsed, net.last_notice, net.notice_number)
		if storage_panel.is_open:
			storage_panel.sync(net.storage, own_bag, net.elapsed, net.self_id, _bag_slots())
			if storage_notice != net.notice_number and net.last_notice_site == "storage":
				storage_panel.feedback(net.last_notice)
				storage_notice = net.notice_number
		if not tracked_source.is_empty():
			var source: Dictionary = WildPeople.SOURCES[tracked_source]
			var offset := Vector2(source.x, source.z) - body_pos
			hud.bearing.text = source.name
			hud.bearing_distance.text = "%d m" % roundi(offset.length())
			var relative := wrapf(atan2(-offset.x, -offset.y) - yaw, -PI, PI)
			hud.bearing_arrow.text = "↑" if absf(relative) < .32 else "身后" if absf(relative) > 2.72 else "←" if relative > 0 else "→"
		if telemetry_clock <= 0.0:
			telemetry_clock = .25
			state.menuVisible = hud.panel.is_visible_in_tree()
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

func _observe_wildlife(eye: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if now < next_sighting_ms or not net.survival.has("fieldGuide"):
		return
	var known: Array = net.survival.fieldGuide.animals
	if known.size() == Survival.SIGHTING_RANGE.size():
		return
	var actors := {"croc": wildlife.crocodile, "eagle": wildlife.eagle, "dog": camp_dog, "boar":forest_boar, "sheep":lake_life.live_sheep if net.sheep_alive else null}
	var offsets := {"croc": .22, "eagle": .25, "dog": .48, "boar":.52, "sheep":.64}
	for species: String in actors:
		var animal: Node3D = actors[species]
		if animal == null or not animal.is_visible_in_tree() or species in known or now < int(sighting_retry.get(species, 0)):
			continue
		var at := animal.global_position + Vector3.UP * float(offsets[species])
		if eye.distance_squared_to(at) > float(Survival.SIGHTING_RANGE[species]) ** 2 or not camera.is_position_in_frustum(at):
			continue
		sighting_retry[species] = now + 1500
		next_sighting_ms = now + 350
		net.report_sighting(species, yaw, camera.rotation.x)
		return

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
	stone_scene.update_stones(net.stones, avatars, net.self_id, camera, net.elapsed, net.rain, net.line_cut, local_hiker if not first_person_view else null, net.player_motion.swimming)
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
		var reach_surface: String = "ground" if food.has("tableId") else food.surface
		if not Survival.can_reach(body_pos, Vector2(at.x, at.z), reach_surface):
			continue
		var aim_point: Vector3 = terrain.household.pickup_point(id, at, camera.position, forward)
		var score := forward.dot(camera.position.direction_to(aim_point))
		if score > best:
			food_target = id
			best = score
	var jug_record: Dictionary = net.storage.get("camp-water-jug",{})
	if jug_record.get("mode") == "ground" and body_pos.distance_squared_to(Survival.horizontal(jug_record.at)) <= Survival.JUG_REACH ** 2:
		var jug := Stones.unpack(jug_record.at) + Vector3.UP*0.14
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

func _lake_target(feet: float) -> String:
	if not net.lake_household:
		return ""
	var moored := Ferry.moored(net.elapsed,net.ferry_departure)
	if net.player_motion.get("onFerry",false):
		var local: Vector2 = net.player_motion.get("ferryLocal",Ferry.ENTRY)
		if net.player_motion.get("crouched",false) and Ferry.under_canopy(local) and absf(local.x-.055)<.82:
			var hull := Ferry.pose(net.elapsed,net.ferry_departure)
			var side := Vector2(0,-1).rotated(-yaw+float(hull.yaw)).y
			return Beds.PORT if (local.y + .5*side)>0 else Beds.STARBOARD
		return "leave" if moored else "riding"
	if net.sheep_alive and Sheep.reachable(body_pos,feet,net.elapsed,net.sheared_at):
		var at: Vector3 = Sheep.pose(net.elapsed,net.sheared_at).at + Vector3.UP * 0.67
		if (-camera.basis.z).dot(camera.position.direction_to(at)) > 0.62:
			return "growing" if Sheep.shorn(net.elapsed,net.sheared_at) else "shear"
	if moored and Ferry.at_pier(body_pos,feet):
		return "board"
	return ""

func _bed_user(id: String) -> String:
	for person: Dictionary in net.players.values():
		if person.get("bed","") == id:
			return "队友 %d 正在休息" % int(person.slot)
	for npc: Dictionary in net.wild_people.get("people",{}).values():
		if npc.phase in ["captive","companion"] and npc.get("bedGoal","") == id:
			return npc.name + ("正在休息" if npc.get("bed","")==id else "正在前往床边")
	return ""

func _interaction_prompt(can_fix: bool) -> String:
	if not str(net.player_motion.get("bed","")).is_empty():
		return "躺卧休息 · 健康 %d / 100    E  起身" % roundi(net.survival.get("health",100))
	if not net.is_piloting() and net.survival.get("health", 100.0) <= 0.0:
		var left := ceili(Survival.rescue_time_left(net.survival.get("downAt", -1.0), net.elapsed))
		return "倒地 · 等待队友救援（还有 %d 秒）" % left if left > 0 else "正在返回营地"
	if not rescue_target.is_empty() and net.players.has(rescue_target):
		var ally: Dictionary = net.players[rescue_target]
		var left := ceili(Survival.rescue_time_left(ally.get("downAt", -1.0), net.elapsed))
		return "E    救起队友 %d · 还有 %d 秒" % [int(ally.slot), left]
	if not held_storage.is_empty() and net.storage.has(held_storage):
		var spec: Dictionary = Storage.KINDS[net.storage[held_storage].kind]
		var place_note := "G  摆放" if placement.get("ok",false) else Storage.place_hint(placement.get("reason","no_surface"))
		return "%s  ·  %s    R  旋转%s" % [spec.name,place_note,"    左键  投掷    E  操作" if spec.get("throwable",true) else "    Shift  对齐"]
	if not construction_recipe.is_empty():
		var note := "G  建造" if placement.get("ok",false) else Storage.place_hint(placement.get("reason","no_surface"))
		return "%s  ·  %s    R  旋转    Shift  对齐    Esc  退出" % [Storage.RECIPES[construction_recipe].name,note]
	if not mine_target.is_empty():
		var stock: int = net.mines[mine_target].stock
		var name: String = Mining.VEINS[mine_target].name
		return "F    开采%s  ·  余 %d 块" % [name,stock] if stock > 0 else "%s    表层已采完" % name
	if jug_target:
		return "F    喝水    G  拿起水壶"
	if not storage_target.is_empty() and net.storage.has(storage_target):
		var kind: String = net.storage[storage_target].kind
		var spec: Dictionary = Storage.KINDS[kind]
		if Beds.is_bed(kind):
			var occupant := _bed_user(storage_target)
			return str(spec.name)+" · "+occupant if not occupant.is_empty() else str(spec.name)+"    E  躺下休息    G  "+("收卷" if kind==Beds.BEDROLL else "搬动")
		var detail := " · %d 格" % spec.capacity if spec.capacity > 0 and not kind.begins_with("corpse_") else ""
		var actions := "互动    G  拿起" if spec.carry else "互动"
		return "E    %s · %s%s" % [actions, spec.name, detail]
	if not people_target.is_empty():
		var npc: Dictionary = net.wild_people.people[people_target]
		if npc.phase=="resident":
			return "E    查看%s的营地生活\n%s" % [npc.name,npc.help]
		return "E    %s · %s · 健康 %d%%\n左腿伤 %d / 右腿伤 %d · 查看照料、制服与缴获" % [npc.name, WildPeople.PHASE_NAMES.get(npc.phase, npc.phase), roundi(100.0 * npc.health / npc.maxHealth), roundi(npc.legL), roundi(npc.legR)]
	match lake_target:
		"board": return "鹿鸣湖住船    E 上船    F 开船    R 装水"
		Beds.PORT, Beds.STARBOARD:
			var occupant := _bed_user(lake_target)
			return "船舱铺位 · "+occupant if not occupant.is_empty() else "船舱铺位    E 躺下休息    Ctrl 蹲行    V 环顾"
		"leave": return "WASD 甲板走动 · Ctrl 蹲行进篷 · V 换视角    E 上岸    F 开船    R 装水"
		"riding": return "环湖航行 · WASD 走动 · Ctrl 蹲行进篷 · V 换视角 · R 装水"
		"shear": return "绵羊    E  剪羊毛"
		"growing": return "绵羊 · 新毛正在长"
	if not reed_target.is_empty():
		return "芦苇茬 · 正在生长" if Reeds.cut(reed_target,net.reed_cuts,net.elapsed) else "湖岸芦苇    E  采一束"
	if source_target == "water":
		return "鹿鸣湖淡水    F  装一份水"
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
		if Survival.CLOTHING.has(item):
			return "G    拿起%s" % Survival.ITEM_NAMES[item]
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

func _find_rescue_target(at: Vector3, swimming: bool) -> String:
	var selected := ""
	var best := 0.85
	var from := at + Vector3.UP * PlayerMotion.eye_offset(swimming)
	for id: String in net.players:
		var ally: Dictionary = net.players[id]
		if id == net.self_id or float(ally.health) > 0.0:
			continue
		if Survival.rescue_time_left(ally.get("downAt", -1.0), net.elapsed) <= 0.0:
			continue
		if not ally.get("grounded", false) and not ally.swimming:
			continue
		var feet := Vector3(ally.x, ally.y, ally.z)
		if not Survival.within_rescue_reach(at, feet):
			continue
		var to := feet + Vector3.UP * Survival.rescue_contact_height(ally.swimming)
		var facing := (-camera.global_basis.z).dot(camera.global_position.direction_to(to))
		if facing <= best:
			continue
		var solids := PlacementWorld.nearby(placement_grid, net.storage, body_pos, Survival.RESCUE_REACH + 1.5)
		if Placement.trace(from, to, solids).is_empty() and not Spaceship.blocks_sight(net.ship, from, to):
			selected = id
			best = facing
	return selected

func _find_mine(feet: float) -> String:
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	for id: String in net.mines:
		if not MinesLayout.data.has(id):
			continue
		var target := MinesLayout.gather(id)
		if body_pos.distance_squared_to(Vector2(target.x,target.z)) > Mining.REACH*Mining.REACH:
			continue
		if forward.dot((target-eye).normalized()) < .982:
			continue
		var solids := PlacementWorld.nearby(placement_grid,net.storage,body_pos)
		if Mining.reachable({"point":body_pos,"y":feet},target,solids):
			return id
	return ""

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
		if LakeLayout.can_fill_water(body_pos,net.player_motion.y):
			source_target = "water"
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
	var self_data: Dictionary = net.players.get(net.self_id, {})
	var eye_body := first_person_view and not piloting
	var hiker_visible: bool = chase_ship if piloting else not eye_body or (
		not (on_houseboat or not str(net.player_motion.get("bed","")).is_empty()) and not net.player_motion.swimming and not net.player_motion.get("storageSeated", false) and float(self_data.get("health", 100.0)) > 0)
	if hiker_visible and local_hiker == null:
		local_hiker = Hiker.new()
		add_child(local_hiker)
		local_hiker.position = Vector3(body_pos.x, net.player_motion.y, body_pos.y)
		local_hiker.outfit(int(self_data.get("slot",1)))
	if local_hiker != null:
		local_hiker.visible = hiker_visible
		var loose_stone := not Stones.held_by(net.stones, net.self_id).is_empty()
		local_hiker.eye_pitch = pitch
		local_hiker.set_eye_view(eye_body, not (Weapons.firearm(self_data.get("weapon", "")) or loose_stone))
		local_hiker.wear_clothes(net.survival.get("worn", Survival.initial_wear()))
		local_hiker.wear_backpack(not (piloting or eye_body or net.player_motion.get("crouched",false)) and str(net.player_motion.get("bed","")).is_empty() and net.backpack_enabled and net.backpack_owner == net.self_id)
		local_hiker.wear_trail_gear(int(net.survival.get("bag",{}).get("boar_bedroll",0))>0,int(net.survival.get("bag",{}).get("tusk_whistle",0))>0)
		if piloting:
			_seat_hiker(local_hiker)
		else:
			_stand_hiker(local_hiker, Vector3(body_pos.x, net.player_motion.y, body_pos.y))
			_storage_seat(local_hiker, net.player_motion)
			local_hiker.set_motion_state(net.player_motion)
			local_hiker.set_recovery_state(self_data, net.elapsed)
			local_hiker.melee.sync(self_data, net.elapsed)
			local_hiker.heading = float(net.player_motion.bedYaw) if not str(net.player_motion.get("bed","")).is_empty() else yaw
			local_hiker.holding = loose_stone or not str(net.survival.get("weapon", "")).is_empty()
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
		person.wear_backpack(not is_pilot and str(data.get("bed","")).is_empty() and not data.get("crouched",false) and net.backpack_owner == key)
		person.wear_trail_gear(data.get("bedroll",false),data.get("whistle",false))
		if is_pilot:
			_seat_hiker(person)
			person.show()
		else:
			_stand_hiker(person, at)
			_storage_seat(person, data)
			person.set_motion_state(data)
			person.set_recovery_state(data, net.elapsed)
			person.melee.sync(data, net.elapsed)
			person.heading = float(data.get("bedYaw",data.get("yaw", 0.0)))
			person.holding = not Stones.held_by(net.stones, key).is_empty() or not str(data.get("weapon", "")).is_empty()
			person.shielding = data.get("shield", false)
			person.blocking = data.get("blocking", false)
			person.advance(delta)
			person.visible = float(data.health) <= 0.0 or Vector2(person.position.x, person.position.z).distance_squared_to(body_pos) > 0.20

func _storage_seat(hiker: Node3D, actor: Dictionary) -> void:
	var seated: bool = actor.get("storageSeated", false)
	if hiker.seated != seated:
		hiker.set_seated(seated)
	if seated:
		hiker.position = hiker.target
		hiker.rotation.y = float(actor.get("yaw", yaw))


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
	var equipment_tab: Rect2 = hud.camp_tabs.role.get_global_rect()
	var viewport := get_viewport().get_visible_rect().size
	return {
		"ready": _playable(),
		"menuOpen": menu_open,
		"atlas": atlas.observables(),
		"east": {"packs":terrain.east.packs.keys(),"plants":terrain.east.counts,"darkness":weather.cave_darkness},
		"storageOpen": storage_panel.is_open, "storageTarget": storage_target, "heldStorage": held_storage,
		"storagePanel": storage_panel.observables(),
		"mineTarget": mine_target, "mines": net.mines,
		"rescueTarget": rescue_target, "rescueSeconds": Survival.rescue_time_left(net.survival.get("downAt", -1.0), net.elapsed),
		"storageRendered": storage_scene.live.size(),
		"placementPreview": {"visible":storage_scene.ghost != null and storage_scene.ghost.visible,
			"ok":placement.get("ok",false),"reason":placement.get("reason",""),"recipe":construction_recipe,
			"at":Stones.pack(placement.pose.origin) if placement.has("pose") else []},
		"connected":net.ready_in_room, "locked":locked, "room":room_code, "selfId":net.self_id,
		"members":net.players.size(), "players":net.players, "remoteAvatars":avatars.size(), "playerMotion":_motion_observables(), "localPhysics":{"grounded":net.player_motion.get("grounded", true), "vy":net.player_motion.get("vy", 0.0), "vx":net.player_motion.get("vx", 0.0), "vz":net.player_motion.get("vz", 0.0), "waterVy":net.player_motion.get("waterVy", 0.0)}, "x":body_pos.x, "z":body_pos.y,
		"yaw":yaw, "pitch":pitch, "quest":net.quest, "elapsed":net.elapsed, "rain":net.rain,
		"dayPart":weather.day_part, "stones":net.stones, "heldStone":held_stone, "pickupStone":pickup_stone,
		"stoneAction":stone_action, "lineCut":net.line_cut, "waterImpacts":net.water_impacts,
		"survival":net.survival, "provisions":net.provisions, "inventoryPanel":hud.inventory_observables(), "provisionScene":terrain.household.observables(net.provisions), "backpackOpen":backpack_open, "bagSlots":_bag_slots(),
		"equipmentOpen":backpack_open and hud.character_view.visible,
		"fieldGuide":hud.guide_page.observables() if hud.guide_page.is_visible_in_tree() else {"open": false},
		"equipmentTabRect":[equipment_tab.position.x,equipment_tab.position.y,equipment_tab.size.x,equipment_tab.size.y],
		"backpackOwner": net.backpack_owner, "backpackTarget": backpack_target,
		"thirdPerson": chase_ship if net.is_piloting() else boat_panorama if on_houseboat else third_person,
		"weaponView": {"aim": sight_blend, "fov": camera.fov, "firstPerson": first_person_view, "scope": hud.scope_overlay.visible},
		"dog": net.dog, "dogTarget": dog_target,
		"boatPanorama":boat_panorama, "crouched":net.player_motion.get("crouched",false), "restingBed":net.player_motion.get("bed",""), "deck":Stones.pack(Vector3(net.player_motion.get("ferryLocal",Vector2.ZERO).x,0,net.player_motion.get("ferryLocal",Vector2.ZERO).y)), "lakeLife":lake_life.observables(), "lakeTarget":lake_target, "onFerry":net.player_motion.get("onFerry",false),
		"boar":net.boar, "boarAnimation":forest_boar.clip, "reedTarget":reed_target,"reedCuts":net.reed_cuts, "sheepAlive":net.sheep_alive, "shearedAt":net.sheared_at,
		"wildPeople": net.wild_people, "peopleTarget": people_target, "peopleOpen": people_open, "sourceTarget": source_target, "peoplePanel": people_panel.observables(), "peopleWarmupMs": people_scene.warmup_ms, "peopleWarmupCount": people_scene.warmup_count, "peoplePoolHits": people_scene.pool_hits, "peopleColdCreates": people_scene.cold_creates, "peoplePoolByKey": people_scene.pool_by_key, "peopleColdByKey": people_scene.cold_by_key,
		"ship": net.ship, "shipPiloting": net.is_piloting(), "shipTarget": ship_target,
		"shipCameraYaw": ship_view_yaw,
		"fps": Engine.get_frames_per_second(),
		"swimming": net.player_motion.swimming and not net.is_piloting(), "y": net.player_motion.y,
		"canPutProvision":_can_put_on_table(), "foodTarget":food_target, "jugTarget":jug_target,
		"groveElapsed":net.grove_elapsed, "grove":terrain.grove.render_state(),
		"groveHint":terrain.grove.observe(camera.position, -camera.basis.z) if net.ready_in_room else "",
		"sheltered":bool(net.quest.get("repaired",false)) and absf(body_pos.x-1.9)<2.6 and absf(body_pos.y+89.6)<2.7,
		"zone":terrain.focus_zone(), "resident":terrain.resident_count(), "focusReady":terrain.is_focus_ready(),
		"lanternWarmupMs": terrain.lantern_warmup_ms,
		"previewWarming": preview_warming,
		"previewProgress": preview_progress,
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
