extends SceneTree

const Placement = preload("res://placement.gd")
const Lake = preload("res://lake_layout.gd")
const DIRECTORY := "res://props/construction"

var checks: Array[Dictionary] = []
var counts := {}
var geometry := {}
var profiles := {}

func _initialize() -> void:
	_verify.call_deferred()

func _check(ok: bool, title: String, detail := "") -> void:
	checks.append({"name":title,"ok":ok})
	if not ok:
		push_error(title + ": " + detail)

func _v(k: Array) -> Vector3:
	return Vector3(float(k[0]),float(k[1]),float(k[2]))

func _bounds(shape: Dictionary) -> AABB:
	return AABB(_v(shape.position),_v(shape.size))

func _profile(piece: Dictionary) -> Dictionary:
	var parts: Array[Dictionary] = []
	for part: Dictionary in piece.colliders:
		var at := _v(part.get("offset",[0,0,0]))
		var rotation := Basis.from_euler(_v(part.get("rotation",[0,0,0])))
		parts.append(Placement.solid("",_bounds(part),Transform3D(rotation,at),int(part.faces)))
	var feet := PackedVector3Array()
	for foot: Array in piece.feet:
		feet.append(_v(foot))
	var result := {"bounds":_bounds(piece.bounds),"parts":parts,"feet":feet,"center_of_mass":_v(piece.center_of_mass)}
	if piece.has("anchor"):
		result.anchor = _v(piece.anchor)
	return result

func _pose(node: Node3D) -> Transform3D:
	var transform := node.transform
	var parent := node.get_parent() as Node3D
	while parent != null:
		transform = parent.transform * transform
		parent = parent.get_parent() as Node3D
	return transform

func _parts_from_runtime(kind: String, profile: Dictionary) -> void:
	var resource := load(DIRECTORY.path_join(kind+".glb")) as PackedScene
	_check(resource != null,kind + " imported by Godot's resource loader")
	if resource == null:
		return
	var tree := resource.instantiate() as Node3D
	var meshes := tree.find_children("*","MeshInstance3D",true,false)
	if tree is MeshInstance3D:
		meshes.push_front(tree)
	var lo := Vector3(INF,INF,INF)
	var hi := -lo
	var surfaces: Array[Dictionary] = []
	var triangles := 0
	var mapped := 0
	for mesh: MeshInstance3D in meshes:
		var transform := _pose(mesh)
		for i in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for j in verts.size():
				verts[j] = transform * verts[j]
				lo = lo.min(verts[j])
				hi = hi.max(verts[j])
			if indices.is_empty():
				for j in verts.size():
					indices.append(j)
			surfaces.append({"verts":verts,"indices":indices})
			triangles += int(indices.size()/3.0)
			var mat := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null and mat.albedo_texture != null and mat.normal_texture != null and mat.roughness_texture != null:
				mapped += 1
	tree.free()
	var expected: AABB = profile.bounds
	geometry[kind] = surfaces
	counts[kind] = {"triangles":triangles,"surfaces":surfaces.size(),"mapped_surfaces":mapped,
		"min":[lo.x,lo.y,lo.z],"dimensions":[hi.x-lo.x,hi.y-lo.y,hi.z-lo.z]}
	_check(not surfaces.is_empty() and (hi-lo).distance_to(expected.size) < .00005 and lo.distance_to(expected.position) < .00005
		and absf(lo.y) < .00005,kind + " actual min, max and support origin agree with JSON",str([lo,hi]))
	_check(mapped == surfaces.size() and mapped > 0,kind + " all surfaces retain color, tangent normal and roughness maps")
	var supported := true
	for foot: Vector3 in profile.feet:
		if not _cross(kind,foot - Vector3.UP*.009,foot + Vector3.UP*.019):
			supported = false
	_check(supported,kind + " declared feet touch its actual exported underside")

func _cross(kind: String, start: Vector3, end: Vector3) -> bool:
	for surface: Dictionary in geometry[kind]:
		var indices: PackedInt32Array = surface.indices
		var verts: PackedVector3Array = surface.verts
		for j in range(0,indices.size(),3):
			if Geometry3D.segment_intersects_triangle(start,end,verts[indices[j]],verts[indices[j+1]],verts[indices[j+2]]) != null:
				return true
	return false

func _door(clear: Array) -> void:
	var open := true
	var half: float = float(clear[0])*.5
	for x: float in [-half+.017, -.29,0.0,.29,half-.017]:
		for height: float in [.035,.55,1.15,1.67,float(clear[1])-.023]:
			if _cross("cabin_doorway",Vector3(x,height,-.41),Vector3(x,height,.41)):
				open = false
	_check(open,"exported doorway is physically open across its clear span and a player-width path")
	_check(_cross("cabin_doorway",Vector3(0,2.14,-.41),Vector3(0,2.14,.41))
		and _cross("cabin_doorway",Vector3(.69,1.30,-.41),Vector3(.69,1.30,.41)),
		"door lintel and log jambs still collide")

func _assembly(layout: Dictionary) -> void:
	var base := Vector3(8.0,Lake.walk_height(Vector2(8.0,-82.2)),-82.2)
	var scene: Array[Dictionary] = []
	var foundation := Placement.solve(base+Vector3.UP*1.4,base-Vector3.UP*.24,0.0,profiles.cabin_floor,scene)
	_check(foundation.ok,"actual floor feet support the first module on game terrain",str(foundation))
	if not foundation.ok:
		return
	scene.append_array(Placement.bodies("floor",profiles.cabin_floor,foundation.pose))
	for index in layout.walls.size():
		var entry: Dictionary = layout.walls[index]
		var at := base + _v(entry.at)
		var profile: Dictionary = profiles[entry.kind]
		var answer := Placement.solve(at + Vector3.UP*.86, at - Vector3.UP*.11, float(entry.yaw),profile,scene)
		_check(answer.ok and answer.supports.has("floor"),"wall %d settles on deck with the neighboring log ends" % (index+1),str(answer))
		if not answer.ok:
			return
		scene.append_array(Placement.bodies("wall-%d" % index,profile,answer.pose))
	var roof: Dictionary = profiles.cabin_roof
	var anchor: Vector3 = roof.anchor
	var at := base + _v(layout.roofAt) + anchor
	var start := at + Vector3.UP*.95
	var finish := at - Vector3.UP*.11
	var preview := Placement.solve(start,finish,0.0,roof,scene)
	_check(preview.ok and preview.supports.has("wall-0") and preview.supports.has("wall-2")
		and (preview.pose as Transform3D).origin.distance_to(base+_v(layout.roofAt)) < .00005,
		"roof rests on both same-height rails at the authored anchor",str(preview))
	var one_wall: Array[Dictionary] = scene.filter(func(shape: Dictionary) -> bool: return shape.id != "wall-2")
	var unsupported := Placement.solve(start,finish,0.0,roof,one_wall)
	_check(not unsupported.ok and unsupported.reason == "unstable","missing opposite wall makes the same roof placement unstable",str(unsupported))
	if preview.ok:
		scene.append_array(Placement.bodies("roof",roof,preview.pose))
		var pose: Transform3D = preview.pose
		var aim := pose.origin + Vector3(0,1.36,.72)
		var surface := Placement.solve(aim,aim-Vector3.UP*.94,0,
			{"bounds":AABB(Vector3(-.11,0,-.12),Vector3(.22,.3,.24)),"align":true,"slope_limit":deg_to_rad(33.0)},scene)
		_check(surface.ok and surface.supports.has("roof"),"rated object can rest on the visible pitched roof",str(surface))

func _verify() -> void:
	var kit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY.path_join("cabin_kit.json")))
	for kind: String in kit.pieces:
		var profile := _profile(kit.pieces[kind])
		profiles[kind] = profile
		_parts_from_runtime(kind,profile)
	if geometry.has("cabin_doorway"):
		_door(kit.assembly.doorClear)
	if geometry.size() == kit.pieces.size():
		_assembly(kit.assembly)
	var failed := checks.filter(func(entry: Dictionary) -> bool: return not entry.ok).size()
	var report := {"validation":"cabin-kit Godot import and compound placement","checks":checks,"assets":counts,"failures":failed}
	if OS.get_cmdline_user_args().size() == 1:
		var file := FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  ") + "\n")
		file.close()
	print("COOP_CABIN_KIT ", checks.size(), " failures=", failed)
	quit(0 if failed == 0 else 1)
