extends SceneTree
const Motion = preload("res://player_motion.gd")
const Rules = preload("res://rules.gd")
const Lake = preload("res://lake_layout.gd")
const Hiker = preload("res://hiker.gd")
const Survival = preload("res://survival.gd")
var failed := 0
var checks := []
var samples := {}
const DT := 1.0 / 60.0
func _initialize() -> void:
	_verify.call_deferred()
func _check(ok: bool, label: String) -> void:
	checks.append({"ok": ok, "check": label})
	if not ok:
		failed += 1
		push_error(label)
func _person(at: Vector2) -> Hiker:
	var h := Hiker.new()
	root.add_child(h)
	h.outfit(1)
	h.wear_clothes(Survival.initial_wear())
	h.position = Vector3(at.x, 0, at.y)
	h.target = h.position
	return h
func _step(h: Hiker, actor: Dictionary, direction: Vector2, lift := 0.0, grid := {}) -> void:
	Motion.step(actor, direction, lift, DT, grid, {})
	h.target = Vector3(actor.point.x, actor.y, actor.point.y)
	h.set_motion_state(actor)
	h.advance(DT, true)
func _verify() -> void:
	var start := Vector2(14, -76)
	var h := _person(start)
	var actor := Motion.spawn(start)
	var foot_low := INF
	var foot_high := -INF
	var steady_foot_low := INF
	for i in 120:
		_step(h, actor, Vector2(0.4, 0))
		for boot: MeshInstance3D in h.boots:
			var sole := INF
			# A rotated AABB includes empty corners outside the ellipsoid; measure the real mesh.
			for vertex: Vector3 in boot.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				sole = minf(sole, (boot.global_transform * vertex).y)
			foot_low = minf(foot_low, sole)
			if i > 30:
				steady_foot_low = minf(steady_foot_low, sole)
			foot_high = maxf(foot_high, sole)
	_check(h.motion_clip == "move/Walk" and absf(h.render_speed - 1.44) < .05 and absf(h.motion_rate - 1.44/1.46) < .05, "real partial-direction motion selects a speed-matched walk without a new input mode")
	_check(foot_low > -0.004 and foot_high > foot_low + .04, "walking plants and lifts the actual attached boots without sinking into the floor")
	samples.walk = {"speed": h.render_speed, "rate": h.motion_rate, "footBottomRange": [foot_low, foot_high], "steadyFootLow": steady_foot_low}
	var run_foot_low := INF
	for i in 90:
		_step(h, actor, Vector2.RIGHT)
		for boot: MeshInstance3D in h.boots:
			for vertex: Vector3 in boot.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				run_foot_low = minf(run_foot_low, (boot.global_transform * vertex).y)
	samples.run = {"speed": h.render_speed, "rate": h.motion_rate, "footLowIncludingBlend": run_foot_low}
	_check(run_foot_low > -0.004, "actual default-speed boots remain above the floor through walk/run blending")
	_check(h.motion_clip == "move/Run" and absf(h.render_speed - Rules.SPEED) < .05 and absf(h.motion_rate - Rules.SPEED / 3.56) < .05, "existing full-speed movement automatically selects the authored run")
	var wall_at: Vector2 = actor.point + Vector2(1.5, 0)
	var wall := Rules.collision_grid([{"type": "tree", "x": wall_at.x, "z": wall_at.y, "r": .4}])
	for i in 120:
		_step(h, actor, Vector2.RIGHT, 0, wall)
	_check(h.motion_clip == "Stand" and absf(actor.vx) < .001 and h.render_speed < .08, "holding movement into a real collision stops the feet instead of running in place")
	actor = Motion.spawn(start)
	h.position = Vector3(start.x, actor.y, start.y)
	h.last_grounded = true
	h.last_swimming = false
	h.motion_seen = false
	var highest := 0.0
	var apex_air := false
	var stages := []
	var previous_y := float(actor.y)
	var land_events := 0
	var grounded_transitions := 0
	for i in 120:
		var before_grounded: bool = actor.grounded
		_step(h, actor, Vector2.ZERO, 1.0)
		highest = maxf(highest, actor.y)
		if h.motion_clip not in stages:
			stages.append(h.motion_clip)
		if not actor.grounded and absf(actor.vy) < .25:
			apex_air = h.motion_clip == "move/Air"
		if not before_grounded and actor.grounded:
			grounded_transitions += 1
		if h.motion_clip == "move/Land":
			land_events += 1
		previous_y = actor.y
	_check(highest > .65 and "move/Takeoff" in stages and "move/Air" in stages and "move/Land" in stages, "the actual ballistic jump drives takeoff, flight and contact landing")
	_check(apex_air, "zero vertical speed at the jump apex remains airborne rather than falsely landing")
	_check(grounded_transitions == 1 and actor.grounded and is_zero_approx(actor.y) and land_events >= 10 and h.motion_clip == "Stand", "holding jump cannot repeat; the real landing has a short recovery and returns to idle")
	samples.jump = {"height": highest, "stages": stages, "landingFrames": land_events, "contacts": grounded_transitions}
	actor = Motion.spawn(Vector2(-26, -40))
	h.position = Vector3(actor.point.x, actor.y, actor.point.y)
	h.motion_seen = false
	var hand_start := Vector3.ZERO
	var hand_travel := 0.0
	var foot_start := Vector3.ZERO
	var foot_travel := 0.0
	h.holding = true
	h.shielding = true
	for i in 100:
		_step(h, actor, Vector2.UP)
		var hand := h.rig.get_bone_global_pose(h.grip_bone).origin
		var foot := h.rig.get_bone_global_pose(h.foot_bones[0]).origin
		if i == 20:
			hand_start = hand
			foot_start = foot
		if i > 20:
			hand_travel = maxf(hand_travel, hand.distance_to(hand_start))
			foot_travel = maxf(foot_travel, foot.distance_to(foot_start))
	_check(actor.swimming and not actor.grounded and h.motion_clip == "move/Swim" and h.body.transform.is_equal_approx(Transform3D.IDENTITY), "real deep-water movement selects the authored swim without the old whole-body rotation")
	_check(hand_travel > .15 and foot_travel > .05 and h.holding_blend < .01 and h.shield_blend < .01, "swimming has real arm strokes and leg kicks, with free arms while carried gear is stowed")
	for i in 90:
		_step(h, actor, Vector2.ZERO)
	_check(h.motion_clip == "move/Tread" and actor.swimming and not actor.grounded and h.render_speed < .08, "stopping in deep water treads rather than holding a frozen stroke")
	var surface_y := float(actor.y)
	for i in 35:
		_step(h, actor, Vector2.ZERO, -1.0)
	_check(h.motion_clip == "move/Swim" and actor.y < surface_y - .5 and actor.waterVy < -.5 and not actor.grounded, "a real dive drives swimming even with no horizontal movement")
	for i in 60:
		_step(h, actor, Vector2.ZERO, 1.0)
	for i in 30:
		_step(h, actor, Vector2.ZERO)
	_check(h.motion_clip == "move/Tread" and absf(float(actor.y) - surface_y) < .02, "rising back to the water surface returns to floating tread")
	for i in 360:
		_step(h, actor, Vector2.DOWN)
	_check(not actor.swimming and actor.grounded and h.motion_clip in ["move/Walk", "move/Run"] and absf(actor.y - Lake.walk_height(actor.point)) < .01, "crossing the real shallow bank resumes grounded locomotion")
	samples.swim = {"handExcursion": hand_travel, "footExcursion": foot_travel, "shore": [actor.point.x, actor.point.y], "grounded": actor.grounded}
	h.set_seated(true)
	_check(h.seated and h.motion_clip == "Sit" and h.animator.assigned_animation == "Sit" and h.garments.cap.visible, "the existing seated pose and hat attachment remain compatible")
	h.set_seated(false)
	h.wear_clothes({"cap": false, "jacket": true, "pants": true})
	h.wear_clothes(Survival.initial_wear())
	_check(h.garments.cap.visible and not h.hair.visible and h.motion_clip == "Stand" and h.animator.assigned_animation == "Stand", "clothing changes and preview-style neutral standing remain natural")
	samples.transitions = h.motion_events
	_verify_recovery()
	print("PLAYER_LOCOMOTION " + JSON.stringify({"checks": checks, "failed": failed, "total": checks.size(), "samples": samples}))
	h.free()
	quit(0 if failed == 0 else 1)

func _head_height(hiker: Hiker) -> float:
	return hiker.rig.to_global(hiker.rig.get_bone_global_pose(hiker.head_bone).origin).y

func _verify_recovery() -> void:
	var h := _person(Vector2.ZERO)
	var state := Motion.spawn(Vector2.ZERO)
	state.merge({"health":0.0,"downAt":20.0})
	h.set_motion_state(state)
	h.holding = true
	h.shielding = true
	var boot_low := INF
	for index in 61:
		h.set_recovery_state(state, 20.0 + float(index)/60.0)
		h.advance(DT, true)
		for boot: MeshInstance3D in h.boots:
			for vertex: Vector3 in boot.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				boot_low = minf(boot_low, (boot.global_transform * vertex).y)
	var down := _head_height(h)
	var down_hand := h.rig.get_bone_global_pose(h.grip_bone)
	_check(h.motion_clip == "recovery/Knockout" and down < .40 and h.holding_blend < .01 and h.shield_blend < .01,
		"the equipped player lands prone and carried-item poses do not override the fall")
	h.set_recovery_state(state, 34.5)
	h.advance(DT, true)
	_check(is_equal_approx(_head_height(h), down) and h.rig.get_bone_global_pose(h.grip_bone).is_equal_approx(down_hand),
		"late observations hold the final fall pose on the shared room clock")
	state.health = 45.0
	state.downAt = -1.0
	state.revivedAt = 34.5
	h.holding = false
	h.shielding = false
	h.set_recovery_state(state, 34.5)
	h.advance(DT, true)
	_check(h.motion_clip == "recovery/Recover" and absf(_head_height(h) - down) < .025,
		"the get-up starts from the settled fall pose at the same world position")
	for index in range(1, 76):
		h.set_recovery_state(state, 34.5 + float(index)/60.0)
		h.advance(DT, true)
		for boot: MeshInstance3D in h.boots:
			for vertex: Vector3 in boot.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				boot_low = minf(boot_low, (boot.global_transform * vertex).y)
	var rising := _head_height(h)
	_check(h.motion_clip == "Stand" and rising > 1.50 and h.position == Vector3.ZERO,
		"the equipped player returns to standing without changing the actor position")
	_check(boot_low >= -.03, "the actual attached boots remain close to or above the floor during the fall and rise")
	samples.recovery = {"fallenHead":down, "standingHead":rising, "minEquippedBoot":boot_low}
	h.free()
