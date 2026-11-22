extends Node3D

const CHARACTER = preload("res://props/sky_character.glb")
const BACKPACK = preload("res://props/camp_backpack.glb")
const BOOT = preload("res://props/camp_boot.glb")
const Clothing = preload("res://clothing.gd")
const MeleePose = preload("res://player_melee_pose.gd")
const LOCOMOTION = preload("res://animations/player_locomotion.tres")
const RECOVERY = preload("res://animations/player_recovery.tres")
const WALK_REFERENCE_SPEED := 1.46
const RUN_REFERENCE_SPEED := 3.56

const LIMBS := [
	[&"thigh_L", &"shin_L", &"upper_arm_L", &"forearm_L"],
	[&"thigh_R", &"shin_R", &"upper_arm_R", &"forearm_R"],
]
const CLOTHING_BONES := {
	"jacket": {"Root": &"upper_chest", "Arm_L": &"upper_arm_L", "Arm_R": &"upper_arm_R",
		"Forearm_L": &"forearm_L", "Forearm_R": &"forearm_R"},
	"pants": {"Root": &"hips", "Leg_L": &"thigh_L", "Leg_R": &"thigh_R",
		"Shin_L": &"shin_L", "Shin_R": &"shin_R"},
}
const CLOTHING_FIT := {
	"boar_cloak":[Vector3.ONE,Vector3(0,1.465,.005)],
	"cap": [Vector3(0.78, 0.79, 0.85), Vector3(0.0, 0.374, 0.010)],
	"helmet": [Vector3.ONE, Vector3(0.0, 1.634, -0.004)],
	"jacket": [Vector3(0.93, 0.99, 0.96), Vector3(0.0, 0.045, 0.008)],
	"pants": [Vector3(0.95, 1.157, 0.95), Vector3(0.0, -0.005, 0.0)],
}
const BACKPACK_REST := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.19, 0.215))
const JACKET_LINER_REST := Transform3D(
	Basis(Vector3.RIGHT, Vector3.UP, Vector3(0.0, 0.0, 0.64)), Vector3(0.0, 1.13, 0.025))

class GarmentRig:
	var skeleton: Skeleton3D
	var to_body := Transform3D.IDENTITY
	var from_body := Transform3D.IDENTITY
	var rest: Array[Transform3D] = []
	var pose: Array[Transform3D] = []
	var tracks := PackedInt32Array()

var target := Vector3.ZERO
var heading := 0.0
var gait := 0.0
var player_slot := 0
var holding := false
var shielding := false
var blocking := false
var swimming := false
var grounded := true
var vertical_speed := 0.0
var water_vertical_speed := 0.0
var physical_speed := -1.0
var render_speed := 0.0
var motion_clip := "Stand"
var motion_rate := 1.0
var motion_elapsed := 0.0
var knockout_elapsed := -1.0
var rise_elapsed := -1.0
var last_grounded := true
var last_swimming := false
var motion_seen := false
var holding_blend := 0.0
var shield_blend := 0.0
var block_blend := 0.0
var transition_left := 0.0
var motion_events: Array[Dictionary] = []
var seated := false
var crouched := false
var resting := false
var on_deck := false
var eye_view := false
var eye_upper := true
var eye_pitch := 0.0
var melee := MeleePose.new()
var body := Node3D.new()
var model: Node3D
var rig: Skeleton3D
var animator: AnimationPlayer
var trail_gear: Dictionary={}
var hip_bone: int
var backpack: Node3D
var jacket_liner: MeshInstance3D
var pants_instance: MeshInstance3D
var pants_regular: ArrayMesh
var garments: Dictionary = {}
var garment_rigs: Dictionary = {}
var worn: Dictionary = {}
var torso: Node3D
var bare_legs: Node3D
var shorts: Node3D
var hair: Node3D
var head_mesh: Node3D
var glasses: Node3D
var hands: Node3D
var inner_wrists: Node3D
var boots: Array[MeshInstance3D] = []
var boot_stand: Array[Transform3D] = []
var foot_bones := PackedInt32Array()
var head_bone: int
var grip_bone: int
var backpack_bone: int
var chest_pitch_axis := Vector3.RIGHT
var rig_to_body: Transform3D
var standing_inverse: Array[Transform3D] = []
var bend_base: Dictionary = {}
var bend_axis: Dictionary = {}
var bend_indices: Dictionary = {}
var bend_angles: Dictionary = {}
static var liner_mesh: ArrayMesh
static var pants_waist_fit: ArrayMesh
static var boot_meshes: Dictionary = {}

func outfit(slot: int) -> void:
	player_slot = slot
	add_child(body)
	model = CHARACTER.instantiate()
	body.add_child(model)
	rig = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	animator = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animator.add_animation_library(&"deck", preload("res://animations/player_deck.tres"))
	animator.add_animation_library(&"move", LOCOMOTION)
	animator.add_animation_library(&"recovery", RECOVERY)
	torso = model.find_child("SkyTorso", true, false) as Node3D
	bare_legs = model.find_child("SkyLegs", true, false) as Node3D
	shorts = model.find_child("SkyShorts", true, false) as Node3D
	hair = model.find_child("SkyHair", true, false) as Node3D
	head_mesh = model.find_child("SkyHead", true, false) as Node3D
	glasses = model.find_child("SkyGlasses", true, false) as Node3D
	hands = model.find_child("SkyHands", true, false) as Node3D
	inner_wrists = model.find_child("SkyInnerWrists", true, false) as Node3D
	inner_wrists.hide()
	for skin: MeshInstance3D in [torso, bare_legs, hands, head_mesh]:
		var material := skin.get_active_material(0) as StandardMaterial3D
		material.vertex_color_use_as_albedo = true
	head_bone = rig.find_bone(&"head")
	grip_bone = rig.find_bone(&"hand_R")
	hip_bone=rig.find_bone(&"hips")
	backpack_bone = rig.find_bone(&"upper_chest")
	rig_to_body = body.global_transform.affine_inverse() * rig.global_transform
	_sample_pose(&"Stand")
	for index in rig.get_bone_count():
		standing_inverse.append(_bone_in_body(index).affine_inverse())
	chest_pitch_axis = standing_inverse[backpack_bone].basis.orthonormalized() * Vector3.RIGHT
	_add_boots()
	for chain: Array in LIMBS:
		for name: StringName in chain:
			var index := rig.find_bone(name)
			bend_indices[name] = index
			bend_base[name] = rig.get_bone_pose_rotation(index)
			bend_axis[name] = standing_inverse[index].basis.orthonormalized() * Vector3.RIGHT

func _add_boots() -> void:
	model.find_child("SkyFeet", true, false).hide()
	if boot_meshes.is_empty():
		var asset: Node3D = BOOT.instantiate()
		for name in ["BootLeft", "BootRight"]:
			boot_meshes[name] = (asset.get_node(name) as MeshInstance3D).mesh
		asset.free()
	for name: StringName in [&"foot_L", &"foot_R"]:
		var index := rig.find_bone(name)
		var ankle := _bone_in_body(index).origin
		# The boot is authored with its sole at zero and its origin below the ankle.
		var rest := Transform3D(Basis.IDENTITY, Vector3(ankle.x, 0.0, ankle.z))
		var boot := MeshInstance3D.new()
		boot.name = "BootLeft" if name == &"foot_L" else "BootRight"
		boot.mesh = boot_meshes[String(boot.name)]
		boot.transform = rest
		body.add_child(boot)
		foot_bones.append(index)
		boot_stand.append(rest)
		boots.append(boot)

func _sample_pose(clip: StringName) -> void:
	melee.restore(rig)
	rig.reset_bone_poses()
	animator.play(clip)
	animator.seek(0.0, true)
	animator.pause()
	rig.force_update_all_bone_transforms()
	bend_angles.clear()

func _bone_in_body(index: int) -> Transform3D:
	return rig_to_body * rig.get_bone_global_pose(index)

func _deformation(index: int) -> Transform3D:
	return _bone_in_body(index) * standing_inverse[index]

func wear_clothes(equipment: Dictionary) -> void:
	if worn == equipment:
		return
	worn = equipment.duplicate()
	for item: String in Clothing.MODELS:
		if bool(worn.get(item, false)) and not garments.has(item):
			_load_garment(item)
	_refresh_clothing()

func _load_garment(item: String) -> void:
	var garment: Node3D = Clothing.MODELS[item].instantiate()
	var fit: Array = CLOTHING_FIT[item]
	body.add_child(garment)
	garment.scale = fit[0]
	garment.position = fit[1]
	garments[item] = garment
	if item in ["cap", "helmet","boar_cloak"]:
		return
	if item == "jacket":
		_add_jacket_liner()
	elif item == "pants":
		pants_instance = garment.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		pants_regular = pants_instance.mesh as ArrayMesh
	var binding := GarmentRig.new()
	binding.skeleton = garment.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	binding.to_body = body.global_transform.affine_inverse() * binding.skeleton.global_transform
	binding.from_body = binding.to_body.affine_inverse()
	for index in binding.skeleton.get_bone_count():
		var name := String(binding.skeleton.get_bone_name(index))
		var rest := binding.skeleton.get_bone_global_rest(index)
		if item == "jacket" and name.begins_with("Forearm_"):
			# Align the scanned cuff opening with the fitted wrist before rotating it.
			var cuff := Vector3(.016 if name == "Forearm_R" else -.016, -.010, .034)
			rest.origin += binding.from_body.basis * cuff
		binding.rest.append(rest)
		binding.pose.append(Transform3D.IDENTITY)
		binding.tracks.append(rig.find_bone(CLOTHING_BONES[item][name]))
	garment_rigs[item] = binding

func _add_jacket_liner() -> void:
	# The open jacket has an inner layer, while its sleeves cover the skinned torso.
	if liner_mesh == null:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.151
		capsule.height = 0.49
		capsule.radial_segments = 14
		capsule.rings = 5
		var arrays := capsule.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		# Preserve the front of the dark inner layer and keep its back inside the coat.
		for index in vertices.size():
			var p := vertices[index]
			var normal := normals[index]
			p.x *= 0.90
			normal.x /= 0.90
			if p.z > -0.048:
				p.z = -0.048 + (p.z + 0.048) * 0.17
				normal.z /= 0.17
			vertices[index] = p
			normals[index] = normal.normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		liner_mesh = ArrayMesh.new()
		liner_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var fabric := StandardMaterial3D.new()
		fabric.albedo_color = Color("#283431")
		fabric.roughness = 0.95
		liner_mesh.surface_set_material(0, fabric)
	jacket_liner = MeshInstance3D.new()
	jacket_liner.mesh = liner_mesh
	jacket_liner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(jacket_liner)

func _tucked_pants(source: ArrayMesh) -> ArrayMesh:
	var fitted := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index in vertices.size():
			var p := vertices[index]
			if p.y <= 0.72:
				continue
			var waist := smoothstep(0.745, 0.864, p.y)
			var across := 1.0 - 0.19 * waist
			var depth := 1.0 - 0.28 * waist
			p.x *= across
			p.z *= depth
			p.y -= 0.12 * (p.y - 0.72) * smoothstep(0.72, 0.77, p.y)
			vertices[index] = p
			var normal := normals[index]
			normals[index] = Vector3(normal.x / across, normal.y, normal.z / depth).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		# The fitted waist keeps the exact vertex order, so the imported LODs still apply.
		var lods := {}
		var surface_data := RenderingServer.mesh_get_surface(source.get_rid(), surface)
		for level: Dictionary in surface_data.get("lods", []):
			var raw: PackedByteArray = level.index_data
			var indices := PackedInt32Array()
			if vertices.size() <= 65536:
				indices.resize(raw.size() >> 1)
				for i in indices.size():
					indices[i] = raw.decode_u16(i * 2)
			else:
				indices = raw.to_int32_array()
			lods[float(level.edge_length)] = indices
		var flags := source.surface_get_format(surface) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		fitted.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], lods, flags)
		fitted.surface_set_material(surface, source.surface_get_material(surface))
	return fitted

func set_eye_view(enabled: bool, upper_visible: bool) -> void:
	if eye_view == enabled and eye_upper == upper_visible:
		return
	eye_view = enabled
	eye_upper = upper_visible
	_refresh_clothing()

func _refresh_clothing() -> void:
	var jacket := bool(worn.get("jacket", false))
	var pants := bool(worn.get("pants", false))
	var helmet := bool(worn.get("helmet", false))
	var cap := bool(worn.get("cap", false)) and not helmet
	var upper := not eye_view or eye_upper
	torso.visible = not jacket and upper
	head_mesh.visible = not eye_view
	glasses.visible = not eye_view
	hands.visible = upper
	inner_wrists.visible = jacket and upper
	bare_legs.visible = not pants
	shorts.visible = not pants
	hair.visible = not (cap or helmet or eye_view)
	for item: String in garments:
		garments[item].visible = cap if item == "cap" else bool(worn.get(item, false))
		if eye_view and (item in ["cap", "helmet","boar_cloak"] or item == "jacket" and not upper):
			garments[item].hide()
	if jacket_liner != null:
		jacket_liner.visible = jacket and upper
	if pants_instance != null:
		if pants and jacket and pants_waist_fit == null:
			pants_waist_fit = _tucked_pants(pants_regular)
		pants_instance.mesh = pants_waist_fit if pants and jacket else pants_regular
	_update_garments()

func _update_garments() -> void:
	for item: String in garment_rigs:
		if not garments[item].visible:
			continue
		var binding: GarmentRig = garment_rigs[item]
		# Express each body bone's movement since the fitting pose in garment rig space.
		for index in binding.tracks.size():
			var moved := binding.from_body * _deformation(binding.tracks[index]) * binding.to_body
			var pose := moved * binding.rest[index]
			var parent := binding.skeleton.get_bone_parent(index)
			var local_pose := binding.pose[parent].affine_inverse() * pose if parent >= 0 else pose
			binding.pose[index] = pose
			binding.skeleton.set_bone_pose(index, local_pose)
	for item in ["cap", "helmet"]:
		if garments.has(item) and garments[item].visible:
			var fit: Array = CLOTHING_FIT[item]
			var fitted := Transform3D(Basis.from_scale(fit[0]), fit[1])
			garments[item].transform = _deformation(head_bone) * fitted
	if garments.has("boar_cloak") and garments.boar_cloak.visible:
		garments.boar_cloak.transform=_deformation(backpack_bone)*Transform3D(Basis(Vector3.UP,PI),CLOTHING_FIT.boar_cloak[1])
	for item: String in trail_gear:
		var prop: Node3D=trail_gear[item]
		if prop.visible:
			var pack:=item=="boar_bedroll"
			prop.transform=_deformation(backpack_bone if pack else hip_bone)*Transform3D(Basis.IDENTITY,Vector3(0,1.00,.295) if pack else Vector3(.178,.95,.015))
	if backpack != null and backpack.visible:
		backpack.transform = _deformation(backpack_bone) * BACKPACK_REST
	if jacket_liner != null and jacket_liner.visible:
		jacket_liner.transform = _deformation(backpack_bone) * JACKET_LINER_REST
	for index in boots.size():
		boots[index].transform = _deformation(foot_bones[index]) * boot_stand[index]

func wear_trail_gear(roll: bool, whistle: bool) -> void:
	for item: String in ["boar_bedroll","tusk_whistle"]:
		var show_it:=roll and backpack!=null and backpack.visible if item=="boar_bedroll" else whistle
		show_it=show_it and not eye_view
		if show_it and not trail_gear.has(item):
			var scene: PackedScene=load("res://props/wild_boar/"+item+".glb")
			trail_gear[item]=scene.instantiate()
			body.add_child(trail_gear[item])
		if trail_gear.has(item):
			trail_gear[item].visible=show_it

func wear_backpack(equipped: bool) -> void:
	if equipped and backpack == null:
		backpack = BACKPACK.instantiate() as Node3D
		backpack.hide()
		body.add_child(backpack)
	if backpack != null and backpack.visible != equipped:
		backpack.visible = equipped
		if equipped:
			backpack.transform = _deformation(backpack_bone) * BACKPACK_REST

func set_seated(value: bool) -> void:
	if seated == value:
		return
	seated = value
	body.transform = Transform3D.IDENTITY
	motion_seen = false
	motion_clip = "Sit" if seated else "Stand"
	transition_left = 0.0
	if seated:
		position = Vector3.ZERO
		rotation = Vector3.ZERO
	_sample_pose(&"Sit" if seated else &"Stand")
	_update_garments()

func _bend(bone: StringName, angle: float) -> bool:
	if is_equal_approx(float(bend_angles.get(bone, INF)), angle):
		return false
	bend_angles[bone] = angle
	var base: Quaternion = bend_base[bone]
	rig.set_bone_pose_rotation(bend_indices[bone], base * Quaternion(bend_axis[bone], angle))
	return true

func set_motion_state(state: Dictionary) -> void:
	resting = not str(state.get("bed","")).is_empty()
	crouched = state.get("crouched",false)
	on_deck = state.get("onFerry",false)
	swimming = state.get("swimming", false)
	vertical_speed = float(state.get("vy", 0.0))
	water_vertical_speed = float(state.get("waterVy", 0.0))
	grounded = state.get("grounded", not swimming and absf(vertical_speed) < 0.05)
	physical_speed = Vector2(state.get("vx", 0.0), state.get("vz", 0.0)).length() if state.has("vx") else -1.0

func set_recovery_state(state: Dictionary, elapsed: float) -> void:
	var down_at := float(state.get("downAt", -1.0))
	var lifted_at := float(state.get("revivedAt", -1.0))
	knockout_elapsed = maxf(0.0, elapsed - down_at) if down_at >= 0.0 and float(state.health) <= 0.0 else -1.0
	rise_elapsed = maxf(0.0, elapsed - lifted_at) if lifted_at >= 0.0 else -1.0

func _select_motion(delta: float) -> String:
	transition_left = maxf(0.0, transition_left - delta)
	if resting:
		return "deck/Sleep"
	if crouched:
		return "deck/CrouchWalk" if physical_speed > .06 else "deck/Crouch"
	if swimming:
		transition_left = 0.0
		return "move/Swim" if render_speed > 0.12 or absf(water_vertical_speed) > 0.12 else "move/Tread"
	if not grounded:
		if last_grounded and vertical_speed > 2.5:
			transition_left = 0.14
		if motion_clip == "move/Takeoff" and transition_left > 0.0 or last_grounded and vertical_speed > 2.5:
			return "move/Takeoff"
		return "move/Air"
	if not last_grounded and not last_swimming:
		transition_left = 0.22
		return "move/Land"
	if motion_clip == "move/Land" and transition_left > 0.0:
		return "move/Land"
	if render_speed < 0.08:
		return "Stand"
	return "move/Run" if render_speed > (2.10 if motion_clip == "move/Run" else 2.35) else "move/Walk"

func _hold_arm(upper: StringName, lower: StringName, angle: float, elbow: float, weight: float) -> void:
	if weight < 0.001:
		return
	for spec: Array in [[upper, angle], [lower, elbow]]:
		var index: int = bend_indices[spec[0]]
		var base: Quaternion = bend_base[spec[0]]
		var axis: Vector3 = bend_axis[spec[0]]
		var target_rotation := base * Quaternion(axis, spec[1])
		rig.set_bone_pose_rotation(index, rig.get_bone_pose_rotation(index).slerp(target_rotation, weight))

func advance(delta: float, local := false) -> void:
	var previous := position
	var dt := clampf(delta, 0.001, 0.10)
	position = target if local else position.lerp(target, 1.0 - exp(-16.0 * delta))
	# A grounded snapshot has already landed: do not interpolate the feet through the floor.
	if grounded and not swimming:
		position.y = target.y
	rotation.y = heading if local else lerp_angle(rotation.y, heading, 1.0 - exp(-12.0 * delta))
	if not visible:
		motion_seen = false
		transition_left = 0.0
		last_grounded = grounded
		last_swimming = swimming
		return
	if seated:
		return
	melee.restore(rig)
	body.transform = Transform3D.IDENTITY
	if resting:
		body.position = Vector3(0,.137,-.84)
		body.rotation.x = PI*.5
	elif eye_view:
		# Put the eye ahead of the collar so the camera can look down the legs.
		body.position.z = lerpf(.065, .275, smoothstep(.48, 1.40, -eye_pitch))
	# Use rendered horizontal displacement, never jump height or input intent, to time the feet.
	var actual_speed := Vector2(position.x - previous.x, position.z - previous.z).length() / maxf(delta, 0.001)
	actual_speed = maxf(physical_speed,0.0) if on_deck else minf(actual_speed, 5.5)
	render_speed = lerpf(render_speed, actual_speed, 1.0 - exp(-dt * 18.0))
	if actual_speed < 0.01 and (physical_speed < 0.01 or physical_speed < 0.0):
		render_speed = move_toward(render_speed, 0.0, dt * 16.0)
	var recovery_clip := ""
	if not swimming:
		if knockout_elapsed >= 0.0:
			recovery_clip = "recovery/Knockout"
		elif rise_elapsed >= 0.0 and rise_elapsed < RECOVERY.get_animation(&"Recover").length and render_speed < .18:
			recovery_clip = "recovery/Recover"
	var clip := _select_motion(dt) if recovery_clip.is_empty() else recovery_clip
	var rate := clampf(render_speed / WALK_REFERENCE_SPEED, 0.05, 2.5) if clip == "move/Walk" else clampf(render_speed / RUN_REFERENCE_SPEED, 0.10, 1.65) if clip == "move/Run" else clampf(render_speed / 2.25, 0.75, 1.35) if clip == "move/Swim" else 1.0
	if clip != motion_clip or not motion_seen:
		var phase := animator.current_animation_position / maxf(0.01, animator.current_animation_length)
		var keep_phase := motion_clip in ["move/Walk", "move/Run"] and clip in ["move/Walk", "move/Run"]
		animator.play(clip, 0.12 if not (resting or crouched or motion_clip.begins_with("deck/")) and motion_seen and recovery_clip.is_empty() else 0.0)
		if keep_phase:
			animator.seek(phase * animator.get_animation(clip).length)
		motion_events.append({"clip": clip, "atMs": Time.get_ticks_msec(), "grounded": grounded, "vy": vertical_speed, "swimming": swimming})
		while motion_events.size() > 12:
			motion_events.pop_front()
		motion_clip = clip
		motion_elapsed = 0.0
		motion_seen = true
	motion_rate = rate
	animator.speed_scale = rate
	if recovery_clip.is_empty():
		animator.advance(dt)
		motion_elapsed += dt
	else:
		var age := knockout_elapsed if recovery_clip == "recovery/Knockout" else rise_elapsed
		motion_elapsed = minf(age, animator.get_animation(clip).length)
		animator.seek(motion_elapsed, true)
	# Sample the carried pose first. The strike drives the same sleeves and hand mount.
	if recovery_clip.is_empty() and knockout_elapsed < 0.0:
		holding_blend = move_toward(holding_blend, float(holding and not swimming and not resting), dt * 10.0)
		shield_blend = move_toward(shield_blend, float(shielding and not swimming and not resting), dt * 10.0)
	else:
		holding_blend = 0.0
		shield_blend = 0.0
	block_blend = move_toward(block_blend, float(blocking), dt * 10.0)
	_hold_arm(&"upper_arm_R", &"forearm_R", 0.84, 0.37, holding_blend)
	_hold_arm(&"upper_arm_L", &"forearm_L", lerpf(0.52, 1.10, block_blend), lerpf(0.35, 0.75, block_blend), shield_blend)
	if recovery_clip.is_empty() and not swimming and not (resting or crouched) and knockout_elapsed < 0.0:
		var legs := 1.0 - smoothstep(.10, 1.05, render_speed) if grounded else 0.0
		melee.apply(rig, animator, legs, shielding, backpack_bone, chest_pitch_axis)
	rig.force_update_all_bone_transforms()
	_update_garments()
	last_grounded = grounded
	last_swimming = swimming

func motion_observables() -> Dictionary:
	return {"clip": motion_clip, "time": animator.current_animation_position if animator != null else 0.0,
		"rate": motion_rate, "renderSpeed": render_speed, "physicalSpeed": physical_speed,
		"grounded": grounded, "vy": vertical_speed, "swimming": swimming, "waterVy": water_vertical_speed,
		"attackClip": String(melee.clip) if not melee.underneath.is_empty() else "", "attackPhase": melee.phase, "eyeView": eye_view,
		"holdingBlend": holding_blend, "shieldBlend": shield_blend, "tickMs": Time.get_ticks_msec(), "transitions": motion_events}

func melee_mount(weapon: String) -> Transform3D:
	# In the fitted standing hand, the grip runs from the little finger toward
	# the index finger. The blade model already points along local -Z.
	var fitted := Basis.IDENTITY if weapon == "katana" else Basis(Vector3.RIGHT, -PI / 2.0)
	var direction := body.global_basis * _deformation(grip_bone).basis.orthonormalized() * fitted
	return Transform3D(direction, held_item_position())

func held_item_position() -> Vector3:
	return rig.to_global(rig.get_bone_global_pose(grip_bone) * Vector3(0, 0.063, 0.0))
