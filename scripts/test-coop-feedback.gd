extends SceneTree
const Client = preload("res://client.gd")
const Stones = preload("res://stones.gd")

class OfflineNetwork extends "res://network.gd":
	func start_room(_url: String, _code: String, _token: String = "") -> void:
		pass

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
	client._update_stones()
	_check(client.grindstone_target and client.pickup_stone.is_empty() and "走近磨石" in client._interaction_prompt(true), "Aiming at the large grindstone must explain how to use it.")
	client.body_pos = Vector2(1.9, -85.0)
	client.camera.position = Vector3(client.body_pos.x, Client.EYE_HEIGHT, client.body_pos.y)
	for id in ["camp-flat", "camp-round"]:
		client.camera.look_at(Stones.unpack(client.net.stones[id].at))
		client._update_stones()
		_check(client.pickup_stone == id and "E" in client._interaction_prompt(true), "The actual camp stone must still be pickable: " + id)
	client.body_pos = Vector2(0.96, -87.45)
	client.camera.position = Vector3(client.body_pos.x, Client.EYE_HEIGHT, client.body_pos.y)
	client.camera.look_at(grind)
	client.net.stones["camp-flat"].mode = "held"
	client.net.stones["camp-flat"].holder = "tester"
	client._update_stones()
	_check(client.stone_action == "grind" and "F" in client._interaction_prompt(true), "Holding a flat stone in reach must offer F.")
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
	client.free()
	if failures == 0:
		print("CAMP_FEEDBACK_OK: grindstone hint, camp pickups, sharpening, lamp fade, dawn sweep, rain")
	quit(int(failures != 0))
