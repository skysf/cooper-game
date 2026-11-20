extends RefCounted

const Placement = preload("res://placement.gd")
const Lake = preload("res://lake_layout.gd")
const Rules = preload("res://rules.gd")
const Survival = preload("res://survival.gd")
const Stones = preload("res://stones.gd")
const MinesLayout = preload("res://mines_layout.gd")
const CABIN_KIT := "res://props/construction/cabin_kit.json"

const REACH := 4.2
const HAND_REACH_Y := 2.05
const CELL_SIZE := 4.0
const PLAYER := AABB(Vector3(-0.28, 0.20, -0.28), Vector3(0.56, 1.45, 0.56))
const RAMP_CLEARANCE := AABB(Vector3(-0.13, 0.20, -0.13), Vector3(0.26, 1.45, 0.26))
const FLAT_FIXTURES := {
	"wicker_basket": [Vector2(0.193, 0.182), 0.452, Vector2(0.091, 0.09), 0],
	"wood_crate": [Vector2(0.413, 0.205), 0.35, Vector2(0.365, 0.161), Placement.TOP],
	"military_crate": [Vector2(0.481, 0.201), 0.360, Vector2(0.427, 0.172), Placement.TOP],
	"wood_barrel": [Vector2(0.316, 0.316), 0.780, Vector2(0.192, 0.192), Placement.TOP],
	"wood_barrel_tall": [Vector2(0.372, 0.372), 0.920, Vector2(0.245, 0.245), Placement.TOP],
	"wood_sign": [Vector2(0.29, 0.046), 1.044, Vector2(0.050, 0.026), 0],
	"rope_ladder": [Vector2(0.220, 0.036), 2.018, Vector2(0.185, 0.018), 0],
	"campfire": [Vector2(0.319, 0.305), 0.381, Vector2(0.206, 0.195), 0],
	"iron_furnace": [Vector2(0.561, 0.515), 1.14, Vector2(0.39,0.35), 0],
	"table_gnome": [Vector2(0.054, 0.057), 0.195, Vector2(0.034, 0.036), 0],
	"table_babushka": [Vector2(0.039, 0.038), 0.155, Vector2(0.023, 0.023), 0],
	"water_jug": [Vector2(0.144, 0.092), 0.248, Vector2(0.050, 0.050), 0],
}

static var _profiles: Dictionary = {}
static var _kit: Dictionary = {}
static var _mine_grid: Dictionary = {}

static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]),float(values[1]),float(values[2]))

static func _cabin_profile(kind: String) -> Dictionary:
	if _kit.is_empty():
		_kit = JSON.parse_string(FileAccess.get_file_as_string(CABIN_KIT))
	var piece: Dictionary = _kit.pieces.get(kind,{})
	if piece.is_empty():
		return {}
	var bounds := AABB(_vector(piece.bounds.position), _vector(piece.bounds.size))
	var parts: Array[Dictionary] = []
	for box: Dictionary in piece.colliders:
		var offset := _vector(box.get("offset",[0,0,0]))
		var rotation := Basis.from_euler(_vector(box.get("rotation",[0,0,0])))
		parts.append(Placement.solid("",AABB(_vector(box.position),_vector(box.size)),Transform3D(rotation,offset),int(box.faces)))
	var feet := PackedVector3Array()
	for foot: Array in piece.feet:
		feet.append(_vector(foot))
	return {"bounds":bounds,"parts":parts,"feet":feet,"center_of_mass":_vector(piece.center_of_mass),
		"anchor":_vector(piece.get("anchor",[0,0,0]))}

static func _box(half: Vector2, height: float, bottom := 0.0) -> AABB:
	return AABB(Vector3(-half.x, bottom, -half.y), Vector3(half.x * 2.0, height, half.y * 2.0))

static func profile(kind: String) -> Dictionary:
	if _profiles.has(kind):
		return _profiles[kind]
	var result: Dictionary = {}
	match kind:
		"wood_table", "wood_chair":
			result = _furniture(kind == "wood_table")
		_:
			if kind.begins_with("cabin_"):
				result = _cabin_profile(kind)
			elif FLAT_FIXTURES.has(kind):
				var shape: Array = FLAT_FIXTURES[kind]
				result = {"bounds":_box(shape[0], shape[1]), "feet":Placement.rectangle_feet(_box(shape[2], 0.0)),
					"faces":shape[3], "align":kind not in ["wood_sign", "rope_ladder", "campfire", "iron_furnace"]}
	_profiles[kind] = result
	return result

static func _furniture(table: bool) -> Dictionary:
	var half := Vector2(0.795, 0.359) if table else Vector2(0.21, 0.230)
	var foot := Vector2(0.697, 0.282) if table else Vector2(0.18, 0.173)
	var top := .79 if table else .455
	var thickness := .052 if table else .090
	var parts: Array[Dictionary] = [Placement.solid("", _box(half if table else Vector2(.20,.197), thickness, top-thickness))]
	for x: float in [-foot.x, foot.x]:
		for z: float in [-foot.y, foot.y]:
			var at := Transform3D(Basis.IDENTITY, Vector3(x,0,z))
			parts.append(Placement.solid("", _box(Vector2(.048,.048) if table else Vector2(.044,.040), top-thickness), at, 0))
	if not table:
		parts.append(Placement.solid("", AABB(Vector3(-.177,.455,.158), Vector3(.354,.438,.072)), Transform3D.IDENTITY, 0))
	return {"bounds":_box(half, top if table else .893), "feet":Placement.rectangle_feet(_box(foot, 0.0)), "parts":parts, "align":true}

static func saved_rotation(value: Variant) -> Quaternion:
	if value is not Array or value.size() != 4:
		return Quaternion(0,0,0,0)
	for component: Variant in value:
		if not Survival.finite_number(component) or absf(float(component)) > 1.01:
			return Quaternion(0,0,0,0)
	var rotation := Quaternion(value[0], value[1], value[2], value[3])
	return rotation.normalized() if absf(rotation.length_squared() - 1.0) < .02 else Quaternion(0,0,0,0)

static func pose(record: Dictionary) -> Transform3D:
	var rotation := saved_rotation(record.get("rotation"))
	var basis := Basis(rotation) if rotation.length_squared() > .9 else Basis(Vector3.UP, float(record.yaw))
	return Transform3D(basis, Stones.unpack(record.at))

static func closest_contact(record: Dictionary, profile_data: Dictionary, hand: Vector3) -> Vector3:
	var nearest := Vector3.INF
	var distance := INF
	for piece: Dictionary in Placement.bodies("", profile_data, pose(record)):
		var piece_pose: Transform3D = piece.pose
		var box: AABB = piece.bounds
		var contact := piece_pose * (piece_pose.affine_inverse() * hand).clamp(box.position, box.end)
		var candidate := hand.distance_squared_to(contact)
		if candidate < distance:
			distance = candidate
			nearest = contact
	return nearest

static func _register(grid: Dictionary, part: Dictionary) -> void:
	var bounds: AABB = part.pose * part.bounds
	var low := Vector2(bounds.position.x, bounds.position.z) / CELL_SIZE
	var high := Vector2(bounds.end.x, bounds.end.z) / CELL_SIZE
	for x in range(floori(low.x),floori(high.x)+1):
		for z in range(floori(low.y),floori(high.y)+1):
			var cell := Vector2i(x,z)
			if not grid.has(cell):
				grid[cell] = []
			grid[cell].append(part)

static func static_grid(world: Dictionary) -> Dictionary:
	var grid := {}
	var index := 0
	for obstacle: Dictionary in world.get("obstacles", []) + Lake.Coast.obstacles:
		var kind: String = obstacle.type
		if kind == "table":
			continue
		var point := Vector2(obstacle.x,obstacle.z)
		var origin := Vector3(point.x,Lake.ground_height(point),point.y)
		var radius := float(obstacle.r)
		var extent := Vector2(radius, float(obstacle.get("depth", radius)))
		var height := 2.38
		var faces := 0
		match kind:
			"rock":
				height = float(obstacle.get("height",radius*.74))
			"bench":
				height = .53
				faces = Placement.TOP
			"tower": height = 6.9
		var basis := Basis(Vector3.UP, float(obstacle.get("yaw",0.0)))
		_register(grid, Placement.solid("world-%d" % index, _box(extent,height), Transform3D(basis,origin),faces))
		index += 1
	if world.has("shelter"):
		var cabin: Dictionary = world.shelter
		var run := float(cabin.width)*.5 + .4
		var rise := 3.56 - 2.04
		for side: float in [-1.0,1.0]:
			var basis := Basis(Vector3.BACK, -side*atan2(rise,run))
			var center := Vector3(float(cabin.x)+side*run*.5,(2.04+3.56)*.5,float(cabin.z))
			_register(grid, Placement.solid("cabin-roof", _box(Vector2(Vector2(run,rise).length()*.5,float(cabin.depth)*.5+.43),.098,-.049),Transform3D(basis,center)))
	for part: Dictionary in MinesLayout.solids():
		_register(grid,part)
	return grid

static func mine_grid() -> Dictionary:
	if _mine_grid.is_empty():
		for part: Dictionary in MinesLayout.solids():
			_register(_mine_grid,part)
	return _mine_grid

static func nearby(grid: Dictionary, records: Dictionary, point: Vector2, radius := REACH + 2.4) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var seen := {}
	var low := Vector2i(((point - Vector2.ONE*radius)/CELL_SIZE).floor())
	var high := Vector2i(((point + Vector2.ONE*radius)/CELL_SIZE).floor())
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1):
			for part: Dictionary in grid.get(Vector2i(x,z), []):
				var key := [part.id, part.pose.origin]
				if not seen.has(key):
					seen[key] = true
					output.append(part)
	for id: String in records:
		var record: Dictionary = records[id]
		if record.mode != "ground" or point.distance_squared_to(Survival.horizontal(record.at)) > radius * radius:
			continue
		var shape := profile(record.kind)
		if not shape.is_empty():
			output.append_array(Placement.bodies(id, shape, pose(record)))
	return output

static func blocks_player(solids: Array[Dictionary], point: Vector2, feet: float) -> bool:
	var occupant := Placement.solid("player",PLAYER,Transform3D(Basis.IDENTITY,Vector3(point.x,feet,point.y)),0)
	for part: Dictionary in solids:
		var body := occupant
		if part.get("walk_surface",false):
			if _feet_above_ramp(part,point,feet):
				continue
			body = Placement.solid("footing",RAMP_CLEARANCE,occupant.pose,0)
		if Placement.overlaps(part,body):
			return true
	return false

static func _feet_above_ramp(part: Dictionary, point: Vector2, feet: float) -> bool:
	if (part.pose as Transform3D).basis.y.y < .72:
		return false
	return feet + .05 >= _ramp_plane_height(part,point)

static func _ramp_plane_height(part: Dictionary, point: Vector2) -> float:
	var ramp: Transform3D = part.pose
	var bounds: AABB = part.bounds
	var normal := ramp.basis.y
	var top := ramp * Vector3(bounds.get_center().x,bounds.end.y,bounds.get_center().z)
	var offset := point - Vector2(top.x,top.z)
	return top.y - Vector2(normal.x,normal.z).dot(offset) / normal.y

static func floor_height(solids: Array[Dictionary], point: Vector2, feet: float, ground: float) -> float:
	if solids.is_empty():
		return ground
	var start := Vector3(point.x,maxf(feet,ground)+.215,point.y)
	var finish := Vector3(point.x,ground-.040,point.y)
	var hit := Placement.trace(start,finish,solids)
	if not hit.is_empty() and hit.support and hit.normal.y > .80:
		return maxf(ground,float(hit.point.y))
	if hit.get("walk_surface",false):
		# A ramp's short end face can sit above a neighboring top at a bend.
		# Footing uses the overlapping tops within step reach.
		for part: Dictionary in solids:
			if not part.get("walk_surface",false) or part.id != hit.id:
				continue
			var ramp: Transform3D = part.pose
			if ramp.basis.y.y <= .80:
				continue
			var height := _ramp_plane_height(part,point)
			if height <= ground or height > start.y + Placement.CONTACT:
				continue
			var local := ramp.affine_inverse() * Vector3(point.x,height,point.y)
			var bounds: AABB = part.bounds
			if local.x >= bounds.position.x and local.x <= bounds.end.x and local.z >= bounds.position.z and local.z <= bounds.end.z:
				ground = height
	return ground

static func preview(grid: Dictionary, records: Dictionary, moving: String, point: Vector2,
		feet: float, eye: float, aim_yaw: float, aim_pitch: float, rotation: float, snap := false,
		building := "") -> Dictionary:
	var record: Dictionary = records.get(moving, {})
	var kind: String = record.get("kind",building)
	var shape := profile(kind)
	if shape.is_empty():
		return {}
	var origin := Vector3(point.x,feet+eye,point.y)
	var direction := -Basis.from_euler(Vector3(aim_pitch,aim_yaw,0.0)).z
	var destination := origin + direction * REACH
	var solids := nearby(grid,records,point)
	var socket := _snap_socket(records,Placement.trace(origin,destination,solids,moving),kind) if snap and kind.begins_with("cabin_") else {}
	var result: Dictionary
	if socket.is_empty():
		result = Placement.solve(origin,destination,rotation,shape,solids,moving)
	else:
		rotation = socket.yaw
		result = Placement.solve(socket.at + Vector3.UP*.09,socket.at - Vector3.UP*.09,rotation,shape,solids,moving)
	result.yaw = rotation
	if result.ok:
		if blocks_player(Placement.bodies(moving,shape,result.pose),point,feet):
			result.ok = false
			result.reason = "player"
	return result

static func _snap_socket(records: Dictionary, hit: Dictionary, kind: String) -> Dictionary:
	if hit.is_empty() or not hit.support:
		return {}
	var support: Dictionary = records.get(hit.id,{})
	var support_kind: String = support.get("kind","")
	if kind in ["cabin_wall","cabin_doorway"] and support_kind == "cabin_floor" and hit.normal.y >= .95:
		var floor_pose := pose(support)
		var on_floor: Vector3 = floor_pose.affine_inverse() * hit.point
		if maxf(absf(on_floor.x),absf(on_floor.z)) < .83:
			return {}
		var distance: float = float(_kit.assembly.wallCenterDistance)*.5
		var top: float = _kit.assembly.floorTop
		if absf(on_floor.x) > absf(on_floor.z):
			var side := signf(on_floor.x)
			return {"at":floor_pose*Vector3(side*distance,top,0),"yaw":float(support.yaw)+side*PI*.5}
		var side := signf(on_floor.z)
		return {"at":floor_pose*Vector3(0,top,side*distance),"yaw":float(support.yaw)+(PI if side < 0 else 0.0)}
	if kind == "cabin_roof" and support_kind in ["cabin_wall","cabin_doorway"]:
		var wall_pose := pose(support)
		var height: float = _kit.assembly.wallHeight
		var wall_hit: Vector3 = wall_pose.affine_inverse()*hit.point
		if wall_hit.y >= height-.48:
			return {"at":wall_pose*(Vector3.UP*height),"yaw":support.yaw}
	return {}
