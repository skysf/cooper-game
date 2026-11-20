extends SceneTree
const Shelter = preload("res://rain_shelter.gd")
func _initialize() -> void:
	var shelter := Shelter.new()
	var eye := Vector3(-74.044518,22.51204,-29.55)
	var cell := Vector3i((eye / Shelter.FOCUS_CELL).floor())
	var origin := Vector2((cell.x + .5) * Shelter.FOCUS_CELL, (cell.z + .5) * Shelter.FOCUS_CELL)
	var data := PackedFloat32Array()
	Shelter._pack_nearby(shelter._mine, origin, cell.y * Shelter.FOCUS_CELL - Shelter.DROP_BOTTOM, data)
	var rows := data.size() / 16
	assert(rows == 117)
	var out := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	out.store_32(rows)
	out.store_buffer(data.to_byte_array())
	quit()
