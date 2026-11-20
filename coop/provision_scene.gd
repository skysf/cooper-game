extends Node3D

const Survival = preload("res://survival.gd")
const Weapons = preload("res://weapons.gd")
const Clothing = preload("res://clothing.gd")
const TABLE = preload("res://props/camp_table.glb")
const JUG = preload("res://props/camp_water_jug.glb")
const GNOME = preload("res://props/table_gnome.glb")
const BABUSHKA = preload("res://props/table_babushka.glb")
const BACKPACK = preload("res://props/camp_backpack.glb")
const FOOD = {
	"apple": preload("res://props/food_apple.glb"),
	"bread": preload("res://props/food_bread.glb"),
}
const SUPPLIES := {"water": JUG, "wood": preload("res://props/material_wood.glb"), "tarp": preload("res://props/material_tarp.glb")}
const EQUIPMENT := {"club": "res://wild_people/club.glb", "spear": "res://wild_people/spear.glb", "shield": "res://wild_people/shield.glb", "stone": "res://props/stone_round.glb"}

var food_nodes: Dictionary = {}
var weapon_models: Dictionary = {}
var ground_backpack: Node3D

func _ready() -> void:
	_place(TABLE, Vector3(Survival.TABLE_CENTER.x, 0.0, Survival.TABLE_CENTER.y))
	_place(JUG, Vector3(Survival.JUG.x, Survival.TABLE_TOP, Survival.JUG.y), -0.32)
	_place(GNOME, Vector3(3.52, Survival.TABLE_TOP, -89.12), PI * 0.5 - 0.12)
	_place(BABUSHKA, Vector3(3.74, Survival.TABLE_TOP, -89.12), 0.17)
	ground_backpack = _place(BACKPACK, Vector3(Survival.BACKPACK.x, 0.28, Survival.BACKPACK.y), 0.3)
	ground_backpack.hide()

func show_ground_backpack(available: bool) -> void:
	ground_backpack.visible = available

func update_contents(provisions: Dictionary) -> void:
	for id: String in food_nodes.keys():
		if not provisions.has(id):
			food_nodes[id].hide()
			food_nodes[id].queue_free()
			food_nodes.erase(id)
	for id: String in provisions:
		var info: Dictionary = provisions[id]
		if not (FOOD.has(info.item) or Clothing.MODELS.has(info.item) or EQUIPMENT.has(info.item)
			or SUPPLIES.has(info.item) or Weapons.CAMP_MODELS.has(info.item)):
			continue
		var at := Vector3(info.at[0], info.at[1], info.at[2])
		if not food_nodes.has(id):
			var heading := TAU * float(posmod(id.hash(), 360)) / 360.0
			if Clothing.MODELS.has(info.item):
				var garment := Clothing.on_ground(info.item)
				garment.position = at
				garment.rotation.y = heading
				add_child(garment)
				food_nodes[id] = garment
			elif Weapons.CAMP_MODELS.has(info.item):
				food_nodes[id] = _place_ground_weapon(info.item, at, 1.47 if id.begins_with("camp-weapon-") else heading)
			else:
				var resource: PackedScene = load(EQUIPMENT[info.item]) if EQUIPMENT.has(info.item) else SUPPLIES[info.item] if SUPPLIES.has(info.item) else FOOD[info.item]
				food_nodes[id] = _place(resource, at, heading)
				if EQUIPMENT.has(info.item):
					food_nodes[id].rotation.x = PI * 0.5
					food_nodes[id].position.y += 0.06
		else:
			food_nodes[id].position = at + (Vector3.UP * 0.06 if EQUIPMENT.has(info.item) else Vector3.ZERO)

func _place(scene: PackedScene, at: Vector3, yaw: float = 0.0) -> Node3D:
	var item := scene.instantiate() as Node3D
	item.position = at
	item.rotation.y = yaw
	add_child(item)
	return item

func _place_ground_weapon(item: String, at: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	if not weapon_models.has(item):
		weapon_models[item] = load(Weapons.CAMP_MODELS[item])
	var scene: PackedScene = weapon_models[item]
	var model := scene.instantiate() as Node3D
	root.add_child(model)
	model.rotation.z = PI * 0.5
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var bounds: AABB = root.global_transform.affine_inverse() * meshes[0].global_transform * meshes[0].get_aabb()
	for mesh: MeshInstance3D in meshes:
		bounds = bounds.merge(root.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb())
	var center := bounds.get_center()
	model.position = -Vector3(center.x, bounds.position.y, center.z)
	root.set_meta("weapon_extent", Vector2(bounds.size.z * 0.49, bounds.size.y * 0.5))
	root.position = at
	root.rotation.y = yaw
	return root

func pickup_point(id: String, at: Vector3, eye: Vector3, forward: Vector3) -> Vector3:
	var node := food_nodes.get(id) as Node3D
	if node == null or not node.has_meta("weapon_extent"):
		return at + Vector3.UP * 0.05
	var extent: Vector2 = node.get_meta("weapon_extent")
	var center := at + Vector3.UP * extent.y
	var axis := node.global_basis.z * extent.x
	return Geometry3D.get_closest_points_between_segments(eye, eye + forward * 6.0, center - axis, center + axis)[1]

func observables(provisions: Dictionary) -> Array:
	var output := []
	for id: String in food_nodes:
		var node: Node3D = food_nodes[id]
		if provisions.has(id) and is_instance_valid(node):
			output.append({"id": id, "item": provisions[id].item, "visible": node.is_visible_in_tree(),
				"at": [node.position.x, node.position.y, node.position.z]})
	return output
