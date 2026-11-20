extends SceneTree

const Motion = preload("res://player_motion.gd")
const Rules = preload("res://rules.gd")
const Lake = preload("res://lake_layout.gd")
var failures := 0
var report := {"mode": "independent deterministic real PlayerMotion.step; no animation state setters", "checks": [], "trace": {}}

func _initialize() -> void:
	_verify.call_deferred()

func expect(label: String, ok: bool) -> void:
	report.checks.append({"name": label, "ok": ok})
	if not ok:
		failures += 1
		push_error(label)

func sample(a: Dictionary) -> Dictionary:
	return {"x": a.point.x, "z": a.point.y, "y": a.y, "vy": a.vy, "grounded": a.get("grounded"), "vx": a.get("vx"), "vz": a.get("vz"), "swimming": a.swimming, "waterVy": a.get("waterVy"), "floor": Lake.walk_height(a.point), "surface": Lake.surface_height(a.point) if is_finite(Lake.surface_height(a.point)) else null}

func _verify() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	var grid := Rules.collision_grid(world.obstacles)
	for magnitude in [0.4, 1.0]:
		var a := Motion.spawn(Vector2(10.5, -86))
		for i in 60:
			Motion.step(a, Vector2(0, -magnitude), 0.0, 1.0 / 60.0, grid, {})
		var distance: float = -86.0 - a.point.y
		expect("real direction magnitude " + str(magnitude) + " preserves existing speed", absf(distance - Rules.SPEED * magnitude) < .06)
		report.trace["speed-" + str(magnitude)] = sample(a)
	var wall := Motion.spawn(Vector2(10.5, -86))
	var last := Vector2.ZERO
	for i in 240:
		if i == 180:
			last = wall.point
		Motion.step(wall, Vector2.UP, 0.0, 1.0 / 60.0, grid, {})
	expect("held motion against real tree stops physical displacement", wall.point.distance_to(last) < .025 and absf(wall.get("vx", 0.0)) + absf(wall.get("vz", 0.0)) < .02)
	report.trace.wall = sample(wall)
	var jump := Motion.spawn(Vector2(10.5, -86))
	var jump_trace := []
	# This real integration step lands almost exactly on the trajectory apex.
	var dt := Motion.JUMP_SPEED / (Motion.GRAVITY * 30.0)
	var peak := 0.0
	var near_apex := false
	var false_contact := false
	for i in 100:
		Motion.step(jump, Vector2.ZERO, 1.0, dt, grid, {})
		peak = maxf(peak, jump.y)
		if jump.y > Lake.walk_height(jump.point) + .03:
			false_contact = false_contact or jump.get("grounded", false)
			if absf(jump.vy) < .02:
				near_apex = true
		jump_trace.append(sample(jump))
	expect("Space rises and held Space lands without re-jumping", peak > .65 and absf(jump.y - Lake.walk_height(jump.point)) < .01 and jump.get("grounded", false))
	expect("zero-vy apex is still physically airborne", near_apex and not false_contact)
	report.trace.jump = jump_trace
	var swimmer := Motion.spawn(Vector2(-24, -29))
	var water_trace := []
	var shallow_walk := false
	for i in 240:
		Motion.step(swimmer, Vector2.UP, 0.0, 1.0 / 60.0, grid, {})
		var depth := Lake.surface_height(swimmer.point) - Lake.walk_height(swimmer.point)
		if is_finite(depth) and depth > .03 and depth < Motion.SWIM_MIN_DEPTH - .03:
			shallow_walk = shallow_walk or not swimmer.swimming and swimmer.get("grounded", false)
		if i % 4 == 0:
			water_trace.append(sample(swimmer))
	expect("real shallow water remains grounded walking", shallow_walk)
	expect("continuing from shore reaches actual swimming", swimmer.swimming and not swimmer.get("grounded", true))
	for i in 60:
		Motion.step(swimmer, Vector2.ZERO, 0.0, 1.0 / 60.0, grid, {})
	expect("release in deep water floats without horizontal motion", swimmer.swimming and absf(swimmer.get("vx", 0.0)) + absf(swimmer.get("vz", 0.0)) < .02)
	for i in 300:
		Motion.step(swimmer, Vector2.DOWN, 0.0, 1.0 / 60.0, grid, {})
	expect("real return to shore restores ground contact", not swimmer.swimming and swimmer.get("grounded", false) and absf(swimmer.y - Lake.walk_height(swimmer.point)) < .01)
	water_trace.append(sample(swimmer))
	report.trace.water = water_trace
	report.ok = failures == 0
	var output := FileAccess.open(args[0], FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print("INDEPENDENT_MOTION_PHYSICS ", JSON.stringify({"ok": failures == 0, "checks": report.checks.size()}))
	quit(0 if failures == 0 else 1)
