extends Node3D

const Mines = preload("res://mines_layout.gd")
const LANTERN = preload("res://props/camp_lantern.glb")
const LANTERN_SCALE := 0.52
const BAIL_CENTER_Y := -0.049
const HANGER_OFFSET_Y := 0.002
const WICK_CENTER_Y := -0.392
const LIGHT_INSET := 0.16

var _seams: Dictionary = {}
var _remaining: Dictionary = {}

func _ready() -> void:
	for id: String in Mines.data:
		var record: Dictionary = Mines.data[id]
		var cave := Node3D.new()
		cave.name = id
		cave.transform = Mines.pose(id)
		add_child(cave)
		_mount(cave, record.model)
		var seam: Node3D = _mount(cave, record.seam.model)
		if seam != null:
			seam.position = Mines.vector(record.seam.at)
			seam.rotation.y = float(record.seam.yaw)
			seam.visible = int(_remaining.get(id, 1)) > 0
			_seams[id] = seam
		for i in record.lamps.size():
			_mount_lamp(cave, record.lamps[i], record.floor, i)

func _mount_lamp(cave: Node3D, record: Dictionary, floor: Array, index: int) -> void:
	var at := Mines.vector(record.at)
	var side := 1.0 if at.x > _lane_center(floor, at.z) else -1.0
	var lantern := LANTERN.instantiate() as Node3D
	lantern.name = "HurricaneLantern%d" % index
	# The bail loops through the existing gallery bracket 7 mm below this station.
	lantern.position = at + Vector3.UP * (HANGER_OFFSET_Y - BAIL_CENTER_Y * LANTERN_SCALE)
	lantern.rotation.y = -side * PI * .5
	lantern.scale = Vector3.ONE * LANTERN_SCALE
	(lantern.get_node("Mount") as Node3D).hide()
	for part: MeshInstance3D in lantern.find_children("*", "MeshInstance3D", true, false):
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cave.add_child(lantern)

	var light := OmniLight3D.new()
	light.name = "OilLamp%d" % index
	# A small inset keeps the old bracket away from the brightest part of the wall wash.
	light.position = lantern.position + Vector3(-side * LIGHT_INSET, WICK_CENTER_Y * LANTERN_SCALE, 0.0)
	light.omni_range = float(record.range)
	light.light_energy = float(record.energy) * (0.40 if index == 0 else 0.35)
	light.omni_attenuation = 1.18
	light.light_cull_mask &= ~Mines.COAST_SCENERY_LAYER
	var warm := Color(record.color[0], record.color[1], record.color[2])
	light.light_color = warm.lerp(Color.WHITE, 0.46)
	light.light_specular = 0.23
	light.shadow_enabled = index == 1 or index == 2
	light.distance_fade_enabled = true
	light.distance_fade_begin = 23.0
	light.distance_fade_shadow = 18.0
	light.distance_fade_length = 8.0
	cave.add_child(light)

func _lane_center(floor: Array, z: float) -> float:
	for i in range(1, floor.size()):
		var next: Array = floor[i]
		if z <= float(next[0]):
			var prior: Array = floor[i - 1]
			var fraction := clampf(inverse_lerp(float(prior[0]), float(next[0]), z), 0.0, 1.0)
			return lerpf(float(prior[2]), float(next[2]), fraction)
	return float(floor.back()[2])

func set_remaining(id: String, count: int) -> void:
	_remaining[id] = count
	if _seams.has(id):
		_seams[id].visible = count > 0

func _mount(parent: Node3D, path: String) -> Node3D:
	var source := load(path) as PackedScene
	if source == null:
		return null
	var instance := source.instantiate() as Node3D
	parent.add_child(instance)
	return instance
