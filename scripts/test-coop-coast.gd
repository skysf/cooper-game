extends SceneTree

const Coast = preload("res://coast_layout.gd")
const Lake = preload("res://lake_layout.gd")
const Motion = preload("res://player_motion.gd")
const Ship = preload("res://spaceship.gd")
const Rules = preload("res://rules.gd")
const Atlas = preload("res://field_atlas.gd")
const STEP := 1.0 / 60.0

var failures := 0
var notes: Array[Dictionary] = []
var grid: Dictionary
var ship_grid: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func _expect(ok: bool, description: String) -> void:
	notes.append({"check": description, "ok": ok})
	if not ok:
		failures += 1
		push_error(description)

func _toward(actor: Dictionary, target: Vector2, swim_count: Array[int]) -> bool:
	var start: Vector2 = actor.point
	var budget := ceili((start.distance_to(target) * 1.25 + 2.0) / (STEP * Motion.SWIM_SPEED))
	for frame in budget:
		var at: Vector2 = actor.point
		if at.distance_to(target) < 0.085:
			return true
		Motion.step(actor, (target - at).limit_length(), 0.0, STEP, grid, {}, ship_grid)
		if actor.swimming:
			swim_count[0] += 1
	printerr("Coast route stopped at %s y %.2f toward %s" % [actor.point, actor.y, target])
	return false

func _route(actor: Dictionary, name: String, swim_count: Array[int]) -> bool:
	for point: Array in Coast.layout[name]:
		if not _toward(actor, Vector2(point[0], point[1]), swim_count):
			return false
	return true

func _check_buddha() -> void:
	var statue := Coast.buddha
	var ledge: Vector2 = Atlas.LANDMARKS.buddha.landing
	var beachgoer := Motion.spawn(ledge)
	_expect(Rules.free_at(ledge, grid) and beachgoer.grounded and not beachgoer.swimming
		and Coast.area(ledge, Lake.water_y()) == "buddha", "The atlas arrival is dry, open and beside the sculpture")
	var route := [Vector2(11.7,21),Vector2(11.7,15.1),Vector2(10.6,15.35),Vector2(9.5,16),
		Vector2(8.2,16.35),Vector2(6.6,16.6),Vector2(4.43,16.96)]
	for waypoint: Vector2 in route:
		var goal := statue.pose * waypoint
		for i in 360:
			if beachgoer.point.distance_to(goal) < .11:
				break
			var jump := 1.0 if i > 50 and i % 80 < 5 else 0.0
			Motion.step(beachgoer, beachgoer.point.direction_to(goal), jump, STEP, grid, {}, ship_grid)
	for i in 90:
		Motion.step(beachgoer, Vector2.ZERO, 0.0, STEP, grid, {}, ship_grid)
	_expect(beachgoer.point.distance_to(statue.pose * route.back()) < .12 and beachgoer.grounded
		and absf(beachgoer.y - statue.sole_y - 2.28)<.025, "Movement and jumping reach the nail from the atlas landing")
	var crest := Coast.height(statue.pose * Vector2(0,-12))
	_expect(crest > statue.sole_y + 72, "The continuous headland rises above the Buddha's crown")
	var island: Vector2 = Atlas.LANDMARKS.island.landing
	var eye := Coast.height(island) + Motion.WALK_EYE
	for feature: Vector3 in [Vector3(0,68,1), Vector3(0,61,5), Vector3(7,32,12), Vector3(4.43,2.28,16.96)]:
		var target := statue.pose * Vector2(feature.x,feature.z)
		var visible := true
		for i in range(1,160):
			var t := float(i) / 160.0
			if Coast.height(island.lerp(target,t)) > lerpf(eye,statue.sole_y+feature.y,t):
				visible = false
				break
		_expect(visible, "Clear island sightline to sculpture at local height %.2f" % feature.y)
	for side: float in [-1., 1.]:
		var seated := true
		for dx: float in [-.42,.42]:
			for dz: float in [-.39,.39]:
				var point := statue.pose * Vector2(side*4.43+dx, 16.96+dz)
				var actor := Motion.put_ashore(Vector3(point.x,statue.sole_y+3.3,point.y))
				for tick in 90:
					Motion.step(actor, Vector2.ZERO, 0., STEP, grid, {}, ship_grid)
				seated = seated and actor.grounded and absf(actor.y - statue.sole_y - 2.27)<.025 and Rules.obstacle_free_at(point,grid,actor.y)
		_expect(seated, "Four player footprints land on a single big toenail on side %.0f" % side)
	var at := statue.pose * Vector2(7,18.75)
	var walker := Motion.spawn(at)
	var blocked := statue.pose * Vector2(7,7)
	for i in 180:
		Motion.step(walker, walker.point.direction_to(blocked), 0, STEP, grid, {}, ship_grid)
	_expect(walker.point.distance_to(blocked)>6.0 and walker.y < statue.sole_y+3,
		"Walking into the toes cannot pass through the foot or snap up onto the knees")

func _run() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	ship_grid = Ship.collision_grid(world)
	_check_buddha()
	var join_error := 0.0
	for z in range(-117, 12):
		var a := Lake.ground_height(Vector2(-30.001, z))
		var b := Lake.ground_height(Vector2(-29.999, z))
		join_error = maxf(join_error, absf(a - b))
	_expect(join_error < 0.085, "The inland and coastal height fields meet at the old western edge")
	var actor := Motion.spawn(Coast.point("entry"))
	var swim_count: Array[int] = [0]
	_expect(_route(actor, "ridgeTrail", swim_count) and actor.y > 15.8 and swim_count[0] == 0,
		"Normal player movement walks from the lake up to the clifftop")
	_expect(_route(actor, "beachTrail", swim_count) and actor.y < 1.5,
		"The descending trail reaches the shore with the same collision data")
	_expect(_toward(actor, Coast.point("reef"), swim_count) and actor.swimming,
		"Normal movement switches to swimming and crosses the outer reef")
	_expect(_toward(actor, Coast.point("landing"), swim_count)
		and _route(actor, "islandTrail", swim_count) and not actor.swimming and actor.y > 7.0,
		"A swimmer can land and walk to the top of the offshore island")
	_expect(swim_count[0] > 100, "The bay and ocean route includes sustained swimming")

	var flight := Ship.from_save({}, ship_grid)
	var velocity := Vector3.ZERO
	for frame in 660:
		velocity = Ship.step(flight, velocity, Vector2(-0.83, 0.55), 1.0, PI * 0.5, STEP, ship_grid)
	var flight_start: Vector2 = Ship.point(flight)
	var flight_target := Vector2(-172.0, -55.0)
	var fastest := 0.0
	for frame in 1100:
		var offset := flight_target - Ship.point(flight)
		velocity = Ship.step(flight, velocity, offset.limit_length(), 0.0, PI * 0.5, STEP, ship_grid)
		fastest = maxf(fastest, Vector2(velocity.x, velocity.z).length())
		if offset.length() < 0.15:
			break
	_expect(flight_start.x > -112.0 and Ship.point(flight).distance_to(flight_target) < 0.4 and fastest >= 10.9,
		"The same ship flies at full speed from the mainland across the reef to the island")
	var float_site := Vector2(-143.0, -53.5)
	var afloat := Ship.from_save({"x": float_site.x, "z": float_site.y, "yaw": PI * 0.5}, ship_grid)
	var dismount := Ship.dismount(afloat, grid, ship_grid, 0.0)
	_expect(afloat.onWater and dismount.is_finite() and Motion.put_ashore(dismount).swimming,
		"The ship can park on sea water and let a player get out to swim")
	var persisted := Motion.spawn(flight_target)
	_expect(persisted.y > 0.3 and persisted.grounded, "A saved island location restores on the new terrain")
	print("COAST_PHYSICS ", JSON.stringify({"checks": notes, "seamError": join_error, "swimFrames": swim_count[0],
		"fastestShip": fastest, "shipTargetDistance": Ship.point(flight).distance_to(flight_target)}))
	quit(0 if failures == 0 else 1)
