extends SceneTree

const Hiker = preload("res://hiker.gd")
const Survival = preload("res://survival.gd")
const Clothing = preload("res://clothing.gd")
const Preview = preload("res://character_preview.gd")
const DT := 1.0 / 60.0
const JOINTS := [&"upper_chest",&"upper_arm_L",&"forearm_L",&"upper_arm_R",&"forearm_R",&"hand_L",&"hand_R",&"head",&"hips"]

func _initialize() -> void:
	_verify.call_deferred()

func _transform(t: Transform3D) -> Array:
	return [_vec(t.basis.x),_vec(t.basis.y),_vec(t.basis.z),_vec(t.origin)]

func _vec(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func _verify() -> void:
	var measurements := {}
	var previous := ["stand", "carry_local", "carry_remote", "block", "fall_knees", "down", "get_up_knee", "sit", "swim"]
	for pose: String in previous:
		var h := Hiker.new()
		root.add_child(h)
		h.outfit(2)
		h.wear_clothes(Survival.initial_wear())
		match pose:
			"sit":
				h.set_seated(true)
			"carry_local","carry_remote","block":
				h.holding = true
				h.shielding = pose == "block"
				h.blocking = pose == "block"
				for k in 15:
					h.advance(DT,pose != "carry_remote")
			"fall_knees","down","get_up_knee":
				h.set_motion_state({"grounded":true,"swimming":false,"vy":0.0,"vx":0.0,"vz":0.0})
				var recovering: bool = pose == "get_up_knee"
				var at := 10.0 + (0.34 if pose == "fall_knees" else (0.90 if pose == "down" else 0.55))
				h.set_recovery_state({"health":50.0 if recovering else 0.0,"downAt":-1.0 if recovering else 10.0,
					"revivedAt":10.0 if recovering else -1.0},at)
				h.advance(DT,false)
			"swim":
				h.set_motion_state({"swimming":true,"vy":-0.2,"waterVy":-0.2,"grounded":false,"vx":0.0,"vz":0.0})
				for i in 20:
					h.advance(DT,false)
		var info := {"deformations":{},"bones":{},"garment":{},"phase":h.motion_clip,
			"time":h.animator.current_animation_position,"liner":_transform(h.jacket_liner.transform)}
		var garment: Node3D = h.garments.jacket
		var mesh: MeshInstance3D = garment.find_children("*","MeshInstance3D",true,false)[0]
		var binding: Hiker.GarmentRig = h.garment_rigs.jacket
		binding.skeleton.force_update_all_bone_transforms()
		for joint: StringName in JOINTS:
			var bone := h.rig.find_bone(joint)
			info.deformations[joint] = _transform(h._deformation(bone))
			info.bones[joint] = _vec(h._bone_in_body(bone).origin)
		for index in binding.skeleton.get_bone_count():
			var gar_bone := binding.skeleton.get_bone_name(index)
			info.garment[gar_bone] = _transform(binding.skeleton.get_bone_global_pose(index)*binding.rest[index].affine_inverse())
		info.to_body = _transform(binding.to_body)
		info.mesh = {"visible":mesh.is_visible_in_tree(),"surfaces":mesh.mesh.get_surface_count(),
			"vertices":mesh.mesh.surface_get_array_len(0),"indices":mesh.mesh.surface_get_array_index_len(0),
			"bounds":[_vec(mesh.get_aabb().position),_vec(mesh.get_aabb().size)],
			"skinBinds":mesh.skin.get_bind_count(),"boneAdjustmentCount":binding.tracks.size()}
		if pose == "stand":
			# The dropped prop must use the very same imported mesh.
			var drop := Clothing.on_ground("jacket")
			var drop_mesh := drop.get_child(0) as MeshInstance3D
			info.drop = {"sharedMesh":mesh.mesh == drop_mesh.mesh,"lowestPoint":(drop_mesh.transform*drop_mesh.get_aabb()).position.y}
			drop.free()
			h.wear_clothes({})
			info.unequip = not h.garments.jacket.visible and h.torso.visible and not h.jacket_liner.visible
			h.wear_clothes(Survival.initial_wear())
			info.reequip = h.garments.jacket.visible and not h.torso.visible and h.jacket_liner.visible
			var panel := Preview.new()
			root.add_child(panel)
			panel.update_character(Survival.initial_wear(),false,2)
			var preview_mesh: MeshInstance3D = panel.person.garments.jacket.find_children("*","MeshInstance3D",true,false)[0]
			info.uiSharesGameMesh = preview_mesh.mesh == mesh.mesh
			panel.free()
		measurements[pose] = info
		h.free()
	var file := FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(measurements,"  "))
	file.close()
	print("JACKET_IN_GAME_POSES ",measurements.keys())
	quit(0)
