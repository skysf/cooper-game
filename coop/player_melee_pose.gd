extends RefCounted

const Weapons = preload("res://weapons.gd")
const GUARD_HOLD := 0.16
const GUARD_RELEASE := 0.30

var clip: StringName = &""
var phase := 0.0
var weight := 0.0
var pitch := 0.0
var last_at := -10.0
var last_weapon := ""
var chained := false
var tracks := {}
var underneath := {}

func sync(state: Dictionary, elapsed: float) -> void:
	var weapon: String = state.get("weapon", "")
	var at := float(state.get("attackAt", -10.0))
	clip = &""
	weight = 0.0
	if at < 0.0 or state.get("attackWeapon", weapon) != weapon or float(state.get("health", 100.0)) <= 0.0:
		return
	var duration := float(Weapons.stats(weapon).time)
	var age := maxf(0.0, elapsed - at)
	var fist := weapon.is_empty()
	if age >= duration + (GUARD_HOLD + GUARD_RELEASE if fist else 0.0):
		return
	clip = Weapons.melee_clip(weapon, int(state.get("punchStep", 0)), state.get("shield", false))
	if clip == &"":
		return
	if at != last_at:
		chained = fist and last_weapon == "" and at - last_at <= duration + GUARD_HOLD
		last_at = at
		last_weapon = weapon
	phase = clampf(age / duration, 0.0, 1.0)
	weight = 1.0 if chained else smoothstep(0.0, minf(0.09, duration * .18), age)
	if fist:
		weight *= 1.0 - smoothstep(duration + GUARD_HOLD, duration + GUARD_HOLD + GUARD_RELEASE, age)
	else:
		weight *= 1.0 - smoothstep(.75, 1.0, phase)
	pitch = clampf(float(state.get("attackPitch", 0.0)), -.75, .72)

func restore(rig: Skeleton3D) -> void:
	for bone: int in underneath:
		rig.set_bone_pose(bone, underneath[bone])
	underneath.clear()

func _tracks(rig: Skeleton3D, action: Animation) -> Array:
	if tracks.has(clip):
		return tracks[clip]
	var items := []
	for i in action.get_track_count():
		var path := action.track_get_path(i)
		if path.get_subname_count() == 0:
			continue
		var bone_name := String(path.get_subname(0))
		var kind := action.track_get_type(i)
		if kind != Animation.TYPE_ROTATION_3D and not (bone_name == "hips" and kind == Animation.TYPE_POSITION_3D):
			continue
		var bone := rig.find_bone(bone_name)
		if bone < 0 or bone_name == "root":
			continue
		var lower := bone_name == "hips" or bone_name.begins_with("thigh") or bone_name.begins_with("shin") or bone_name.begins_with("foot") or bone_name.begins_with("toes")
		items.append({"bone": bone, "track": i, "position": kind == Animation.TYPE_POSITION_3D,
			"lower": lower, "shield_arm": not lower and bone_name.ends_with("_L")})
	tracks[clip] = items
	return items

func apply(rig: Skeleton3D, animator: AnimationPlayer, leg_weight: float, shield: bool, chest: int, pitch_axis: Vector3) -> void:
	if weight <= .001 or clip == &"" or not animator.has_animation(clip):
		return
	var action := animator.get_animation(clip)
	var time := phase * action.length
	for entry: Dictionary in _tracks(rig, action):
		if shield and entry.shield_arm:
			continue
		var amount := weight * (leg_weight if entry.lower else 1.0)
		if amount <= .001:
			continue
		var bone: int = entry.bone
		if not underneath.has(bone):
			underneath[bone] = rig.get_bone_pose(bone)
		if entry.position:
			rig.set_bone_pose_position(bone, rig.get_bone_pose_position(bone).lerp(
				action.position_track_interpolate(entry.track, time), amount))
		else:
			var rotation := action.rotation_track_interpolate(entry.track, time)
			if bone == chest:
				rotation *= Quaternion(pitch_axis, pitch)
			rig.set_bone_pose_rotation(bone, rig.get_bone_pose_rotation(bone).slerp(rotation, amount))
