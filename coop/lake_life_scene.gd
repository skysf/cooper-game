extends Node3D

signal blade_entered_water(at: Vector3, elapsed: float)

const Ferry = preload("res://lake_ferry.gd")
const Sheep = preload("res://lake_sheep.gd")
const Lake = preload("res://lake_layout.gd")
const LakeSurface = preload("res://lake.gd")
const BASE := "res://props/lake_life/"
const CREW := {"herbalist":-1.88,"ferryman":1.68}

var boat := Node3D.new()
var animals := Node3D.new()
var live_sheep: Node3D
var assets := {}
var requested := {}
var hull_pose := {}
var sheep_pose := {}
var last_sample := -100.0

func _ready() -> void:
	boat.name = "LakeHouseboat"
	animals.name = "EastMeadow"
	add_child(boat)
	add_child(animals)

func _asset(key: String, parent: Node3D) -> Dictionary:
	if assets.has(key):
		return assets[key]
	var path := BASE + key + ".glb"
	if not requested.has(key):
		ResourceLoader.load_threaded_request(path)
		requested[key] = true
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
		return {}
	var packed: PackedScene = ResourceLoader.load_threaded_get(path)
	var root := packed.instantiate() as Node3D
	parent.add_child(root)
	for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		mesh.layers |= LakeSurface.REFLECTION_LAYER
	var entry := {"root":root}
	var anim := root.find_children("*","AnimationPlayer",true,false)
	if not anim.is_empty():
		var player: AnimationPlayer = anim[0]
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		entry.player = player
	if CREW.has(key):
		root.position = Vector3(CREW[key], Ferry.DECK, 0.0)
		root.rotation.y = PI / 2.0
		var skeleton: Skeleton3D = root.find_children("*","Skeleton3D",true,false)[0]
		var index := skeleton.find_bone("Oar")
		if index >= 0:
			var pin := Vector3(-0.610,0.844,0.115) if key == "herbalist" else Vector3(0.630,0.895,0.115)
			var end := pin + Vector3.LEFT * 2.16 if key == "herbalist" else pin + Vector3.RIGHT * 2.16
			entry.skeleton = skeleton
			entry.bone = index
			entry.tip = skeleton.get_bone_global_rest(index).affine_inverse() * end
	assets[key] = entry
	return entry

func _sample(entry: Dictionary, pose: Dictionary) -> void:
	var player: AnimationPlayer = entry.player
	if not player.has_animation(pose.clip):
		return
	if player.current_animation != pose.clip:
		player.play(pose.clip)
	player.seek(clampf(pose.phase, 0.0, player.current_animation_length), true)
	player.advance(0.0)

func _sample_crew(entry: Dictionary, key: String, elapsed: float, departed: float) -> void:
	var player: AnimationPlayer = entry.player
	var duration := player.get_animation("Moored").length
	var offset := 3.35 if key == "herbalist" else .65
	var clip: String = hull_pose.clip
	var phase: float = hull_pose.phase
	var age := elapsed-departed
	var blend := 1.0
	var previous := {}
	if clip=="Moored":
		phase = fposmod(elapsed+offset,duration)
		if departed>=0 and age>=Ferry.CIRCUIT and age<Ferry.CIRCUIT+.62:
			previous={"clip":"Land","phase":Ferry.LAND}
			blend=smoothstep(0,.62,age-Ferry.CIRCUIT)
	elif clip=="CastOff" and phase<.70:
		previous={"clip":"Moored","phase":fposmod(departed+offset,duration)}
		blend=smoothstep(0,.70,phase)
	if previous.is_empty():
		_sample(entry,{"clip":clip,"phase":phase})
		return
	var skeleton: Skeleton3D = entry.skeleton
	_sample(entry,previous)
	var poses: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_pose(index))
	_sample(entry,{"clip":clip,"phase":phase})
	for index in poses.size():
		skeleton.set_bone_pose(index,poses[index].interpolate_with(skeleton.get_bone_pose(index),blend))

func sync(enabled: bool, departed: float, elapsed: float, sheep_alive: bool, sheared: float, eye: Vector3) -> void:
	visible = enabled
	if not enabled:
		return
	hull_pose = Ferry.pose(elapsed, departed)
	var point: Vector2 = hull_pose.point
	var distance := Vector2(eye.x,eye.z).distance_to(point)
	boat.visible = distance < 65.0
	var interval := 1.0 / 30.0 if distance < 17.0 else 1.0 / 15.0
	var sample_now := elapsed < last_sample or elapsed - last_sample >= interval
	if boat.visible:
		_asset("hull", boat)
		var rowing: bool = hull_pose.clip == "Row"
		var progress := float(hull_pose.phase) / Ferry.STROKE * TAU if rowing else 0.0
		boat.position = Vector3(point.x,Lake.water_y()-Ferry.WATERLINE + 0.008*sin(elapsed*1.55),point.y)
		boat.rotation = Vector3(0.007*sin(elapsed*1.31), hull_pose.yaw, 0.007*sin(progress))
		for key: String in CREW:
			var entry := _asset(key,boat)
			if entry.is_empty() or not sample_now:
				continue
			_sample_crew(entry,key,elapsed,departed)
			if entry.has("skeleton"):
				var skeleton: Skeleton3D = entry.skeleton
				var blade := skeleton.to_global(skeleton.get_bone_global_pose(entry.bone) * (entry.tip as Vector3))
				var submerged := blade.y <= Lake.water_y()
				if rowing and submerged and entry.has("submerged") and not entry.submerged:
					blade.y = Lake.water_y()
					blade_entered_water.emit(blade,elapsed)
				entry.submerged = submerged
	animals.visible = sheep_alive and Vector2(eye.x,eye.z).distance_squared_to(Sheep.MEADOW[0]) < 49.0 * 49.0
	if animals.visible:
		sheep_pose = Sheep.pose(elapsed,sheared)
		var key := "shorn" if Sheep.shorn(elapsed,sheared) else "fleece"
		var entry := _asset(key,animals)
		if not entry.is_empty():
			if live_sheep != entry.root:
				if live_sheep != null:
					live_sheep.hide()
				live_sheep = entry.root
				live_sheep.show()
				_sample(entry,sheep_pose)
			live_sheep.position = sheep_pose.at
			live_sheep.rotation.y = sheep_pose.yaw
			if sample_now:
				_sample(entry,sheep_pose)
	if sample_now:
		last_sample = elapsed

func observables() -> Dictionary:
	var players := {}
	for key: String in CREW:
		if assets.has(key):
			players[key] = (assets[key].player as AnimationPlayer).current_animation
	return {"clip":hull_pose.get("clip",""),"phase":hull_pose.get("phase",0.0),"crew":players,
		"sheepClip":sheep_pose.get("clip","") if animals.visible else ""}
