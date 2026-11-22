extends RefCounted

const Ferry = preload("res://lake_ferry.gd")
const Lake = preload("res://lake_layout.gd")
const PlacementWorld = preload("res://placement_world.gd")
const KIND := "camp_rope_bed"
const BEDROLL := "boar_bedding"

static func is_bed(kind: String) -> bool:
	return kind==KIND or kind==BEDROLL

const PORT := "ferry-port"
const STARBOARD := "ferry-starboard"
const HEAL_PER_SECOND := 1.5

static func aboard(id: String) -> bool:
	return id == PORT or id == STARBOARD

static func berth(id: String) -> Vector2:
	return Vector2(0.055, 0.493 if id == PORT else -0.493)

static func socket(room: Dictionary, id: String) -> Dictionary:
	if aboard(id):
		var hull := Ferry.pose(room.data.elapsed,room.data.ferryDepartedAt)
		var at := Ferry.world_point(berth(id),hull)
		return {"point":at,"y":Lake.water_y()-Ferry.WATERLINE+0.633,"yaw":float(hull.yaw)+PI*.5}
	var record: Dictionary = room.data.get("storage",{}).get(id,{})
	if not is_bed(record.get("kind","")) or record.get("mode") != "ground":
		return {}
	var pose := PlacementWorld.pose(record)
	var height:=.075 if record.kind==BEDROLL else .50
	var at := pose * Vector3(0,height,0)
	return {"point":Vector2(at.x,at.z),"y":at.y,"ground":pose.origin.y,"yaw":atan2(-pose.basis.z.x,-pose.basis.z.z)}

static func claimed(room: Dictionary, id: String, except_id := "") -> bool:
	for player: String in room.actors:
		if player != except_id and room.actors[player].get("bed","") == id:
			return true
	for npc: Dictionary in room.data.get("wildPeople",{}).get("people",{}).values():
		if npc.id != except_id and npc.phase in ["captive","companion"] and (npc.get("bed","") == id or npc.get("bedGoal","") == id):
			return true
	return false

static func sleep_player(room: Dictionary, player: String, id: String) -> bool:
	var actor: Dictionary = room.actors[player]
	if not str(actor.get("bed","")).is_empty() or claimed(room,id) or socket(room,id).is_empty():
		return false
	if aboard(id) and (not actor.get("onFerry",false) or not actor.get("crouched",false) or not Ferry.under_canopy(actor.ferryLocal) or actor.ferryLocal.distance_to(berth(id))>1.00):
		return false
	actor.bedExit = Vector3(actor.point.x,actor.y,actor.point.y)
	actor.erase("storageSeat")
	actor.erase("climbing")
	actor.bed = id
	place_player(room,actor)
	return true

static func place_player(room: Dictionary, actor: Dictionary) -> void:
	var rest := socket(room,actor.bed)
	if rest.is_empty():
		wake_player(room,actor)
		return
	actor.point = rest.point
	actor.y = rest.y
	actor.bedYaw = rest.yaw
	actor.vy = 0.0
	actor.vx = 0.0
	actor.vz = 0.0
	actor.swimming = false
	actor.grounded = true
	actor.crouched = false
	if aboard(actor.bed):
		actor.onFerry = true
		actor.ferryLocal = berth(actor.bed)

static func wake_player(room: Dictionary, actor: Dictionary) -> void:
	if aboard(actor.get("bed","")):
		Ferry.place(actor,Vector2(0.055,0),Ferry.pose(room.data.elapsed,room.data.ferryDepartedAt),Lake.water_y())
	elif actor.has("bedExit"):
		var at: Vector3 = actor.bedExit
		actor.point = Vector2(at.x,at.z)
		actor.y = at.y
	actor.bed = ""
	actor.erase("bedExit")

static func nearest_cot(room: Dictionary, at: Vector2, except_id: String) -> String:
	var best := INF
	var result := ""
	for id: String in room.data.get("storage",{}):
		var obj: Dictionary = room.data.storage[id]
		if not is_bed(obj.kind) or obj.mode != "ground":
			continue
		var distance := at.distance_squared_to(Vector2(obj.at[0],obj.at[2]))
		if distance < best and not claimed(room,id,except_id):
			best = distance
			result = id
	return result
