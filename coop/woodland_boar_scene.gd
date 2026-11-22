extends Node3D

const Model = preload("res://props/wild_boar/wild_boar.glb")
const Boar = preload("res://woodland_boar.gd")
var animal: Node3D
var tilt_at:=Vector2.INF
var tilt_yaw: float=INF
var player: AnimationPlayer
var clip := ""

func _ready() -> void:
	animal = Model.instantiate() as Node3D
	add_child(animal)
	player=animal.find_children("*","AnimationPlayer",true,false)[0]
	for key: String in Boar.LOOPING:
		player.get_animation(key).loop_mode=Animation.LOOP_LINEAR
	hide()

func sync(b: Dictionary, elapsed: float, delta: float, eye: Vector3) -> void:
	visible=not b.is_empty() and eye.distance_squared_to(Boar.world_at(b))<65.*65.
	if not visible:
		if not clip.is_empty():player.stop()
		clip=""
		return
	var dest:=Boar.world_at(b)
	var smooth:=1.0-exp(-19.0*delta)
	position=dest if clip.is_empty() or position.distance_squared_to(dest)>9.0 else position.lerp(dest,smooth)
	rotation.y=b.yaw if clip.is_empty() else lerp_angle(rotation.y,b.yaw,smooth)
	var at:=Vector2(position.x,position.z)
	if at.distance_squared_to(tilt_at)>.036 or absf(rotation.y-tilt_yaw)>.10:
		tilt_at=at
		tilt_yaw=rotation.y
		animal.basis=Boar.ground_tilt(at,rotation.y)
	if clip!=b.clip:
		var fade:=.10 if not clip.is_empty() else 0.0
		clip=b.clip
		var animation:=player.get_animation(clip)
		player.play(clip,fade)
		var age:=maxf(0.,elapsed-float(b.clipAt))
		player.seek(fposmod(age,animation.length) if clip in Boar.LOOPING else minf(age,animation.length),true)
