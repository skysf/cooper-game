extends SceneTree

const Lake = preload("res://lake_layout.gd")
const Mines = preload("res://mines_layout.gd")
const MinesScene = preload("res://mines_scene.gd")
const Placement = preload("res://placement.gd")
const PlacementWorld = preload("res://placement_world.gd")
const Rules = preload("res://rules.gd")
const Motion = preload("res://player_motion.gd")
const Mining = preload("res://mining.gd")
const ASSETS := "res://props/mines"

var failures: Array[String] = []
var meshes := {}
var checks := 0
var measurements := {}

func _initialize() -> void:
	_verify.call_deferred()

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func _tree_pose(node: Node3D) -> Transform3D:
	var result := node.transform
	var above := node.get_parent() as Node3D
	while above != null:
		result = above.transform * result
		above = above.get_parent() as Node3D
	return result

func _measure(id: String) -> void:
	var packed := load(ASSETS.path_join(id + ".glb")) as PackedScene
	_check(packed != null, id + " imports as a scene")
	if packed == null:
		return
	var root_model := packed.instantiate() as Node3D
	var instances := root_model.find_children("*", "MeshInstance3D", true, false)
	if root_model is MeshInstance3D:
		instances.push_front(root_model)
	var geometry: Array[Dictionary] = []
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var surfaces := 0
	var textured := 0
	var mapped_roughness := 0
	var triangle_count := 0
	for part: MeshInstance3D in instances:
		var transform := _tree_pose(part)
		for i in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for j in verts.size():
				verts[j] = transform * verts[j]
				lo = lo.min(verts[j])
				hi = hi.max(verts[j])
			if indices.is_empty():
				for j in verts.size():
					indices.append(j)
			geometry.append({"verts":verts, "indices":indices})
			triangle_count += int(indices.size() / 3.0)
			surfaces += 1
			var mat := part.mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null and mat.albedo_texture != null and mat.normal_texture != null:
				textured += 1
				if mat.roughness_texture != null:
					mapped_roughness += 1
	root_model.free()
	meshes[id] = geometry
	measurements[id] = {"size":str(hi-lo), "base":lo.y, "surfaces":surfaces, "textured":textured,
		"triangles":triangle_count}
	if id == "iron_seam":
		_check(triangle_count > 2000 and textured == 1 and surfaces == 1 and mapped_roughness == 1,
			id + " uses one continuous mapped mineral material across the detailed surface")
	elif id in ["coal", "iron_ore"]:
		_check(triangle_count >= 300 and textured == 1 and surfaces == 1 and mapped_roughness == 1,
			id + " imports a continuous color, normal and roughness material")
	else:
		_check(triangle_count > 80 and textured >= 2, id + " includes detailed geometry and mapped materials")
	if id in ["coal", "iron_ore", "iron_ingot"]:
		_check(absf(lo.y) < .00005 and hi.x-lo.x > .12 and hi.x-lo.x < .32, id + " rests on the ground at hand scale")
		var icon := load(ASSETS.path_join("inventory_" + id + ".png")) as Texture2D
		_check(icon != null and icon.get_image().detect_alpha() == Image.ALPHA_BLEND, id + " includes a transparent render")

func _mesh_intersection(id: String, from: Vector3, to: Vector3) -> Variant:
	for surface: Dictionary in meshes.get(id, []):
		var indices: PackedInt32Array = surface.indices
		var verts: PackedVector3Array = surface.verts
		for i in range(0, indices.size(), 3):
			var point: Variant = Geometry3D.segment_intersects_triangle(from,to,verts[indices[i]],verts[indices[i+1]],verts[indices[i+2]])
			if point != null:
				return point
	return null

func _section(floor: Array, z: float) -> Vector3:
	for i in range(1, floor.size()):
		var a: Array = floor[i-1]
		var b: Array = floor[i]
		if z <= float(b[0]):
			var t := clampf((z-float(a[0]))/(float(b[0])-float(a[0])), 0.0, 1.0)
			return Vector3(lerpf(a[2], b[2], t), lerpf(a[1], b[1], t), lerpf(a[3], b[3], t))
	var last: Array = floor.back()
	return Vector3(last[2], last[1], last[3])

func _xz(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)

func _geometry(id: String, entry: Dictionary, solids: Array[Dictionary]) -> void:
	var cave := Mines.pose(id)
	var floor: Array = entry.floor
	var opening := true
	var support := true
	var blocked := true
	var visual_clear := true
	var maximum_error := 0.0
	var maximum_grade := 0.0
	var previous := _section(floor, -.4).y
	for i in range(1,319):
		var z := -.4 + float(i)*.1
		var section := _section(floor,z)
		var local := Vector3(section.x,section.y,z)
		var world := cave * local
		var test_ground := Lake.walk_height(_xz(world),world.y)
		var floor_height := PlacementWorld.floor_height(solids,_xz(world),world.y,test_ground)
		maximum_error = maxf(maximum_error,absf(floor_height-world.y))
		maximum_grade = maxf(maximum_grade,absf(section.y-previous)*10.0)
		previous = section.y
		opening = opening and not PlacementWorld.blocks_player(solids,_xz(world),floor_height)
		support = support and absf(floor_height-world.y) < .038 and world.y >= test_ground - .02
		if i % 8 == 0 and z > .1 and z < 31.6:
			var l: Variant = _mesh_intersection(id,local+Vector3.UP*.22,local-Vector3.UP*.18)
			visual_clear = visual_clear and l != null and absf((l as Vector3).y-local.y)<.042
			visual_clear = visual_clear and _mesh_intersection(id,local+Vector3.UP*.14,local+Vector3.UP*1.70)==null
			var eye := local+Vector3.UP*1.23
			for side: float in [-1.0,1.0]:
				var outward := eye+Vector3.RIGHT*(side*(section.z+.59))
				var hit := Placement.trace(cave*eye,cave*outward,solids)
				blocked = blocked and hit.get("id","") == id
				blocked = blocked and _mesh_intersection(id,eye,outward) != null
			var high := local+Vector3.UP*3.4
			blocked = blocked and Placement.trace(cave*(local+Vector3.UP*1.68),cave*high,solids).get("id","") == id
			blocked = blocked and _mesh_intersection(id,local+Vector3.UP*1.70,high) != null
	_check(opening, id + " adult player corridor is clear through the open entrance")
	_check(support and maximum_grade < .755, id + " floor supports continuous travel down the gallery")
	_check(visual_clear, id + " glTF shows real walkable tread and an empty head cavity")
	_check(blocked, id + " rock walls and roof block matching OBB and visual rays")
	var back := float(floor.back()[0])
	var end := _section(floor,back-.45)
	var before := Vector3(end.x,end.y+1.2,back-.45)
	var after := Vector3(end.x,end.y+1.2,back+.9)
	_check(Placement.trace(cave*before,cave*after,solids).get("id","") == id and _mesh_intersection(id,before,after) != null,
		id + " terminates at a sealed back wall")
	var gather: Vector3 = Mines.vector(entry.gather)
	var aim := Vector3(_section(floor,gather.z).x,gather.y,gather.z)
	_check(Mines.gather(id).distance_to(cave*gather)<.00001 and aim.distance_to(gather)<float(_section(floor,gather.z).z)+.1,
		id + " shared gather target is accessible from the gallery")
	measurements[id]["peak_floor_grade"] = maximum_grade
	measurements[id]["floor_collision_error"] = maximum_error
	measurements[id]["obbs"] = solids.size()

func _motion_contacts(id: String, entry: Dictionary, solids: Array[Dictionary], grid: Dictionary) -> void:
	var cave := Mines.pose(id)
	var local := cave.affine_inverse()
	var side_depth := 5.2
	var section := _section(entry.floor,side_depth)
	var start := cave * Vector3(section.x,section.y,side_depth)
	for direction: float in [-1.0,1.0]:
		var player := Motion.spawn(_xz(start))
		player.y = start.y
		for i in 52:
			Motion.step(player,_xz(cave.basis.x)*direction,0.0,1.0/60.0,grid,{})
		var reached := local * Vector3(player.point.x,player.y,player.point.y)
		_check(direction*(reached.x-section.x) < section.z-.14, id + " horizontal movement stops at the rock wall")
	var frame: Dictionary = entry.frames[0]
	var jump_origin := cave * Mines.vector(frame.at)
	var jumper := Motion.spawn(_xz(jump_origin))
	jumper.y = jump_origin.y
	var apex := jump_origin.y
	for i in 84:
		Motion.step(jumper,Vector2.ZERO,1.0 if i == 0 else 0.0,1.0/60.0,grid,{})
		apex = maxf(apex,float(jumper.y))
	var travel := apex-jump_origin.y
	_check(travel > .24 and travel < .61 and absf(float(jumper.y)-jump_origin.y)<.025,
		"%s jump stops at lintel and returns to floor, measured %.3f m" % [id,travel])
	measurements[id]["jump_apex_m"] = travel
	var gather := Mines.vector(entry.gather)
	var p := _section(entry.floor,gather.z)
	var center := cave * Vector3(lerpf(p.x,gather.x,.35),p.y,gather.z)
	var side := signf(gather.x-p.x)
	var outside := cave * Vector3(p.x+side*(p.z+1.06),p.y,gather.z)
	var focus := Mines.gather(id)
	_check(Mining.reachable({"point":_xz(center),"y":center.y},focus,solids)
		and not Mining.reachable({"point":_xz(outside),"y":outside.y},focus,solids),
		id + " mining is visible from the chamber and blocked through its rock wall")
	var seam_id := id.split("_")[0]+"_seam"
	_check(_mesh_intersection(seam_id,Vector3(-.52,0.0,0.0),Vector3(.24,0.0,0.0)) != null,
		id + " gather point aligns with its exported ore face")

func _walk(id: String, entry: Dictionary, grid: Dictionary, fps: float) -> void:
	var cave := Mines.pose(id)
	var waypoints: Array[Vector2] = []
	for at: Array in entry.route:
		waypoints.append(_xz(Mines.vector(at)))
	var z := .13
	while z <= float(entry.floor.back()[0])-.55:
		var p := _section(entry.floor,z)
		waypoints.append(_xz(cave*Vector3(p.x,p.y,z)))
		z+=.23
	var position: Vector2 = waypoints.pop_front()
	var player := Motion.spawn(position)
	var dt := 1.0 / fps
	var stepped := 0.0
	var travelled := 0
	var stuck := -1
	for i in waypoints.size():
		var waypoint := waypoints[i]
		var attempts := 0
		while position.distance_to(waypoint) > .035 and attempts < 480:
			attempts += 1
			var offset := waypoint-position
			var direction := (offset/(Rules.SPEED*dt)).limit_length()
			Motion.step(player,direction,0.0,dt,grid,{})
			position = player.point
			stepped = maxf(stepped, float(player.y)-Lake.walk_height(position))
		travelled += attempts
		if position.distance_to(waypoint) > .035:
			stuck = i
			break
	var pending := Vector2.ZERO if stuck < 0 else waypoints[stuck]
	_check(stuck < 0 and not player.swimming, "%s traverses at %d Hz without jumping, position %s toward %s at %.3f m" %
		[id,fps,position,pending,float(player.y)])
	measurements[id]["travel_ticks_%d" % fps] = travelled
	measurements[id]["height_above_terrain"] = stepped

func _verify_levels() -> void:
	for id: String in Mines.data:
		var previous_dark := -1.0
		var previous_y := INF
		for z: float in [0.0,3.0,7.0,14.0,23.0,30.0]:
			var at := Lake.Gallery.station(id,z)
			var dark := Lake.Gallery.darkness(at+Vector3.UP*1.65)
			_check(previous_dark < dark and previous_y > at.y,id+" descends and darkens at "+str(z))
			_check(absf(Lake.walk_height(_xz(at),at.y)-at.y)<.01,id+" rests on the underground floor")
			if z>=7:
				var hill := Lake.ground_height(_xz(at))
				_check(hill>at.y+3.0 and absf(Lake.walk_height(_xz(at),hill)-hill)<.01,id+" supports the hillside above the same gallery")
			previous_y = at.y
			previous_dark = dark

func _verify() -> void:
	_check(Mines.data.keys().size() == 2, "Exactly one world source per mineral")
	for id: String in ["coal","iron_ore","iron_ingot","coal_seam","iron_seam","coal_mine","iron_mine"]:
		_measure(id)
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	var grid := Rules.collision_grid(world.obstacles)
	for id: String in Mines.data:
		var entry: Dictionary = Mines.data[id]
		var solids := Mines.solids(id)
		_geometry(id,entry,solids)
		_walk(id,entry,grid,60.0)
		_walk(id,entry,grid,30.0)
		_motion_contacts(id,entry,solids,grid)
	_verify_levels()
	var scene := MinesScene.new()
	root.add_child(scene)
	var lamps := scene.find_children("*", "OmniLight3D", true, false)
	_check(lamps.size() == 8, "Both galleries have an independent graded lamp chain")
	var local_spill := lamps.all(func(lamp: OmniLight3D) -> bool:
		return lamp.light_cull_mask & 1 and not lamp.light_cull_mask & Mines.COAST_SCENERY_LAYER)
	_check(local_spill, "Mine lamps light the galleries and leave coastal scenery batches to daylight")
	for id: String in Mines.data:
		scene.set_remaining(id,0)
		var seam: Node3D = scene._seams.get(id)
		_check(seam != null and not seam.visible, id + " depletion hides the shared seam")
		scene.set_remaining(id,10)
		_check(seam != null and seam.visible, id + " refilling restores seam visibility")
	scene.queue_free()
	print(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements}))
	quit(0 if failures.is_empty() else 1)
