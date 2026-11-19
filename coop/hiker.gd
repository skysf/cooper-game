extends Node3D

const CHARACTER = preload("res://props/sky_character.glb")
const BACKPACK = preload("res://props/camp_backpack.glb")
const Clothing = preload("res://clothing.gd")

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
	"cap": [Vector3(0.78, 0.79, 0.85), Vector3(0.0, 0.374, 0.010)],
	"jacket": [Vector3(0.93, 0.99, 0.96), Vector3(0.0, 0.045, 0.008)],
	"pants": [Vector3(0.95, 1.157, 0.95), Vector3(0.0, -0.005, 0.0)],
}
const BACKPACK_REST := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.19, 0.215))
const JACKET_LINER_REST := Transform3D(
	Basis(Vector3.RIGHT, Vector3.UP, Vector3(0.0, 0.0, 0.64)), Vector3(0.0, 1.13, 0.025))
const BOOT_SCALE := Vector3(0.142, 0.138, 0.282)

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
var swimming := false
var swim_pose := 0.0
var seated := false
var body := Node3D.new()
var model: Node3D
var rig: Skeleton3D
var animator: AnimationPlayer
var backpack: Node3D
var jacket_liner: MeshInstance3D
var garments: Dictionary = {}
var garment_rigs: Dictionary = {}
var worn: Dictionary = {}
var torso: Node3D
var bare_legs: Node3D
var shorts: Node3D
var hair: Node3D
var boots: Array[MeshInstance3D] = []
var boot_stand: Array[Transform3D] = []
var foot_bones := PackedInt32Array()
var head_bone: int
var grip_bone: int
var backpack_bone: int
var rig_to_body: Transform3D
var standing_inverse: Array[Transform3D] = []
var bend_base: Dictionary = {}
var bend_axis: Dictionary = {}
var bend_indices: Dictionary = {}
var bend_angles: Dictionary = {}
static var liner_mesh: CapsuleMesh
static var boot_mesh: SphereMesh

func outfit(slot: int) -> void:
	player_slot = slot
	add_child(body)
	model = CHARACTER.instantiate()
	body.add_child(model)
	rig = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	animator = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	torso = model.find_child("SkyTorso", true, false) as Node3D
	bare_legs = model.find_child("SkyLegs", true, false) as Node3D
	shorts = model.find_child("SkyShorts", true, false) as Node3D
	hair = model.find_child("SkyHair", true, false) as Node3D
	head_bone = rig.find_bone(&"head")
	grip_bone = rig.find_bone(&"hand_R")
	backpack_bone = rig.find_bone(&"upper_chest")
	rig_to_body = body.global_transform.affine_inverse() * rig.global_transform
	_sample_pose(&"Stand")
	for index in rig.get_bone_count():
		standing_inverse.append(_bone_in_body(index).affine_inverse())
	_add_boots()
	for chain: Array in LIMBS:
		for name: StringName in chain:
			var index := rig.find_bone(name)
			bend_indices[name] = index
			bend_base[name] = rig.get_bone_pose_rotation(index)
			bend_axis[name] = standing_inverse[index].basis.orthonormalized() * Vector3.RIGHT

func _add_boots() -> void:
	model.find_child("SkyFeet", true, false).hide()
	if boot_mesh == null:
		boot_mesh = SphereMesh.new()
		boot_mesh.radial_segments = 14
		boot_mesh.rings = 8
		var rubber := StandardMaterial3D.new()
		rubber.albedo_color = Color("#343430")
		rubber.roughness = 0.85
		boot_mesh.material = rubber
	for name: StringName in [&"foot_L", &"foot_R"]:
		var index := rig.find_bone(name)
		var rest := Transform3D(Basis.from_scale(BOOT_SCALE), _bone_in_body(index).origin + Vector3(0, 0.003, -0.067))
		var boot := MeshInstance3D.new()
		boot.mesh = boot_mesh
		boot.transform = rest
		body.add_child(boot)
		foot_bones.append(index)
		boot_stand.append(rest)
		boots.append(boot)

func _sample_pose(clip: StringName) -> void:
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
	if item == "cap":
		return
	if item == "jacket":
		_add_jacket_liner()
	var binding := GarmentRig.new()
	binding.skeleton = garment.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	binding.to_body = body.global_transform.affine_inverse() * binding.skeleton.global_transform
	binding.from_body = binding.to_body.affine_inverse()
	for index in binding.skeleton.get_bone_count():
		var name := String(binding.skeleton.get_bone_name(index))
		binding.rest.append(binding.skeleton.get_bone_global_rest(index))
		binding.pose.append(Transform3D.IDENTITY)
		binding.tracks.append(rig.find_bone(CLOTHING_BONES[item][name]))
	garment_rigs[item] = binding

func _add_jacket_liner() -> void:
	# The open jacket has an inner layer, while its sleeves cover the skinned torso.
	if liner_mesh == null:
		liner_mesh = CapsuleMesh.new()
		liner_mesh.radius = 0.151
		liner_mesh.height = 0.49
		liner_mesh.radial_segments = 14
		liner_mesh.rings = 5
		var fabric := StandardMaterial3D.new()
		fabric.albedo_color = Color("#283431")
		fabric.roughness = 0.95
		liner_mesh.material = fabric
	jacket_liner = MeshInstance3D.new()
	jacket_liner.mesh = liner_mesh
	jacket_liner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(jacket_liner)

func _refresh_clothing() -> void:
	var jacket := bool(worn.get("jacket", false))
	var pants := bool(worn.get("pants", false))
	var cap := bool(worn.get("cap", false))
	torso.visible = not jacket
	bare_legs.visible = not pants
	shorts.visible = not pants
	hair.visible = not cap
	for item: String in garments:
		garments[item].visible = bool(worn.get(item, false))
	if jacket_liner != null:
		jacket_liner.visible = jacket
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
	if garments.has("cap") and garments.cap.visible:
		var fit: Array = CLOTHING_FIT.cap
		var fitted := Transform3D(Basis.from_scale(fit[0]), fit[1])
		garments.cap.transform = _deformation(head_bone) * fitted
	if backpack != null and backpack.visible:
		backpack.transform = _deformation(backpack_bone) * BACKPACK_REST
	if jacket_liner != null and jacket_liner.visible:
		jacket_liner.transform = _deformation(backpack_bone) * JACKET_LINER_REST
	for index in boots.size():
		boots[index].transform = _deformation(foot_bones[index]) * boot_stand[index]

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
	swim_pose = 0.0
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

func advance(delta: float, local := false) -> void:
	var previous := position
	position = target if local else position.lerp(target, 1.0 - exp(-16.0 * delta))
	rotation.y = heading if local else lerp_angle(rotation.y, heading, 1.0 - exp(-12.0 * delta))
	if not visible:
		return
	var speed := position.distance_to(previous) / maxf(delta, 0.001)
	swim_pose = lerpf(swim_pose, float(swimming), 1.0 - exp(-delta * 9.0))
	body.rotation.x = -1.40 * swim_pose
	body.position = Vector3(0.0, 0.06, 1.08) * swim_pose
	gait += lerpf(minf(speed, 5.0) * 2.7, 2.4 + minf(speed, 2.5) * 1.55, swim_pose) * delta
	var changed := false
	for side in LIMBS.size():
		var cycle := sin(gait + side * PI)
		var swing := lerpf(cycle * clampf(speed * 0.14, 0.0, 0.48), 0.14 + cycle * 0.31, swim_pose)
		var knee := -maxf(0.0, cycle) * lerpf(clampf(speed * 0.11, 0.0, 0.35), 0.40, swim_pose)
		var carrying := holding and side == 1
		var arm := 0.84 if carrying else lerpf(-swing * 0.64, 1.64 + cycle * 0.79, swim_pose)
		var elbow := 0.37 if carrying else swim_pose * 0.25
		changed = _bend(LIMBS[side][0], swing) or changed
		changed = _bend(LIMBS[side][1], knee) or changed
		changed = _bend(LIMBS[side][2], arm) or changed
		changed = _bend(LIMBS[side][3], elbow) or changed
	if changed:
		rig.force_update_all_bone_transforms()
		_update_garments()

func held_item_position() -> Vector3:
	return rig.to_global(rig.get_bone_global_pose(grip_bone) * Vector3(0, 0.063, 0.0))
