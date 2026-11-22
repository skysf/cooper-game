extends Node3D

const Face = preload("res://wild_face.gd")
const People = preload("res://wild_people.gd")
const Lake = preload("res://lake_layout.gd")
const Weapons = preload("res://weapons.gd")
const MODELS := {"male": "res://wild_people/male.glb", "female": "res://wild_people/female.glb", "male_elite": "res://wild_people/male_elite.glb", "female_elite": "res://wild_people/female_elite.glb"}
const WARM_LAYER := 1 << 19
const WARMUP_PER_MODEL := 2
const EQUIPMENT := {"wicker_strip": "res://props/storage/wicker_strip.glb", "club": "res://wild_people/club.glb", "spear": "res://wild_people/spear.glb", "shield": "res://wild_people/shield.glb", "stone": "res://props/stone_round.glb"}
var actors: Dictionary = {}
var player_gear: Dictionary = {}
var sources: Dictionary = {}
var loaded: Dictionary = {}
var pools: Dictionary = {}
var warmup_ms := 0.0
var warmup_count := 0
var pool_hits := 0
var cold_creates := 0
var pool_by_key: Dictionary = {}
var cold_by_key: Dictionary = {}
var trace_enabled := false
var view := Vector3.ZERO
var label_font: FontFile

func _load(path: String) -> PackedScene:
	if not loaded.has(path) and ResourceLoader.exists(path):
		loaded[path] = load(path)
	return loaded.get(path) as PackedScene

func _label(text: String) -> Label3D:
	var label := Label3D.new()
	label.text = text
	if label_font == null:
		label_font = preload("res://fonts/TrailSans.otf").duplicate() as FontFile
		label_font.fallbacks = [preload("res://fonts/CampHanSupplement.otf")]
	label.font = label_font
	label.font_size = 35
	label.pixel_size = 0.008
	label.outline_size = 7
	label.modulate = Color("#e9d8ac")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	return label

func _create(npc: Dictionary) -> Dictionary:
	var key: String = npc.sex + ("_elite" if npc.elite else "")
	if pools.has(key) and not pools[key].is_empty():
		var record: Dictionary = pools[key].pop_back()
		record.root.name = npc.id
		record.root.show()
		record.clip = ""
		if record.animator != null:
			record.animator.stop()
		pool_hits += 1
		pool_by_key[key] = int(pool_by_key.get(key, 0)) + 1
		return record
	cold_creates += 1
	cold_by_key[key] = int(cold_by_key.get(key, 0)) + 1
	return _make_actor(npc)

func _make_actor(npc: Dictionary) -> Dictionary:
	var key: String = npc.sex + ("_elite" if npc.elite else "")
	var resource := _load(MODELS[key])
	if resource == null:
		return {}
	var root := Node3D.new()
	root.name = npc.id
	add_child(root)
	var model := resource.instantiate() as Node3D
	root.add_child(model)
	var rigs := model.find_children("*", "Skeleton3D", true, false)
	var animators := model.find_children("*", "AnimationPlayer", true, false)
	var animator := animators[0] as AnimationPlayer if not animators.is_empty() else null
	if animator != null:
		animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var label := _label("")
	root.add_child(label)
	label.position.y = 2.12
	var record := {"root": root, "model": model, "face": Face.new(model), "key": key, "rig": rigs[0] if not rigs.is_empty() else null, "animator": animator, "label": label, "clip": "", "weapon": "?", "shield": false, "right": null, "left": null}
	return record

func _attach(rig: Skeleton3D, bone: String, item: String) -> Node3D:
	var packed := _load(EQUIPMENT[item])
	if packed == null or rig.find_bone(bone) < 0:
		return null
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	rig.add_child(attachment)
	var model := packed.instantiate() as Node3D
	attachment.add_child(model)
	return attachment


func _trace_event(kind: String, npc: Dictionary, started: int = -1) -> void:
	if not trace_enabled or not OS.has_feature("web"):
		return
	var sample := {"wall": Time.get_unix_time_from_system() * 1000.0, "event": kind, "id": npc.get("id", ""), "sex": npc.get("sex", ""), "elite": npc.get("elite", false), "phase": npc.get("phase", "warm"), "clip": npc.get("clip", ""), "weapon": npc.get("weapon", ""), "x": npc.get("x", 0), "z": npc.get("z", 0), "cpuUs": Time.get_ticks_usec() - started if started >= 0 else 0}
	JavaScriptBridge.eval("window.__CooperWildEvents.push(" + JSON.stringify(sample) + ");if(window.__CooperWildEvents.length>1024)window.__CooperWildEvents.shift()")

func _equip_actor(a: Dictionary, npc: Dictionary) -> void:
	if a.rig != null and (a.weapon != npc.weapon or a.shield != npc.shield):
		var traced_at := Time.get_ticks_usec() if trace_enabled else 0
		for key: String in ["right", "left"]:
			if a[key] != null:
				a[key].queue_free()
			a[key] = null
		if not npc.weapon.is_empty():
			a.right = _attach(a.rig, "grip_R", npc.weapon)
		if npc.shield:
			a.left = _attach(a.rig, "grip_L", "shield")
		a.weapon = npc.weapon
		a.shield = npc.shield
		if trace_enabled:
			_trace_event("equipment", npc, traced_at)

func sync(people: Dictionary, elapsed: float, delta: float, eye := Vector3.ZERO, focused := "") -> void:
	view = eye
	for id: String in actors.keys():
		if not people.has(id) or people[id].phase == "gone":
			var retired: Dictionary = actors[id]
			retired.root.hide()
			if not pools.has(retired.key):
				pools[retired.key] = []
			if pools[retired.key].size() < 4:
				pools[retired.key].append(retired)
			else:
				retired.root.queue_free()
			actors.erase(id)
	for id: String in people:
		var npc: Dictionary = people[id]
		if npc.phase == "gone":
			continue
		if not actors.has(id):
			var created := _create(npc)
			if created.is_empty():
				continue
			actors[id] = created
			created.root.position = Vector3(npc.x, npc.get("y", 0), npc.z)
			created.root.rotation.y = npc.yaw
		var a: Dictionary = actors[id]
		var root: Node3D = a.root
		var target := Vector3(npc.x,npc.get("y",0),npc.z)
		root.position = target if People.Footing.floor_transition(root.position,target) else root.position.lerp(target,1.0-exp(-delta*13.0))
		root.rotation.y = lerp_angle(root.rotation.y, npc.yaw, 1.0 - exp(-delta * 12.0))
		var distance := root.position.distance_to(eye)
		root.visible = distance < 85.0
		a.face.apply(Face.pose(npc, elapsed) if distance < 23.0 else Vector3.ZERO)
		var sleeping: bool = npc.get("clip","") == "Sleep" and npc.has("bed")
		var body_model: Node3D = a.model
		body_model.rotation.x = PI*.5 if sleeping else 0.0
		body_model.position = Vector3(0,.146,-.86) if sleeping else Vector3.ZERO
		var previous_label: bool = a.label.visible
		# The user reserves overhead identity text for recruited allies only.
		a.label.visible = npc.phase == "companion" and distance < 8.0
		a.label.font_size = 22
		a.label.pixel_size = 0.005
		a.label.text = "%s · 同伴" % npc.name
		a.label.modulate = Color("#d8d4a5")
		if trace_enabled and previous_label != a.label.visible:
			_trace_event("label-visible" if a.label.visible else "label-hidden", npc)
		a.label.position.y = .65 if sleeping else 0.9 if npc.phase in ["dead", "down"] else 2.12
		_equip_actor(a, npc)
		if a.right != null:
			a.right.visible = not sleeping
		if a.left != null:
			a.left.visible = not sleeping
		var animator: AnimationPlayer = a.animator
		if animator == null or distance > 42.0:
			continue
		var clip: String = "Idle" if sleeping else npc.clip
		if not animator.has_animation(clip):
			clip = "Idle"
		if a.clip != clip:
			var traced_at := Time.get_ticks_usec() if trace_enabled else 0
			animator.play(clip, 0.13 if not a.clip.is_empty() else 0.0)
			a.clip = clip
			if trace_enabled:
				_trace_event("clip", npc, traced_at)
		var animation := animator.get_animation(clip)
		var time := _pose_time(npc, root, clip, elapsed, animation.length)
		var loop := animation.loop_mode != Animation.LOOP_NONE
		var clock_step := delta if loop else clampf(time, 0.0, delta)
		if not loop:
			time = minf(time, maxf(0.0, animation.length - 0.001))
		# Advance the blend by frame time while sampling the clip at the shared phase.
		var start := fposmod(time - clock_step, animation.length) if loop else maxf(0.0, time - clock_step)
		var seek_at := Time.get_ticks_usec() if trace_enabled else 0
		animator.seek(start, false)
		animator.advance(clock_step)
		if npc.phase=="resident" and npc.get("duty","") in ["fire","craft"] and clip=="GatherFruit" and float(npc.get("workUntil",0))>elapsed:
			_hearth_pose(a.rig,npc.duty,elapsed-float(npc.clipAt))
		if trace_enabled and Time.get_ticks_usec() - seek_at > 1500:
			_trace_event("seek-slow", npc, seek_at)

func face_samples() -> Dictionary:
	var result := {}
	for id: String in actors:
		var actor: Dictionary = actors[id]
		var face: Face = actor.face
		if face.skin != null and actor.root.position.distance_squared_to(view) < 36.0:
			result[id] = [face.skin.get_blend_shape_value(face.shapes[0]), face.skin.get_blend_shape_value(face.shapes[1]), face.skin.get_blend_shape_value(face.shapes[2])]
	return result

func _hearth_pose(rig: Skeleton3D, duty: String, age: float) -> void:
	if rig == null:
		return
	var weight := smoothstep(.30,.85,age)*(1.0-smoothstep(2.85,3.3,age))
	var stroke := .5-.5*cos(age*(10.5 if duty=="craft" else 4.1))
	for side: String in ["L","R"]:
		var hand := rig.find_bone("forearm_"+side)
		if hand<0:
			continue
		var bend := .35*stroke if side=="R" else -.12*stroke if duty=="fire" else .09
		rig.set_bone_pose_rotation(hand,rig.get_bone_pose_rotation(hand)*Quaternion(Vector3.RIGHT,bend*weight))

func _pose_time(npc: Dictionary, root: Node3D, clip: String, elapsed: float, length: float) -> float:
	if npc.has("stepPhase"):
		var phase: float = npc.stepPhase
		if People.STRIDE_METERS.has(clip):
			var lag := Vector2(npc.x - root.position.x, npc.z - root.position.z)
			var forward := Vector2(0, -1).rotated(-npc.yaw)
			return fposmod(phase - lag.dot(forward) / float(People.STRIDE_METERS[clip]), 1.0) * length
		if clip in ["TurnLeft", "TurnRight"]:
			var lag := absf(angle_difference(root.rotation.y, npc.yaw))
			return fposmod(phase - lag / People.TURN_RADIANS, 1.0) * length
	return maxf(0.0, elapsed - float(npc.clipAt))


func _layers(root: Node3D, mask: int) -> void:
	for visual: VisualInstance3D in root.find_children("*", "VisualInstance3D", true, false):
		visual.layers = mask

func warm_up() -> void:
	var started := Time.get_ticks_usec()
	var preview := SubViewport.new()
	preview.size = Vector2i(96, 96)
	preview.world_3d = get_world_3d()
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(preview)
	var lens := Camera3D.new()
	lens.cull_mask = WARM_LAYER
	lens.fov = 58.0
	lens.near = 0.07
	lens.far = 4.5
	preview.add_child(lens)
	lens.make_current()
	for key: String in MODELS:
		if not pools.has(key):
			pools[key] = []
		for copy in WARMUP_PER_MODEL:
			var npc := {"id": "warm-" + key + str(copy), "sex": "female" if key.begins_with("female") else "male", "elite": key.ends_with("elite"), "weapon": "spear", "shield": true}
			var record := _make_actor(npc)
			if record.is_empty():
				continue
			_equip_actor(record, npc)
			_layers(record.root, WARM_LAYER)
			record.label.font_size = 22
			record.label.pixel_size = 0.005
			record.label.text = "岩岚 木衡 阿峦 砾川 林弦 山青 禾岚 阿榆 苇宁 溪棠 叶遥 芦音 同伴"
			record.label.show()
			record.root.rotation.y = PI
			var animator: AnimationPlayer = record.animator
			animator.play("Guard")
			animator.seek(0.0, true)
			animator.pause()
			for center: Vector3 in [Vector3(2.0, 0, -86.0), Vector3(20.0, 0, -70.0)]:
				record.root.position = center
				lens.global_position = center + Vector3(0, 1.05, 3.0)
				lens.look_at(center + Vector3.UP)
				await get_tree().process_frame
				preview.render_target_update_mode = SubViewport.UPDATE_ONCE
				await RenderingServer.frame_post_draw
				preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
			record.root.hide()
			_layers(record.root, 1)
			pools[key].append(record)
			warmup_count += 1
	for item: String in EQUIPMENT:
		_load(EQUIPMENT[item])
	preview.queue_free()
	await preview.tree_exited
	warmup_ms = (Time.get_ticks_usec() - started) / 1000.0

func sync_sources(state: Dictionary, eye: Vector3) -> void:
	for key: String in People.SOURCES:
		var info: Dictionary = People.SOURCES[key]
		if not sources.has(key):
			var marker := Node3D.new()
			marker.position = Vector3(info.x, Lake.walk_height(Vector2(info.x, info.z)), info.z)
			add_child(marker)
			var label := _label("")
			label.position.y = 1.0
			marker.add_child(label)
			# Woodland labels follow the position of each growing patch.
			sources[key] = {"root": marker, "label": label}
		var marker: Dictionary = sources[key]
		marker.root.visible = not state.is_empty() and marker.root.position.distance_to(eye) < 36.0
		marker.label.font_size = 27
		marker.label.pixel_size = 0.005
		marker.label.text = "%s · %d\n走近按 F" % [info.name, state.get("resources", {}).get(key, {}).get("stock", 0)]

func equip_players(players: Dictionary, avatars: Dictionary, self_id: String, camera: Camera3D,
		local_hiker: Node3D, _delta: float, elapsed: float, local_hands_hidden := false, aim := 0.0) -> void:
	for id: String in player_gear.keys():
		if not players.has(id):
			player_gear[id].root.queue_free()
			player_gear.erase(id)
	for id: String in players:
		var person: Dictionary = players[id]
		var weapon: String = person.get("weapon", "")
		var shield: bool = person.get("shield", false)
		if not player_gear.has(id):
			var root := Node3D.new()
			add_child(root)
			player_gear[id] = {"root": root, "weapon": "?", "shield": false, "right": null, "left": null, "sight": Vector3.ZERO}
		var gear: Dictionary = player_gear[id]
		if weapon != gear.weapon or shield != gear.shield:
			for side in ["right", "left"]:
				if gear[side] != null:
					gear[side].queue_free()
				gear[side] = null
			var path: String = Weapons.CAMP_MODELS.get(weapon, EQUIPMENT.get(weapon, ""))
			if not path.is_empty():
				var packed := _load(path)
				if packed != null:
					gear.right = packed.instantiate()
					gear.root.add_child(gear.right)
					var sight := gear.right.find_child("Sight", true, false) as Node3D
					gear.sight = gear.right.to_local(sight.global_position) if sight != null else Vector3.ZERO
			if shield:
				var packed := _load(EQUIPMENT.shield)
				if packed != null:
					gear.left = packed.instantiate()
					gear.root.add_child(gear.left)
			gear.weapon = weapon
			gear.shield = shield
		var hiker: Node3D = local_hiker if id == self_id else avatars.get(id)
		var first: bool = id == self_id and (hiker == null or hiker.eye_view or not hiker.visible)
		var firearm := Weapons.firearm(weapon)
		var age := maxf(0.0, elapsed - float(person.get("attackAt", -10.0)))
		if person.get("attackWeapon", weapon) != weapon:
			age = INF
		var recoil := exp(-age * (17.0 if weapon == "rifle" else 25.0)) if firearm else 0.0
		if first and firearm:
			gear.root.global_transform = camera.global_transform
			if gear.right != null:
				_pose_view_firearm(gear.right, weapon, recoil, aim, gear.sight)
			if gear.left != null:
				gear.left.hide()
		elif hiker != null:
			gear.root.global_transform = Transform3D.IDENTITY
			if gear.right != null:
				gear.right.visible = true
				if firearm:
					gear.right.global_position = hiker.held_item_position()
					var aim_pitch: Variant = person.get("aimPitch")
					var tilt := -0.22 if aim_pitch == null else float(aim_pitch)
					gear.right.global_basis = Basis.from_euler(Vector3(tilt + recoil * 0.10, hiker.rotation.y, 0.0))
				else:
					gear.right.global_transform = hiker.melee_mount(weapon)
			if gear.left != null:
				gear.left.visible = not firearm
				var index: int = hiker.rig.find_bone("hand_L")
				gear.left.global_position = hiker.rig.to_global(hiker.rig.get_bone_global_pose(index).origin) if index >= 0 else hiker.position
				gear.left.global_rotation = Vector3(0, hiker.rotation.y, 0)
		var hands_hidden: bool = local_hands_hidden if id == self_id else person.get("swimming", false) or hiker != null and hiker.seated
		var incapacitated: bool = float(person.get("health", 100.0)) <= 0.0 or hiker != null and hiker.motion_clip == "recovery/Recover"
		gear.root.visible = (first and firearm or hiker != null and hiker.visible) and not hands_hidden and not incapacitated and str(person.get("bed","")).is_empty()

func _pose_view_firearm(model: Node3D, weapon: String, recoil: float, aim: float, sight: Vector3) -> void:
	model.visible = weapon != "rifle" or aim < 0.82
	var rifle := weapon == "rifle"
	var raised := smoothstep(0.0, 1.0, aim)
	var carry := Vector3(0.23, -0.27, -0.47) if rifle else Vector3(0.19, -0.24, -0.47)
	var eye_line := Vector3(0.0, 0.0, -0.23 if rifle else -0.48)
	model.position = carry.lerp(eye_line - sight, raised) + Vector3.BACK * recoil * (0.072 if rifle else 0.048)
	var rest := Vector3(0.031, -0.082, -0.056)
	model.rotation = rest * (1.0 - raised) + Vector3.RIGHT * recoil * (0.08 if rifle else 0.12)
