extends SceneTree

# Exercises the same prediction and reconnect adapter as the browser and Mac game.
const Network = preload("res://network.gd")

class PausableNetwork extends "res://network.gd":
	var hold_snapshot_ack := true

	func _send(message: Dictionary) -> void:
		if not hold_snapshot_ack or not message.has("snapshotAck"):
			super._send(message)

var a := PausableNetwork.new()
var b := Network.new()
var phase := -2
var initial := Vector2.ZERO
var checkpoint := Vector2.ZERO
var first_id := ""
var second_id := ""
var deadline := 0
var render_resume_at := 0
var original_socket: WebSocketPeer

func _initialize() -> void:
	root.add_child(a)
	root.add_child(b)
	var url := "ws://127.0.0.1:" + OS.get_cmdline_user_args()[0]
	a.start_room(url, "adapter", "fe213deb47c249ed87f574338aa91665")
	b.start_room(url, "adapter", "37317804a48d4eddbf7e4cf01718888a")
	deadline = Time.get_ticks_msec() + 35000

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		printerr("Adapter timed out in phase ", phase, ": ", a.status, " / ", b.status)
		quit(1)
		return false
	if phase == 2 and not a.ready_in_room and not b.ready_in_room:
		print("ROOM_ADAPTER_OFFLINE")
		phase = 3
	if phase == -2:
		if a.ready_in_room and a._snapshot_seq == 1 and b.ready_in_room:
			original_socket = a._socket
			render_resume_at = Time.get_ticks_msec() + Network.SNAPSHOT_TIMEOUT_MS + 250
			a.set_process(false)
			phase = -1
		return false
	if phase == -1:
		if Time.get_ticks_msec() >= render_resume_at:
			a.hold_snapshot_ack = false
			a.set_process(true)
			phase = 0
		return false
	if phase == 0 and a._socket != original_socket:
		printerr("The rendered client reconnected before it could acknowledge its pending snapshot")
		quit(1)
		return false
	if not (a.ready_in_room and b.ready_in_room and a.players.size() == 2 and b.players.size() == 2):
		return false
	match phase:
		0:
			if a._snapshot_seq < 2:
				return false
			print("ROOM_ADAPTER_RENDER_RESUMED")
			first_id = a.self_id
			second_id = b.self_id
			initial = a.local_position
			a.set_motion(Vector2(0, 1), 0)
			phase = 1
		1:
			if a.local_position.distance_to(initial) > 2.2:
				a.set_motion(Vector2.ZERO, 0)
			if a._direction.is_zero_approx() and b.players.has(first_id):
				var remote: Dictionary = b.players[first_id]
				checkpoint = Vector2(remote.x, remote.z)
				if checkpoint.distance_to(initial) > 2 and checkpoint.distance_to(a.local_position) < .5:
					print("ROOM_ADAPTER_CHECKPOINT ", JSON.stringify({"id": first_id, "x": checkpoint.x, "z": checkpoint.y}))
					phase = 2
		3:
			if a.self_id == first_id and b.self_id == second_id and a.local_position.distance_to(checkpoint) < .5:
				print("ROOM_ADAPTER_RESTORED")
				quit(0)
	return false
