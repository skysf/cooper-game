extends Node3D

const Dog = preload("res://camp_dog.gd")
const LakeLayout = preload("res://lake_layout.gd")
const MASTIFF = preload("res://props/camp_mastiff.glb")

var player: AnimationPlayer
var clip := ""

func _ready() -> void:
	var model := MASTIFF.instantiate() as Node3D
	add_child(model)
	player = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	hide()

func sync(state: Dictionary, elapsed: float, received_at: float, delta: float) -> void:
	visible = not state.is_empty()
	if state.is_empty():
		player.pause()
		clip = ""
		return
	var at := Dog.position(state)
	var feet := float(state.get("y",LakeLayout.walk_height(at)))
	if received_at >= 0.0 and not state.get("fixtureNear",false) and state.clip in [Dog.WALK, Dog.RUN]:
		var drift := clampf(elapsed - received_at, 0.0, 0.10)
		at += Vector2(float(state.get("vx", 0.0)), float(state.get("vz", 0.0))) * drift
		feet = LakeLayout.walk_height(at)
	var target := Vector3(at.x, feet, at.y)
	var angle := float(state.yaw)
	if clip.is_empty():
		position = target
		rotation.y = angle
	else:
		var blend := 1.0 - exp(-12.0 * delta)
		position = target if Dog.Footing.floor_transition(position,target) else position.lerp(target,blend)
		rotation.y = lerp_angle(rotation.y, angle, blend)
	var next: String = state.clip
	var rate := 1.0
	if next in [Dog.WALK, Dog.RUN]:
		var nominal := Dog.WALK_SPEED if next == Dog.WALK else Dog.TROT_SPEED
		rate = clampf(float(state.get("speed", nominal)) / nominal, 0.2, 2.0)
	if next != clip:
		var moving := next in [Dog.STAND, Dog.WALK, Dog.RUN] or clip in [Dog.STAND, Dog.WALK, Dog.RUN]
		var fade := 0.18 if moving and not clip.is_empty() else 0.0
		clip = next
		var track := Dog.IDLE if clip == Dog.STAND else clip
		player.speed_scale = rate
		player.play(track, fade)
		var animation := player.get_animation(track)
		var time := maxf(elapsed - float(state.clipAt), 0.0) * rate
		player.seek(fposmod(time, animation.length) if animation.loop_mode != Animation.LOOP_NONE else minf(time, animation.length), true)
	else:
		player.speed_scale = lerpf(player.speed_scale, rate, 1.0 - exp(-14.0 * delta))
