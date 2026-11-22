extends SceneTree

const Land = preload("res://east/land.gd")
const Lake = preload("res://lake_layout.gd")
const Region = preload("res://east/region_scene.gd")
const Rules = preload("res://rules.gd")
const Motion = preload("res://player_motion.gd")
const Ship = preload("res://spaceship.gd")
const CameraProbe = preload("res://follow_camera.gd")
var failures: Array[String] = []

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error(note)

func _initialize() -> void:
	var shrubs := Region.new()
	var roots := {}
	for kind: String in shrubs.root_rims:
		var highest := -INF
		for plant: Array in shrubs.plants[kind]:
			var pose := shrubs.plant_pose(kind,plant)
			for v: Array in shrubs.root_rims[kind]:
				var contact := pose * Vector3(v[0],v[1],v[2])
				highest = maxf(highest,contact.y-Lake.ground_height(Vector2(contact.x,contact.z)))
		check(highest < -.023,kind+" actual rendered root rim stays under ground")
		roots[kind] = {"instances":shrubs.plants[kind].size(),"leastCoverM":-highest}
	shrubs.free()
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	var grid := Rules.collision_grid(world.obstacles)
	var air := Ship.collision_grid(world)
	var follow := CameraProbe.new()
	follow.configure(world)
	var args := OS.get_cmdline_user_args()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var fixture: Dictionary = data.collisionFixture
	var approaches := []
	for p: Dictionary in fixture.approaches:
		var from := Vector2(p.start[0],p.start[1])
		var aim := Vector2(p.aim[0],p.aim[1])
		var direction := from.direction_to(aim)
		check(absf(Land.Rocks.top(aim)-float(p.top))<.003,"Rendered rock height agrees with mesh ray")
		for fps: float in [30.,60.]:
			var actor := Motion.spawn(from)
			var furthest := 0.0
			for i in int(fps*1.35):
				Motion.step(actor,direction,1.0 if i==int(fps*.45) else 0.0,1.0/fps,grid,{},air)
				var advance: float = (actor.point-from).dot(direction)
				furthest = maxf(furthest,advance)
				check(actor.y+.012>=Land.Rocks.top(actor.point),"Feet never enter the visible stone")
			check(furthest<from.distance_to(aim)+.12,"Walking and jumping into the broad rock face stops the body")
			approaches.append({"fps":fps,"advanceM":furthest})
		var pivot := Vector3(from.x,Lake.ground_height(from)+.6,from.y)
		var camera_length := follow.clear_distance(pivot,Vector3(direction.x,0,direction.y)*3)
		check(camera_length<1.9,"Chase camera shortens before touching the rock")
	var roof := Vector3(fixture.roof[0],fixture.roof[1],fixture.roof[2])
	var xz := Vector2(roof.x,roof.z)
	var restored := Motion.spawn(xz,fixture.oldFeet)
	check(absf(restored.y-roof.y)<.004,"An old subterranean save resumes on the rock")
	var falling := Motion.put_ashore(roof+Vector3.UP*2.0)
	for i in 150:
		Motion.step(falling,Vector2.ZERO,0,.016,grid,{},air)
	check(falling.grounded and absf(falling.y-roof.y)<.004,"Landing on the visible rock surface")
	var shores := {}
	for id: String in Land.springs:
		var camp: Dictionary = Land.region.camps[id]
		var spring: Dictionary = Land.springs[id]
		var center := Vector2(camp.water[0],camp.water[1])
		var count := 0
		for i in range(-32,33):
			for j in range(-32,33):
				var at := center+.12*Vector2(i,j)
				if is_finite(Lake.surface_height(at)):
					count+=1
					check(Lake.ground_height(at)<float(spring.level) and at.distance_to(center)<3.3,"Water is contained by a continuous soil bank")
		check(count>700 and absf(Lake.surface_height(center)-Lake.walk_height(center)-.4)<.002,"Spring is a real shallow hollow")
		shores[id] = count
	print("EASTERN_CONTACTS ",JSON.stringify({"rootContacts":roots,"rockApproaches":approaches,"savedFeet":restored.y,"landing":falling.y,"springSamples":shores,"errors":failures}))
	quit(0 if failures.is_empty() else 1)
