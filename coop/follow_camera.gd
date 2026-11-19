extends RefCounted

const Rules = preload("res://rules.gd")
const LakeLayout = preload("res://lake_layout.gd")
const CAMERA_MARGIN := 0.14

var blockers: Dictionary
var roof_center: Vector2
var roof_half_size: Vector2

func configure(world: Dictionary) -> void:
	blockers = Rules.collision_grid(world.obstacles)
	var shelter: Dictionary = world.shelter
	roof_center = Vector2(shelter.x, shelter.z)
	roof_half_size = Vector2(shelter.width, shelter.depth) * 0.5 + Vector2(0.43, 0.45)

func clear_distance(pivot: Vector3, offset: Vector3) -> float:
	var length := offset.length()
	var steps := maxi(1, ceili(length / 0.10))
	for step in range(1, steps + 1):
		var at := pivot + offset * (float(step) / steps)
		var ground := Vector2(at.x, at.z)
		var from_roof := (ground - roof_center).abs()
		var roof_height := 3.56 - 1.52 * from_roof.x / roof_half_size.x
		var hits_roof := from_roof.x < roof_half_size.x and from_roof.y < roof_half_size.y and absf(at.y - roof_height) < 0.20
		if hits_roof or not Rules.obstacle_free_at(ground, blockers) or at.y < LakeLayout.walk_height(ground) + CAMERA_MARGIN:
			return maxf(0.18, length * float(step - 1) / steps - CAMERA_MARGIN)
	return length
