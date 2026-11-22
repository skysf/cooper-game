extends Node3D

const Reeds = preload("res://lake_reeds.gd")
const Plants = preload("res://vegetation/photo_landscapes/field_plants.gd")
const KINDS := ["reed_silver","reed_ochre","reed_cut"]
var material := Plants.material(.26)
var batches := {}
var tufts: Array[Dictionary] = []
var previous_mask := -1

func build(reflection_layer: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9135
	for i in Reeds.BEARINGS.size():
		var angle: float = Reeds.BEARINGS[i]*.01
		for j in 5:
			var a := float(angle) + (j-2)*.019 + rng.randf_range(-.009,.009)
			var p := Reeds.Lake.shore_at(a, .994 if j==2 else rng.randf_range(.948,1.067))
			var in_rock := false
			for rock: Dictionary in Reeds.Lake.layout.boulders:
				if p.distance_to(Vector2(rock.x,rock.z)) < float(rock.radius)+.12:
					in_rock = true
					break
			if in_rock: continue
			var basis := Basis(Vector3.UP,rng.randf_range(-1.05,1.32)).scaled(Vector3.ONE*rng.randf_range(.78,1.15))
			var pos := Vector3(p.x,Reeds.Lake.ground_height(p)-.023,p.y)
			tufts.append({"patch":i,"kind":KINDS[rng.randi_range(0,1)],"pose":Transform3D(basis,pos)})
	var initial := []
	for tuft: Dictionary in tufts:
		initial.append(tuft.pose)
	for kind: String in KINDS:
		var node := Plants.batch(self,kind,initial,material,78.0)
		node.layers |= reflection_layer
		batches[kind] = node.multimesh
	sync({},0.0)

func sync(times: Dictionary, elapsed: float) -> void:
	var mask := 0
	for id: String in times:
		if Reeds.cut(id,times,elapsed):
			var slot := Reeds.BEARINGS.find(int(id))
			if slot >= 0: mask |= 1 << slot
	if previous_mask == mask: return
	previous_mask = mask
	var count := {"reed_silver":0,"reed_ochre":0,"reed_cut":0}
	for tuft: Dictionary in tufts:
		var kind: String = "reed_cut" if mask & (1 << int(tuft.patch)) else tuft.kind
		var batch: MultiMesh = batches[kind]
		batch.set_instance_transform(count[kind],tuft.pose)
		count[kind] += 1
	for kind: String in KINDS:
		batches[kind].visible_instance_count = count[kind]
