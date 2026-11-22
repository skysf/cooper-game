extends RefCounted

# Vertical stone intervals from the displayed GLB. A column can have open air
# between the foot and the hand, so walking and sight queries keep both bounds.
const STEP_UP := .23
const EMPTY := 32767
const HEADER := 24
const FOOTPRINT := [Vector2.ZERO, Vector2(.27,0), Vector2(-.27,0), Vector2(0,.27),
	Vector2(0,-.27), Vector2(.19,.19), Vector2(.19,-.19), Vector2(-.19,.19), Vector2(-.19,-.19)]

var pose: Transform2D
var inverse: Transform2D
var yaw: float
var sole_y: float
var landing: Vector2
var bounds: Rect2
var _data := FileAccess.get_file_as_bytes("res://coast/buddha_contact.bin")
var _size := Vector2i(_data.decode_s32(0), _data.decode_s32(4))
var _layers := _data.decode_s32(8)
var _spacing := _data.decode_s32(12) * .001
var _origin := Vector2(_data.decode_s32(16), _data.decode_s32(20)) * .001

func _init(site: Dictionary) -> void:
	yaw = deg_to_rad(float(site.yawDegrees))
	sole_y = float(site.soleY)
	pose = Transform2D(-yaw, Vector2(site.origin[0], site.origin[1]))
	inverse = pose.affine_inverse()
	landing = pose * Vector2(site.landingLocal[0], site.landingLocal[1])
	bounds = (pose * Rect2(_origin, Vector2(_size) * _spacing)).grow(.5)

func _column(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= _size.x or cell.y >= _size.y:
		return -1
	return HEADER + (cell.y * _size.x + cell.x) * _layers * 4

func _top(cell: Vector2i, ceiling: float) -> float:
	var start := _column(cell)
	var top := -INF
	if start >= 0:
		for offset in range(start, start + 4 * _layers, 4):
			var cm := _data.decode_s16(offset + 2)
			var y := sole_y + .01 * cm
			if cm == EMPTY or y > ceiling:
				break
			top = y
	return top

func floor_at(at: Vector2, ceiling := INF) -> float:
	if not bounds.has_point(at):
		return -INF
	var grid := (inverse * at - _origin) / _spacing
	var center := _top(Vector2i(grid.round()), ceiling)
	if not is_finite(center):
		return -INF
	# Interpolate a continuous surface without blending across a vertical edge.
	var cell := Vector2i(grid.floor())
	var frac := grid - Vector2(cell)
	var height := 0.0
	for z in 2:
		for x in 2:
			var y := _top(cell + Vector2i(x,z), ceiling)
			var weight := (frac.x if x else 1.0-frac.x) * (frac.y if z else 1.0-frac.y)
			height += weight * (y if absf(y-center) <= .30 else center)
	return height

func _intersecting_top(local: Vector2, low: float, high: float) -> float:
	var start := _column(Vector2i(((local - _origin) / _spacing).round()))
	if start >= 0:
		for offset in range(start, start + 4 * _layers, 4):
			var cm := _data.decode_s16(offset)
			if cm == EMPTY or sole_y + cm * .01 > high:
				break
			var y := sole_y + .01 * _data.decode_s16(offset + 2)
			if y > low:
				return y
	return -INF

func intersects(at: Vector2, low: float, high: float) -> bool:
	return bounds.has_point(at) and is_finite(_intersecting_top(inverse * at, low, high))

func clears(at: Vector2, feet: float, from: Vector2) -> bool:
	if not bounds.has_point(at):
		return true
	var local := inverse * at
	var previous := inverse * from if from.is_finite() else Vector2.INF
	for offset: Vector2 in FOOTPRINT:
		var high := _intersecting_top(local + offset, feet + STEP_UP, feet + 1.72)
		if is_finite(high):
			if previous.is_finite() and high <= _intersecting_top(previous + offset, feet + STEP_UP, feet + 1.72) + .002:
				continue
			return false
	return true
