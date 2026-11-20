extends SceneTree
## Run after importing either an isolated candidate project or the production assets.

const LIVE := {
	"crocodile": {"Attack":1.066667,"Dive":1.266667,"Hit":.766667,"Idle":1.866667,"Surface":1.266667,"Swim":1.066667,"Walk":1.133333},
	"mastiff": {"Run":.5,"Eat":1.6,"Attack":.933333,"Limp":1.1,"Lie-down":1.466667,"Rest":4.4,"Rise":1.366667,"Walk":.9,"Idle":5.6},
}
const LOOPS := {
	"crocodile":["Idle","Walk","Swim"],
	"mastiff":["Idle","Walk","Run","Eat","Limp","Rest"]
}
const PAWS := ["Fore.Paw.L","Fore.Paw.R","Hind.Paw.L","Hind.Paw.R"]

var failures: Array[String] = []
var checks := 0
var report := {}
var model: Node3D
var rig: Skeleton3D
var player: AnimationPlayer
var meshes: Array[Node]
var species := ""

func _initialize() -> void:
	_verify.call_deferred()

func _verify() -> void:
	for id: String in LIVE:
		species = id
		var asset := load("res://props/camp_%s.glb" % id) as PackedScene
		_check(asset != null,id + " loads as an animated model")
		if asset == null:
			continue
		model = asset.instantiate()
		root.add_child(model)
		rig = model.find_children("*","Skeleton3D",true,false)[0]
		player = model.find_children("*","AnimationPlayer",true,false)[0]
		meshes = model.find_children("*","MeshInstance3D",true,false)
		_check(rig.get_bone_count() == (26 if id=="crocodile" else 23),id + " retains its published skeleton")
		report[id] = {"live":{}}
		for clip: String in LIVE[id]:
			var motion := player.get_animation(clip)
			_check(motion != null and absf(motion.length-LIVE[id][clip])<.002
				and (motion.loop_mode!=Animation.LOOP_NONE) == (clip in LOOPS[id]),id + " retains " + clip + " timing")
			if motion != null:
				report[id].live[clip] = [motion.length,motion.loop_mode,motion.get_track_count()]
		var dead := _validate("Dead",.1)
		if id=="crocodile":
			var collapse := _validate("Collapse",.9)
			if not collapse.is_empty() and not dead.is_empty():
				_crocodile(collapse,dead)
		elif not dead.is_empty():
			_mastiff(dead)
		model.free()
	if ResourceLoader.exists("res://camp_storage_scene.gd"):
		_rendered_corpses()
	print(JSON.stringify({"checks":checks,"failures":failures,"assets":report}))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
		push_error(text)

func _bone_poses() -> Dictionary:
	var result := {}
	for i in rig.get_bone_count():
		result[rig.get_bone_name(i)] = rig.get_bone_global_pose(i)
	return result

func _pose(clip: String, seconds: float) -> void:
	player.play(clip,0.0)
	player.seek(seconds,true)
	player.pause()
	rig.force_update_all_bone_transforms()

func _validate(clip: String, length: float) -> Dictionary:
	var motion := player.get_animation(clip)
	_check(motion != null and absf(motion.length-length)<.002 and motion.loop_mode==Animation.LOOP_NONE,
		species + " plays " + clip + " once with deterministic room-time duration")
	if motion == null:
		return {}
	var samples: Array[Dictionary] = []
	var frames := roundi(motion.length*60.)
	var lowest := INF
	var lead := {}
	var typical := {}
	for i in range(frames+1):
		_pose(clip,motion.length*float(i)/frames)
		var support := _measure()
		support.time = float(i)/60.
		samples.append(support)
		lowest = minf(lowest,float(support.low[1]))
		if i==0:
			lead = _bone_poses()
		if i==mini(6,frames):
			typical = _bone_poses()
	var ending := _bone_poses()
	var floor_end: float = samples.back().low[1]
	_check(lowest >= -.008 and floor_end < .014,species+" "+clip+" is grounded throughout at 60 Hz")
	report[species][clip] = {"samples":samples,"maxPenetrationM":maxf(-lowest,0.0),"duration":motion.length}
	return {"samples":samples,"opening":lead,"early":typical,"last":ending}

func _crocodile(collapse: Dictionary, dead: Dictionary) -> void:
	_check(_difference(collapse.last,dead.opening)<.001,
		"Crocodile Collapse hands off to Dead without a skeletal jump")
	_check(_difference(dead.last,dead.opening)<.00001,"Crocodile Dead remains static")
	var first: Dictionary = collapse.samples.front()
	var final: Dictionary = collapse.samples.back()
	_check(first.torsoBottom - final.torsoBottom >= .014 and final.torsoBottom < .030,
		"Crocodile transfers its weight to the belly")
	_check(final.headBottom < .042,"Crocodile chin settles close to the ground")
	var root_position: Vector3 = (collapse.last.Root as Transform3D).origin
	_check(Vector2(root_position.x,root_position.z).length() < .075,
		"Crocodile body stays within seven and a half centimetres of the interaction anchor")
	var base: Transform3D = collapse.opening["Fore.Paw.L"]
	var early: Transform3D = collapse.early["Fore.Paw.L"]
	_check(Vector2(base.origin.x-early.origin.x,base.origin.z-early.origin.z).length()<.035,
		"Crocodile keeps one front foot planted during the last brace")
	for bone: String in PAWS + ["Jaw","Tail.07"]:
		var original: Transform3D = collapse.opening[bone]
		var finish: Transform3D = collapse.last[bone]
		_check(original.origin.distance_to(finish.origin)>.025 or original.basis.get_rotation_quaternion().angle_to(
			finish.basis.get_rotation_quaternion())>.065,"Crocodile articulates " + bone)

func _mastiff(dead: Dictionary) -> void:
	_check(_difference(dead.opening,dead.last)<.00001,"Mastiff Dead remains static")
	var finishing: Dictionary = dead.samples.back()
	_pose("Rest",.55)
	var resting := _measure()
	var rest_root := rig.get_bone_global_pose(rig.find_bone("Root"))
	var out_root: Transform3D = dead.opening.Root
	var tilt := rest_root.basis.get_rotation_quaternion().angle_to(out_root.basis.get_rotation_quaternion())
	_check(rad_to_deg(tilt)>68.0 and rad_to_deg(tilt)<99.0 and float(finishing.high[1]) < float(resting.high[1])-.09,
		"Mastiff settles onto its side with a lower silhouette than its living Rest")
	_check(finishing.torsoBottom<.030 and finishing.headBottom<.075,
		"Mastiff rests on its flank and cheek")

func _difference(first: Dictionary, second: Dictionary) -> float:
	var error := 0.0
	for bone: String in first:
		var a: Transform3D = first[bone]
		var b: Transform3D = second[bone]
		error = maxf(error,a.origin.distance_to(b.origin))
		error = maxf(error,1.0-absf(a.basis.get_rotation_quaternion().dot(b.basis.get_rotation_quaternion())))
	return error

func _measure() -> Dictionary:
	var low := Vector3.INF
	var high := -low
	var torso := INF
	var chin := INF
	for mesh: MeshInstance3D in meshes:
		var skin := mesh.skin
		var transforms: Array[Transform3D] = []
		for bind in skin.get_bind_count():
			var bone := rig.find_bone(skin.get_bind_name(bind))
			transforms.append(rig.global_transform * rig.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
		for k in mesh.mesh.get_surface_count():
			var a := mesh.mesh.surface_get_arrays(k)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var links := int(joints.size()/float(verts.size()))
			for i in verts.size():
				var source := verts[i]
				var point := Vector3.ZERO
				for j in links:
					var n := i*links+j
					if weights[n]>0.0:
						point += (transforms[joints[n]] * source)*weights[n]
				low = low.min(point)
				high = high.max(point)
				if species=="crocodile":
					if absf(source.x)<.215 and source.z>-.41 and source.z<.42 and source.y<.185:
						torso = minf(torso, point.y)
					if source.z<-.65 and absf(source.x)<.39:
						chin = minf(chin,point.y)
				else:
					if source.z>-.235 and source.z<.31 and absf(source.x)>.086 and source.y>.34:
						torso = minf(torso,point.y)
					if source.z<-.294 and source.y>.62:
						chin = minf(chin,point.y)
	return {"low":[low.x,low.y,low.z],"high":[high.x,high.y,high.z],"torsoBottom":torso,"headBottom":chin}

func _rendered_corpses() -> void:
	var stage: Node3D = (load("res://camp_storage_scene.gd") as GDScript).new()
	var camera := Camera3D.new()
	root.add_child(stage)
	root.add_child(camera)
	var shore := Vector3(.30,.13,-.44)
	var records := {
		"croc": {"kind":"corpse_croc","mode":"ground","at":[shore.x,shore.y,shore.z],"yaw":.76,
			"deadAt":20.0,"landAt":20.9,"bag":{},"text":"","owner":"","fuelUntil":0.0},
		"dog": {"kind":"corpse_dog","mode":"ground","at":[1.,0.,-.9],"yaw":.48,
			"deadAt":20.0,"bag":{},"text":"","owner":"","fuelUntil":0.0},
	}
	stage.sync(records,{},"",camera,true,20.36)
	var crocodile: Dictionary = stage.live.croc
	var dog: Dictionary = stage.live.dog
	var croc_player: AnimationPlayer = crocodile.corpse_animator
	var dog_player: AnimationPlayer = dog.corpse_animator
	var instance: Node3D = crocodile.root
	_check(croc_player.assigned_animation == "Collapse" and absf(croc_player.current_animation_position-.36)<.002,
		"Storage corpse renderer seeks into the same crocodile collapse for late observers")
	_check(instance.position.is_equal_approx(shore) and is_equal_approx(instance.rotation.y,.76)
		and is_zero_approx(instance.rotation.x) and is_zero_approx(instance.rotation.z),
		"Crocodile renderer preserves the authoritative ground and heading")
	_check(dog_player.assigned_animation=="Dead","Storage corpse renderer uses the mastiff side pose")
	stage.sync(records,{},"",camera,true,20.9)
	_check(croc_player.assigned_animation == "Dead","Storage corpse renderer shows Dead at the loot threshold")
	records.croc.erase("landAt")
	stage.sync({},{},"",camera,true,20.32)
	stage.sync(records,{},"",camera,true,20.32)
	var old_croc: AnimationPlayer = stage.live.croc.corpse_animator
	_check(old_croc.assigned_animation=="Dead","Legacy corpse snapshots immediately render as settled")
	stage.queue_free()
	camera.queue_free()
