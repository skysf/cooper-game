extends RefCounted

# Each prototype is indexed once. Clients and the room can query the actual top of
# its final triangles before the streamed visual pack arrives.
const CELL := 5.0
const FACE_CELL := 0.38
const STEP := 0.23
const FOOTPRINT := [Vector2.ZERO, Vector2(.27,0), Vector2(-.27,0), Vector2(0,.27), Vector2(0,-.27),
	Vector2(.19,.19), Vector2(-.19,.19), Vector2(.19,-.19), Vector2(-.19,-.19)]
static var faces := FileAccess.get_file_as_bytes("res://east/rock_faces.bin").to_vector3_array()
static var profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://east/rock_profiles.json"))
static var instances := {}

static func _static_init() -> void:
	for shape: Dictionary in profiles.values():
		var tiles := {}
		for index in range(int(shape.first), int(shape.first) + 3 * int(shape.triangles), 3):
			var a := faces[index]
			var b := faces[index+1]
			var c := faces[index+2]
			var low := a.min(b).min(c) / FACE_CELL
			var high := a.max(b).max(c) / FACE_CELL
			for x in range(floori(low.x), floori(high.x)+1):
				for z in range(floori(low.z), floori(high.z)+1):
					var cell := Vector2i(x,z)
					if not tiles.has(cell):
						tiles[cell] = []
					tiles[cell].append(index)
		shape.tiles = tiles
	var obstacles: Array = JSON.parse_string(FileAccess.get_file_as_string("res://east/obstacles.json"))
	for row: Dictionary in obstacles:
		if not row.has("profile"):
			continue
		var shape: Dictionary = profiles[row.profile]
		var pose := Transform2D(-float(row.yaw),Vector2(row.x,row.z)).scaled_local(Vector2.ONE*float(row.scale))
		var low := Vector2(shape.min[0],shape.min[2])
		var high := Vector2(shape.max[0],shape.max[2])
		var bounds := (pose * Rect2(low,high-low)).grow(.30)
		var record := {"inverse":pose.affine_inverse(), "scale":row.scale, "base":row.base, "tiles":shape.tiles}
		for x in range(floori(bounds.position.x/CELL),floori(bounds.end.x/CELL)+1):
			for z in range(floori(bounds.position.y/CELL),floori(bounds.end.y/CELL)+1):
				var cell := Vector2i(x,z)
				if not instances.has(cell):
					instances[cell] = []
				instances[cell].append(record)

static func top(at: Vector2) -> float:
	var result := -INF
	var cell := Vector2i((at/CELL).floor())
	if not instances.has(cell):
		return result
	for rock: Dictionary in instances[cell]:
		var p: Vector2 = rock.inverse * at
		var tile := Vector2i((p/FACE_CELL).floor())
		if not rock.tiles.has(tile):
			continue
		for i: int in rock.tiles[tile]:
			var a := faces[i]
			var b := faces[i+1]-a
			var c := faces[i+2]-a
			var dx := p.x-a.x
			var dz := p.y-a.z
			var det := b.x*c.z-b.z*c.x
			var u := (dx*c.z-dz*c.x)/det
			var v := (b.x*dz-b.z*dx)/det
			if u>=-.00001 and v>=-.00001 and u+v<=1.00001:
				result = maxf(result, float(rock.base)+(a.y+u*b.y+v*c.y)*float(rock.scale))
	return result

static func clears(at: Vector2, feet: float, from := Vector2.INF) -> bool:
	if not instances.has(Vector2i((at/CELL).floor())):
		return true
	for offset: Vector2 in FOOTPRINT:
		var ledge := top(at+offset)
		if ledge > feet+STEP:
			# Feet follow the surface under the centre. A downhill or tangential step
			# can leave a steep edge that was already beside the player's shoulder.
			if from.is_finite() and ledge <= top(from+offset)+.002:
				continue
			return false
	return true
