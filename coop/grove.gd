extends Node3D

const STAGES := [
	{"id": "sapling", "label": "幼苗", "age": 0.0, "height": 0.34, "mesh_height": 0.65},
	{"id": "young", "label": "幼树", "age": 2.0, "height": 1.0, "mesh_height": 2.4},
	{"id": "mature", "label": "成树", "age": 9.0, "height": 3.75, "mesh_height": 7.0},
]
const FINAL_AGE := 16.0
const FINAL_HEIGHT := 7.0
const VIEW_DISTANCE := 28.0
const OBSERVE_DISTANCE := 6.0
const PINE_PILOT_ID := "trail-mature"
const PINE_PILOT_MODEL := "res://pines/pine_mature_refined.glb"
const PINE_DETAIL_NAMES := ["LOD0", "LOD1", "LOD2"]
const PINE_NEAR_DISTANCE := 8.0
const PINE_FAR_DISTANCE := 18.0
const PINE_DETAIL_MARGIN := 1.0

var trees: Array[Dictionary] = []
var species_catalog: Dictionary
var models: Dictionary = {}
var pine_pilot_model: PackedScene
var viewer_position := Vector3.ZERO
var seconds_per_year := 5.0
var last_sample := -1.0

func configure(config: Dictionary) -> void:
	if config.is_empty():
		return
	seconds_per_year = float(config.secondsPerYear)
	species_catalog = config.get("species", {"pine": {"label": "松树", "modelPrefix": "res://pines/pine"}})
	for species in species_catalog:
		var stages: Array[PackedScene] = []
		for stage in STAGES:
			var path := "%s_%s.glb" % [species_catalog[species].modelPrefix, stage.id]
			var model := load(path) as PackedScene
			if model == null:
				push_error("Missing tree model: " + path)
				return
			stages.append(model)
		models[species] = stages
	if ResourceLoader.exists(PINE_PILOT_MODEL):
		pine_pilot_model = load(PINE_PILOT_MODEL) as PackedScene
	for tree in config.trees:
		var species: String = tree.get("species", "pine")
		var root := Node3D.new()
		root.name = tree.id
		root.position = Vector3(tree.x, 0.0, tree.z)
		root.rotation.y = tree.yaw
		add_child(root)
		trees.append({
			"spec": tree, "species": species, "root": root, "model": null,
			"stage": -1, "height": 0.0, "age": 0.0, "details": [], "detail": -1,
		})

func update_focus(focus: Vector3) -> void:
	viewer_position = focus
	for tree in trees:
		var root: Node3D = tree.root
		var distance := _distance_squared(root.position, focus)
		root.visible = distance < VIEW_DISTANCE * VIEW_DISTANCE
		if not tree.details.is_empty():
			_update_pine_detail(tree, distance)

func set_room_time(seconds: float) -> void:
	if seconds == last_sample:
		return
	last_sample = seconds
	for tree in trees:
		var age := minf(FINAL_AGE, float(tree.spec.initialAge) + seconds / seconds_per_year)
		if age == tree.age and tree.model != null:
			continue
		var stage := _stage_at(age)
		if stage != tree.stage:
			_replace_model(tree, stage)
		var lower: Dictionary = STAGES[stage]
		var upper: Dictionary = STAGES[stage + 1] if stage + 1 < STAGES.size() else {"age": FINAL_AGE, "height": FINAL_HEIGHT}
		var progress := inverse_lerp(lower.age, upper.age, age)
		var height := lerpf(lower.height, upper.height, progress) * float(tree.spec.size)
		# Adjacent stages share their boundary height. The roots never move.
		tree.model.scale = Vector3.ONE * (height / float(lower.mesh_height))
		tree.height = height
		tree.age = age

func _stage_at(age: float) -> int:
	for stage in range(STAGES.size() - 1, 0, -1):
		if age >= float(STAGES[stage].age):
			return stage
	return 0

func _replace_model(tree: Dictionary, stage: int) -> void:
	var root: Node3D = tree.root
	var old_model: Node3D = tree.model
	if old_model != null:
		root.remove_child(old_model)
		old_model.queue_free()
	tree.details.clear()
	tree.detail = -1
	var model: Node3D
	if tree.spec.id == PINE_PILOT_ID and tree.species == "pine" and STAGES[stage].id == "mature" and pine_pilot_model != null:
		model = pine_pilot_model.instantiate() as Node3D
		for detail_name in PINE_DETAIL_NAMES:
			var detail := model.find_child(detail_name, true, false) as Node3D
			if detail == null:
				push_warning("Missing pine detail group: " + detail_name)
				model.free()
				model = null
				tree.details.clear()
				break
			tree.details.append(detail)
	if model == null:
		model = models[tree.species][stage].instantiate() as Node3D
	root.add_child(model)
	tree.model = model
	tree.stage = stage
	if not tree.details.is_empty():
		_update_pine_detail(tree, _distance_squared(root.position, viewer_position))

func _update_pine_detail(tree: Dictionary, distance_squared: float) -> void:
	var previous := int(tree.detail)
	var near_limit := PINE_NEAR_DISTANCE
	var far_limit := PINE_FAR_DISTANCE
	# Widen the active band so walking sideways along a boundary does not flicker.
	if previous >= 0:
		near_limit += PINE_DETAIL_MARGIN if previous == 0 else -PINE_DETAIL_MARGIN
		far_limit += PINE_DETAIL_MARGIN if previous <= 1 else -PINE_DETAIL_MARGIN
	var detail := 2
	if distance_squared < near_limit * near_limit:
		detail = 0
	elif distance_squared < far_limit * far_limit:
		detail = 1
	if detail == previous:
		return
	for i in tree.details.size():
		tree.details[i].visible = i == detail
	tree.detail = detail

func _distance_squared(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_squared_to(Vector2(b.x, b.z))

func observe(focus: Vector3, forward: Vector3) -> String:
	var nearest := OBSERVE_DISTANCE * OBSERVE_DISTANCE
	var eye := Vector2(focus.x, focus.z)
	var facing := Vector2(forward.x, forward.z).normalized()
	var hint := ""
	for tree in trees:
		if tree.model == null:
			continue
		var root: Node3D = tree.root
		var offset := Vector2(root.position.x, root.position.z) - eye
		var distance := offset.length_squared()
		if distance >= nearest or offset.normalized().dot(facing) < 0.73:
			continue
		nearest = distance
		var stage := int(tree.stage)
		hint = "%s · %s" % [species_catalog[tree.species].label, STAGES[stage].label]
		if stage + 1 < STAGES.size():
			var next: Dictionary = STAGES[stage + 1]
			var wait := ceili((next.age - tree.age) * seconds_per_year)
			hint += " · %d 秒后长成%s" % [wait, next.label]
	return hint

func render_state() -> Array[Dictionary]:
	var state: Array[Dictionary] = []
	for tree in trees:
		var model: Node3D = tree.model
		if model != null and model.is_visible_in_tree():
			var stage: Dictionary = STAGES[tree.stage]
			var item := {"id": tree.spec.id, "species": tree.species, "stage": stage.id, "height": tree.height}
			if tree.detail >= 0:
				item.detail = PINE_DETAIL_NAMES[tree.detail]
			state.append(item)
	return state
