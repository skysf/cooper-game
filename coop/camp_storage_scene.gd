extends Node3D

const Storage = preload("res://camp_storage.gd")
const Stones = preload("res://stones.gd")
const Survival = preload("res://survival.gd")
const Lake = preload("res://lake_layout.gd")
const Placement = preload("res://placement.gd")
const PlacementWorld = preload("res://placement_world.gd")
const WindField = preload("res://vegetation/wind_field.gd")
const FIRE_SHADER = preload("res://materials/campfire.gdshader")

var live: Dictionary = {}
var resources: Dictionary = {}
var hidden_flame := StandardMaterial3D.new()
var flame_quad := QuadMesh.new()
var sign_font: Font
var ghost: Node3D
var ghost_kind := ""
var ghost_material := StandardMaterial3D.new()
var room_time := 0.0

func _ready() -> void:
	hidden_flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hidden_flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hidden_flame.albedo_color = Color.TRANSPARENT
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for kind: String in ["wicker_basket","wood_crate","military_crate","wood_barrel","wood_barrel_tall","campfire"]:
		ResourceLoader.load_threaded_request(Storage.MODELS[kind])

func _model_for(kind: String, shorn := false) -> PackedScene:
	var path: String = "res://props/lake_life/shorn.glb" if kind == "corpse_sheep" and shorn else Storage.MODELS[kind]
	if not resources.has(path):
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return null
		resources[path] = ResourceLoader.load_threaded_get(path) if status == ResourceLoader.THREAD_LOAD_LOADED else load(path)
	return resources[path]

func _make(kind: String, shorn := false) -> Dictionary:
	var packed := _model_for(kind, shorn)
	if packed == null:
		return {}
	var root := Node3D.new()
	add_child(root)
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	var entry := {"root":root,"kind":kind,"model":model}
	if kind == "wood_sign":
		var label := Label3D.new()
		if sign_font == null:
			var system := SystemFont.new()
			system.font_names = PackedStringArray(["PingFang SC","Microsoft YaHei","Noto Sans CJK SC"])
			var packed_font: FontFile = load("res://fonts/CampSignCJK.otf")
			if packed_font != null:
				sign_font = packed_font.duplicate()
				sign_font.fallbacks = [system]
			else:
				sign_font = system
		label.font = sign_font
		label.font_size = 34
		label.width = 349
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.pixel_size = 0.0013
		label.modulate = Color("#ede1be")
		label.outline_modulate = Color("#221a13")
		label.outline_size = 2
		label.position = Vector3(0.0,0.925,-0.045)
		label.rotation.y = PI
		root.add_child(label)
		entry.label = label
	if kind == "campfire":
		_style_fire_model(model)
		var flame := MeshInstance3D.new()
		flame.mesh = flame_quad
		var material := ShaderMaterial.new()
		material.shader = FIRE_SHADER
		flame.material_override = material
		flame.position.y = 0.10
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.custom_aabb = AABB(Vector3(-1.0, -0.04, -1.0), Vector3(2.0, 1.29, 2.0))
		flame.visibility_range_end = 36.0
		flame.hide()
		root.add_child(flame)
		var light := OmniLight3D.new()
		light.position.y = 0.25
		light.light_color = Color("#ffb676")
		light.omni_range = 3.1
		light.distance_fade_enabled = true
		light.distance_fade_begin = 18.0
		light.distance_fade_length = 6.0
		light.hide()
		root.add_child(light)
		entry.light = light
		entry.flame = flame
		entry.fire_material = material
	if kind == "iron_furnace":
		var light := OmniLight3D.new()
		light.position = Vector3(0.0,.37,-.46)
		light.light_color = Color("#ff8837")
		light.omni_range = 2.75
		root.add_child(light)
		entry.light = light
	if kind.begins_with("corpse_"):
		var animators := model.find_children("*","AnimationPlayer",true,false)
		if not animators.is_empty():
			var animator := animators[0] as AnimationPlayer
			animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			entry.corpse_animator = animator
	return entry

func _style_fire_model(model: Node3D, body: Material = null) -> void:
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.push_front(model)
	for mesh: MeshInstance3D in meshes:
		for surface: int in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface)
			if original != null and original.resource_name.begins_with("Flame"):
				mesh.set_surface_override_material(surface, hidden_flame)
			elif body != null:
				mesh.set_surface_override_material(surface, body)

func sync(records: Dictionary, players: Dictionary, self_id: String, camera: Camera3D,
		first_person: bool, elapsed: float, rain := 0.0) -> void:
	room_time = elapsed
	var wind := WindField.sample(elapsed, rain)
	for id: String in live.keys():
		if not records.has(id):
			live[id].root.queue_free()
			live.erase(id)
	for id: String in records:
		var record: Dictionary = records[id]
		var at := Stones.unpack(record.at)
		var heading := float(record.yaw)
		var lean := Vector3.ZERO
		var death_pose := {}
		if record.mode == "held":
			var holder: Dictionary = players.get(record.get("holder",""),{})
			if holder.is_empty():
				continue
			heading = float(holder.yaw)
			var reach := 0.77 + float(Storage.KINDS[record.kind].radius) * 0.44
			if first_person and record.holder == self_id:
				at = camera.global_position - camera.global_basis.z * reach - Vector3.UP * 0.92
			else:
				var forward := Vector3(0.0,0.0,-reach).rotated(Vector3.UP,heading)
				at = Vector3(holder.x,float(holder.y)+0.66,holder.z) + forward
		elif record.mode == "air":
			at = Stones.flight_position(record,elapsed)
			var age := maxf(0.0,elapsed-float(record.launch))
			lean = Vector3(age*4.25,0.0,age*1.45)
		elif record.kind.begins_with("corpse_"):
			death_pose = _corpse_death_pose(record, at, elapsed)
			at = death_pose.at
		var distant := at.distance_squared_to(camera.position) > 62.0 * 62.0
		if not live.has(id):
			if distant:
				continue
			var made := _make(record.kind, record.get("shorn",false))
			if made.is_empty():
				continue
			live[id] = made
		var entry: Dictionary = live[id]
		var root: Node3D = entry.root
		var large: bool = not Storage.KINDS[record.kind].get("throwable",true)
		root.visible = not distant and not (record.mode == "held" and record.get("holder") == self_id and large)
		if distant:
			continue
		if record.mode == "ground" and record.has("rotation"):
			root.transform = PlacementWorld.pose(record)
		else:
			root.position = at
			root.rotation = Vector3(lean.x,heading,lean.z)
			if record.kind=="corpse_boar" and not entry.has("groundTilt"):
				entry.groundTilt=Storage.WoodlandBoar.ground_tilt(Vector2(at.x,at.z),heading)
				entry.model.basis=entry.groundTilt
		if not death_pose.is_empty() and entry.has("corpse_animator"):
			_sample_corpse_pose(entry.corpse_animator, death_pose.clip, death_pose.phase)
		if entry.has("label") and entry.label.text != record.text:
			entry.label.font_size = 22 if record.text.length() > 30 else 29
			entry.label.text = record.text
		if record.kind == "campfire":
			var remaining := float(record.fuelUntil) - elapsed
			var lit := remaining > 0.0
			var light: OmniLight3D = entry.light
			entry.flame.visible = lit
			light.visible = lit
			if lit:
				var power := smoothstep(0.0, 4.0, remaining)
				var at_xz := Vector2(at.x, at.z)
				var material: ShaderMaterial = entry.fire_material
				material.set_shader_parameter("fire_time", elapsed)
				material.set_shader_parameter("fire_power", power)
				material.set_shader_parameter("fire_wind", WindField.at_point(wind, elapsed, at_xz))
				light.light_energy = power * (0.75 + sin(elapsed * 11.0) * 0.11 + sin(elapsed * 5.1) * 0.08)
		if record.kind == "iron_furnace":
			var batch_end: float = record.get("batchReady",0.0)
			entry.light.visible = elapsed < batch_end and record.mode == "ground"
			if entry.light.visible:
				entry.light.light_energy = 1.1 + sin(elapsed*8.2)*.16


func _corpse_death_pose(record: Dictionary, at: Vector3, elapsed: float) -> Dictionary:
	if record.kind == "corpse_eagle":
		return _eagle_death_pose(record, at, elapsed)
	if record.kind=="corpse_boar" and not Storage.corpse_ready(record,elapsed):
		return {"at":at,"clip":"Collapse","phase":clampf((elapsed-float(record.deadAt))/Storage.WoodlandBoar.COLLAPSE_TIME,0.,1.)}
	if record.kind == "corpse_sheep" and not Storage.corpse_ready(record,elapsed):
		return {"at":at, "clip":"Collapse", "phase":clampf((elapsed-float(record.deadAt))/Storage.SHEEP_COLLAPSE_SECONDS,0.0,1.0)}
	if record.kind == "corpse_croc" and not Storage.corpse_ready(record, elapsed):
		var age := maxf(0.0, elapsed - float(record.get("deadAt", elapsed)))
		return {"at":at, "clip":"Collapse", "phase":minf(age / Storage.CROC_COLLAPSE_SECONDS, 1.0)}
	return {"at":at, "clip":"Dead", "phase":0.0}

func _eagle_death_pose(record: Dictionary, at: Vector3, elapsed: float) -> Dictionary:
	if Storage.corpse_ready(record, elapsed):
		return {"at":at, "clip":"Dead", "phase":0.0}
	var end: float = record.landAt
	var start: float = record.deadAt
	if not record.has("fallFrom"):
		return {"at":at, "clip":"Collapse", "phase":clampf((elapsed-start)/maxf(end-start,0.001),0.0,1.0)}
	var origin := Stones.unpack(record.fallFrom)
	var impact: float = record.impactAt
	if elapsed < impact:
		var point := Vector2(origin.x, origin.z)
		var surface := maxf(Lake.walk_height(point), Lake.surface_height(point))
		var phase := clampf((elapsed-start)/maxf(impact-start,0.001),0.0,1.0)
		origin.y = lerpf(origin.y, surface, phase * phase)
		return {"at":origin, "clip":"Collapse" if record.foldedFall else "Fall", "phase":phase}
	# During a lake drift the pose has already settled on the water surface.
	var fraction := smoothstep(0.0, 1.0, (elapsed-impact)/maxf(end-impact,0.001))
	var position := origin.lerp(at, fraction)
	var point := Vector2(position.x, position.z)
	position.y = maxf(Lake.walk_height(point), Lake.surface_height(point))
	return {"at":position, "clip":"Dead", "phase":0.0}

func _sample_corpse_pose(animator: AnimationPlayer, clip: String, phase: float) -> void:
	if not animator.has_animation(clip):
		return
	if animator.assigned_animation != clip:
		animator.play(clip)
	elif clip == "Dead":
		return
	animator.seek(phase * animator.get_animation(clip).length, true)
	animator.pause()

func show_placement(kind: String, answer: Dictionary) -> void:
	if answer.is_empty() or not answer.has("hit"):
		if ghost != null:
			ghost.hide()
		return
	if ghost == null or ghost_kind != kind:
		if ghost != null:
			ghost.queue_free()
			ghost = null
		var packed := _model_for(kind)
		if packed == null:
			return
		ghost = packed.instantiate() as Node3D
		ghost_kind = kind
		add_child(ghost)
		if kind == "campfire":
			_style_fire_model(ghost, ghost_material)
		for mesh: MeshInstance3D in ghost.find_children("*", "MeshInstance3D", true, false):
			if kind != "campfire":
				mesh.material_override = ghost_material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost_material.albedo_color = Color(0.33,0.90,0.40,0.53) if answer.ok else Color(1.0,0.28,0.19,0.58)
	ghost.transform = answer.pose
	ghost.show()

func target(records: Dictionary, point: Vector2, feet: float, camera: Camera3D, static_grid := {}) -> String:
	var found := ""
	var score := INF
	var forward := -camera.global_basis.z
	var hit := Placement.trace(camera.global_position,camera.global_position + forward*6.2,
		PlacementWorld.nearby(static_grid,records,point))
	var selected: String = hit.get("id", "")
	if records.has(selected) and live.has(selected) and Storage.corpse_ready(records[selected], room_time):
		var contact: Vector3 = hit.point
		if absf(contact.y-feet) <= PlacementWorld.HAND_REACH_Y and point.distance_squared_to(Vector2(contact.x,contact.z)) <= Storage.REACH ** 2:
			return selected
	for id: String in records:
		var record: Dictionary = records[id]
		if record.mode != "ground" or not live.has(id) or not Storage.corpse_ready(record, room_time) or not PlacementWorld.profile(record.kind).is_empty():
			continue
		var at := Stones.unpack(record.at)
		var spec: Dictionary = Storage.KINDS[record.kind]
		if absf(at.y-feet) > 1.5 or point.distance_squared_to(Survival.horizontal(record.at)) > Storage.REACH*Storage.REACH:
			continue
		var center := at + Vector3.UP * float(spec.height) * 0.55
		var offset := center-camera.global_position
		var along := offset.dot(forward)
		if along <= 0.0:
			continue
		var away := (offset-forward*along).length()
		var reach := maxf(0.18,float(spec.radius)*0.86)
		if away <= reach and along+away*2.0 < score:
			score = along+away*2.0
			found = id
	return found
