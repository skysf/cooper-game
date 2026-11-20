extends SceneTree
## Copy the seven GLBs under wild_people/ in a temporary project, import, then
## run this script there. It captures posed, textured, engine-rendered frames.
var scene := Node3D.new()
var camera := Camera3D.new()
var container := Node3D.new()
var player: AnimationPlayer
var rig: Skeleton3D
var current: Node3D
var model_name := ""
var evidence := {}
var errors := PackedStringArray()
const MODEL_DIR := "res://wild_people/"

func _initialize() -> void:
	call_deferred("inspect")

func inspect() -> void:
	root.add_child(scene)
	scene.add_child(container)
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#3d4947")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#eeecea")
	env.ambient_light_energy = 0.58
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var world := WorldEnvironment.new()
	world.environment = env
	scene.add_child(world)
	for setup: Array in [[Vector3(-2.3,3.8,-4),0.64],[Vector3(2,2,1.6),0.33]]:
		var light := DirectionalLight3D.new()
		scene.add_child(light)
		light.position=setup[0]
		light.look_at(Vector3(0,0.9,0))
		light.light_energy=setup[1]
		light.shadow_enabled=light.position.z<0
		light.directional_shadow_max_distance=12
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(200,200)
	ground.mesh = ground_mesh
	ground.position.y=-0.012
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#333e3c")
	ground.material_override = mat
	scene.add_child(ground)
	for label: String in ["male","female","male_elite","female_elite"]:
		await load_person(label)
		for job: Array in [["front",Vector3(0,0.11,-4.0)],["side",Vector3(4,.15,-.12)],["back",Vector3(.08,.12,4)],["opposite",Vector3(-4,.15,-.12)]]:
			await capture(label+"-"+str(job[0]), "Idle",0.17,job[1],Vector3(0,.94,0),2.12)
		await capture(label+"-portrait","Idle",0.1,Vector3(.16,.06,-4),Vector3(0,1.587,0),.47)
	await load_person("male_elite")
	attach_prop("spear","grip_R")
	attach_prop("shield","grip_L")
	await capture("shield-guard","Guard",.1,Vector3(.8,.30,-4),Vector3(0,.99,0),2.34)
	await capture("spear-grip","Guard",.1,Vector3(1.8,.32,-3.7),grip_position("grip_R"),.42)
	await capture("shield-grip","Guard",.1,Vector3(-2,.37,3.4),grip_position("grip_L"),.51)
	await capture("shield-block","Block",.3,Vector3(-1.4,.5,-4),Vector3(0,.99,0),2.36)
	await load_person("male")
	attach_prop("club","grip_R")
	await capture("club-attack","Attack",.46,Vector3(1.3,.35,-4),Vector3(0,.93,0),2.04)
	await capture("club-grip","Attack",.46,Vector3(1.6,.30,-3.6),grip_position("grip_R"),.45)
	await load_person("female")
	await capture("throw","Throw",.65,Vector3(1.8,.4,-3.6),Vector3(0,.93,0),2.02)
	await capture("run","Run",.17,Vector3(2.1,.22,-3),Vector3(0,.9,0),2.04)
	await capture("limp","Limp",.34,Vector3(2.1,.22,-3),Vector3(0,.9,0),2.04)
	await capture("limp-other","Limp",1.1,Vector3(2.1,.22,-3),Vector3(0,.9,0),2.04)
	await capture("limp-left","LimpLeft",.34,Vector3(2.1,.22,-3),Vector3(0,.9,0),2.04)
	await capture("down","Down",1.0,Vector3(2.5,3.4,-3),Vector3(0,.18,0),2.27)
	await capture("down-profile","Down",1.0,Vector3(4,.47,0),Vector3(0,.28,0),2.55)
	await capture("captive","Captive",.3,Vector3(1.8,.65,-3.2),Vector3(0,.66,0),1.56)
	await capture("captive-side","Captive",.3,Vector3(4,.42,-.18),Vector3(0,.94,0),1.0)
	await capture("rest","Rest",.5,Vector3(1.8,.65,-3.2),Vector3(0,.70,0),1.64)
	var f:=FileAccess.open("res://frames/checks.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"clips":evidence,"errors":errors},"  "))
	for item: String in errors: push_error(item)
	quit(1 if errors.size() else 0)

func load_person(key: String) -> void:
	if current:
		container.remove_child(current)
		current.queue_free()
	model_name=key
	current=load(MODEL_DIR+key+".glb").instantiate()
	container.add_child(current)
	rig=current.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	player=current.find_children("*","AnimationPlayer",true,false)[0] as AnimationPlayer
	if not evidence.has(key):
		var info: Dictionary = {}
		for clip: StringName in ["Idle","Walk","Run","Attack","Throw","Block","Limp","LimpLeft","Down","Captive","Rest","Guard"]:
			if not player.has_animation(clip):
				errors.append(key+" missing "+str(clip))
				continue
			var anim:=player.get_animation(clip)
			info[clip]={"length":anim.length,"loop":anim.loop_mode,"tracks":anim.get_track_count()}
		info["bones"]=rig.get_bone_count()
		for bone: String in ["grip_R","grip_L"]:
			if rig.find_bone(bone)<0: errors.append(key+" missing "+bone)
		evidence[key]=info
		await measure_clips(key)


func measure_clips(key:String) -> void:
	var skin:MeshInstance3D=current.find_children("*","MeshInstance3D",true,false)[0]
	var samples:Dictionary={}
	for clip:String in ["Idle","Walk","Run","Attack","Throw","Block","Limp","LimpLeft","Down","Captive","Rest","Guard"]:
		if not player.has_animation(clip): continue
		player.play(clip)
		var lo:=INF
		var hi:=-INF
		var ankles:Array=[[],[]]
		var intervals:=48 if clip in ["Run","Walk"] else 16
		for k:int in intervals+1:
			player.seek(player.current_animation_length*k/float(intervals),true)
			player.pause()
			rig.force_update_all_bone_transforms()
			await process_frame
			await RenderingServer.frame_post_draw
			var moving:=skin.bake_mesh_from_current_skeleton_pose()
			var bounds:=moving.get_aabb()
			lo=minf(lo,bounds.position.y)
			hi=maxf(hi,bounds.position.y)
			for side:int in 2:
				var foot:=rig.find_bone("foot_L" if side==0 else "foot_R")
				ankles[side].append(rig.get_bone_global_pose(foot).origin.z)
		samples[clip]={"samples":intervals+1,"ground_min_m":lo,"ground_max_m":hi,
				"ankle_swing_left_m":ankles[0].max()-ankles[0].min(),
				"ankle_swing_right_m":ankles[1].max()-ankles[1].min()}
		if lo < -.015 or hi > .035: errors.append(key+" "+clip+" ground interval "+str([lo,hi]))
		player.pause()
	if float(samples.Limp.ankle_swing_left_m)<1.7*float(samples.Limp.ankle_swing_right_m) or float(samples.LimpLeft.ankle_swing_right_m)<1.7*float(samples.LimpLeft.ankle_swing_left_m):
		errors.append(key+" injured leg asymmetry")
	evidence[key]["phase_sweep"]=samples

func grip_position(bone:String) -> Vector3:
	return rig.to_global(rig.get_bone_global_pose(rig.find_bone(bone)).origin)

func attach_prop(key:String,bone:String) -> void:
	var socket:=BoneAttachment3D.new()
	socket.bone_name=bone
	rig.add_child(socket)
	var prop:Node3D=load(MODEL_DIR+key+".glb").instantiate()
	socket.add_child(prop)

func capture(label:String,clip:String,t:float,from:Vector3,center:Vector3,size:float) -> void:
	player.play(clip)
	player.seek(t,true)
	player.pause()
	rig.force_update_all_bone_transforms()
	camera.position=center+from
	camera.look_at(center,Vector3.UP)
	camera.size=size
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	for bone:BoneAttachment3D in rig.find_children("*","BoneAttachment3D",true,false):
		var prop:=bone.get_child(0) as Node3D
		var joint:=rig.global_transform*rig.get_bone_global_pose(rig.find_bone(bone.bone_name))
		var error_m:=joint.origin.distance_to(prop.global_position)
		evidence[model_name][label+"_"+str(bone.bone_name)+"_origin_error_m"]=error_m
		if error_m>.001: errors.append(label+" grip offset "+str(error_m))
	var picture=root.get_texture().get_image()
	if picture == null or picture.is_empty():
		errors.append("empty viewport "+label)
		return
	var err:=picture.save_png("res://frames/"+label+".png")
	if err!=OK: errors.append("PNG "+label+" "+str(err))
	var skins:=current.find_children("*","MeshInstance3D",true,false)
	for instance: MeshInstance3D in skins:
		if instance.skin==null: continue
		var mesh:=instance.bake_mesh_from_current_skeleton_pose()
		if mesh!=null:
			var bounds:=mesh.get_aabb()
			evidence[model_name][label+"_bounds"]=[bounds.position.x,bounds.position.y,bounds.position.z,bounds.size.x,bounds.size.y,bounds.size.z]
		break
