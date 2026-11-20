extends SceneTree

const Placement = preload("res://placement.gd")
const Lake = preload("res://lake_layout.gd")
const Rules = preload("res://rules.gd")
const Survival = preload("res://survival.gd")

const OBJECT := AABB(Vector3(-0.19, 0.0, -0.17), Vector3(0.38, 0.30, 0.34))
const SHOP := Vector2(8.0, -82.2)
const FEET := [
	Vector3(-0.16, 0.0, -0.14), Vector3(0.16, 0.0, -0.14),
	Vector3(-0.16, 0.0, 0.14), Vector3(0.16, 0.0, 0.14),
]

var tests := 0
var failures := 0

func _initialize() -> void:
	_verify.call_deferred()

func _check(ok: bool, description: String, result := {}) -> void:
	tests += 1
	if not ok:
		failures += 1
		push_error(description + ": " + str(result))

func _drop(at: Vector2, solids: Array[Dictionary] = [], profile := {"bounds": OBJECT},
		from_y := 5.0, yaw := 0.0, moving := "") -> Dictionary:
	return Placement.solve(Vector3(at.x, from_y, at.y), Vector3(at.x, -3.0, at.y),
		yaw, profile, solids, moving)

func _solid(id: String, origin: Vector3, size: Vector3, basis := Basis.IDENTITY,
		faces := Placement.TOP) -> Dictionary:
	return Placement.solid(id, AABB(-size * 0.5, size), Transform3D(basis, origin), faces)

func _verify_terrain() -> void:
	var result := _drop(SHOP)
	_check(result.ok and result.supports == ["terrain"]
		and is_equal_approx(result.pose.origin.y, Lake.walk_height(SHOP)), "flat ground uses real terrain height", result)
	result = _drop(Lake.center())
	_check(not result.ok and result.hit.id == "water", "a dry prop cannot rest on open water", result)
	result = _drop(Rules.MAX_CORNER - Vector2(0.05, 1.0))
	_check(not result.ok, "every foot and the body must stay inside the map", result)
	var wet := Lake.center()
	var platform := _solid("dock-test", Vector3(wet.x, Lake.water_y() + 0.25, wet.y), Vector3(1.3, 0.12, 1.3))
	result = _drop(wet, [platform])
	_check(result.ok and result.supports == ["dock-test"], "a platform above the water supports a dry object", result)

	# A known running section on the actual coastal trail rises toward the ridge.
	var coast := Vector2(-51.4, -66.5)
	var normal := _drop(coast, [], {"bounds": OBJECT, "align": true, "slope_limit": deg_to_rad(42.0)}, 12.0)
	_check(normal.ok and normal.pose.basis.y.y < 0.99 and normal.supports == ["terrain"],
		"an aligned footprint settles on the real coastal slope", normal)
	var level := _drop(coast, [], {"bounds": OBJECT, "slope_limit": deg_to_rad(42.0)}, 12.0)
	_check(not level.ok and level.reason == "unstable", "an upright frame cannot float over the same slope", level)
	var buried := _drop(SHOP, [], {"bounds": OBJECT.grow(0.045), "feet": PackedVector3Array(FEET)})
	_check(not buried.ok and buried.reason == "terrain_overlap", "contact feet do not hide a protrusion into the ground", buried)

func _verify_contacts() -> void:
	var tripod := PackedVector3Array([FEET[0], FEET[1], Vector3(0, 0, 0.14)])
	var result := _drop(SHOP, [], {"bounds": OBJECT, "feet": tripod})
	_check(result.ok, "three feet are enough when they enclose the center of mass", result)
	result = _drop(SHOP, [], {"bounds": OBJECT, "feet": tripod, "center_of_mass": Vector3(0.16, 0.1, 0.11)})
	_check(not result.ok and result.reason == "unstable", "an off-center load tips outside the same contact triangle", result)
	var neighbor := _solid("adjacent", Vector3(SHOP.x + 0.28, 0.15, SHOP.y), Vector3(0.18, 0.3, 0.3))
	result = _drop(SHOP, [neighbor], {"bounds": OBJECT, "feet": PackedVector3Array(FEET)})
	_check(result.ok, "faces may touch without intersecting", result)
	var left := _solid("left", Vector3(SHOP.x - 0.34, 0.7, SHOP.y), Vector3(0.16, 0.2, 0.7))
	var right := _solid("right", Vector3(SHOP.x + 0.34, 0.7, SHOP.y), Vector3(0.16, 0.2, 0.7))
	var board := {"bounds": AABB(Vector3(-0.35, 0.0, -0.19), Vector3(0.7, 0.08, 0.38)),
		"anchor": Vector3(-0.34, 0, 0)}
	result = _drop(SHOP - Vector2(0.34, 0), [right, left], board)
	_check(result.ok and result.supports == ["left", "right"] and absf(result.pose.origin.x - SHOP.x) < 0.001,
		"a panel referenced from one beam can span two physical supports", result)

func _verify_raised() -> void:
	var at := Survival.TABLE_CENTER
	var table := _solid("camp-table", Vector3(at.x, Survival.TABLE_TOP - 0.019, at.y),
		Vector3(1.58, 0.038, 0.72))
	var result := _drop(at, [table])
	_check(result.ok and result.supports == ["camp-table"] and is_equal_approx(result.pose.origin.y, Survival.TABLE_TOP),
		"the existing table dimensions support an elevated object", result)
	result = _drop(at + Vector2(0.69, 0.0), [table])
	_check(not result.ok and result.reason == "unstable", "a table-edge overhang without enough supporting feet is red", result)
	var occupant := _solid("container", Vector3(at.x + 0.24, Survival.TABLE_TOP + 0.25, at.y),
		Vector3(0.22, 0.17, 0.21), Basis(Vector3.UP, 0.45))
	result = _drop(at, [table, occupant])
	_check(not result.ok and result.reason == "occupied", "a second player's overlapping object invalidates a preview", result)
	result = _drop(at, [table, occupant], {"bounds": OBJECT}, 5.0, 0.0, "container")
	_check(result.ok, "the currently moved object does not block its own preview", result)

	var floor_piece := _solid("loft", Vector3(SHOP.x, 2.0, SHOP.y), Vector3(1.1, 0.1, 1.0))
	result = _drop(SHOP, [floor_piece])
	_check(result.ok and result.supports == ["loft"] and absf(result.pose.origin.y - 2.05) < 0.002,
		"the aimed-at loft wins over the lower terrain", result)
	result = _drop(SHOP, [floor_piece], {"bounds": OBJECT}, 1.0)
	_check(result.ok and result.supports == ["terrain"], "the same horizontal point below the loft resolves to the ground", result)
	var ceiling := _solid("beam", Vector3(SHOP.x, 0.26, SHOP.y), Vector3(0.48, 0.07, 0.55))
	result = _drop(SHOP, [ceiling], {"bounds": OBJECT}, 0.19)
	_check(not result.ok and result.reason == "occupied", "a low beam clips the object even with all feet on the ground", result)

	var support := Vector3(SHOP.x, 3.0, SHOP.y)
	var roof := _solid("roof", support, Vector3(1.9, 0.12, 1.7), Basis(Vector3.BACK, -0.28))
	result = _drop(SHOP, [roof], {"bounds": OBJECT, "align": true})
	_check(result.ok and result.supports == ["roof"] and result.pose.basis.y.is_equal_approx(roof.pose.basis.y),
		"an aligned item can rest on a sloping roof panel", result)
	var long := {"bounds": AABB(Vector3(-0.40,0,-0.15), Vector3(0.80,0.2,0.3))}
	var shelf := _solid("shelf", Vector3(SHOP.x, 1.0, SHOP.y), Vector3(1.1, 0.1, 0.42))
	result = _drop(SHOP, [shelf], long)
	_check(result.ok, "long object fits lengthwise on narrow floor piece", result)
	result = _drop(SHOP, [shelf], long, 5.0, PI * 0.5)
	_check(not result.ok and result.reason == "unstable", "rotation updates every contact test", result)

func _verify_wall() -> void:
	var origin := Vector3(SHOP.x, 1.05, SHOP.y)
	var wall := _solid("wall", origin, Vector3(2.0, 2.1, 0.14), Basis.IDENTITY, Placement.SIDES)
	var start := origin + Vector3.BACK * 1.2
	var end := origin - Vector3.BACK * 1.2
	var result := Placement.solve(start, end, 0.0, {"bounds": OBJECT}, [wall])
	_check(not result.ok and result.hit.id == "wall", "the wall can be aimed at but does not balance ordinary furniture", result)
	result = Placement.solve(start, end, 0.0, {"bounds": OBJECT, "mount": true}, [wall])
	_check(result.ok and result.supports == ["wall"] and result.pose.basis.y.is_equal_approx(Vector3.BACK),
		"all mounting contacts can sit flush on the wall", result)
	result = Placement.solve(start + Vector3.RIGHT * 0.89, end + Vector3.RIGHT * 0.89, 0.0,
		{"bounds": OBJECT, "mount": true}, [wall])
	_check(not result.ok and result.reason == "unstable", "mounting anchors cannot hang outside the edge", result)

	var fence := _solid("beam", origin + Vector3.BACK * 0.5, Vector3(0.6, 0.7, 0.08), Basis.IDENTITY, 0)
	result = Placement.solve(start, end, 0.0, {"bounds": OBJECT, "mount": true}, [wall, fence])
	_check(not result.ok and result.hit.id == "beam", "a nearer blocker prevents mounting through it", result)
	result = Placement.solve(start, start + Vector3.UP * 2.0, 0.0, {"bounds": OBJECT}, [wall])
	_check(not result.ok and result.reason == "no_surface", "open air returns a red preview with no supporting surface", result)

func _verify() -> void:
	_verify_terrain()
	_verify_contacts()
	_verify_raised()
	_verify_wall()
	print("COOP_PLACEMENT_CHECKS ", tests, " failures=", failures)
	quit(0 if failures == 0 else 1)
