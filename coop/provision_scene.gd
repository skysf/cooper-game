extends Node3D

const Survival = preload("res://survival.gd")
const TABLE = preload("res://props/camp_table.glb")
const JUG = preload("res://props/camp_water_jug.glb")
const GNOME = preload("res://props/table_gnome.glb")
const BABUSHKA = preload("res://props/table_babushka.glb")
const FOOD = {
	"apple": preload("res://props/food_apple.glb"),
	"bread": preload("res://props/food_bread.glb"),
}

var food_nodes: Dictionary = {}

func _ready() -> void:
	_place(TABLE, Vector3(Survival.TABLE_CENTER.x, 0.0, Survival.TABLE_CENTER.y))
	_place(JUG, Vector3(Survival.JUG.x, Survival.TABLE_TOP, Survival.JUG.y), -0.32)
	_place(GNOME, Vector3(3.52, Survival.TABLE_TOP, -89.12), PI * 0.5 - 0.12)
	_place(BABUSHKA, Vector3(3.74, Survival.TABLE_TOP, -89.12), 0.17)

func update_contents(provisions: Dictionary) -> void:
	for id: String in food_nodes.keys():
		if not provisions.has(id):
			food_nodes[id].hide()
			food_nodes[id].queue_free()
			food_nodes.erase(id)
	for id: String in provisions:
		var info: Dictionary = provisions[id]
		if not FOOD.has(info.item):
			continue
		var at := Vector3(info.at[0], info.at[1], info.at[2])
		if not food_nodes.has(id):
			var heading := TAU * float(posmod(id.hash(), 360)) / 360.0
			food_nodes[id] = _place(FOOD[info.item], at, heading)
		else:
			food_nodes[id].position = at

func _place(scene: PackedScene, at: Vector3, yaw: float = 0.0) -> Node3D:
	var item := scene.instantiate() as Node3D
	item.position = at
	item.rotation.y = yaw
	add_child(item)
	return item
