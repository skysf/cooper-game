extends Node3D

const Survival = preload("res://survival.gd")
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

var food_nodes: Dictionary = {}
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
		if not FOOD.has(info.item) and not Clothing.MODELS.has(info.item):
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
			else:
				food_nodes[id] = _place(FOOD[info.item], at, heading)
		else:
			food_nodes[id].position = at

func _place(scene: PackedScene, at: Vector3, yaw: float = 0.0) -> Node3D:
	var item := scene.instantiate() as Node3D
	item.position = at
	item.rotation.y = yaw
	add_child(item)
	return item
