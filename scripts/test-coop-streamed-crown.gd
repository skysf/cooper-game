extends SceneTree

const Terrain = preload("res://terrain.gd")
const Crown = preload("res://vegetation/streamed_crown.gd")
const Rules = preload("res://rules.gd")
const WindField = preload("res://vegetation/wind_field.gd")
const ATLAS = preload("res://pines/pine_needles.png")

var terrain := Terrain.new()
var report := {"checks": [], "errors": [], "files": {}}

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	root.add_child(terrain)
	terrain.set_process(false)
	var spec: Dictionary = terrain.world.streamedCrowns.approach[0]
	var origin := Vector3(spec.at[0], 0.0, spec.at[1])
	terrain.update_focus(origin + Vector3(4.0, 1.67, 0.0))
	check(terrain.far_trees.approach.visible, "Route starts with the existing distant-tree batch")
	check(load_zone("creek", args[0]), "Adjacent creek chunk loads first")
	check(terrain.streamed_crowns.is_empty() and terrain.far_trees.approach.visible, "Adjacent chunk does not spawn the pilot early")
	terrain.update_water(94.5, 1.0, {})
	check(load_zone("approach", args[0]), "Owning approach chunk loads from its new packet")
	if not terrain.streamed_crowns.has("approach"):
		finish(args[1])
		return
	var pilot = terrain.streamed_crowns.approach[0]
	check(pilot.get_parent() == terrain.loaded.approach, "Pilot belongs to its actual loaded chunk")
	check(terrain.streamed_crowns.approach.size() == 1 and not terrain.far_trees.approach.visible,
		"Exactly one tree and the usual distant batch hides")
	check(pilot.global_position.is_equal_approx(origin), "Original world pivot")
	check(pilot.detail[0].visible and not pilot.detail[1].visible, "Near mesh only beside the tree")
	var near_material: ShaderMaterial = pilot.detail_materials[0][0]
	var far_material: ShaderMaterial = pilot.detail_materials[1][0]
	check(near_material.get_shader_parameter("tree_color") == ATLAS and far_material.get_shader_parameter("tree_color") == ATLAS,
		"Both detail models use the same existing needle scan")
	check(near_material.get_shader_parameter("surface_tint") == far_material.get_shader_parameter("surface_tint"),
		"Identical shading tint across the transition")
	check((near_material.get_shader_parameter("wind_field") as Vector4).is_equal_approx(WindField.sample(94.5, 1.0)),
		"Model starts with current room wind even after a late chunk load")
	check(is_equal_approx(float(near_material.get_shader_parameter("wind_time")), 94.5), "Model starts at current wind phase")
	var midpoint := 0.5 * (Crown.NEAR_END + Crown.FAR_START)
	terrain.update_focus(origin + Vector3(midpoint, 1.67, 0.0))
	check(pilot.detail[0].visible and pilot.detail[1].visible, "Two levels available in the overlap")
	var near_clip: Vector2 = near_material.get_shader_parameter("lod_clip")
	var far_clip: Vector2 = far_material.get_shader_parameter("lod_clip")
	check(near_clip.is_equal_approx(Vector2(.5, 1.0)) and far_clip.is_equal_approx(Vector2(0.0, .5)),
		"The two clips form an exact partition")
	terrain.update_focus(origin + Vector3(Crown.FAR_START + 2.0, 1.67, 0.0))
	check(not pilot.detail[0].visible and pilot.detail[1].visible, "Far mesh only before chunk unload")
	var grid := Rules.collision_grid(terrain.world.obstacles)
	var at := Vector2(origin.x, origin.z)
	check(not Rules.free_at(at, grid) and Rules.free_at(at + Vector2(-0.62, 0.0), grid), "Original foot clearance")
	check(pilot.find_children("*", "CollisionObject3D", true, false).is_empty(), "No duplicate physics body")
	var first: WeakRef = weakref(pilot)
	terrain._unload_chunk("approach")
	check(terrain.streamed_crowns.is_empty() and terrain.far_trees.approach.visible, "Unloading restores the distant batch")
	check(terrain.loaded.has("creek"), "Unloading the pilot leaves the adjacent creek resident")
	await process_frame
	await process_frame
	check(first.get_ref() == null, "The unloaded pilot scene is freed")
	terrain.update_focus(origin + Vector3(5.0, 1.67, 0.0))
	check(load_zone("approach", args[0]), "Reload approach from the same generated packet")
	if terrain.streamed_crowns.has("approach"):
		check(terrain.streamed_crowns.approach.size() == 1 and terrain.streamed_crowns.approach[0].detail[0].visible,
			"Reload creates exactly one pilot with the proper current detail")
	else:
		check(false, "Reload creates exactly one pilot with the proper current detail")
	finish(args[1])

func load_zone(id: String, directory: String) -> bool:
	var path := directory.path_join(id + ".glb")
	var raw := FileAccess.get_file_as_bytes(path)
	var chunk: Dictionary = terrain.chunks.filter(func(candidate: Dictionary) -> bool: return candidate.id == id)[0]
	check(raw.size() == int(chunk.bytes), "Packet size matches world manifest for " + id)
	if raw.is_empty() or raw.size() != int(chunk.bytes):
		return false
	report.files[id] = {"bytes": raw.size(), "sha256": FileAccess.get_sha256(path)}
	terrain._parse_chunk(id, raw)
	return terrain.loaded.has(id)

func check(verified: bool, message: String) -> void:
	if verified:
		report.checks.append(message)
	else:
		report.errors.append(message)
		push_error(message)

func finish(log_path: String) -> void:
	var log := FileAccess.open(log_path, FileAccess.WRITE)
	log.store_string(JSON.stringify(report, "  ") + "\n")
	log.close()
	print("STREAMED_CROWN_LOAD ", report.checks.size(), " checks, ", report.errors.size(), " failures")
	quit(0 if report.errors.is_empty() else 4)
