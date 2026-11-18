extends SceneTree

# Run with Godot --headless --path godot --script ../scripts/check-godot.gd
func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	var forest = load("res://main.tscn").instantiate()
	root.add_child(forest)
	await process_frame
	var cfg: Dictionary = forest.config
	var first_rock: Dictionary = {}
	for obstacle in cfg.obstacles:
		if obstacle.type == "rock":
			first_rock = obstacle
			break
	if first_rock.is_empty():
		push_error("Scene contains no rock collider")
		quit(1)
		return
	var center := Vector2(first_rock.x, first_rock.z)
	var clearance: float = first_rock.r + cfg.player.radius
	var start := center + Vector2(0, clearance + 0.3)
	var position := start
	for step in 50:
		position = forest._slide(position, Vector2(0, -0.1))
	var storm: Dictionary = cfg.weather.storm
	forest._weather_blend(1, storm.wetRoad, storm.wetRock, storm.darken)
	var materials := {}
	for entry in forest.weather_materials:
		materials[entry.kind] = entry.surface.roughness
	var projection: Projection = forest.camera.get_camera_projection()
	var horizontal_fov := rad_to_deg(2 * atan(1.0 / projection.x.x))
	var colored_materials := 0
	var material_count := 0
	for mesh in forest.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var mat = mesh.get_active_material(surface)
			if mat is BaseMaterial3D:
				material_count += 1
				if mat.vertex_color_use_as_albedo:
					colored_materials += 1
	var valid := (
		colored_materials == material_count and material_count >= 2 and
		materials.has("rock") and materials.has("mud")
		and is_equal_approx(materials.mud, storm.wetRoad)
		and is_equal_approx(materials.rock, storm.wetRock)
		and is_equal_approx(horizontal_fov, cfg.render.horizontalFov)
		and is_equal_approx(forest.camera.position.y, cfg.player.eye)
		and position.distance_to(center) >= clearance - 0.0001
		and position.distance_to(start) > 0.01
		and bool(forest.rain.visible) and root.mesh_lod_threshold == 0
	)
	var result := {
		"ok": valid, "mode": "headless logic and import",
		"horizontalFov": horizontal_fov, "eyeHeight": forest.camera.position.y,
		"stormRoughness": materials, "rainVisible": forest.rain.visible,
		"rockClearanceMeasured": position.distance_to(center), "rockClearanceRequired": clearance,
		"automaticLodThreshold": root.mesh_lod_threshold, "materialsUsingVertexColor": colored_materials
	}
	print("GODOT_CHECK ", JSON.stringify(result))
	quit(0 if valid else 1)
