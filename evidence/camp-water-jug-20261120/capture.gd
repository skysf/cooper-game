extends SceneTree
## Run on a project staged with original and candidate jugs and the actual camp table.

const COMPARE := [
	["baseline", "res://props/baseline_water_jug.glb"],
	["candidate", "res://props/camp_water_jug.glb"],
]
const TABLE := "res://props/camp_table.glb"
const StorageView = preload("res://staged-storage-view.gd")
const Placement = preload("res://placement.gd")
const PlacementWorld = preload("res://placement_world.gd")
const Lake = preload("res://lake_layout.gd")
const Stones = preload("res://stones.gd")
const JUG_PATH := "res://props/camp_water_jug.glb"
const KIT_PATH := "res://props/construction/cabin_kit.json"
const TABLE_SPOT := Vector3(-.29,.18,-.37)
const TABLE_JUG := Vector3(.49,.79,.19)
const FLOOR_SPOT := Vector3(.76,.18,.72)
const STUDIO := Vector2i(640,480)
const VIEWS := [Vector3(.92,.52,1.15),Vector3(-.92,.64,-1.15)]
var viewport := SubViewport.new()
var camera := Camera3D.new()
var destination := ""
var report := {}
var failed := false
var site: Vector3
var shell := Node3D.new()
var doorway_light := SpotLight3D.new()
var key := DirectionalLight3D.new()
var solids: Array[Dictionary] = []
var placements := {}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		quit(2)
		return
	destination = args[0]
	viewport.size = STUDIO
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(camera)
	camera.make_current()
	light_studio()
	assemble_room()
	for variant: Array in COMPARE:
		var revision: String = variant[0]
		var jug := model(variant[1])
		var bounds := real_bounds(jug)
		var inspect := inspect_mesh(jug,bounds)
		report[revision] = {"aabb": {"position": floats(bounds.position), "size": floats(bounds.size)}, "assetChecks":inspect}
		for index in VIEWS.size():
			viewport.size = STUDIO
			frame(bounds,VIEWS[index])
			await shot(revision+"-studio-%d" % (index+1))
		jug.free()
		await room_views(revision,variant[1])
	var output := FileAccess.open(destination.path_join("capture.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	quit(3 if failed else 0)

func assemble_room() -> void:
	site = Vector3(9.8,Lake.walk_height(Vector2(9.8,-82.2))+.12,-82.2)
	viewport.add_child(shell)
	var kit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(KIT_PATH))
	piece("floor",kit.pieces.cabin_floor.model,site,0.0)
	for wall: Dictionary in kit.assembly.walls:
		var node := model(kit.pieces[wall.kind].model,shell)
		node.position = site + Stones.unpack(wall.at)
		node.rotation.y = float(wall.yaw)
	var roof := model(kit.pieces.cabin_roof.model,shell)
	roof.position = site + Stones.unpack(kit.assembly.roofAt)
	piece("table",TABLE,site+TABLE_SPOT,0.0)
	var floor_profile := PlacementWorld.profile("cabin_floor")
	var table_profile := PlacementWorld.profile("wood_table")
	solids.append_array(Placement.bodies("floor",floor_profile,Transform3D(Basis.IDENTITY,site)))
	solids.append_array(Placement.bodies("table",table_profile,Transform3D(Basis.IDENTITY,site+TABLE_SPOT)))
	var profile := PlacementWorld.profile("water_jug")
	for fixture: String in ["table","floor"]:
		var origin := site + (TABLE_SPOT+TABLE_JUG if fixture=="table" else FLOOR_SPOT)
		var aim := Placement.solve(origin+Vector3.UP*.60,origin-Vector3.UP*.10,-.32,profile,solids)
		validate(aim.ok and aim.supports.has(fixture) and absf(aim.pose.origin.y-origin.y)<.0001,
			"Placement supports jug at " + fixture + ": " + str(aim))
		placements[fixture] = aim.pose if aim.ok else Transform3D(Basis(Vector3.UP,-.32),origin)
	doorway_light.spot_range = 4.1
	doorway_light.spot_angle = 54.0
	doorway_light.light_color = Color("#eccfa7")
	doorway_light.light_energy = 1.22
	doorway_light.position = site+Vector3(.05,1.75,1.39)
	shell.add_child(doorway_light)
	doorway_light.look_at(site+Vector3(.24,.63,-.28))
	shell.hide()

func piece(label: String, uri: String, at: Vector3, yaw: float) -> void:
	var node := model(uri,shell)
	node.name = label
	node.position = at
	node.rotation.y = yaw

func room_views(revision: String, uri: String) -> void:
	shell.show()
	key.shadow_enabled = true
	viewport.size = Vector2i(960,720)
	var storage := StorageView.new()
	viewport.add_child(storage)
	storage.resources[JUG_PATH] = load(uri)
	var actors := {"reviewer":{"x":site.x+.85,"y":site.y+.18,"z":site.z+1.02,"yaw":.35}}
	var record := {"kind":"water_jug","mode":"ground","yaw":-.32,"at":[0.,0.,0.]}
	var records := {"camp-water-jug":record}
	var table_pose: Transform3D = placements.table
	record.at = floats(table_pose.origin)
	var q := table_pose.basis.get_rotation_quaternion()
	record.rotation = [q.x,q.y,q.z,q.w]
	cam(table_pose*Vector3(.50,.43,.60),table_pose*Vector3(-.09,.095,-.041),42.0)
	storage.sync(records,actors,"",camera,false,50.0)
	var entry: Dictionary = storage.live.get("camp-water-jug",{})
	if entry.is_empty():
		validate(false,"Production storage scene did not instantiate the jug.")
		storage.free()
		shell.hide()
		return
	var prop: Node3D = entry.root
	var packed: String = entry.model.scene_file_path
	validate(packed == uri and absf(prop.position.y-table_pose.origin.y)<.00002 and prop.visible,
		"Storage placed the requested jug on the real table.")
	await shot(revision+"-table")
	var focus := table_pose*Vector3(.040,.221,.0)
	cam(focus + Vector3(.234,.214,.240),focus,35.0)
	await shot(revision+"-join")
	var mouth := table_pose*Vector3(.004,.221,.001)
	cam(mouth+Vector3(.060,.329,.111),mouth,34.0)
	await shot(revision+"-water")
	var ground_pose: Transform3D = placements.floor
	record.at = floats(ground_pose.origin)
	cam(ground_pose*Vector3(-.27,.46,-.49),ground_pose*Vector3(-.014,.091,0.0),43.0)
	storage.sync(records,actors,"",camera,false,50.0)
	validate(storage.live["camp-water-jug"].model == entry.model and prop.position.is_equal_approx(ground_pose.origin),
		"Same jug asset after placing on cabin floor.")
	await shot(revision+"-ground")
	record.mode = "held"
	record.holder = "reviewer"
	var actor: Dictionary = actors.reviewer
	var flow := Vector3(0.0,0.0,-(.77+.12*.44)).rotated(Vector3.UP,float(actor.yaw))
	var held := Vector3(actor.x,float(actor.y)+.66,actor.z)+flow
	cam(held+Vector3(.38,.38,.63),held+Vector3(-.03,.111,0.0),42.0)
	storage.sync(records,actors,"",camera,false,50.0)
	validate(storage.live["camp-water-jug"].model == entry.model and prop.position.is_equal_approx(held) and prop.visible,
		"Same visible model returned by real carried-prop logic.")
	await shot(revision+"-held")
	report[revision]["storagePoses"] = {"table":floats(table_pose.origin-site),
		"ground":floats(ground_pose.origin-site),"held":floats(prop.position-site),"asset":packed}
	storage.free()
	shell.hide()
	key.shadow_enabled = false

func inspect_mesh(prop: Node3D, bounds: AABB) -> Dictionary:
	var metrics := {"waterTop":0.0,"waterRadius":0.0,"mappedMaterialCount":0,"surfaces":0}
	var mesh := prop.find_child("*",true,false) as MeshInstance3D
	if prop is MeshInstance3D:
		mesh = prop
	if mesh == null:
		validate(false,"Missing imported prop mesh")
		return metrics
	var profile := PlacementWorld.profile("water_jug")
	var collision: AABB = profile.bounds
	validate(collision.grow(.00010).encloses(bounds) and absf(bounds.position.y)<.00001,
		"The exact imported jug fits its placement collision profile.")
	for i in mesh.mesh.get_surface_count():
		var material := mesh.mesh.surface_get_material(i) as StandardMaterial3D
		metrics.surfaces += 1
		if material.albedo_texture and material.normal_texture and material.roughness_texture:
			metrics.mappedMaterialCount += 1
		if material.resource_name.begins_with("Water inside jug"):
			var arrays := mesh.mesh.surface_get_arrays(i)
			for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				metrics.waterTop = maxf(metrics.waterTop,point.y)
				metrics.waterRadius = maxf(metrics.waterRadius,Vector2(point.x,point.z).length())
	validate(absf(float(metrics.waterTop)-.174)<.0001 and absf(float(metrics.waterRadius)-.052)<.0001,
		"The visible water disk preserves the original shape and level.")
	metrics.collisionBounds = {"position":floats(collision.position),"size":floats(collision.size)}
	return metrics

func validate(ok: bool, description: String) -> void:
	if not ok:
		failed = true
		push_error(description)

func model(uri: String, parent: Node3D = null) -> Node3D:
	var part := (load(uri) as PackedScene).instantiate() as Node3D
	if parent == null:
		viewport.add_child(part)
	else:
		parent.add_child(part)
	return part

func real_bounds(prop: Node3D) -> AABB:
	var meshes := prop.find_children("*","MeshInstance3D",true,false)
	if prop is MeshInstance3D:
		meshes.push_front(prop)
	var result := AABB()
	for mesh: MeshInstance3D in meshes:
		var current: AABB = mesh.global_transform * mesh.get_aabb()
		result = current if not result.has_volume() else result.merge(current)
	return result

# Match the permanent model-review camera and two fixed lights on the studio shots.
func light_studio() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#334043")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("#dee7eb")
	world.environment.ambient_light_energy = .66
	viewport.add_child(world)
	key.rotation_degrees = Vector3(-45,-33,0)
	key.light_color = Color("#fff5e8")
	key.light_energy = .84
	key.directional_shadow_max_distance = 9.0
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25,158,0)
	fill.light_color = Color("#d8efff")
	fill.light_energy = .36
	viewport.add_child(fill)

func frame(bounds: AABB, angle: Vector3) -> void:
	var center := bounds.get_center()
	var span := bounds.size.length()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = center + angle.normalized()*span*1.28
	camera.look_at(center)
	camera.near = maxf(span*.003,.0005)
	camera.far = span*3.+.03
	var half := bounds.size*.5
	var frame_width := camera.basis.x.abs().dot(half)*2.
	var frame_height := camera.basis.y.abs().dot(half)*2.
	camera.size = maxf(frame_height,frame_width/(float(STUDIO.x)/STUDIO.y))*1.12

func cam(at: Vector3, target: Vector3, fov: float) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.position = at
	camera.look_at(target)
	camera.near = .007
	camera.far = 9.0
	camera.fov = fov

func shot(name: String) -> void:
	for index in 5:
		await RenderingServer.frame_post_draw
	var frame_data := viewport.get_texture().get_image()
	if frame_data == null or frame_data.save_png(destination.path_join(name+".png")) != OK:
		failed = true
		push_error(name+" was not saved")

func floats(v: Vector3) -> Array:
	return [v.x,v.y,v.z]
