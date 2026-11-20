extends SceneTree

const Terrain = preload("res://terrain.gd")
const Atmosphere = preload("res://atmosphere.gd")
const Layout = preload("res://lake_layout.gd")
const WindField = preload("res://vegetation/wind_field.gd")

var view := SubViewport.new()
var terrain := Terrain.new()
var atmosphere := Atmosphere.new()
var camera := Camera3D.new()
var out := ""
var report := {}
var valid := true

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		quit(2)
		return
	out = args[0]
	view.size = Vector2i(1280,720)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(atmosphere)
	view.add_child(terrain)
	terrain.set_process(false)
	view.add_child(camera)
	camera.near = 0.045
	camera.far = 150.0
	camera.make_current()
	aim(Vector3(-9.0, 1.68, -49.1), Vector3(-19.0, 1.48, -49.3), 72.0)
	for id in ["creek", "crossing", "approach"]:
		var path := args[1].path_join(id + ".glb")
		if not FileAccess.file_exists(path):
			quit(3)
			return
		terrain._parse_chunk(id, FileAccess.get_file_as_bytes(path))
	check(terrain.loaded.has("creek") and terrain.loaded.has("crossing"), "Production lake chunks")
	check(terrain.lake.plants.materials.size() == 2, "Two packed species materials")
	check(terrain.lake.plants.find_children("*", "CollisionObject3D", true, false).is_empty(), "No new collision obstacles")
	verify_seeded()
	terrain.grove.set_room_time(89.0)

	# Look through the same path at the forest margin.
	aim(Vector3(-4.78, 1.49, -44.11), Vector3(-7.92, .73, -43.95), 66.0)
	weather(46.0, 0.0)
	await toggle_pair("hazel")
	aim(Vector3(-5.69, .99, -43.47), Vector3(-6.97, .89, -43.71), 54.0)
	weather(46.0, 0.0)
	await shot("hazel-close", 7)
	weather(89.0, 1.0)
	atmosphere.rain.hide()
	await wind_pair("hazel")

	# Look from the walkable bank toward the same four clumps.
	aim(Vector3(-10.31, 1.54, -45.45), Vector3(-14.15, .50, -43.61), 68.0)
	weather(52.0,0.0)
	await toggle_pair("bulrush")
	aim(Vector3(-11.75, 1.14, -44.32), Vector3(-13.05, .63, -44.26), 60.0)
	weather(52.0,0.0)
	await shot("bulrush-close", 7)
	weather(89.0, 1.0)
	atmosphere.rain.hide()
	await wind_pair("bulrush")

	aim(Vector3(-14.17, -.153, -44.38), Vector3(-13.0, -.162, -44.311), 81.0)
	weather(52.0, 0.0)
	check(atmosphere.underwater, "The shallow roots are visible from an underwater camera")
	await shot("bulrush-underwater",9)
	aim(Vector3(-9.35, 1.72, -49.10), Vector3(-24.0, .1, -49.1), 76.0)
	weather(51.0,0.0)
	await toggle_pair("dock")
	print("LAKE_MARGIN_QA " + JSON.stringify(report))
	quit(0 if valid else 4)

func verify_seeded() -> void:
	var counts := {"Hazel":0, "Bulrush":0}
	var batches := {"Hazel":0, "Bulrush":0}
	var route_clearance := INF
	var rock_gap := INF
	var dock_gap := INF
	var depth_range := Vector2(INF,-INF)
	var hazel_grade_range := Vector2(INF,-INF)
	var lift_range := Vector2(INF,-INF)
	var received_cells := []
	for batch: MultiMeshInstance3D in terrain.lake.plants.find_children("*","MultiMeshInstance3D",false,false):
		var key := str(batch.name).get_slice("_",0)
		var rush := key == "Bulrush"
		counts[key] += batch.multimesh.instance_count
		batches[key] += 1
		check(batch.layers & terrain.lake.REFLECTION_LAYER != 0, "Lake reflection sees " + key)
		check(batch.visibility_range_end <= 39.0 and batch.extra_cull_margin > 0.0, "Bounded batches for " + key)
		check(batch.material_override.shader.resource_path.ends_with("lake_margin.gdshader"), "Wind shared by the full source mesh")
		var used := Vector2(batch.position.x,batch.position.z)
		received_cells.append([key,used.x,used.y,batch.multimesh.instance_count])
		for i in batch.multimesh.instance_count:
			var pose := batch.multimesh.get_instance_transform(i)
			var local_root := batch.position + pose.origin
			var location := Vector2(local_root.x,local_root.z)
			var ground := Layout.ground_height(location)
			var scale := pose.basis.x.length()
			var scatter := (0.46 if rush else 0.79) * scale
			check(is_equal_approx(local_root.y + .014, ground), "Root embedded in actual terrain")
			check(not Layout.on_dock(location), "No root on the boardwalk")
			var dock: Dictionary = Layout.layout.dock
			var lane_reach := absf(location.y - float(dock.z)) - (float(dock.halfWidth) + scatter)
			if location.x > -21.5 and location.x < float(dock.east) + 1.1:
				dock_gap = minf(dock_gap,lane_reach)
				check(lane_reach > 1.12, "Clear approach to boardwalk and open-water corridor")
			for stone: Dictionary in Layout.layout.boulders:
				rock_gap = minf(rock_gap, location.distance_to(Vector2(stone.x,stone.z)) - float(stone.radius) - scatter)
			if rush:
				var depth := Layout.water_y() - ground
				check(is_finite(Layout.surface_height(location)) and depth > .15 and depth < .38, "Emergent plant is in shallow water")
				depth_range.x = minf(depth_range.x,depth)
				depth_range.y = maxf(depth_range.y,depth)
			else:
				check(not is_finite(Layout.surface_height(location)) and ground >= -.01, "Hazel stays on dry ground")
				var grade := slope(location)
				hazel_grade_range.x = minf(hazel_grade_range.x,grade)
				hazel_grade_range.y = maxf(hazel_grade_range.y,grade)
				lift_range.x = minf(lift_range.x,ground - Layout.water_y())
				lift_range.y = maxf(lift_range.y,ground - Layout.water_y())
				route_clearance = minf(route_clearance, route_gap(location) - scatter)
	check(counts.Hazel == Layout.layout.lakesideVegetation.hazel.size() and counts.Bulrush == Layout.layout.lakesideVegetation.bulrush.size(), "All trial placements built")
	check(rock_gap > .09 and route_clearance > 2.1, "Existing rock and path clearance")
	report.plants = {"counts":counts,"batches":batches,"cells":received_cells,
		"hazel_bank_grade":[hazel_grade_range.x,hazel_grade_range.y],
		"hazel_height_above_water":[lift_range.x,lift_range.y],
		"bulrush_bed_depth":[depth_range.x,depth_range.y],
		"remaining_lane_clearance":dock_gap,"closest_new_extent_to_rock":rock_gap,
		"closest_hazel_extent_to_route":route_clearance}

func slope(at: Vector2) -> float:
	var east := Vector2(.4,0)
	var south := Vector2(0,.4)
	var a := Layout.ground_height(at + east) - Layout.ground_height(at - east)
	var b := Layout.ground_height(at + south) - Layout.ground_height(at - south)
	return Vector2(a,b).length() / .8

func route_gap(at: Vector2) -> float:
	var route: Array = terrain.world.route
	var distance := INF
	for i in range(1,route.size()):
		var a := Vector2(route[i-1][1],route[i-1][2])
		var b := Vector2(route[i][1],route[i][2])
		var closest := Geometry2D.get_closest_point_to_segment(at,a,b)
		distance = minf(distance,at.distance_to(closest))
	return distance

func aim(origin: Vector3, target: Vector3, fov: float) -> void:
	camera.position = origin
	camera.fov = fov
	camera.look_at(target)
	terrain.update_focus(origin)

func weather(elapsed: float, rain: float) -> void:
	var eye := camera.position
	var surface := Layout.surface_height(Vector2(eye.x,eye.z))
	var depth := surface - eye.y
	atmosphere.update_weather(eye,elapsed,rain,true,is_finite(depth) and depth > .035,depth)
	terrain.set_wet(rain)
	terrain.update_water(elapsed,rain,{
		"sun_direction":atmosphere.sun_direction,"moon_direction":atmosphere.moon_direction,
		"sun_energy":atmosphere.sun_energy,"sky_zenith":atmosphere.sky_zenith,
		"sky_horizon":atmosphere.sky_horizon,"sun_color":atmosphere.sun_color,"moon_color":atmosphere.moon_color,
		"cloud_cover":atmosphere.cloud_cover,"twilight":atmosphere.twilight,"evening_weight":atmosphere.evening_weight,
		"underwater":atmosphere.underwater})
	terrain.lake.reflection.render_target_update_mode = SubViewport.UPDATE_ONCE

func toggle_pair(label: String) -> void:
	terrain.lake.plants.hide()
	terrain.lake.reflection.render_target_update_mode = SubViewport.UPDATE_ONCE
	await shot(label+"-before",12)
	terrain.lake.plants.show()
	terrain.lake.reflection.render_target_update_mode = SubViewport.UPDATE_ONCE
	await shot(label+"-after",12)

func wind_pair(label: String) -> void:
	for label_time in [["steady",77.7],["gust",94.5]]:
		var elapsed: float = label_time[1]
		var wind := WindField.sample(elapsed,1.0)
		terrain.lake.plants.set_wind(elapsed,wind,1.0)
		for material in terrain.lake.plants.materials:
			check((material.get_shader_parameter("wind_field") as Vector4).is_equal_approx(wind), "Wind from the room field")
		terrain.lake.reflection.render_target_update_mode = SubViewport.UPDATE_ONCE
		await shot(label+"-"+label_time[0],7)

func shot(name: String, frames: int) -> void:
	for frame in frames:
		await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	check(image != null and image.save_png(out.path_join(name+".png")) == OK, "Screenshot " + name)

func check(ok: bool, message: String) -> void:
	if not ok:
		valid = false
		push_error(message)
