extends SceneTree
const Scene = preload("res://wild_people_scene.gd")
const People = preload("res://wild_people.gd")
const CHARACTERS := ["male","female","male_elite","female_elite"]
const SETUPS := [
	["stand","Idle",0.17,false], ["stride","Walk",0.19,false], ["crossing","Walk",0.44,false],
	["other_step","Walk",0.73,false], ["held","Guard",0.31,true],
	["sit","Rest",0.48,false], ["kneel","Captive",0.37,false], ["down","Down",0.998,false],
	["run","Run",0.19,false], ["limp","Limp",0.42,false], ["limp_left","LimpLeft",0.42,false],
	["fetch","DrawWater",0.71,false], ["turn","TurnRight",0.24,false],
]
const DT := 1.0/60.0

func _initialize() -> void:
	_run.call_deferred()

func _array(v:Vector3) -> Array:
	return [v.x,v.y,v.z]

func _transform(t: Transform3D) -> Array:
	return [_array(t.basis.x),_array(t.basis.y),_array(t.basis.z),_array(t.origin)]

func _run() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var visual := Scene.new()
	root.add_child(visual)
	var report := {}
	for key: String in CHARACTERS:
		var elite := key.ends_with("_elite")
		var id := "qa-"+key
		var npc := People.make_person(id,4 if elite else 1,"female" if key.begins_with("female") else "male",Vector2.ZERO,130.0)
		npc.phase = "companion"
		npc.weapon = ""
		npc.shield = false
		npc.yaw = 0.0
		var cases := {}
		for scenario: Array in SETUPS:
			if not elite and scenario[0] != "stand":
				continue
			if visual.actors.has(id):
				visual.actors[id].animator.stop()
				visual.actors[id].clip = ""
			npc.clip = scenario[1]
			npc.phase = "captive" if scenario[0] == "kneel" else ("dead" if scenario[0] == "down" else "companion")
			npc.weapon = "spear" if scenario[3] else ""
			npc.shield = scenario[3]
			npc.stepPhase = scenario[2]
			npc.clipAt = 130.0 - scenario[2]
			visual.sync({id:npc},130.0,DT,Vector3(0,1.67,-3))
			var actor: Dictionary = visual.actors[id]
			var rig: Skeleton3D = actor.rig
			var player: AnimationPlayer = actor.animator
			rig.force_update_all_bone_transforms()
			await process_frame
			var part: MeshInstance3D = actor.model.find_children("*","MeshInstance3D",true,false)[0]
			var bindings: Dictionary = {}
			var rotations: Dictionary = {}
			for index in part.skin.get_bind_count():
				var name := str(part.skin.get_bind_name(index))
				var at := rig.find_bone(name)
				bindings[name] = _transform(rig.global_transform*rig.get_bone_global_pose(at)*part.skin.get_bind_pose(index))
				rotations[name] = _transform(rig.get_bone_global_pose(at))
			var gears := {}
			if scenario[3]:
				for row: Array in [["right","grip_R"],["left","grip_L"]]:
					var prop: Node3D = actor[row[0]].get_child(0)
					var expected := rig.global_transform*rig.get_bone_global_pose(rig.find_bone(row[1]))
					gears[row[0]] = {"transform":_transform(prop.global_transform),"offset":expected.origin.distance_to(prop.global_position)}
			cases[scenario[0]] = {"clip":actor.clip,"sampledTime":player.current_animation_position,
				"length":player.current_animation_length,"bones":rotations,"skin":bindings,"gear":gears,
				"skeleton":_transform(rig.global_transform)}
			if scenario[0] == "stand":
				cases[scenario[0]].clips = Array(player.get_animation_list())
				cases[scenario[0]].gpuSurfaces = part.mesh.get_surface_count()
		report[key] = cases
		visual.sync({},130.0,DT)
	var output := FileAccess.open(path,FileAccess.WRITE)
	output.store_string(JSON.stringify(report))
	output.close()
	print("ELITE_REAL_POSES_OK ", report.keys())
	visual.free()
	quit(0)
