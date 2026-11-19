extends RefCounted

const MODELS := {
	"cap": preload("res://props/camp_cap.glb"),
	"jacket": preload("res://props/camp_jacket.glb"),
	"pants": preload("res://props/camp_pants.glb"),
}

static var drop_meshes: Dictionary = {}

static func on_ground(item: String) -> Node3D:
	if not drop_meshes.has(item):
		var prototype: Node3D = MODELS[item].instantiate()
		var meshes := prototype.find_children("*", "MeshInstance3D", true, false)
		var source := (prototype if meshes.is_empty() else meshes[0]) as MeshInstance3D
		drop_meshes[item] = source.mesh
		prototype.free()
	var root := Node3D.new()
	var garment := MeshInstance3D.new()
	garment.mesh = drop_meshes[item]
	if item != "cap":
		garment.basis = Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(0.76, 0.34, 0.68))
	var bounds := Transform3D(garment.basis, Vector3.ZERO) * garment.get_aabb()
	garment.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
	root.add_child(garment)
	return root
