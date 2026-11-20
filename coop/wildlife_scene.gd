extends Node3D

const Wildlife = preload("res://wildlife.gd")
const CROCODILE = preload("res://props/camp_crocodile.glb")
const EAGLE = preload("res://props/camp_eagle.glb")

var crocodile: Node3D
var eagle: Node3D
var crocodile_player: AnimationPlayer
var eagle_player: AnimationPlayer
var perch_offset := Vector3.ZERO
var flight_time := -1.0

func _ready() -> void:
	crocodile = CROCODILE.instantiate() as Node3D
	add_child(crocodile)
	crocodile_player = crocodile.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	crocodile.hide()
	eagle = EAGLE.instantiate() as Node3D
	add_child(eagle)
	eagle_player = eagle.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var contact := eagle.find_child("PerchContact", true, false) as Node3D
	perch_offset = eagle.to_local(contact.global_position)
	eagle.hide()

func sync(croc: Dictionary, elapsed: float, observer: Vector3, delta: float, eagle_alive := true) -> void:
	if croc.is_empty():
		_hide(crocodile, crocodile_player)
		_hide(eagle, eagle_player)
		flight_time = -1.0
		return

	var position_data: Array = croc.at
	var at := Vector3(position_data[0], position_data[1], position_data[2])
	if not croc.get("dead", false) and observer.distance_squared_to(at) <= 52.0 * 52.0:
		var was_visible := crocodile.visible
		var previous := crocodile_player.assigned_animation
		var depth_handoff: bool = (previous == "Dive" and croc.clip == "Swim") or (previous == "Swim" and croc.clip == "Surface")
		_play(crocodile, crocodile_player, croc.clip, elapsed - float(croc.clipAt), not depth_handoff)
		if was_visible:
			var blend := 1.0 - exp(-14.0 * delta)
			crocodile.position = crocodile.position.lerp(at, blend)
			if depth_handoff:
				crocodile.position.y = at.y
			crocodile.rotation.y = lerp_angle(crocodile.rotation.y, float(croc.yaw), blend)
		else:
			crocodile.position = at
			crocodile.rotation.y = float(croc.yaw)
	else:
		_hide(crocodile, crocodile_player)

	if not eagle_alive:
		_hide(eagle, eagle_player)
		flight_time = -1.0
		return
	if flight_time < 0.0 or absf(elapsed - flight_time) > 0.8:
		flight_time = elapsed
	else:
		flight_time += delta
		flight_time = lerpf(flight_time, elapsed, minf(3.0 * delta, 1.0))
	var bird := Wildlife.eagle(flight_time)
	if observer.distance_squared_to(bird.at) <= 76.0 * 76.0:
		_play(eagle, eagle_player, bird.clip, flight_time - float(bird.clipAt))
		eagle.rotation.y = float(bird.yaw)
		eagle.position = bird.at - (eagle.basis * perch_offset) * float(bird.contact)
	else:
		_hide(eagle, eagle_player)

func _play(actor: Node3D, player: AnimationPlayer, clip: String, time: float, blend := true) -> void:
	if actor.visible and player.assigned_animation == clip:
		return
	player.play(clip, 0.18 if actor.visible and blend else 0.0)
	var motion := player.get_animation(clip)
	var age := maxf(time, 0.0)
	player.seek(fposmod(age, motion.length) if motion.loop_mode != Animation.LOOP_NONE else minf(age, motion.length), true)
	actor.show()

func _hide(actor: Node3D, player: AnimationPlayer) -> void:
	if actor.visible:
		actor.hide()
		player.pause()
