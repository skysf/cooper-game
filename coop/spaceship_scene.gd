extends Node3D

const Spaceship = preload("res://spaceship.gd")
const Lake = preload("res://lake_layout.gd")
const MODEL = preload("res://props/camp_red_spaceship.glb")
const EXHAUST = preload("res://materials/spaceship_exhaust.gdshader")

const COCKPIT_EYE := Vector3(0.0, 1.67, 0.23)
const SEAT_ORIGIN := Vector3(0.0, 0.44, 0.36)
const LIFT_PORTS := [Vector3(-0.59, 0.004, 1.64), Vector3(0.59, 0.004, 1.64)]
# The main plumes originate in the large circular aft bells, behind their outer lips.
const TAIL_PORTS := [Vector3(-0.620, 0.401, 2.16), Vector3(0.622, 0.397, 2.16)]
const LIFT_RADIUS := 0.078
const TAIL_RADIUS := 0.22

var body: Node3D
var seat := Marker3D.new()
var initialized := false
var lift_power := 0.0
var tail_power := 0.0
var lift_jets: Array[MeshInstance3D] = []
var tail_jets: Array[MeshInstance3D] = []
var lift_material := ShaderMaterial.new()
var tail_material := ShaderMaterial.new()
var wake_age := 0.0

func _ready() -> void:
	body = MODEL.instantiate()
	add_child(body)
	seat.name = "PilotSeat"
	seat.position = SEAT_ORIGIN
	body.add_child(seat)
	_create_exhaust()
	hide()

func _create_exhaust() -> void:
	var stream := CylinderMesh.new()
	stream.top_radius = 1.0
	stream.bottom_radius = 0.13
	stream.height = 1.0
	stream.radial_segments = 12
	stream.rings = 5
	stream.cap_top = false
	stream.cap_bottom = false
	lift_material.shader = EXHAUST
	tail_material.shader = EXHAUST
	tail_material.set_shader_parameter("outer_flame", Color("#ef6533"))
	tail_material.set_shader_parameter("inner_flame", Color("#ffedcc"))
	lift_jets = _attach_exhaust(stream, LIFT_PORTS, "Lift", 0.0, LIFT_RADIUS, lift_material)
	tail_jets = _attach_exhaust(stream, TAIL_PORTS, "Tail", -PI * 0.5, TAIL_RADIUS, tail_material)

func _attach_exhaust(stream: Mesh, ports: Array, label: String, tilt: float, radius: float,
		material: ShaderMaterial) -> Array[MeshInstance3D]:
	var jets: Array[MeshInstance3D] = []
	for index in ports.size():
		var nozzle := Marker3D.new()
		nozzle.name = "%sNozzle%d" % [label, index + 1]
		nozzle.position = ports[index]
		nozzle.rotation.x = tilt
		body.add_child(nozzle)
		var jet := MeshInstance3D.new()
		jet.mesh = stream
		jet.material_override = material
		jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nozzle.add_child(jet)
		jet.scale = Vector3(radius, 1.0, radius)
		jet.hide()
		jets.append(jet)
	return jets

func cockpit_eye() -> Vector3:
	return body.to_global(COCKPIT_EYE)

func sync(ship: Dictionary, elapsed: float, delta: float, local_pilot := false) -> void:
	if ship.is_empty():
		hide()
		if initialized:
			for jet in lift_jets:
				jet.hide()
			for jet in tail_jets:
				jet.hide()
		initialized = false
		lift_power = 0.0
		tail_power = 0.0
		return
	var at := Spaceship.position(ship)
	var heading: float = ship.yaw
	if not initialized or position.distance_squared_to(at) > 25.0:
		position = at
		rotation.y = heading
		body.rotation = Vector3.ZERO
		body.position.y = 0.0
		initialized = true
	var pose_blend := 1.0 - exp(-delta * (44.0 if local_pilot else 13.0))
	position = position.lerp(at, pose_blend)
	rotation.y = lerp_angle(rotation.y, heading, pose_blend)
	var velocity := Spaceship.velocity_sample(ship).rotated(Vector3.UP, -rotation.y)
	var height := float(ship.get("floor", at.y))
	var airborne := smoothstep(0.11, 1.05, at.y - height)
	var pitch := float(ship.get("tiltX", 0.0)) + velocity.z * 0.012 * airborne
	var bank := float(ship.get("tiltZ", 0.0)) + velocity.x * -0.015 * airborne
	var floater := 0.0
	if ship.onWater:
		floater = sin(elapsed * 2.4) * 0.036
		pitch += sin(elapsed * 1.5) * 0.020
		bank += cos(elapsed * 2.4) * 0.026
	var attitude_blend := 1.0 - exp(-delta * 12.0)
	body.position.y = lerpf(body.position.y, floater, attitude_blend)
	body.rotation.x = lerpf(body.rotation.x, pitch, attitude_blend)
	body.rotation.z = lerpf(body.rotation.z, bank, attitude_blend)
	wake_age += delta
	var spool := 1.0 - exp(-delta * 16.0)
	lift_power = _update_streams(lift_jets, lift_material, lift_power, float(ship.get("thrust", 0.0)),
		spool, Vector2(0.36, 1.74), true)
	tail_power = _update_streams(tail_jets, tail_material, tail_power, float(ship.get("rearThrust", 0.0)),
		spool, Vector2(0.72, 3.20), false)
	show()

func _update_streams(jets: Array[MeshInstance3D], material: ShaderMaterial, power: float,
		target: float, spool: float, lengths: Vector2, ground_clip: bool) -> float:
	if target <= 0.0 and power <= 0.0:
		return 0.0
	power = lerpf(power, target, spool)
	if power <= 0.025 and target <= 0.0:
		for jet in jets:
			jet.hide()
		return 0.0
	material.set_shader_parameter("power", power)
	for index in jets.size():
		var jet := jets[index]
		var length := lerpf(lengths.x, lengths.y, power) * (1.0 + 0.06 * sin(wake_age * 26.0 + index))
		if ground_clip:
			var origin := (jet.get_parent() as Node3D).global_position
			var at := Vector2(origin.x, origin.z)
			length = minf(length, origin.y - maxf(Lake.walk_height(at), Lake.surface_height(at)))
		jet.visible = power > 0.025 and length > 0.045
		if jet.visible:
			jet.scale.y = length
			jet.position.y = -length * 0.5
	return power
