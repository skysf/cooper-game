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
const EYE_HEIGHT := 1.67
const MOUSE_SENSITIVITY := .00215
const NEAR := 2.5
const DEFAULT_WS := "ws://127.0.0.1:4184/room"

var net := Network.new()
var terrain := Terrain.new()
var weather := Weather.new()
var hud := Hud.new()
var stone_scene := StoneScene.new()
var camera := Camera3D.new()
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
var web_join
var web_document
var telemetry_clock := 0.
var last_log := ""
var status_record: FileAccess
var last_flags := -1
var setup_ok := false
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

func _ready() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	for key in world.sites:
		var p: Array = world.sites[key]
		sites[key] = Vector2(p[0],p[1])
	body_pos = Vector2(world.spawn[0],world.spawn[1])
	_read_join()
	add_child(camera)
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 78
	camera.near = .07
	camera.far = 105
	camera.current = true
	camera.position = Vector3(body_pos.x,EYE_HEIGHT,body_pos.y)
	camera.rotation = Vector3(pitch,yaw,0)
	terrain.configure(zone_base)
	add_child(terrain)
	terrain.update_focus(camera.position)
	add_child(weather)
	add_child(stone_scene)
	add_child(net)
	net.start_room(ws_url,room_code,join_token)
	add_child(hud)
	hud.resume_requested.connect(_capture)
	hud.invite_requested.connect(_invite)
	hud.backpack_close_requested.connect(_set_backpack.bind(false))
	hud.backpack_action_requested.connect(_use_backpack)
	setup_ok = true

func _read_join() -> void:
	if web:
		web_document = JavaScriptBridge.get_interface("document")
		web_join = JavaScriptBridge.get_interface("CooperJoin")
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
	if backpack_open or not net.ready_in_room or not terrain.is_focus_ready() or _mouse_locked():
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

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and setup_ok and not web:
		_release()

func _set_backpack(open: bool) -> void:
	if backpack_open == open:
		return
	if open and (not net.ready_in_room or not terrain.is_focus_ready() or net.survival.is_empty()):
		return
	if open:
		backpack_resume_lock = _mouse_locked()
	backpack_open = open
	hud.set_backpack_open(open, net.survival.get("bag", {}), Survival.can_put(body_pos))
	if web and web_join != null:
		web_join.setBackpackOpen(open)
	if open:
		_release()
	elif not web and backpack_resume_lock:
		_capture()

func _input(event: InputEvent) -> void:
	if not setup_ok or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_TAB and not (event.alt_pressed or event.ctrl_pressed or event.meta_pressed) and (backpack_open or not net.survival.is_empty()):
		_set_backpack(not backpack_open)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and backpack_open:
		_set_backpack(false)
		get_viewport().set_input_as_handled()

func _use_backpack(action: String, item: String) -> void:
	if backpack_open:
		net.interact_provision(action, item)

func _unhandled_input(event: InputEvent) -> void:
	if not setup_ok or backpack_open:
		return
	if event is InputEventMouseMotion and _mouse_locked():
		yaw = wrapf(yaw - event.relative.x*MOUSE_SENSITIVITY,-PI,PI)
		pitch = clampf(pitch - event.relative.y*MOUSE_SENSITIVITY,-1.44,1.51)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _mouse_locked() and not held_stone.is_empty():
			net.interact_stone("throw", "", yaw, pitch)
		else:
			_capture()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				if not web:
					_release()
			KEY_E:
				if locked:
					if not food_target.is_empty():
						net.interact_provision("take", str(net.provisions[food_target].item), food_target)
					elif not pickup_stone.is_empty():
						net.interact_stone("pick", pickup_stone)
					elif not grindstone_target and not nearby.is_empty():
						net.interact(nearby)
			KEY_F:
				if locked:
					if not food_target.is_empty():
						net.interact_provision("eat_table", str(net.provisions[food_target].item), food_target)
					elif jug_target:
						net.interact_provision("drink")
					elif not stone_action.is_empty():
						net.interact_stone("context")
			KEY_G:
				if locked and not held_stone.is_empty():
					net.interact_stone("drop")
			KEY_Q:
				if locked:
					prefer_tarp = not prefer_tarp

func _physics_process(_delta: float) -> void:
	if not setup_ok:
		return
	locked = _mouse_locked() and not backpack_open
	var move := Vector2.ZERO
	if locked and net.ready_in_room and terrain.is_focus_ready():
		var sideways := float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
		var forward := float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))
		move = Vector2(sideways,-forward).rotated(-yaw).limit_length(1.)
	net.set_motion(move,yaw)

func _process(delta: float) -> void:
	if not setup_ok:
		return
	locked = _mouse_locked() and not backpack_open
	if backpack_open and not net.ready_in_room:
		_set_backpack(false)
	if locked and not net.ready_in_room:
		_release()
		locked = false
	var previous := body_pos
	if net.ready_in_room:
		body_pos = net.local_position
	var stride := minf(body_pos.distance_to(previous),.18)
	leg_phase += stride * 4.7
	var bob := sin(leg_phase*2.) * .019 * clampf(stride / maxf(delta,.001),0.,1.)
	var height := LakeLayout.walk_height(body_pos) + EYE_HEIGHT + bob
	camera.position = Vector3(body_pos.x, lerpf(camera.position.y, height, minf(delta * 15.0, 1.0)), body_pos.y)
	camera.rotation = Vector3(pitch,yaw,0)
	terrain.update_focus(camera.position)
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
	weather.update_weather(camera.position,yaw,net.elapsed,net.rain,repaired)
	_update_water()
	_sync_hikers(delta)
	_update_stones()
	_update_provisions()
	nearby = _reachable(wood,tarp,repaired)
	plan = _goal(wood,tarp)
	hud_clock -= delta
	telemetry_clock -= delta
	if hud_clock <= 0.0:
		hud_clock = .12
		var state := _state()
		hud.refresh(state,plan,sites[plan]-body_pos,_interaction_prompt(wood and tarp))
		if telemetry_clock <= 0.0:
			telemetry_clock = .25
			_publish(state)

func _update_stones() -> void:
	stone_scene.update_stones(net.stones, avatars, net.self_id, camera, net.elapsed, net.rain, net.line_cut)
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
		if stone.mode not in ["ground", "placed", "submerged"]:
			continue
		var at := Stones.unpack(stone.at)
		if at.y < -0.42 or body_pos.distance_squared_to(Vector2(at.x, at.z)) > Stones.PICKUP_REACH ** 2:
			continue
		var facing := forward.dot(camera.position.direction_to(at))
		if facing > best:
			pickup_stone = id
			best = facing

func _update_water() -> void:
	terrain.update_water(net.elapsed, net.rain, {
		"sun_direction": weather.sun_direction, "moon_direction": weather.moon_direction,
		"sky_zenith": weather.sky_zenith, "sky_horizon": weather.sky_horizon,
		"sun_color": weather.sun_color, "moon_color": weather.moon_color, "cloud_cover": weather.cloud_cover,
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
	if not net.ready_in_room or not terrain.is_focus_ready() or net.survival.is_empty():
		return
	var best := 0.985
	var forward := -camera.basis.z
	for id: String in net.provisions:
		var food: Dictionary = net.provisions[id]
		var at := Stones.unpack(food.at)
		if not Survival.can_reach(body_pos, Vector2(at.x, at.z), str(food.surface)):
			continue
		var score := forward.dot(camera.position.direction_to(at + Vector3.UP * 0.05))
		if score > best:
			food_target = id
			best = score
	if Survival.can_drink(body_pos):
		var jug := Vector3(Survival.JUG.x, Survival.TABLE_TOP + 0.14, Survival.JUG.y)
		if forward.dot(camera.position.direction_to(jug)) > best:
			food_target = ""
			jug_target = true

func _interaction_prompt(can_fix: bool) -> String:
	if not food_target.is_empty():
		var item: String = net.provisions[food_target].item
		return "%s    E  拾取    F  吃" % Survival.ITEM_NAMES[item]
	if jug_target:
		return "F    喝水"
	if not pickup_stone.is_empty():
		return "E    捡起石片" if Stones.flat(pickup_stone) else "E    捡起苔藓石"
	match stone_action:
		"grind": return "F    用磨石磨出刃口"
		"press": return "F    用石块压住帆布角"
		"cut": return "F    割一段麻绳做营地拉绳"
	if grindstone_target:
		if Stones.flat(held_stone) and int(net.stones[held_stone].edge) == 3:
			return "磨石    手里的石片已经磨利"
		if Stones.flat(held_stone) or body_pos.distance_squared_to(Stones.GRIND) > Stones.REACH ** 2:
			return "走近磨石    拿着扁石片按 F"
		return "磨石    拿着扁石片按 F"
	return _action(nearby, can_fix)

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
		return
	for key in net.players:
		if key==net.self_id:
			continue
		var data: Dictionary = net.players[key]
		var at := Vector3(data.x, LakeLayout.walk_height(Vector2(data.x, data.z)), data.z)
		if not avatars.has(key):
			var hiker := Hiker.new()
			add_child(hiker)
			hiker.position = at
			hiker.outfit(int(data.get("slot",2)))
			avatars[key] = hiker
		var person = avatars[key]
		person.target = at
		person.heading = float(data.get("yaw",0.))
		person.holding = not Stones.held_by(net.stones, key).is_empty()
		person.advance(delta)
		person.visible = Vector2(person.position.x,person.position.z).distance_squared_to(body_pos) > .20

func _state() -> Dictionary:
	var button_rect := hud.enter.get_global_rect()
	var panel_rect := hud.panel.get_global_rect()
	var invite_rect := hud.invite.get_global_rect()
	var viewport := get_viewport().get_visible_rect().size
	return {
		"ready": net.ready_in_room and terrain.is_focus_ready(),
		"connected":net.ready_in_room, "locked":locked, "room":room_code, "selfId":net.self_id,
		"members":net.players.size(), "players":net.players, "remoteAvatars":avatars.size(), "x":body_pos.x, "z":body_pos.y,
		"yaw":yaw, "pitch":pitch, "quest":net.quest, "elapsed":net.elapsed, "rain":net.rain,
		"dayPart":weather.day_part, "stones":net.stones, "heldStone":held_stone, "pickupStone":pickup_stone,
		"stoneAction":stone_action, "lineCut":net.line_cut, "waterImpacts":net.water_impacts,
		"survival":net.survival, "provisions":net.provisions, "backpackOpen":backpack_open,
		"canPutProvision":Survival.can_put(body_pos), "foodTarget":food_target, "jugTarget":jug_target,
		"groveElapsed":net.grove_elapsed, "grove":terrain.grove.render_state(),
		"groveHint":terrain.grove.observe(camera.position, -camera.basis.z) if net.ready_in_room else "",
		"sheltered":bool(net.quest.get("repaired",false)) and absf(body_pos.x-1.9)<2.6 and absf(body_pos.y+89.6)<2.7,
		"zone":terrain.focus_zone(), "resident":terrain.resident_count(), "focusReady":terrain.is_focus_ready(),
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
