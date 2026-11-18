extends Node3D

const COATS := ["#70795e", "#687a79", "#807058", "#747085"]
var target := Vector3.ZERO
var heading := 0.0
var gait := 0.0
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var player_slot := 0
var holding := false

func _ellipsoid(parent: Node3D, center: Vector3, radius: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var form := SphereMesh.new()
	form.radial_segments = 14
	form.rings = 8
	var part := MeshInstance3D.new()
	part.mesh = form
	part.material_override = material
	part.scale = radius * 2.0
	parent.add_child(part)
	part.position = center
	return part

func _fabric(color: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.roughness = .85
	return mat

func outfit(slot: int) -> void:
	player_slot = slot
	var coat := _fabric(COATS[posmod(slot - 1, 4)])
	var canvas := _fabric("#524534")
	var rubber := _fabric("#302f2a")
	var dark := _fabric("#474840")
	var skin := _fabric("#9b7d64")
	_ellipsoid(self, Vector3(0,1.12,0), Vector3(.25,.34,.15), coat)
	_ellipsoid(self, Vector3(0,1.54,.005), Vector3(.15,.19,.14), coat)
	_ellipsoid(self, Vector3(0,1.54,-.088), Vector3(.102,.117,.082), skin)
	_ellipsoid(self, Vector3(0,1.24,.145), Vector3(.198,.235,.105), canvas)
	for side in [-1, 1]:
		var hip := Node3D.new()
		add_child(hip)
		hip.position = Vector3(.112*side,.88,0)
		legs.append(hip)
		_ellipsoid(hip,Vector3(0,-.27,0),Vector3(.089,.28,.098),dark)
		_ellipsoid(hip,Vector3(0,-.60,.01),Vector3(.073,.24,.078),dark)
		_ellipsoid(hip,Vector3(0,-.80,-.03),Vector3(.08,.077,.14),rubber)
		var shoulder := Node3D.new()
		add_child(shoulder)
		shoulder.position = Vector3(.206*side,1.35,0)
		arms.append(shoulder)
		_ellipsoid(shoulder, Vector3(.034*side,-.13,0), Vector3(.085,.19,.088),coat)
		_ellipsoid(shoulder, Vector3(.042*side,-.35,-.045), Vector3(.063,.15,.071),coat)
		_ellipsoid(shoulder, Vector3(.042*side,-.49,-.06), Vector3(.052,.075,.052),rubber)

func advance(delta: float) -> void:
	var prev := position
	position = position.lerp(target, 1.0-exp(-16.0*delta))
	rotation.y = lerp_angle(rotation.y, heading, 1.0-exp(-12.0*delta))
	var speed := position.distance_to(prev) / maxf(delta, .001)
	gait += minf(speed, 5.0) * delta * 2.7
	for i in legs.size():
		var swing := sin(gait + i*PI) * clampf(speed*.14,0,.48)
		legs[i].rotation.x = swing
		arms[i].rotation.x = 0.97 if holding and i == 1 else -swing * 0.64

func held_item_position() -> Vector3:
	return arms[1].to_global(Vector3(0.042, -0.485, -0.115))
