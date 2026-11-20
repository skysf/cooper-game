extends SceneTree
## Run with a minimal copy of the game placement scripts and imported models.
## Baseline meshes go in res://before, and candidate assets retain paths under res://after/coop.

const Placement = preload("res://placement.gd")
const World = preload("res://placement_world.gd")
const Survival = preload("res://survival.gd")

const ASSETS := {
	"wood_table": ["before/camp_table.glb", "after/coop/props/camp_table.glb"],
	"wood_chair": ["before/wood_chair.glb", "after/coop/props/storage/wood_chair.glb"],
}

var failed: Array[String] = []
var checks := 0
var measurements := {}

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, condition: String) -> void:
	checks += 1
	if not ok:
		failed.append(condition)
		push_error(condition)

func _relative(node: Node3D) -> Transform3D:
	var pose := node.transform
	var above := node.get_parent() as Node3D
	while above != null:
		pose = above.transform * pose
		above = above.get_parent() as Node3D
	return pose

func _read(path: String) -> Dictionary:
	var handle := load("res://" + path) as PackedScene
	if handle == null:
		return {}
	var assembly := handle.instantiate() as Node3D
	var meshes := assembly.find_children("*","MeshInstance3D",true,false)
	if assembly is MeshInstance3D:
		meshes.push_front(assembly)
	var geometry: Array[Dictionary] = []
	var bounds: AABB
	var faces := 0
	var scars := 0
	var material_maps := 0
	var leg_vertices := PackedVector3Array()
	for node: MeshInstance3D in meshes:
		var pose := _relative(node)
		for surface in node.mesh.get_surface_count():
			var data := node.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
			var inds: PackedInt32Array = data[Mesh.ARRAY_INDEX]
			var shader := node.mesh.surface_get_material(surface) as StandardMaterial3D
			for i in verts.size():
				verts[i] = pose * verts[i]
				if i == 0 and faces == 0:
					bounds = AABB(verts[0],Vector3.ZERO)
				else:
					bounds = bounds.expand(verts[i])
			if inds.is_empty():
				for i in verts.size():
					inds.append(i)
			geometry.append({"vertices":verts,"indices":inds})
			var triangles := int(inds.size()/3.0)
			faces += triangles
			if shader != null:
				if shader.resource_name.begins_with("Fresh fibers in knife cuts"):
					scars += triangles
				if shader.albedo_texture != null and shader.normal_texture != null:
					material_maps += 1
			for vertex: Vector3 in verts:
				if absf(vertex.y) < .0001 and not leg_vertices.has(vertex):
					leg_vertices.append(vertex)
	var marker := assembly.find_child("ChairSeat",true,false) as Node3D
	var result := {"mesh":geometry,"triangles":faces,"bounds":bounds,"scars":scars,
		"maps":material_maps,"feet":leg_vertices,"marker":_relative(marker).origin if marker!=null else Vector3.INF}
	assembly.free()
	return result

func _cross(meshes: Array, from: Vector3, to: Vector3) -> Variant:
	var closest: Variant = null
	var gap := INF
	for surface: Dictionary in meshes:
		var indices: PackedInt32Array = surface.indices
		var vertices: PackedVector3Array = surface.vertices
		for i in range(0,indices.size(),3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(from,to,vertices[indices[i]],
				vertices[indices[i+1]],vertices[indices[i+2]])
			if hit != null and from.distance_squared_to(hit) < gap:
				gap = from.distance_squared_to(hit)
				closest = hit
	return closest

func _measure_y(meshes: Array, point: Vector2, start: float, finish: float) -> float:
	var hit: Variant = _cross(meshes,Vector3(point.x,start,point.y),Vector3(point.x,finish,point.y))
	return float(hit.y) if hit != null else INF

func _point_distance(source: PackedVector3Array, target: PackedVector3Array) -> float:
	var gap := 0.0
	for sample: Vector3 in source:
		var nearby := INF
		for point: Vector3 in target:
			nearby = minf(nearby,sample.distance_squared_to(point))
		gap = maxf(gap,sqrt(nearby))
	return gap

func _feet(before: Dictionary, after: Dictionary, kind: String) -> void:
	var profile := World.profile(kind)
	var maximum := 0.0
	var ground := Vector3(6.75,.4,-83.8)
	var support := Placement.solid("comparison-slope",AABB(Vector3(-2,-.17,-2),Vector3(4,.17,4)),
		Transform3D(Basis(Vector3.RIGHT,deg_to_rad(4.0)),ground))
	var world_solids: Array[Dictionary] = [support]
	var placement := Placement.solve(ground+Vector3.UP,ground-Vector3.UP,.31,profile,world_solids)
	_check(placement.ok and "comparison-slope" in placement.supports,kind + " fits the published placement profile on the same slope")
	var pose: Transform3D = placement.pose
	for point: Vector3 in profile.feet:
		var reference := _measure_y(before.mesh,Vector2(point.x,point.z),-.065,.06)
		var measured := _measure_y(after.mesh,Vector2(point.x,point.z),-.065,.06)
		maximum = maxf(maximum,absf(measured-reference))
		var at := pose * Vector3(point.x,measured,point.z)
		var height_error: float = absf((support.pose.affine_inverse()*at).y)
		_check(is_finite(reference) and is_finite(measured) and absf(reference) < .0006
			and absf(measured) < .0006 and height_error < .001,kind + " ground contact at " + str(point))
	var geometry_gap := maxf(_point_distance(before.feet,after.feet),_point_distance(after.feet,before.feet))
	_check(not before.feet.is_empty() and not after.feet.is_empty() and geometry_gap < .0001,
		kind + " retains its original foot outline")
	measurements[kind]["biggestFootDeltaM"] = maximum
	measurements[kind]["footOutlineDeltaM"] = geometry_gap
	measurements[kind]["slopeSupport"] = placement.supports
	if kind == "wood_table":
		_provision_support(profile, pose, before, after)

func _provision_support(table_profile: Dictionary, table_pose: Transform3D, before: Dictionary, after: Dictionary) -> void:
	var surface := table_pose * Vector3(-.54,Survival.TABLE_TOP,.108)
	var tabletop := Placement.bodies("comparison-table",table_profile,table_pose)
	var item_bounds := AABB(Vector3(-.048,0,-.032),Vector3(.096,.072,.064))
	var contact := Placement.rectangle_feet(item_bounds)
	var item_profile := {"bounds":item_bounds,"feet":contact,"align":true}
	var up := table_pose.basis.y
	var item := Placement.solve(surface+up*.32,surface-up*.043,.19,item_profile,tabletop)
	var backed: bool = item.ok and "comparison-table" in item.supports
	var to_table := table_pose.affine_inverse()
	for corner: Vector3 in contact:
		var local: Vector3 = to_table * (item.pose * corner)
		var foot := Vector2(local.x, local.z)
		var original := _measure_y(before.mesh,foot,local.y+.02,local.y-.015)
		var current := _measure_y(after.mesh,foot,local.y+.02,local.y-.015)
		backed = backed and absf(original-local.y)<.001 and absf(current-local.y)<.001
	_check(backed,"The same tilted table placement supports a small object over four real mesh contacts")

func _slots(before: Dictionary, after: Dictionary, kind: String) -> void:
	var points: Array[Vector2] = []
	var height := .455
	var joints: Array[Vector2] = []
	if kind=="wood_table":
		for slot: Vector2 in Survival.TABLE_SLOTS + [Survival.JUG]:
			points.append(slot-Survival.TABLE_CENTER)
		height=Survival.TABLE_TOP
		joints.assign([Vector2(.60,-.18),Vector2(.41,0),Vector2(-.38,.18)])
		_check(before.scars == after.scars and after.scars > 50,"Table retains its original knife engraving triangles")
	else:
		for x: float in [-.13,0.0,.13]:
			for z: float in [-.11,.095]:
				points.append(Vector2(x,z))
		_check(before.marker.is_equal_approx(Vector3(0,.455,0)) and before.marker.is_equal_approx(after.marker),
			"ChairSeat marker retains its exact local point")
		joints.assign([Vector2(-.403/6.0,0.04),Vector2(.403/6.0,-.03)])
	var delta := 0.0
	for at: Vector2 in points:
		var old := _measure_y(before.mesh,at,height+.025,height-.045)
		var new := _measure_y(after.mesh,at,height+.025,height-.045)
		delta = maxf(delta,absf(new-old))
		_check(is_finite(old) and is_finite(new) and absf(new-old) < .001 and absf(new-height) < .0015,
			kind + " placement contact at " + str(at))
	for joint: Vector2 in joints:
		var was_open := is_inf(_measure_y(before.mesh,joint,height+.008,height-.033))
		var still_open := is_inf(_measure_y(after.mesh,joint,height+.008,height-.033))
		_check(was_open and still_open,kind + " retains a real board seam at " + str(joint))
	measurements[kind]["biggestSurfaceDeltaM"] = delta

func _run() -> void:
	for kind: String in ASSETS:
		var assets: Array = ASSETS[kind]
		var before := _read(assets[0])
		var after := _read(assets[1])
		_check(not before.is_empty() and not after.is_empty(),kind + " before and after import in Godot")
		if before.is_empty() or after.is_empty():
			continue
		var a: AABB = before.bounds
		var b: AABB = after.bounds
		measurements[kind] = {
			"oldTriangles":before.triangles,"newTriangles":after.triangles,
			"oldAABB":[a.position.x,a.position.y,a.position.z,a.size.x,a.size.y,a.size.z],
			"newAABB":[b.position.x,b.position.y,b.position.z,b.size.x,b.size.y,b.size.z],
			"mappedMaterials":after.maps,"engravingTriangles":after.scars,
		}
		_check(a.position.distance_to(b.position)<.0015 and a.end.distance_to(b.end)<.0015,kind + " preserves its authored envelope")
		_check(after.maps>=2,kind + " has mapped long grain and mapped end grain")
		_feet(before,after,kind)
		_slots(before,after,kind)
	print(JSON.stringify({"checks":checks,"failures":failed,"measurements":measurements}))
	quit(0 if failed.is_empty() else 1)
