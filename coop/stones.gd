extends RefCounted

const SPAWNS := {
	"camp-round": Vector2(0.38, -83.86),
	"camp-flat": Vector2(2.72, -83.45),
	"shore-round": Vector2(-9.2, -47.85),
	"shore-flat": Vector2(-9.1, -50.18),
}
const GRIND := Vector2(0.25, -86.25)
const GRIND_HEIGHT := 0.085
const CANVAS := Vector2(3.12, -85.58)
const ROPE := Vector2(2.02, -86.14)
const GRAVITY := Vector3(0.0, -9.81, 0.0)
const REACH := 2.05
const PICKUP_REACH := 2.35

static func flat(id: String) -> bool:
	return id.ends_with("-flat")

static func ground_height(id: String) -> float:
	return 0.019 if flat(id) else 0.038

static func initial() -> Dictionary:
	var stones := {}
	for id: String in SPAWNS:
		var point: Vector2 = SPAWNS[id]
		stones[id] = {"mode": "ground", "at": pack(Vector3(point.x, ground_height(id), point.y)), "edge": 0}
	return stones

static func pack(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func unpack(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func from_save(value: Variant) -> Dictionary:
	var stones := initial()
	if value is not Dictionary:
		return stones
	for id: String in SPAWNS:
		var saved: Variant = value.get(id)
		if saved is not Dictionary or saved.get("mode") not in ["ground", "placed", "submerged"]:
			continue
		var at: Variant = saved.get("at")
		if at is not Array or at.size() != 3:
			continue
		var valid := true
		for axis: Variant in at:
			valid = valid and (axis is float or axis is int) and is_finite(float(axis))
		if valid:
			var edge: Variant = saved.get("edge", 0)
			stones[id] = {"mode": saved.mode, "at": at, "edge": clampi(int(edge), 0, 3) if flat(id) and (edge is int or edge is float) else 0}
	return stones

static func held_by(stones: Dictionary, player: String) -> String:
	for id: String in stones:
		if stones[id].mode == "held" and stones[id].get("holder") == player:
			return id
	return ""

static func flight_position(stone: Dictionary, elapsed: float) -> Vector3:
	var age := maxf(elapsed - float(stone.launch), 0.0)
	return unpack(stone.at) + unpack(stone.velocity) * age + GRAVITY * (0.5 * age * age)

static func context_action(id: String, stone: Dictionary, point: Vector2, line_cut: bool) -> String:
	if id.is_empty():
		return ""
	var out := ""
	var distance := REACH
	if not flat(id):
		return "press" if point.distance_to(CANVAS) <= distance else ""
	if not line_cut and int(stone.edge) > 0 and point.distance_to(ROPE) <= distance:
		distance = point.distance_to(ROPE)
		out = "cut"
	if int(stone.edge) < 3 and point.distance_to(GRIND) <= distance:
		out = "grind"
	return out
