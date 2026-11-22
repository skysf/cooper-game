extends RefCounted

const PlacementWorld = preload("res://placement_world.gd")
const Placement = preload("res://placement.gd")
const Lake = preload("res://lake_layout.gd")
const Rules = preload("res://rules.gd")

const STEP := 0.215
const SAMPLE := 0.12
const PATH_CELL := 0.25
const PATH_MARGIN := 2.15
const PATH_RADIUS := 7.0
const PAD := 0.49

var cells: Dictionary = {}
var signatures: Dictionary = {}
var revision := 0
var sampled_at := -INF

## Each room owns its fixture index. The static terrain navigator remains shared.
static func for_room(room: Dictionary) -> RefCounted:
	if not room.has("companion_footing"):
		room.companion_footing = new()
	var footing: RefCounted = room.companion_footing
	footing.sync(room.data.get("storage",{}),float(room.data.get("elapsed",0.0)))
	return footing

func sync(records: Dictionary, elapsed: float) -> void:
	if elapsed == sampled_at:
		return
	sampled_at = elapsed
	var active := {}
	for id: String in records:
		var item: Dictionary = records[id]
		if item.mode == "ground" and not PlacementWorld.profile(item.kind).is_empty():
			active[id] = [item.kind,item.at.duplicate(),item.yaw,item.get("rotation",[]).duplicate()]
	if active == signatures:
		return
	signatures = active
	revision += 1
	cells.clear()
	for id: String in signatures:
		var record: Dictionary = records[id]
		var profile := PlacementWorld.profile(record.kind)
		var pose := PlacementWorld.pose(record)
		var deck: bool = record.kind == "cabin_floor" and pose.basis.y.y >= 0.80
		var deck_center := pose * Vector3(0.0,profile.bounds.end.y,0.0) if deck else Vector3.ZERO
		for part: Dictionary in Placement.bodies(id,profile,pose):
			part.world_bounds = part.pose * part.bounds
			part.inverse = part.pose.affine_inverse()
			part.deck = deck
			part.top = deck_center
			part.normal = pose.basis.y
			part.surface = deck and (int(part.faces) & Placement.TOP) != 0
			if part.surface:
				var local_top := Vector3(part.bounds.get_center().x,part.bounds.end.y,part.bounds.get_center().z)
				var center: Vector3 = part.pose * local_top
				var normal: Vector3 = part.pose.basis.y
				part.slope = -Vector2(normal.x,normal.z)/normal.y
				part.plane_y = center.y-Vector2(center.x,center.z).dot(part.slope)
			_register(part)

func _register(part: Dictionary) -> void:
	var bounds: AABB = part.world_bounds
	var low := _cell(Vector2(bounds.position.x-PAD,bounds.position.z-PAD))
	var high := _cell(Vector2(bounds.end.x+PAD,bounds.end.z+PAD))
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1):
			var index := Vector2i(x,z)
			if not cells.has(index):
				cells[index] = []
			cells[index].append(part)

static func _cell(point: Vector2) -> Vector2i:
	return Vector2i((point / PlacementWorld.CELL_SIZE).floor())

func near(point: Vector2) -> bool:
	return cells.has(_cell(point))

func height(point: Vector2, feet: float) -> float:
	return _height(point,feet,Lake.walk_height(point,feet),cells.get(_cell(point),[]))

func _height(point: Vector2, feet: float, ground: float, parts: Array) -> float:
	var top := ground
	var reach := maxf(feet,ground)+STEP
	for part: Dictionary in parts:
		if not part.surface:
			continue
		var world_bounds: AABB = part.world_bounds
		if point.x < world_bounds.position.x or point.x > world_bounds.end.x \
				or point.y < world_bounds.position.z or point.y > world_bounds.end.z:
			continue
		var level := float(part.plane_y)+point.dot(part.slope)
		if level <= top or level > reach:
			continue
		var local: Vector3 = part.inverse * Vector3(point.x,level,point.y)
		var bounds: AABB = part.bounds
		if local.x >= bounds.position.x and local.x <= bounds.end.x and local.z >= bounds.position.z and local.z <= bounds.end.z:
			top = level
	return top

func _blocks(point: Vector2, feet: float, entering_from: float, body: Vector2, parts: Array, ground: float) -> bool:
	var radius := body.x
	var waist := feet+0.045
	var head := feet+body.y
	for part: Dictionary in parts:
		var bounds: AABB = part.world_bounds
		if bounds.end.y <= waist or bounds.position.y >= head or point.x+radius <= bounds.position.x \
				or point.x-radius >= bounds.end.x or point.y+radius <= bounds.position.z or point.y-radius >= bounds.end.z:
			continue
		if part.deck:
			var offset := Vector2(point.x-part.top.x,point.y-part.top.z)
			var top: float = part.top.y - Vector2(part.normal.x,part.normal.z).dot(offset)/float(part.normal.y)
			if top <= maxf(entering_from,ground)+STEP+0.003:
				continue
		if part.pose.basis.y.y >= 0.9999:
			var at: Vector3 = part.inverse * Vector3(point.x,feet,point.y)
			var edge := at.clamp(part.bounds.position,part.bounds.end)
			if Vector2(at.x-edge.x,at.z-edge.z).length_squared() < radius*radius:
				return true
		else:
			var box := AABB(Vector3(-radius,0.045,-radius),Vector3(radius*2,body.y-0.045,radius*2))
			var occupant := Placement.solid("agent",box,Transform3D(Basis.IDENTITY,Vector3(point.x,feet,point.y)),0)
			if Placement.overlaps(part,occupant):
				return true
	return false

func clear(at: Vector2, goal: Vector2, feet: float, body: Vector2) -> bool:
	if cells.is_empty():
		return true
	var count := maxi(1,ceili(at.distance_to(goal) / SAMPLE))
	var last_cell := Vector2i.MAX
	var parts: Array = []
	var skipped := false
	for i in range(1,count+1):
		var point := at.lerp(goal,float(i)/count)
		var cell := _cell(point)
		if cell != last_cell:
			last_cell = cell
			parts = cells.get(cell,[])
		if parts.is_empty():
			skipped = true
			continue
		var ground := Lake.walk_height(point,feet)
		if skipped:
			feet = ground
			skipped = false
		var y := _height(point,feet,ground,parts)
		if _blocks(point,y,feet,body,parts,ground):
			return false
		feet = y
	return true

func move(at: Vector2, direction: Vector2, delta: float, grid: Dictionary, speed: float,
		feet: float, body: Vector2) -> Vector3:
	var motion := direction.limit_length()*speed*clampf(delta,0.0,0.1)
	if not near(at) and not near(at+motion):
		var next := Rules.move(at,direction,delta,grid,false,speed)
		return Vector3(next.x,Lake.walk_height(next,feet),next.y)
	var count := maxi(1,ceili(motion.length()/SAMPLE))
	for i in count:
		var next := (at+motion/count).clamp(Rules.MIN_CORNER,Rules.MAX_CORNER)
		for axis in 2:
			var candidate := at
			candidate[axis] = next[axis]
			var on_fixture := feet > Lake.walk_height(at,feet)+0.03
			if candidate.is_equal_approx(at) or not Rules.free_at(candidate,grid) or not Lake.Coast.can_step(at,candidate,feet if on_fixture else -INF):
				continue
			var ground := Lake.walk_height(candidate,feet)
			var parts: Array = cells.get(_cell(candidate),[])
			var y := _height(candidate,feet,ground,parts)
			if not _blocks(candidate,y,feet,body,parts,ground):
				at = candidate
				feet = y
	return Vector3(at.x,feet,at.y)

func waypoint(at: Vector2, preferred: Vector2, goal: Vector2, route: Dictionary,
		grid: Dictionary, feet: float, body: Vector2, elapsed: float) -> Vector2:
	if cells.is_empty() or clear(at,preferred,feet,body):
		return preferred
	var needs_retry: bool = int(route.get("fixtureIndex",0)) >= route.get("fixturePath",PackedVector2Array()).size()
	if route.get("fixtureRevision",-1) != revision or (needs_retry and elapsed >= float(route.get("fixtureRefresh",0.0))) \
			or goal.distance_squared_to(route.get("fixtureGoal",Vector2.INF)) > 0.5*0.5:
		route.fixturePath = _path(at,goal,grid,feet,body)
		route.fixtureRevision = revision
		route.fixtureRefresh = elapsed+0.75
		route.fixtureGoal = goal
		route.fixtureIndex = 0
	var path: PackedVector2Array = route.fixturePath
	var index: int = route.fixtureIndex
	while index < path.size() and at.distance_squared_to(path[index]) < 0.12*0.12:
		index += 1
	while index+1 < path.size() and _clear_terrain(at,path[index+1],grid) and clear(at,path[index+1],feet,body):
		index += 1
	route.fixtureIndex = index
	if index < path.size() and clear(at,path[index],feet,body):
		return path[index]
	route.fixtureIndex = path.size()
	return at

func _path(at: Vector2, goal: Vector2, grid: Dictionary, feet: float, body: Vector2) -> PackedVector2Array:
	var destination := at + (goal-at).limit_length(PATH_RADIUS)
	var margin := Vector2.ONE*PATH_MARGIN
	var lower := Vector2i(((at.min(destination)-margin)/PATH_CELL).floor())
	var upper := Vector2i(((at.max(destination)+margin)/PATH_CELL).ceil())
	var navigation := AStarGrid2D.new()
	navigation.region = Rect2i(lower,upper-lower+Vector2i.ONE)
	navigation.cell_size = Vector2.ONE*PATH_CELL
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for x in range(lower.x,upper.x+1):
		for z in range(lower.y,upper.y+1):
			var cell := Vector2i(x,z)
			var point := Vector2(cell)*PATH_CELL
			if point != point.clamp(Rules.MIN_CORNER,Rules.MAX_CORNER) or not Rules.free_at(point,grid):
				navigation.set_point_solid(cell)
				continue
			var parts: Array = cells.get(_cell(point),[])
			if not parts.is_empty():
				var ground := Lake.walk_height(point,feet)
				if _blocks(point,_height(point,feet,ground,parts),feet,body,parts,ground):
					navigation.set_point_solid(cell)
	var start := _nearest(at,navigation,grid,feet,body,true)
	var finish := _nearest(destination,navigation,grid,feet,body,false)
	if navigation.is_in_boundsv(start) and navigation.is_in_boundsv(finish):
		return navigation.get_point_path(start,finish,true)
	return PackedVector2Array()

func _nearest(at: Vector2, navigation: AStarGrid2D, grid: Dictionary, feet: float, body: Vector2, reachable: bool) -> Vector2i:
	var center := Vector2i((at/PATH_CELL).round())
	var nearest := navigation.region.end
	var best := INF
	for x in range(center.x-2,center.x+3):
		for z in range(center.y-2,center.y+3):
			var cell := Vector2i(x,z)
			var point := Vector2(cell)*PATH_CELL
			var distance := at.distance_squared_to(point)
			if distance < best and navigation.is_in_boundsv(cell) and not navigation.is_point_solid(cell) \
					and (not reachable or (_clear_terrain(at,point,grid) and clear(at,point,feet,body))):
				nearest = cell
				best = distance
	return nearest

func _clear_terrain(at: Vector2, goal: Vector2, grid: Dictionary) -> bool:
	var count := maxi(1,ceili(at.distance_to(goal)/SAMPLE))
	var last := at
	for i in range(1,count+1):
		var next := at.lerp(goal,float(i)/count)
		if not Rules.free_at(next,grid) or not Lake.Coast.can_step(last,next):
			return false
		last = next
	return true

static func floor_transition(current: Vector3, target: Vector3) -> bool:
	return absf(current.y-target.y) > 0.115 and (absf(current.y-Lake.walk_height(Vector2(current.x,current.z))) > 0.10 \
		or absf(target.y-Lake.walk_height(Vector2(target.x,target.z))) > 0.10)
