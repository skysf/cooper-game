extends SceneTree
# Art fixture: run with an isolated project containing the production Hiker and gear.
const Hiker = preload("res://hiker.gd")
const Movement = preload("res://animations/player_locomotion.tres")

func _initialize() -> void:
	call_deferred("sample")

func sample() -> void:
	var hiker = Hiker.new()
	root.add_child(hiker)
	hiker.outfit(1)
	hiker.wear_clothes({"cap":true,"jacket":true,"pants":true})
	hiker.wear_backpack(true)
	if not hiker.animator.has_animation_library(&"move"):
		hiker.animator.add_animation_library(&"move",Movement)
	var result := {}
	for clip in Movement.get_animation_list():
		var values := []
		var anim := Movement.get_animation(clip)
		for n in 61:
			var t := n/60.0
			hiker.animator.play("move/"+clip)
			hiker.animator.seek(t*anim.length,true)
			hiker.animator.pause()
			hiker.rig.force_update_all_bone_transforms()
			hiker._update_garments()
			var floor_y := []
			var boot_z := []
			for boot in hiker.boots:
				var b: Transform3D = boot.transform
				floor_y.append(snappedf(b.origin.y - .5*Vector3(b.basis.x.y,b.basis.y.y,b.basis.z.y).length(),.0001))
				boot_z.append(snappedf(b.origin.z,.0001))
			var eye: Vector3 = hiker._deformation(hiker.head_bone)*Vector3(0,1.659,-.073)
			var palm_l: Vector3 = hiker._bone_in_body(hiker.rig.find_bone("hand_L")).origin
			var palm_r: Vector3 = hiker._bone_in_body(hiker.rig.find_bone("hand_R")).origin
			values.append([t,floor_y,boot_z,[eye.x,eye.y,eye.z],[palm_l.x,palm_l.y,palm_l.z],[palm_r.x,palm_r.y,palm_r.z]])
		result[clip]=values
	var output := FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
	output.store_string(JSON.stringify(result))
	output.close()
	quit()
