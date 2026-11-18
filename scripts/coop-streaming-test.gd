extends SceneTree

# Run the regular terrain streamer against the running local game's release GLBs.
# This moves the streaming focus at fixed checkpoints, independently of the network avatar.
const Terrain = preload("res://terrain.gd")
const ROUNDS := 12
const CAMP := -85.0
const CHECKPOINTS := [-78.0, -70.0, -61.0, -53.0, -45.0, -36.0, -26.0, -17.0,
	-26.0, -36.0, -45.0, -53.0, -61.0, -70.0, -78.0, CAMP]
var terrain := Terrain.new()
var observed := {}
var sample_file: FileAccess
var sample_path := ""
var released := {"nodes": 0, "meshes": 0, "materials": 0}
var peak := 0
var failures: Array[String] = []
var source_url := "http://localhost:4184/coop/zones/"

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		source_url = OS.get_cmdline_user_args()[0]
	# Stream samples to disk so retaining a growing list of sample dictionaries
	# does not itself look like a slow increase in the monitored engine heap.
	sample_path = OS.get_temp_dir().path_join("coop-stream-samples-%s.jsonl" % OS.get_process_id())
	sample_file = FileAccess.open(sample_path, FileAccess.WRITE)
	if sample_file == null:
		printerr("Cannot create a temporary sample log")
		quit(1)
		return
	terrain.configure(source_url)
	root.add_child(terrain)
	if not await settle(CAMP):
		finish()
		return
	record_sample(0)
	for round_number in range(1, ROUNDS + 1):
		for z: float in CHECKPOINTS:
			if not await settle(z):
				finish()
				return
		record_sample(round_number)
	# Wait until queued GLTF nodes and refcounted resources have been released.
	terrain.queue_free()
	await process_frame
	await process_frame
	for key in observed.keys():
		check_release(key)
	finish()

func settle(z: float) -> bool:
	terrain.update_focus(Vector3(1.9, 1.67, z))
	var deadline := Time.get_ticks_msec() + 30000
	var consecutive := 0
	while Time.get_ticks_msec() < deadline:
		await process_frame
		peak = maxi(peak, terrain.resident_count())
		for chunk in terrain.loaded.values():
			var id: int = chunk.get_instance_id()
			if not observed.has(id):
				observed[id] = handles(chunk)
		var ready: bool = terrain.pending.is_empty() and terrain.is_focus_ready()
		for chunk in terrain.chunks:
			var distance := maxf(0, maxf(float(chunk.lo) - z, z - float(chunk.hi)))
			if distance <= terrain.PREFETCH_METRES and not terrain.loaded.has(chunk.id):
				ready = false
			if distance > terrain.KEEP_METRES and terrain.loaded.has(chunk.id):
				ready = false
		consecutive = consecutive + 1 if ready else 0
		if consecutive >= 3:
			var active: Array = terrain.loaded.values().map(func(n): return n.get_instance_id())
			for key in observed.keys():
				if not active.has(key):
					check_release(key)
			return failures.is_empty()
	failures.append("Timed out at z=%s: %s" % [z, terrain.last_error])
	return false

# Store integer ObjectIDs only, so the test itself never extends a resource lifetime.
func handles(chunk: Node) -> Dictionary:
	var nodes: Array = [chunk.get_instance_id()]
	var meshes := {}
	var imported_materials := {}
	for node in chunk.find_children("*", "", true, false):
		nodes.append(node.get_instance_id())
		if node is MeshInstance3D and node.mesh != null:
			meshes[node.mesh.get_instance_id()] = true
			for i in node.mesh.get_surface_count():
				var surface: Material = node.mesh.surface_get_material(i)
				if surface != null and not terrain.materials.values().has(surface):
					imported_materials[surface.get_instance_id()] = true
	return {"nodes": nodes, "meshes": meshes.keys(), "materials": imported_materials.keys()}

func check_release(key: int) -> void:
	for kind in released:
		for object_id in observed[key][kind]:
			if is_instance_id_valid(object_id):
				failures.append("Unloaded chunk %s retains %s ID %s" % [key, kind, object_id])
			else:
				released[kind] += 1
	observed.erase(key)

func sample(round_number: int) -> Dictionary:
	var ids: Array = terrain.loaded.keys()
	ids.sort()
	return {
		"round": round_number, "at": "camp", "resident": ids,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphanNodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"staticMemoryBytes": int(Performance.get_monitor(Performance.MEMORY_STATIC))
	}

func record_sample(round_number: int) -> void:
	sample_file.store_line(JSON.stringify(sample(round_number)))

func finish() -> void:
	sample_file.close()
	var observations: Array = []
	for line in FileAccess.get_file_as_string(sample_path).split("\n", false):
		observations.append(JSON.parse_string(line))
	DirAccess.remove_absolute(sample_path)
	var report := {
		"mode": "headless Godot editor, native HTTPRequest, single terrain instance; no browser/GPU memory measurement",
		"utc": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info().string, "url": source_url, "requestedRounds": ROUNDS,
		"routeZPerRound": CHECKPOINTS, "peakResident": peak,
		"observations": observations, "releasedObjectIDs": released, "failures": failures
	}
	var path := ProjectSettings.globalize_path("res://../evidence/coop-streaming.json")
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		printerr("Cannot write ", path)
		quit(1)
		return
	output.store_string(JSON.stringify(report, "  ") + "\n")
	output.close()
	print("Completed ", observations.size()-1, "/", ROUNDS, " rounds, peak resident ", peak, ", released ", released)
	if not failures.is_empty():
		printerr(failures)
	quit(0 if failures.is_empty() and observations.size() == ROUNDS + 1 else 1)
