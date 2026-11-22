extends SceneTree
const Client = preload("res://client.gd")
const Stones = preload("res://stones.gd")
const CampDog = preload("res://camp_dog.gd")
const Wildlife = preload("res://wildlife.gd")
const CampAudio = preload("res://camp_audio.gd")

class OfflineNetwork extends "res://network.gd":
	var last_stone_input: Dictionary = {}
	var last_provision_input: Dictionary = {}
	var last_dog_input: Dictionary = {}
	var last_ship_input: Dictionary = {}

	func start_room(_url: String, _code: String, _token: String = "") -> void:
		pass

	func _send(message: Dictionary) -> void:
		if message.get("t") == "stone":
			last_stone_input = message
		elif message.get("t") == "provision":
			last_provision_input = message
		elif message.get("t") == "dog":
			last_dog_input = message
		elif message.get("t") == "ship":
			last_ship_input = message

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _run() -> void:
	var client := Client.new()
	client.net.free()
	client.net = OfflineNetwork.new()
	root.add_child(client)
	client.set_process(false)
	client.set_physics_process(false)
	client.net.set_process(false)
	client.terrain.set_process(false)
	client.net.ready_in_room = true
	client.net.self_id = "tester"
	client.terrain.loaded.camp = true
	client.net.stones = Stones.initial()
	var grind := Vector3(Stones.GRIND.x, Stones.GRIND_HEIGHT, Stones.GRIND.y)
	client.body_pos = Vector2(0.96, -88.53)
	client.camera.position = Vector3(client.body_pos.x, Client.EYE_HEIGHT, client.body_pos.y)
	client.camera.look_at(grind)
	client.yaw = client.camera.rotation.y
	client._update_stones()
	var empty_hint := client._interaction_prompt(true)
	_check(client.grindstone_target and client.pickup_stone.is_empty() and "固定磨石" in empty_hint and "F" not in empty_hint, "The fixed grindstone must direct an empty-handed player to a flat stone.")
	client.locked = true
	for button: Key in [KEY_E, KEY_F]:
		var key := InputEventKey.new()
		key.physical_keycode = button
		key.pressed = true
		client._unhandled_input(key)
		_check(client.net.last_stone_input.is_empty() and "扁石片在" in client.hud.toast.text and "按 E" in client.hud.toast.text, "Both keys help locate the nearby flat stone without sending a grind request.")
	client.body_pos = Vector2(1.9, -85.0)
	client.camera.position = Vector3(client.body_pos.x, Client.EYE_HEIGHT, client.body_pos.y)
	for id in ["camp-flat", "camp-round"]:
		client.camera.look_at(Stones.unpack(client.net.stones[id].at))
		client._update_stones()
		_check(client.pickup_stone == id and "E" in client._interaction_prompt(true), "The actual camp stone must still be pickable: " + id)
		var pick_key := InputEventKey.new()
		pick_key.physical_keycode = KEY_E
		pick_key.pressed = true
		client._unhandled_input(pick_key)
		_check(client.net.last_stone_input.get("action") == "pick" and client.net.last_stone_input.get("id") == id, "E requests the small stone shown in the current pickup prompt.")
	client.body_pos = Vector2(0.96, -87.45)
	client.camera.position = Vector3(client.body_pos.x, Client.EYE_HEIGHT, client.body_pos.y)
	client.camera.look_at(grind)
	client.net.stones["camp-round"].mode = "held"
	client.net.stones["camp-round"].holder = "tester"
	client._update_stones()
	_check("按 G 放下圆石" in client._interaction_prompt(true), "A player holding a round stone should be told how to free their hand.")
	client.net.stones["camp-round"].mode = "ground"
	client.net.stones["camp-round"].erase("holder")
	client.net.stones["camp-flat"].mode = "held"
	client.net.stones["camp-flat"].holder = "tester"
	client._update_stones()
	_check(client.stone_action == "grind" and "F" in client._interaction_prompt(true), "Holding a flat stone in reach must offer F.")
	var grind_key := InputEventKey.new()
	grind_key.physical_keycode = KEY_F
	grind_key.pressed = true
	client._unhandled_input(grind_key)
	_check(client.net.last_stone_input.get("action") == "context", "F sends a grind interaction with the right stone near the grindstone.")
	client.net.stones["camp-flat"].edge = 3
	client._update_stones()
	_check(client.stone_action.is_empty() and "已经磨利" in client._interaction_prompt(true), "Aiming at the grindstone with a sharpened stone should never trigger the nearby rope action.")
	var rope := Vector3(Stones.ROPE.x, 0.115, Stones.ROPE.y)
	client.camera.look_at(rope)
	client._update_stones()
	_check(client.stone_action == "cut", "The sharpened stone must still cut when looking at the rope.")

	var terrain := client.terrain
	_check(terrain.fire_lamp.visible and terrain.flame.visible and terrain.fire_lamp.light_energy == 0.0, "The unlit lamp must already be registered with zero energy.")
	terrain.set_quest(true, true, true)
	_check(terrain.roof_patch.visible and terrain.fire_lamp.light_energy == 0.0, "Repair should start the light transition at zero.")
	terrain.update_flame(0.0, 0.11)
	var early := terrain.fire_lamp.light_energy
	terrain.update_flame(0.0, 0.22)
	var middle := terrain.fire_lamp.light_energy
	terrain.update_flame(0.0, 0.22)
	_check(early > 0.0 and early < middle and middle < 1.35 and is_equal_approx(terrain.fire_lamp.light_energy, 1.35), "Lamp must rise smoothly to its full intensity.")
	terrain.set_quest(false, false, false)
	terrain.update_flame(0.0, 0.55)
	_check(terrain.fire_lamp.visible and terrain.flame.visible and terrain.fire_lamp.light_energy == 0.0, "Reset must fade the lamp back to zero.")

	var weather := client.weather
	var previous := 0.0
	var passed_twilight := false
	var found_night := false
	for i in range(2000, 3600):
		weather._update_sky(float(i) * 0.1, 0.0)
		var opacity := weather.sun.shadow_opacity
		_check(weather.sun.shadow_enabled and absf(opacity - previous) < 0.1, "The dawn shadow configuration must remain stable and its opacity must be continuous.")
		found_night = found_night or (weather.day_part == "night" and opacity == 0.0)
		passed_twilight = passed_twilight or (opacity > 0.05 and opacity < 0.95)
		previous = opacity
	_check(found_night and passed_twilight and is_equal_approx(previous, 1.0), "The sweep must cover night, dawn and full daylight.")
	weather._update_sky(360.0, 1.0)
	_check(weather.sun.shadow_enabled and weather.sun.shadow_opacity == 0.0, "Storms should fade shadow opacity while keeping the pass configured.")
	_verify_evening(client)
	_verify_backpack_and_view(client)
	_verify_clothing(client)
	_verify_inventory_filters(client)
	_verify_cached_character_preview(client)
	_verify_dog(client)
	_verify_audio(client)
	_verify_wildlife(client)
	_verify_travel_controls(client)
	_verify_jump_eye(client)
	client.free()
	if failures == 0:
		print("CAMP_FEEDBACK_OK: camp, avatar, equipment, dog, crocodile animations and eagle flight and perch")
	quit(int(failures != 0))

func _verify_travel_controls(client) -> void:
	var ship := Client.Spaceship.from_save(null, {})
	client.net.ship = ship
	client.spaceship.sync(ship, 0.0, 1.0 / 60.0)
	var hull: MeshInstance3D = client.spaceship.find_children("*", "MeshInstance3D", true, false)[0]
	_check(hull.get_aabb().size.z > 4.5 and hull.get_active_material(0).albedo_texture != null,
		"the imported flight model has the intended scale and textured hull")
	client.body_pos = Client.Spaceship.exit_point(ship)
	client.terrain.update_focus(Vector3(client.body_pos.x, 1.67, client.body_pos.y))
	client.camera.position = Vector3(client.body_pos.x, 1.67, client.body_pos.y)
	client.camera.look_at(Client.Spaceship.position(ship) + Vector3.UP * 0.85)
	client._update_ship_target()
	_check(client.ship_target and "登上飞船" in client._interaction_prompt(true), "a nearby pointed-at ship offers boarding")
	client.locked = true
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	client._unhandled_input(key)
	_check(client.net.last_ship_input.get("action") == "board", "E sends the board action")
	ship.pilot = client.net.self_id
	client.chase_ship = true
	client._sync_hikers(1.0 / 60.0)
	var hip := _avatar_joint(client.local_hiker, &"thigh_R")
	var knee := _avatar_joint(client.local_hiker, &"shin_R")
	var ankle := _avatar_joint(client.local_hiker, &"foot_R")
	_check(client.local_hiker.visible and client.local_hiker.seated
		and client.local_hiker.get_parent() == client.spaceship.seat
		and knee.z < hip.z - 0.35 and absf(knee.y - hip.y) < 0.07 and ankle.y < knee.y - 0.32
		and client.local_hiker.garments.pants.visible,
		"the visible local driver uses the clothed seated model with bent knees")
	ship.y = 2.4
	ship.thrust = 1.0
	ship.landed = false
	for i in 12:
		client.spaceship.sync(ship, 0.0, 1.0 / 60.0, true)
	for i in client.spaceship.lift_jets.size():
		var jet: MeshInstance3D = client.spaceship.lift_jets[i]
		_check(jet.visible and jet.position.y < -0.3 and jet.get_parent().position
			== Client.SpaceshipScene.LIFT_PORTS[i], "each downward lift stream is below an original engine nozzle")
		_check(not client.spaceship.tail_jets[i].visible, "a vertical climb leaves both rear bells dark")
	ship.rearThrust = 1.0
	for i in 12:
		client.spaceship.sync(ship, 0.0, 1.0 / 60.0, true)
	for i in client.spaceship.tail_jets.size():
		var tail: MeshInstance3D = client.spaceship.tail_jets[i]
		var bell := tail.get_parent() as Node3D
		_check(tail.visible and bell.position == Client.SpaceshipScene.TAIL_PORTS[i]
			and (bell.basis * tail.position).z > 1.0 and client.spaceship.lift_jets[i].visible,
			"diagonal climb emits rearward from the real aft bells and still uses the downward jets")
	ship.rearThrust = 0.0
	for i in 22:
		client.spaceship.sync(ship, 0.0, 1.0 / 60.0, true)
	_check(not client.spaceship.tail_jets[0].visible and not client.spaceship.tail_jets[1].visible,
		"the two aft plumes shut off when aft thrust ends")
	key.physical_keycode = KEY_V
	client._unhandled_input(key)
	client._update_ship_camera()
	client._sync_hikers(1.0 / 60.0)
	_check(not client.chase_ship and not client.local_hiker.visible
		and client.camera.position.is_equal_approx(client.spaceship.cockpit_eye()),
		"V switches to the cockpit eye and releases the visible avatar from that view")
	for chase: bool in [false, true]:
		client.chase_ship = chase
		client.ship_view_yaw = 3.1
		client.yaw = -3.0
		var previous: float = client.ship_view_yaw
		for i in 10:
			client._update_ship_camera(1.0 / 30.0)
			var turn := angle_difference(previous, float(client.ship_view_yaw))
			_check(turn >= 0.0 and turn < 0.13, "both cameras turn continuously across 180 degrees at 30 Hz")
			previous = client.ship_view_yaw
		_check(absf(angle_difference(previous, client.yaw)) < 0.002, "the view settles on the requested heading")
	key.physical_keycode = KEY_E
	client._unhandled_input(key)
	_check(client.net.last_ship_input.get("action") == "exit", "E sends the disembark action when aboard")
	ship.pilot = "teammate"
	client.net.players.teammate = {"x": ship.x, "y": ship.y, "z": ship.z, "slot": 2}
	client._sync_hikers(1.0 / 60.0)
	_check(client.avatars.teammate.visible and client.avatars.teammate.seated
		and client.avatars.teammate.get_parent() == client.spaceship.seat,
		"a remote pilot uses the same visible driving position")
	client.weather.update_weather(Vector3(-26, -1, -50), 30.0, 0.0, false, true)
	client._update_water()
	_check(client.weather.underwater and client.weather.environment.fog_depth_end <= 16.0
		and client.terrain.lake.lake_material.get_shader_parameter("underwater"), "diving selects underwater fog and water shading")
	client.weather.update_weather(Vector3(-26, 1, -50), 30.0, 0.0, false)
	_check(not client.weather.underwater and client.weather.environment.fog_depth_end >= 600.0, "Surfacing restores the distant ridges.")
	client.weather.update_weather(Vector3(255,29,-94), 38.0, 0.0, false)
	_check(client.camera.far >= client.weather.environment.fog_depth_end and client.weather.environment.fog_depth_begin >= 100.0,
		"Clear inland air and the camera both admit the far side of the watershed.")
	client.weather.update_weather(Vector3(255,29,-94), 82.0, 1.0, false)
	_check(client.weather.environment.fog_depth_end <= 52.0, "Heavy rain reduces inland visibility.")

func _verify_jump_eye(client: Client) -> void:
	client.third_person = false
	client.net.ship.pilot = ""
	client.net.players.erase("teammate")
	client.net.local_position = Vector2(1,-85)
	var grid := client.follow_camera.blockers
	for fps: float in [30.,60.]:
		var actor := Client.PlayerMotion.spawn(client.net.local_position)
		client.net.player_motion = actor
		client.body_pos = client.net.local_position
		client.eye_offset = Client.EYE_HEIGHT
		var worst := 0.0
		var peak := 0.0
		for i in int(fps):
			Client.PlayerMotion.step(actor,Vector2.ZERO,float(i==1),1./fps,grid,{})
			client._process(1./fps)
			worst = maxf(worst,absf(client.camera.position.y-client.local_hiker.position.y-Client.EYE_HEIGHT))
			peak = maxf(peak,actor.y)
		_check(peak > .45 and actor.grounded and worst < .002,
			"First-person eye stays above the collar through takeoff and landing at %d FPS (error %.4f m)." % [fps,worst])

func _verify_evening(client) -> void:
	var weather = client.weather
	var water: ShaderMaterial = client.terrain.lake.lake_material
	var photo: Texture2D = weather.sky_material.get_shader_parameter("evening_sky")
	_check(photo != null and photo.get_width() == 2048 and water.get_shader_parameter("evening_sky") == photo,
		"The sky and lake should use the same 2K evening panorama.")
	for sample: Vector3 in [Vector3(36, 0, 0), Vector3(120, 0, 1), Vector3(120, 1, 0),
			Vector3(158, 0, 0), Vector3(290, 0, 0), Vector3(540, 0, 1)]:
		client.net.elapsed = sample.x
		client.net.rain = sample.y
		weather._update_sky(sample.x, sample.y)
		client._update_water()
		_check((weather.evening_weight > 0.5 if sample.z > 0.0 else is_zero_approx(weather.evening_weight))
			and is_equal_approx(water.get_shader_parameter("evening_weight"), weather.evening_weight)
			and is_equal_approx(water.get_shader_parameter("twilight"), weather.twilight),
			"Sky and water should share twilight at room time %s with rain %s." % [sample.x, sample.y])

func _verify_backpack_and_view(client) -> void:
	client.net.survival = {"bag":{"apple": 3, "bread": 1}}
	client.net.backpack_enabled = true
	client.net.stones = {}
	client.body_pos = Vector2(1.18, -88.72)
	client.camera.position = Vector3(client.body_pos.x, Client.EYE_HEIGHT, client.body_pos.y)
	var backpack := client.terrain.household.ground_backpack as Node3D
	client.camera.look_at(backpack.global_position)
	client._update_provisions()
	_check(backpack.visible and client.backpack_target and client._bag_slots() == 6, "the floor backpack has a pickup prompt before equipping")
	client._set_backpack(true)
	var hud = client.hud
	_check(hud.backpack_slots[0].icon != null and hud.backpack_slots[1].icon != null and hud.backpack_slots[0].text.is_empty() and hud.backpack_quantities[0].text == "×3" and not hud.backpack_slots[6].visible, "food slots render model thumbnails in the original six-slot inventory")
	client._set_backpack(false)
	client.net.backpack_owner = client.net.self_id
	client._update_provisions()
	client._set_backpack(true)
	_check(not backpack.visible and not client.backpack_target and client._bag_slots() == 12 and hud.backpack_slots[11].visible, "wearing the backpack removes it from the floor and reveals six more slots")
	client._set_backpack(false)

	var key := InputEventKey.new()
	key.physical_keycode = KEY_V
	key.pressed = true
	client.locked = true
	client._unhandled_input(key)
	client.body_pos = Vector2(1.9, -85.0)
	client.pitch = 0.10
	client.yaw = 0.0
	var eye := Vector3(client.body_pos.x, Client.EYE_HEIGHT, client.body_pos.y)
	client._update_camera(eye, 0.016)
	client._sync_hikers(0.016)
	var person := client.local_hiker as Node3D
	_check(client.third_person and person != null and person.visible and person.backpack.visible, "V shows the same player's body and worn backpack")
	var frame: Rect2 = client.get_viewport().get_visible_rect()
	for y in [0.02, 1.75]:
		var point: Vector3 = person.global_position + Vector3.UP * y
		_check(not client.camera.is_position_behind(point) and frame.has_point(client.camera.unproject_position(point)), "the follow camera keeps both feet and head in frame")
	var wall_clearance: float = client.follow_camera.clear_distance(Vector3(4.05, 1.1, -89.5), Vector3(3.5, 0.0, 0.0))
	_check(wall_clearance < 0.6, "the camera retracts before crossing the cabin wall")
	client._unhandled_input(key)
	client._update_camera(eye, 0.016)
	client._sync_hikers(0.016)
	_check(not client.third_person and person.visible and person.eye_view and not person.head_mesh.visible
		and person.boots[0].is_visible_in_tree() and not person.backpack.visible and client.camera.position.is_equal_approx(eye),
		"V restores the eye position, hides the camera-side head and exposes the player's own feet")

func _verify_clothing(client) -> void:
	var survival := preload("res://survival.gd")
	client.net.survival = survival.initial_state()
	client.net.survival.bag.cap = 2
	client.net.survival.worn.cap = false
	client._set_backpack(true)
	var hud = client.hud
	hud._select_slot(0)
	_check(hud.backpack_slots[0].icon != null and hud.backpack_items.count("cap") == 1 and hud.backpack_quantities[0].text == "×2" and hud.detail_title.text == "帽子", "identical garments share one slot with their total count and actual image")
	_check(hud.backpack_actions.wear.visible and not hud.backpack_actions.eat.visible, "clothing has wear and drop actions instead of food actions")
	hud._submit_backpack_action("wear")
	_check(client.net.last_provision_input.get("action") == "wear", "the item page sends a wear request")
	hud._show_camp_page("role")
	hud._select_equipment("jacket")
	var preview = hud.character_preview.person
	_check(hud.character_view.visible and not hud.inventory_view.visible and preview.garments.jacket.visible and preview.garments.pants.visible and not preview.garments.has("cap"), "the rotatable character shows exactly the equipped clothes")
	_check(preview.model.find_child("SkyHead", true, false) != null and preview.hair.visible,
		"the character screen shows the imported portrait and its hair when the cap is off")
	preview.wear_clothes(survival.initial_wear())
	_check(not preview.hair.visible and preview.garments.cap.visible
		and preview.model.find_child("SkyGlasses", true, false).visible,
		"wearing the cap hides only the crown hair and keeps the glasses on the face")
	preview.wear_clothes(client.net.survival.worn)
	var arm: Skeleton3D = preview.garment_rigs.jacket.skeleton
	var leg: Skeleton3D = preview.garment_rigs.pants.skeleton
	var forearm := arm.find_bone(&"Forearm_R")
	var shin := leg.find_bone(&"Shin_R")
	var arm_standing := arm.get_bone_global_pose(forearm)
	var leg_standing := leg.get_bone_global_pose(shin)
	var boot_standing: Transform3D = preview.boots[1].transform
	var relaxed_hand: Vector3 = preview.body.to_local(preview.held_item_position())
	preview.heading = preview.rotation.y
	preview.holding = true
	for frame in 15:
		preview.target = preview.position + Vector3(0, 0, 0.05)
		preview.advance(0.016, true)
	_check(not arm_standing.basis.is_equal_approx(arm.get_bone_global_pose(forearm).basis)
		and not leg_standing.basis.is_equal_approx(leg.get_bone_global_pose(shin).basis),
		"moving the human arm and knee also moves the worn jacket and trousers")
	_check(not preview.model.find_child("SkyFeet", true, false).visible
		and not boot_standing.is_equal_approx(preview.boots[1].transform),
		"the outdoor boot follows the foot bone without bare-foot geometry clipping through it")
	_check((preview.body.to_local(preview.held_item_position()) - relaxed_hand).length() > 0.32,
		"raising the modeled right hand moves the world stone grip")
	preview.holding = false
	for frame in 30:
		preview.advance(0.016, true)
	_check(arm_standing.is_equal_approx(arm.get_bone_global_pose(forearm))
		and leg_standing.is_equal_approx(leg.get_bone_global_pose(shin)),
		"stopping smoothly restores the garments to the fitted standing pose")
	hud._submit_equipment_action("drop_worn")
	_check(client.net.last_provision_input.get("action") == "drop_worn" and client.net.last_provision_input.get("item") == "jacket", "the character page can drop a worn garment directly")
	client._set_backpack(false)
	var spot := Vector3(1.9, 0.012, -85.2)
	client.net.provisions = {"ground-jacket": survival.provision("jacket", spot, "ground")}
	client.body_pos = Vector2(1.9, -84.5)
	client.camera.position = Vector3(1.9, Client.EYE_HEIGHT, -84.5)
	client.camera.look_at(spot + Vector3.UP * 0.05)
	client._update_provisions()
	_check(client.terrain.household.food_nodes.has("ground-jacket"), "the ground drop uses the same jacket mesh")
	_check(client.food_target == "ground-jacket" and client._interaction_prompt(true) == "G    拿起夹克", "aiming at clothing offers the pickup key")
	var pick_key := InputEventKey.new()
	pick_key.physical_keycode = KEY_G
	pick_key.pressed = true
	client.locked = true
	client._unhandled_input(pick_key)
	_check(client.net.last_provision_input.get("action") == "take" and client.net.last_provision_input.get("id") == "ground-jacket", "G picks up the targeted garment")

func _avatar_joint(hiker: Node3D, joint: StringName) -> Vector3:
	return hiker.rig.get_bone_global_pose(hiker.rig.find_bone(joint)).origin

func _verify_inventory_filters(client) -> void:
	var survival := preload("res://survival.gd")
	client.net.survival = survival.initial_state()
	client.net.survival.bag = {"apple": 4, "bread": 1, "cap": 1}
	client.net.survival.worn.cap = false
	client._set_backpack(true)
	var hud = client.hud
	hud._show_camp_page("bag")
	hud.category_buttons.gear.pressed.emit()
	_check(not hud.backpack_slots[0].visible and hud.backpack_slots[2].visible and hud.detail_title.text == "帽子",
		"filtering to gear selects the visible hat without changing its physical inventory slot")
	hud._refresh_backpack({"bread": 1, "cap": 1}, false, survival.SLOT_COUNT)
	_check(hud.selected_slot == 1 and hud.detail_title.text == "帽子",
		"the selected garment remains selected when removing earlier stacks shifts its slot")
	hud.category_buttons.food.pressed.emit()
	_check(hud.detail_title.text == "面包" and hud.backpack_actions.eat.visible and hud.backpack_actions.put.disabled,
		"filtering to food exposes the eat action and disables returning food away from the table")
	hud._refresh_backpack({"bread": 1, "cap": 1}, true, survival.SLOT_COUNT)
	_check(not hud.backpack_actions.put.disabled, "returning food becomes available when the player reaches the table")
	hud.camp_tabs.role.pressed.emit()
	hud.equipment_buttons.cap.pressed.emit()
	hud.equipment_actions.wear.pressed.emit()
	_check(client.net.last_provision_input.get("action") == "wear" and client.net.last_provision_input.get("item") == "cap",
		"an occupied backpack slot can equip an empty body slot directly from the clothing page")
	hud._refresh_backpack({"apple": 18, "bread": 7, "cap": 4, "water": 7, "club": 4, "spear": 4}, false, survival.SLOT_COUNT)
	hud.equipment_buttons.jacket.pressed.emit()
	_check(hud.equipment_actions.remove_worn.disabled and not hud.equipment_actions.drop_worn.disabled,
		"a full backpack disables removing a worn jacket while leaving direct dropping available")
	hud.category_buttons.all.pressed.emit()
	hud.camp_tabs.bag.pressed.emit()
	_check(hud.character_preview.view.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"switching back to inventory stops rendering the character viewport")
	client._set_backpack(false)

func _verify_cached_character_preview(client) -> void:
	var hud = client.hud
	client._set_backpack(true)
	hud._show_camp_page("bag")
	var preview = hud.character_preview
	var model_id: int = preview.person.get_instance_id()
	preview.update_character(hud.worn, hud.wearing_backpack, hud.preview_slot + 1)
	_check(preview.person.get_instance_id() == model_id
		and preview.view.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"updating the hidden preview keeps the prepared avatar and does not start drawing")
	preview._draw_once()
	# The headless renderer cannot submit a frame. Simulate the one draw having completed.
	preview._finish_draw()
	hud._show_camp_page("role")
	_check(preview.view.render_target_update_mode == SubViewport.UPDATE_DISABLED
		and preview.texture == preview.view.get_texture(),
		"first opening with an existing portrait reuses the retained texture without rendering again")
	hud._show_camp_page("bag")
	hud._show_camp_page("role")
	_check(preview.view.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"closing and reopening the role page keeps the cached image")
	client._set_backpack(false)

func _verify_dog(client) -> void:
	client.net.provisions = {}
	client._update_provisions()
	client.net.dog = CampDog.from_save(null, {}, {}, false, 12.0)
	client.net.elapsed = 12.0
	client.body_pos = CampDog.HOME + Vector2(0.0, 1.35)
	client.camera.position = Vector3(client.body_pos.x, Client.EYE_HEIGHT, client.body_pos.y)
	client.camera.look_at(Vector3(CampDog.HOME.x, 0.52, CampDog.HOME.y))
	client._update_dog(0.016)
	var player: AnimationPlayer = client.camp_dog.player
	_check(client.camp_dog.visible and client.dog_target and "收养" in client._interaction_prompt(true), "the mastiff is visible and an unowned dog can be adopted")
	_check(player.current_animation == CampDog.IDLE and player.get_animation(CampDog.IDLE).loop_mode == Animation.LOOP_LINEAR, "the standing dog plays the living idle loop")
	var use := InputEventKey.new()
	use.physical_keycode = KEY_E
	use.pressed = true
	client.locked = true
	client._unhandled_input(use)
	_check(client.net.last_dog_input.get("action") == "adopt", "E sends adoption on the dog target")
	client.net.dog.owner = client.net.self_id
	client.net.dog.mode = "follow"
	client._unhandled_input(use)
	_check(client.net.last_dog_input.get("action") == "stay", "the adopter can ask the dog to wait")
	client.net.dog.mode = "stay"
	client._unhandled_input(use)
	_check(client.net.last_dog_input.get("action") == "follow", "the waiting dog can be recalled")
	for clip: String in [CampDog.DOWN, CampDog.REST, CampDog.RISE]:
		client.net.dog.clip = clip
		client.net.dog.clipAt = 11.55
		client._update_dog(0.016)
		_check(player.current_animation == clip and is_equal_approx(player.current_animation_position, 0.45), "the client plays the synchronized dog animation at the room phase: " + clip)
	_check(player.get_animation(CampDog.REST).loop_mode == Animation.LOOP_LINEAR, "the imported rest animation is a loop")
	for gait: Array in [[CampDog.WALK, CampDog.WALK_SPEED], [CampDog.RUN, CampDog.TROT_SPEED]]:
		client.net.dog.clip = gait[0]
		client.net.dog.speed = gait[1] * 1.25
		client._update_dog(0.016)
		_check(player.current_animation == gait[0] and player.get_animation(gait[0]).loop_mode == Animation.LOOP_LINEAR and is_equal_approx(player.speed_scale, 1.25), "walking and trotting cycle at the actual movement pace")
	client.net.dog = {}
	client._update_dog(0.016)
	_check(not client.camp_dog.visible and not client.dog_target, "old servers and disconnects do not show a stale dog")

func _verify_wildlife(client) -> void:
	var animals = client.wildlife
	var crocodile_player: AnimationPlayer = animals.crocodile_player
	var eagle_player: AnimationPlayer = animals.eagle_player
	var observer := Vector3(-10.0, 2.0, -47.0)
	var croc := Wildlife.crocodile_pose(Wildlife.crocodile(0.0))
	for clip: String in ["Idle", "Walk", "Swim", "Dive", "Surface", "Attack", "Hit"]:
		croc.clip = clip
		animals.sync(croc, 0.3, observer, 0.016)
		_check(crocodile_player.current_animation == clip, "the in-game crocodile plays " + clip)
	var names := {}
	for key: Array in Wildlife.EAGLE_ROUTE:
		var time := float(key[0]) + 0.2
		animals.sync(croc, time, observer, 0.016)
		var pose := Wildlife.eagle(time)
		names[pose.clip] = true
		_check(eagle_player.current_animation == pose.clip, "the in-game eagle plays " + str(pose.clip))
		if pose.clip == "PerchIdle":
			var anchor: Node3D = animals.eagle.find_child("PerchContact", true, false)
			_check(anchor.global_position.is_equal_approx(Wildlife.PERCH), "the eagle's talons align with the center of the branch")
	_check(names.size() == 10, "the eagle path uses all ten authored clips")
	animals.sync(croc, 0.0, Vector3(80, 0, 80), 0.016)
	_check(not crocodile_player.is_playing() and not eagle_player.is_playing(), "distant wildlife does not keep animating off in the woods")

func _verify_audio(client) -> void:
	var audio: CampAudio = client.camp_audio
	var lake = CampAudio.Lake
	for cue: Array in CampAudio.CUES.values():
		for clip: AudioStreamWAV in cue[0]:
			_check(clip.format == AudioStreamWAV.FORMAT_16_BITS and not clip.stereo, "the LAN browser receives the same mono PCM as Godot")
	_check(CampAudio.ENGINE_LOOP.loop_mode == AudioStreamWAV.LOOP_FORWARD, "the red ship's running sample is a forward loop")
	_check(audio._voices.size() == CampAudio.VOICE_COUNT, "one-shots use a fixed pool")
	_check(audio._surface(Vector2(1.9, -85.0)) == &"trail" and audio._surface(Vector2(13.0, -85.0)) == &"leaves", "the path and off-trail forest have distinct footsteps")
	_check(audio._surface(Vector2(21, -8.1)) == &"leaves" and audio._surface(Vector2(108, -86)) == &"leaves", "north lookout and the wooded eastern slope use forest soil")
	_check(audio._surface(Vector2(78, -68)) == &"trail" and audio._surface(Vector2(315, -72)) == &"trail", "the eastern trail and bare plateau share compact earth")
	_check(audio._surface(Vector2(-10.8, -49.1)) == &"wood" and audio._surface(lake.shore_at(-0.20, 0.967)) == &"wade", "the deck and shallow water use their own footsteps")
	audio._camera = client.camera
	var path := Vector3(1.9, 0.0, -85.0)
	client.camera.position = path + Vector3.UP * 1.6
	var cursor: int = audio._voice_cursor
	audio._track("test-walker", path, CampAudio.Pose.GROUND, 0.10, true, true)
	audio._track("test-walker", path, CampAudio.Pose.GROUND, 0.10, true, true)
	_check(audio._voice_cursor == cursor, "standing still never emits a step")
	audio._track("test-walker", path + Vector3(0.0, 0.0, -0.39), CampAudio.Pose.GROUND, 0.10, true, true)
	_check(String(audio._voices[cursor].stream.resource_path).get_file().begins_with("step_soil_"), "a real grounded stride plays the SkyCut soil recording")
	cursor = audio._voice_cursor
	audio._track("test-walker", path + Vector3(0.0, 0.35, -0.7), CampAudio.Pose.AIR, 0.10, true, true)
	_check(audio._voice_cursor == cursor, "airborne movement never emits a step")
	var swimmer := Vector3(-12.0, lake.water_y() - 0.12, -52.0)
	client.camera.position = swimmer + Vector3.UP
	audio._track("test-swimmer", swimmer + Vector3.RIGHT * 0.2, CampAudio.Pose.GROUND, 0.10, false, true)
	audio._track("test-swimmer", swimmer, CampAudio.Pose.SWIM, 0.10, false, true)
	_check(audio._voices[cursor].stream.resource_path.ends_with("swim-entry.wav"), "nearby teammate entering the lake plays a splash")
	cursor = audio._voice_cursor
	for i in range(1, 5):
		audio._track("test-swimmer", swimmer - Vector3.RIGHT * (float(i) * 0.20), CampAudio.Pose.SWIM, 0.10, false, true)
	_check(String(audio._voices[cursor].stream.resource_path).get_file() == "swimmer_stroke.wav", "continued swimming plays a separate stroke")
	var events := [{"id": 1, "cue": "stone_water", "point": Stones.pack(swimmer), "at": 1.0}]
	cursor = audio._voice_cursor
	audio._consume_stones(events, 1.05, true)
	_check(audio._voices[cursor].stream.resource_path.ends_with("stone-water.wav"), "an authoritative splash uses the stone sample")
	cursor = audio._voice_cursor
	audio._consume_stones(events, 1.15, true)
	_check(audio._voice_cursor == cursor, "the same event in later snapshots does not replay")
	audio._update_engine({"pilot": "tester", "thrust": 0.85}, swimmer, 0.1, false)
	_check(audio._engine.playing and audio._voices[cursor].stream.resource_path.ends_with("engine-start.wav"), "boarding starts one loop and one startup sound")
	cursor = audio._voice_cursor
	audio._update_engine({"pilot": ""}, swimmer, 0.1, false)
	_check(audio._voices[cursor].stream.resource_path.ends_with("engine-stop.wav"), "leaving the parked ship triggers the shutdown sound")
	audio._update_engine({"pilot": ""}, swimmer, 1.0, false)
	_check(not audio._engine.playing, "the engine loop fades out and stops after dismounting")
	audio._reset_room()
