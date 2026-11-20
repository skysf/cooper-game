extends SceneTree
## Run against an imported coop project. Uses the normal route, hit and storage entry points.
const Scene = preload("res://camp_storage_scene.gd")
const Storage = preload("res://camp_storage.gd")
const Wildlife = preload("res://wildlife.gd")
const Health = preload("res://storage_wildlife.gd")
const Lake = preload("res://lake_layout.gd")
const Rules = preload("res://rules.gd")
const Stones = preload("res://stones.gd")
const Survival = preload("res://survival.gd")
const ID := "corpse-eagle"

class CorpseScene extends Scene:
	func _ready() -> void:
		pass

var grid: Dictionary
var scene := CorpseScene.new()
var camera := Camera3D.new()
var errors: Array[String] = []
var report := {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.add_child(scene)
	root.add_child(camera)
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	var dry_flight := -1.0
	for i in range(40, 260):
		var clock := i * 0.25
		var bird := Wildlife.eagle(clock)
		var at: Vector3 = bird.at
		if bird.clip in ["Glide", "Flap", "BankLeft", "BankRight"] and not is_finite(Lake.surface_height(Vector2(at.x, at.z))):
			dry_flight = clock
			break
	_check(dry_flight >= 0.0, "Dry flight exists on the current route")
	for row: Array in [["perch", 4.0, "Collapse", false], ["dry_flight", dry_flight, "Fall", false],
			["lake_flight", 20.0, "Fall", true], ["ground", 39.0, "Collapse", false]]:
		_case(row[0], row[1], row[2], row[3])
	scene.queue_free()
	await process_frame
	print("COOP_EAGLE_DEATH ", JSON.stringify({"cases": report, "errors": errors}))
	quit(0 if errors.is_empty() else 1)

func _case(label: String, time: float, clip: String, lake: bool) -> void:
	var room := {"data": {"elapsed":time, "storage":{}, "storageWildlife":Health.from_save(null),
		"survival":{"one":Survival.initial_state(),"two":Survival.initial_state()}, "backpackOwner":""},
		"actors":{}, "crocodile":{}}
	var bird := Wildlife.eagle(time)
	var basis := Basis(Vector3.UP, float(bird.yaw))
	var origin: Vector3 = bird.at - basis * Health.EAGLE_PERCH_OFFSET * float(bird.contact)
	var hit := origin + Vector3.UP * 0.24
	_check(Health.hit(room, hit + Vector3.UP, hit + Vector3.DOWN, 0.01, 48.0, grid), label + " lethal contact")
	_check(not Health.alive(room,"eagle"), label + " stored death suppresses live bird")
	_check(not Health.hit(room, hit + Vector3.UP, hit + Vector3.DOWN, 0.01, 48.0, grid), label + " duplicate hit")
	if not room.data.storage.has(ID):
		return
	var record: Dictionary = room.data.storage[ID]
	var at := Stones.unpack(record.at)
	var point := Vector2(at.x, at.z)
	var land: float = record.landAt
	var impact: float = record.get("impactAt", land)
	var has_fall: bool = record.has("fallFrom")
	_check(has_fall == (label != "ground"), label + " expected air or ground state")
	_check(not is_finite(Lake.surface_height(point)) or at.y > Lake.surface_height(point), label + " dry harvest point")
	_check(Rules.free_at(point, grid), label + " accessible harvest point")
	_check((land > impact) == lake, label + " shore transfer only for actual lake death")
	for id: String in ["one","two"]:
		room.actors[id] = {"point":point, "y":at.y, "swimming":false}
		room.data.survival[id].bag = {}
	camera.position = at + Vector3(0.0, 1.65, 1.18)
	camera.look_at(at + Vector3.UP * 0.15)
	var frozen := JSON.parse_string(JSON.stringify(room.data.storage)) as Dictionary
	scene.sync(room.data.storage, {}, "one", camera, true, time)
	if not scene.live.has(ID):
		_check(false, label + " missing corpse model")
		return
	var instance: Dictionary = scene.live[ID]
	var animator: AnimationPlayer = instance.corpse_animator
	var root_node: Node3D = instance.root
	_check(animator.assigned_animation == clip, label + " initial flight/collapse clip")
	_check(root_node.position.distance_to(origin if has_fall else at) < 0.001, label + " starts at actual route origin")
	_check(scene.target(room.data.storage, point, at.y, camera) == "", label + " aim is disabled in flight")
	_check(not Storage.action(room, "one", {"action":"take", "id":ID, "item":"eagle_claw"}, grid).ok, label + " server rejects early harvest")
	var mid := (time + impact) * 0.5
	var copy := Storage.from_save(frozen, mid, grid)
	_check(absf(float(copy[ID].landAt) - land) < 0.001 and copy[ID].has("fallFrom") == has_fall, label + " active save preserves clock")
	scene.sync(copy, {}, "one", camera, true, mid)
	var mid_y := root_node.position.y
	if has_fall:
		var floor_y := maxf(Lake.walk_height(Vector2(origin.x,origin.z)), Lake.surface_height(Vector2(origin.x,origin.z)))
		_check(absf(impact - time - sqrt(2.0 * (origin.y-floor_y) / -Stones.GRAVITY.y)) < 0.001, label + " physical gravity duration")
		_check(absf(mid_y-lerpf(origin.y,floor_y,0.25)) < 0.001, label + " gravity position at mid flight")
	if lake:
		scene.sync(copy, {}, "one", camera, true, impact + 0.001)
		_check(animator.assigned_animation == "Dead" and absf(root_node.position.y-Lake.water_y()) < 0.001, label + " splashes down at actual position")
		_check(Vector2(root_node.position.x,root_node.position.z).distance_to(Vector2(origin.x,origin.z)) < 0.001, label + " lake fall is vertical")
		_check(scene.target(copy, point, at.y, camera) == "", label + " drifting corpse is unreachable")
		room.data.elapsed = (land + impact) * 0.5
		scene.sync(copy, {}, "one", camera, true, room.data.elapsed)
		_check(Vector2(root_node.position.x,root_node.position.z).distance_to(Vector2(origin.x,origin.z).lerp(point,0.5)) < 0.001, label + " visible drift toward shore")
		_check(not Storage.action(room, "one", {"action":"take", "id":ID, "item":"eagle_claw"}, grid).ok, label + " server rejects until shore")
	room.data.elapsed = land + 0.01
	scene.sync(copy, {}, "one", camera, true, room.data.elapsed)
	_check(animator.assigned_animation == "Dead", label + " holds authored rest pose")
	_check(root_node.position.distance_to(at) < 0.001 and absf(root_node.rotation.z) < 0.001, label + " contacts ground without scene roll")
	_check(scene.target(copy, point, at.y, camera) == ID, label + " targetable on safe ground")
	_check(Storage.action(room, "one", {"action":"take", "id":ID, "item":"eagle_claw"}, grid).ok, label + " first player claims the claw")
	_check(not Storage.action(room, "two", {"action":"take", "id":ID, "item":"eagle_claw"}, grid).ok, label + " no duplicate harvest")
	_check(Storage.action(room, "two", {"action":"take", "id":ID, "item":"eagle_meat"}, grid).ok and int(record.bag.get("eagle_feather",0)) == 1,
		label + " second player can harvest remaining meat while feather remains")
	var settled := Storage.from_save(room.data.storage, room.data.elapsed, grid)
	_check(not settled[ID].has("landAt") and int(settled[ID].bag.get("eagle_feather",0)) == 1, label + " settled save preserves remaining loot")
	for key: String in ["landAt", "impactAt", "fallFrom", "foldedFall"]:
		frozen[ID].erase(key)
	var old := Storage.from_save(frozen, time, grid)
	scene.sync(old, {}, "one",camera,true,time)
	_check(animator.assigned_animation == "Dead" and root_node.position.distance_to(at) < 0.001, label + " old saves load directly settled")
	report[label] = {"clip":clip, "fallSeconds":impact-time if has_fall else 0.0, "transitionSeconds":land-time,
		"origin":Stones.pack(origin), "midHeight":mid_y, "shoreSeconds":land-impact, "land":record.at}
	scene.sync({}, {}, "one", camera, true, land)

func _check(passed: bool, description: String) -> void:
	if not passed:
		errors.append(description)
